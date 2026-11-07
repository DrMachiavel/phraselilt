import AVFoundation
import Combine
import Foundation

@MainActor public final class MicrophoneRecorder: NSObject, Recording, AVAudioRecorderDelegate {
  private var recorder: AVAudioRecorder?
  private var generation = UUID()
  public var interrupted: (() -> Void)?
  public override init() { super.init() }
  public func start(to url: URL) async throws {
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
    guard recorder.prepareToRecord(), recorder.record(forDuration: 59) else {
      throw PracticeError.microphone
    }
    self.recorder = recorder
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
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
    Task { @MainActor [weak self] in self?.interrupted?() }
  }
  nonisolated public func audioRecorderEncodeErrorDidOccur(
    _ recorder: AVAudioRecorder, error: (any Error)?
  ) {
    Task { @MainActor [weak self] in self?.interrupted?() }
  }
}

@MainActor public protocol ReferenceSpeaking: AnyObject {
  func speak(_ text: String, variety: ReferenceVariety, voiceID: String?) throws
  func stop()
}

@MainActor
public final class Playback: NSObject, ObservableObject, ReferenceSpeaking,
  AVSpeechSynthesizerDelegate
{
  @Published public private(set) var activeWord: NSRange?
  @Published public private(set) var playing = false
  @Published public private(set) var position: Double?
  @Published public private(set) var spokenWord: String?
  private var utteranceID: ObjectIdentifier?
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
      self?.stop()
    }
  }

  public func speak(_ text: String, variety: ReferenceVariety, voiceID: String? = nil) throws {
    stop()
    let voices = Self.voices(for: variety)
    guard let voice = voices.first(where: { $0.identifier == voiceID }) ?? voices.first else {
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
      self?.spokenWord = nil
      self?.utteranceID = nil
      self?.playing = false
      self?.activeWord = nil
    }
  }
}
