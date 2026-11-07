import AVFoundation
import Combine
import Foundation
import OnnxRuntimeBindings

public struct SoundHint: Equatable, Sendable {
  public let range: NSRange
  public let word: String
}

public struct SoundCandidate: Sendable {
  public let range: NSRange
  public let word: String
  public let segment: WordSegment
  public let tail: [String]
}

public struct AcousticPhone: Sendable {
  public let sound: String
  public let peak: Float
  public let targetPeak: Float
  public let time: Double
  public init(sound: String, peak: Float, targetPeak: Float, time: Double) {
    self.sound = sound
    self.peak = peak
    self.targetPeak = targetPeak
    self.time = time
  }
}

public enum SoundHintRules {
  // Reviewed, deliberately small vocabulary. This is not a text-derived diagnosis.
  static let tails = [
    "think": ["ɪ", "ŋ", "k"], "thing": ["ɪ", "ŋ"],
    "things": ["ɪ", "ŋ", "z"], "three": ["ɹ", "i"],
    "thank": ["æ", "ŋ", "k"], "thanks": ["æ", "ŋ", "k", "s"],
  ]
  public static func candidates(for clip: Clip) -> [SoundCandidate] {
    guard clip.intentConfirmed, clip.variety == .american else { return [] }
    let excerpt = clip.practiceSegment
    let pattern = try! NSRegularExpression(pattern: "[A-Za-z]+(?:['’][A-Za-z]+)?")
    let text = clip.intendedText as NSString
    let matches = pattern.matches(
      in: clip.intendedText, range: NSRange(location: 0, length: text.length))
    let sourceText = excerpt?.text ?? clip.rawRecognition
    let source = sourceText as NSString
    let sourceMatches = pattern.matches(
      in: sourceText, range: NSRange(location: 0, length: source.length))
    let timed = clip.words.filter {
      guard let excerpt else { return true }
      return $0.start >= excerpt.start - 0.01
        && $0.start + $0.duration <= excerpt.start + excerpt.duration + 0.01
    }
    // Same-length corrections can reuse approximate ASR word windows, never their
    // lexical judgement. Acoustic onset/context evidence must independently support a hint.
    // Changed word counts need realignment and abstain in this small prototype.
    guard matches.count == timed.count, sourceMatches.count == timed.count else { return [] }
    var result: [SoundCandidate] = []
    for (index, pair) in zip(matches, timed).enumerated() {
      let (match, word) = pair
      let expected = text.substring(with: match.range).lowercased()
      let labels = pattern.matches(
        in: word.text, range: NSRange(location: 0, length: (word.text as NSString).length))
      guard labels.count == 1,
        (word.text as NSString).substring(with: labels[0].range).lowercased()
          == source.substring(with: sourceMatches[index].range).lowercased()
      else { return [] }
      if let tail = tails[expected], word.duration >= 0.15, word.duration <= 1.5,
        word.start >= 0.08, word.start + word.duration <= clip.duration - 0.08
      {
        result.append(
          SoundCandidate(
            range: NSRange(location: match.range.location, length: 2), word: expected,
            segment: word, tail: tail))
      }
    }
    return Array(result.prefix(6))
  }
  public static func hint(for candidate: SoundCandidate, phones: [AcousticPhone]) -> SoundHint? {
    // Require an unconstrained competing onset and matching following sounds.
    // Never flag missing sounds, alignment alone, transcript differences or recognizer agreement.
    for i in phones.indices {
      let phone = phones[i]
      guard ["f", "s", "t"].contains(phone.sound), phone.peak >= 0.85, phone.targetPeak < 0.1,
        phone.time >= candidate.segment.start - 0.04,
        phone.time <= candidate.segment.start + candidate.segment.duration * 0.4,
        i + candidate.tail.count < phones.count
      else { continue }
      let tail = Array(phones[(i + 1)...(i + candidate.tail.count)])
      guard tail.map(\.sound) == candidate.tail, tail.allSatisfy({ $0.peak >= 0.6 }),
        !phones.contains(where: { $0.sound == "θ" && abs($0.time - phone.time) < 0.12 })
      else { continue }
      return SoundHint(range: candidate.range, word: candidate.word)
    }
    return nil
  }
}

