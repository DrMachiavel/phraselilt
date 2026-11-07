import AVFoundation
import Combine
import Foundation

@MainActor public final class MicrophoneRecorder: NSObject, Recording, AVAudioRecorderDelegate {
  private var recorder: AVAudioRecorder?
  private var generation = UUID()
  public var interrupted: (() -> Void)?
  public var finished: (() -> Void)?
  public override init() { super.init() }
  public func start(to url: URL, maximumDuration: TimeInterval) async throws {
    let current = UUID()
    generation = current
    let allowed = await AVAudioApplication.requestRecordPermission()
    guard current == generation else { throw CancellationError() }
    guard allowed else { throw PracticeError.microphone }
    let recorder = try AVAudioRecorder(
      url: url,
      settings: [
        AVFormatIDKey: kAudioFormatMPEG4AAC,
        AVSampleRateKey: 44100, AVNumberOfChannelsKey: 1,
        AVEncoderBitRateKey: 96000,
      ])
    recorder.delegate = self
    guard recorder.prepareToRecord(), recorder.record(forDuration: min(59, max(1, maximumDuration)))
    else {
      throw PracticeError.microphone
    }
    self.recorder = recorder
    do {
      try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    } catch {
      stop()
      throw error
    }
  }
  public func stop() {
    generation = UUID()
    recorder?.delegate = nil
    recorder?.stop()
    recorder = nil
  }
  public func cancel() { stop() }
  nonisolated public func audioRecorderDidFinishRecording(
    _ recorder: AVAudioRecorder, successfully flag: Bool
  ) {
    let id = ObjectIdentifier(recorder)
    Task { @MainActor [weak self] in
      guard let self, self.recorder.map(ObjectIdentifier.init) == id else { return }
      if flag { self.finished?() } else { self.interrupted?() }
    }
  }
  nonisolated public func audioRecorderEncodeErrorDidOccur(
    _ recorder: AVAudioRecorder, error: (any Error)?
  ) {
    let id = ObjectIdentifier(recorder)
    Task { @MainActor [weak self] in
      guard let self, self.recorder.map(ObjectIdentifier.init) == id else { return }
      self.interrupted?()
    }
  }
}

@MainActor public protocol ReferenceSpeaking: AnyObject {
  func speak(_ text: String, variety: ReferenceVariety, voiceID: String?) throws
  func stop()
}

@MainActor
public final class Playback: NSObject, ObservableObject, ReferenceSpeaking,
  AVSpeechSynthesizerDelegate, ListeningAudio
{
  @Published public private(set) var activeWord: NSRange?
  @Published public private(set) var playing = false
  @Published public private(set) var position: Double?
  @Published public private(set) var spokenWord: String?
  private var utteranceID: ObjectIdentifier?
  private var completion: CheckedContinuation<Void, any Error>?
  private var operationID: UUID?
  private var player: AVAudioPlayer?
  private var stopTask: Task<Void, Never>?
  private let synth = AVSpeechSynthesizer()
  public override init() {
    super.init()
    synth.delegate = self
  }
  public static func voices(for variety: ReferenceVariety) -> [AVSpeechSynthesisVoice] {
    AVSpeechSynthesisVoice.speechVoices().filter {
      $0.language == variety.locale && !$0.voiceTraits.contains(.isPersonalVoice)
        && !$0.voiceTraits.contains(.isNoveltyVoice)
    }
  }
  public static func defaultVoice(for variety: ReferenceVariety) -> AVSpeechSynthesisVoice? {
    let voices = voices(for: variety)
    return voices.first(where: { $0.name == (variety == .american ? "Samantha" : "Daniel") })
      ?? voices.first
  }
  public func play(url: URL, segment: WordSegment? = nil) throws {
    stop()
    let player = try AVAudioPlayer(contentsOf: url)
    self.player = player
    if let segment { player.currentTime = max(0, segment.start) }
    guard player.play() else { throw PracticeError.invalidAudio }
    playing = true
    let duration = min(segment?.duration ?? player.duration, player.duration - player.currentTime)
    stopTask = Task { [weak self] in
      let end = Date().addingTimeInterval(max(0, duration))
      while !Task.isCancelled, Date() < end {
        self?.position = self?.player?.currentTime
        try? await Task.sleep(for: .milliseconds(60))
      }
      guard !Task.isCancelled else { return }
      self?.complete()
    }
  }

  public func speak(_ text: String, variety: ReferenceVariety, voiceID: String? = nil) throws {
    stop()
    let voices = Self.voices(for: variety)
    guard
      let voice = voices.first(where: { $0.identifier == voiceID })
        ?? Self.defaultVoice(for: variety)
    else {
      throw PracticeError.noVoice
    }
    let utterance = AVSpeechUtterance(string: text)
    utterance.voice = voice
    utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
    utteranceID = ObjectIdentifier(utterance)
    playing = true
    synth.speak(utterance)
  }
  public func stop() {
    completion?.resume(throwing: CancellationError())
    completion = nil
    operationID = nil
    utteranceID = nil
    position = nil
    spokenWord = nil
    stopTask?.cancel()
    stopTask = nil
    player?.stop()
    player = nil
    synth.stopSpeaking(at: .immediate)
    playing = false
    activeWord = nil
  }
  private func complete() {
    let completed = completion
    completion = nil
    stop()
    completed?.resume()
  }
  public func reference(_ text: String, variety: ReferenceVariety, voiceID: String?) async throws {
    try Task.checkCancellation()
    let id = UUID()
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, any Error>) in
        do {
          try speak(text, variety: variety, voiceID: voiceID)
          operationID = id
          completion = continuation
        } catch { continuation.resume(throwing: error) }
      }
    } onCancel: {
      Task { @MainActor [weak self] in if self?.operationID == id { self?.stop() } }
    }
  }
  public func recording(_ url: URL, segment: WordSegment?) async throws {
    try Task.checkCancellation()
    let id = UUID()
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, any Error>) in
        do {
          try play(url: url, segment: segment)
          operationID = id
          completion = continuation
        } catch { continuation.resume(throwing: error) }
      }
    } onCancel: {
      Task { @MainActor [weak self] in if self?.operationID == id { self?.stop() } }
    }
  }
  nonisolated public func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance
  ) {
    let id = ObjectIdentifier(utterance)
    Task { @MainActor [weak self] in if self?.utteranceID == id { self?.stop() } }
  }
  nonisolated public func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange,
    utterance: AVSpeechUtterance
  ) {
    let id = ObjectIdentifier(utterance)
    let text = (utterance.speechString as NSString).substring(with: characterRange)
    Task { @MainActor [weak self] in
      guard self?.utteranceID == id else { return }
      self?.activeWord = characterRange
      self?.spokenWord = text
    }
  }
  nonisolated public func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance
  ) {
    let id = ObjectIdentifier(utterance)
    Task { @MainActor [weak self] in
      guard self?.utteranceID == id else { return }
      self?.complete()
    }
  }
}