public protocol SoundAssessing: Sendable {
  func assess(url: URL, candidates: [SoundCandidate]) async throws -> [SoundHint]
}

public actor LocalSoundAssessor: SoundAssessing {
  private let modelDirectory: URL
  public init(modelDirectory: URL = SoundModelFiles.root) { self.modelDirectory = modelDirectory }
  public func assess(url: URL, candidates: [SoundCandidate]) async throws -> [SoundHint] {
    guard !candidates.isEmpty else { return [] }
    try Task.checkCancellation()
    guard try AudioValidator.inspect(url).caution == nil else { return [] }
    for (name, size, hash) in SoundModelFiles.entries {
      try SoundModelFiles.verify(
        modelDirectory.appendingPathComponent(name), size: size, hash: hash)
    }
    let env = try ORTEnv(loggingLevel: .fatal)
    let options = try ORTSessionOptions()
    try options.setIntraOpNumThreads(2)
    try options.addConfigEntry(withKey: "session.intra_op.allow_spinning", value: "0")
    let session = try ORTSession(
      env: env, modelPath: modelDirectory.appendingPathComponent("phonemes.onnx").path,
      sessionOptions: options)
    let vocabulary = try JSONDecoder().decode(
      [String: Int].self,
      from: Data(contentsOf: modelDirectory.appendingPathComponent("vocab.json")))
    guard let target = vocabulary["θ"], vocabulary["<pad>"] == 0 else {
      throw PracticeError.modelsMissing
    }
    let inverse = Dictionary(uniqueKeysWithValues: vocabulary.map { ($0.value, $0.key) })
    var hints: [SoundHint] = []
    for candidate in candidates {
      try Task.checkCancellation()
      let start = max(0, candidate.segment.start - 0.08)
      let samples = try Self.samples(
        url: url, start: start, duration: candidate.segment.duration + 0.16)
      let inputData = samples.withUnsafeBufferPointer {
        NSMutableData(bytes: $0.baseAddress!, length: $0.count * 4)
      }
      let input = try ORTValue(
        tensorData: inputData, elementType: .float, shape: [1, NSNumber(value: samples.count)])
      let names = try session.outputNames()
      guard let name = names.first else { throw PracticeError.invalidAudio }
      let output = try session.run(
        withInputs: ["input_values": input], outputNames: [name], runOptions: nil)
      guard let tensor = output[name] else { throw PracticeError.invalidAudio }
      let shape = try tensor.tensorTypeAndShapeInfo().shape.map(\.intValue)
      guard shape.count == 3, shape[0] == 1, shape[1] > 0, shape[1] < 100,
        shape[2] == (vocabulary.values.max() ?? -1) + 1
      else { throw PracticeError.invalidAudio }
      let data = try tensor.tensorData() as Data
      let phones = data.withUnsafeBytes { bytes -> [AcousticPhone] in
        let values = bytes.bindMemory(to: Float.self)
        guard values.count == shape[1] * shape[2] else { return [] }
        var result: [AcousticPhone] = []
        var last = -1
        for frame in 0..<shape[1] {
          let row = Array(values[(frame * shape[2])..<((frame + 1) * shape[2])])
          guard row.allSatisfy(\.isFinite), let best = row.indices.max(by: { row[$0] < row[$1] })
          else { return [] }
          let maximum = row[best]
          let sum = row.reduce(Float(0)) { $0 + exp($1 - maximum) }
          if best != 0 && best != last {
            let sound = (inverse[best] ?? "?").replacingOccurrences(of: "ː", with: "")
            result.append(
              AcousticPhone(
                sound: sound, peak: 1 / sum, targetPeak: exp(row[target] - maximum) / sum,
                time: start + Double(frame) * 0.02))
          }
          last = best
        }
        return result
      }
      if let hint = SoundHintRules.hint(for: candidate, phones: phones) { hints.append(hint) }
      if hints.count == 2 { break }
    }
    try Task.checkCancellation()
    return hints
  }
  private static func samples(url: URL, start: Double, duration: Double) throws -> [Float] {
    let file = try AVAudioFile(forReading: url)
    let source = file.processingFormat
    file.framePosition = AVAudioFramePosition(start * source.sampleRate)
    let count = min(
      AVAudioFrameCount(duration * source.sampleRate),
      AVAudioFrameCount(max(0, file.length - file.framePosition)))
    guard count > 0, let input = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: count),
      let destination = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false),
      let converter = AVAudioConverter(from: source, to: destination),
      let output = AVAudioPCMBuffer(
        pcmFormat: destination, frameCapacity: AVAudioFrameCount(duration * 16000) + 100)
    else { throw PracticeError.invalidAudio }
    try file.read(into: input, frameCount: count)
    let sourceInput = ConversionInput(buffer: input)
    var error: NSError?
    let status = converter.convert(to: output, error: &error) { _, state in
      sourceInput.take(state)
    }
    guard error == nil, status != .error, let channel = output.floatChannelData,
      output.frameLength >= 1600
    else { throw PracticeError.invalidAudio }
    var values = Array(UnsafeBufferPointer(start: channel[0], count: Int(output.frameLength)))
    let mean = values.reduce(0, +) / Float(values.count)
    let variance = values.reduce(Float(0)) { $0 + ($1 - mean) * ($1 - mean) } / Float(values.count)
    guard variance.isFinite, variance > 0.000001 else { throw PracticeError.invalidAudio }
    let scale = sqrt(variance + 0.0000001)
    for i in values.indices { values[i] = (values[i] - mean) / scale }
    return values
  }
}

@MainActor public final class SoundHints: ObservableObject {
  @Published public private(set) var hints: [SoundHint] = []
  @Published public private(set) var running = false
  @Published public private(set) var status: String?
  private var task: Task<Void, Never>?
  private var generation = UUID()
  private let assessor: any SoundAssessing
  public init(assessor: any SoundAssessing = LocalSoundAssessor()) { self.assessor = assessor }
  public func check(clip: Clip, url: URL) {
    cancel()
    let candidates = SoundHintRules.candidates(for: clip)
    guard !candidates.isEmpty else {
      status =
        "Couldn’t check this sentence. Try a short American-reference sentence with think, thing, things, three, thank or thanks. Individual word timings are needed; changes to the word count need a new recording."
      return
    }
    let current = generation
    running = true
    let assessor = assessor
    task = Task { [weak self] in
      do {
        let result = try await assessor.assess(url: url, candidates: candidates)
        guard let self, self.generation == current, !Task.isCancelled else { return }
        self.hints = Array(result.prefix(2))
        self.running = false
        self.status =
          result.isEmpty
          ? "No sound hint found. This does not mean every sound was correct."
          : "Compare the underlined “th” with Reference. This experimental hint may be wrong; accent variants are valid."
      } catch {
        guard let self, self.generation == current, !Task.isCancelled else { return }
        self.running = false
        self.status =
          "Couldn’t check the sounds. Check the sound model in Settings, or try a clearer recording."
      }
    }
  }
  public func cancel() {
    generation = UUID()
    task?.cancel()
    task = nil
    hints = []
    running = false
    status = nil
  }
}

// AVAudioConverter invokes the input block synchronously; the lock also protects against
// concurrent callback invocation. The buffer is immutable after construction.
private final class ConversionInput: @unchecked Sendable {
  let buffer: AVAudioPCMBuffer
  let lock = NSLock()
  var supplied = false
  init(buffer: AVAudioPCMBuffer) { self.buffer = buffer }
  func take(_ status: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
    lock.lock()
    defer { lock.unlock() }
    if supplied {
      status.pointee = .endOfStream
      return nil
    }
    supplied = true
    status.pointee = .haveData
    return buffer
  }
}
