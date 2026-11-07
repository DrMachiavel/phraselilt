import AVFoundation
import Foundation
import Testing

@testable import PracticeCore

private let device: UInt32 = 42
private func process(
  _ id: String = "com.electron.wispr-flow", pid: Int32 = 123, deviceID: UInt32 = device
) -> InputProcess {
  InputProcess(processID: pid, bundleID: id, devices: [deviceID])
}
private func snapshot(_ processes: [InputProcess] = [], deviceID: UInt32 = device) -> InputSnapshot
{
  InputSnapshot(defaultDevice: deviceID, processes: processes)
}
private let wispr = CaptureSource(kind: .wispr, device: device)
private let granola = CaptureSource(kind: .granola, device: device)

@Test func selectedAppsAreStrictlyScoped() {
  let config = CompanionConfiguration(enabled: true)
  #expect(config.source(for: process(), defaultDevice: device, ownPID: 9) == wispr)
  #expect(
    config.source(for: process("com.electron.wispr-flow.helper"), defaultDevice: device, ownPID: 9)
      == wispr)
  #expect(
    config.source(for: process("com.electron.wispr-flow-fake"), defaultDevice: device, ownPID: 9)
      == nil)
  #expect(config.source(for: process("ai.granola"), defaultDevice: device, ownPID: 9) == nil)
  #expect(config.source(for: process(deviceID: 99), defaultDevice: device, ownPID: 9) == nil)
  #expect(config.source(for: process(), defaultDevice: device, ownPID: 123) == nil)
  let generic = CompanionConfiguration(enabled: true, wispr: false, granola: false, other: true)
  #expect(generic.source(for: process(), defaultDevice: device, ownPID: 9) == nil)
  #expect(
    generic.source(for: process("ai.granola.helper"), defaultDevice: device, ownPID: 9) == nil)
  #expect(
    generic.source(
      for: process("io.github.drmachiavel.PhraseLilt"), defaultDevice: device, ownPID: 9) == nil)
  #expect(
    generic.source(
      for: process("io.github.drmachiavel.PhraseLilt.helper"), defaultDevice: device, ownPID: 9)
      == nil)
  #expect(generic.source(for: process("com.example.call"), defaultDevice: device, ownPID: 9) != nil)
}

@Test func ongoingRecordingIsSkippedUntilItBecomesIdle() {
  var policy = CapturePolicy()
  #expect(policy.consume([wispr], defaultDevice: device) == .none)
  #expect(policy.consume([wispr], defaultDevice: device) == .none)
  #expect(policy.consume([], defaultDevice: device) == .none)
  #expect(policy.consume([wispr], defaultDevice: device) == .start(wispr))
  #expect(policy.consume([wispr], defaultDevice: device) == .none)
  #expect(policy.consume([], defaultDevice: device) == .finish)
}

@Test func durationLimitDoesNotRetriggerAnOpenMicrophone() {
  var policy = CapturePolicy()
  _ = policy.consume([], defaultDevice: device)
  #expect(policy.consume([wispr], defaultDevice: device) == .start(wispr))
  policy.recordingEnded()
  for _ in 0..<10 { #expect(policy.consume([wispr], defaultDevice: device) == .none) }
  _ = policy.consume([], defaultDevice: device)
  #expect(policy.consume([wispr], defaultDevice: device) == .start(wispr))
}

@Test func overlappingAppsNeverExtendOrTransferTheRecording() {
  var policy = CapturePolicy()
  _ = policy.consume([], defaultDevice: device)
  _ = policy.consume([wispr], defaultDevice: device)
  #expect(policy.consume([wispr, granola], defaultDevice: device) == .none)
  #expect(policy.consume([granola], defaultDevice: device) == .finish)
  #expect(policy.consume([granola], defaultDevice: device) == .none)
  _ = policy.consume([], defaultDevice: device)
  #expect(policy.consume([granola], defaultDevice: device) == .start(granola))
}

@Test func deviceChangeCancelsAndResumeWaitsForNewActivity() {
  var policy = CapturePolicy()
  _ = policy.consume([], defaultDevice: device)
  _ = policy.consume([wispr], defaultDevice: device)
  let moved = CaptureSource(kind: .wispr, device: 99)
  #expect(policy.consume([moved], defaultDevice: 99) == .cancel)
  #expect(policy.consume([moved], defaultDevice: 99) == .none)
  policy.reset()
  #expect(policy.consume([moved], defaultDevice: 99) == .none)
}

private struct UnavailableReader: InputActivityReading {
  func snapshot() throws -> InputSnapshot { throw ActivityError.unavailable }
}
private struct EmptyReader: InputActivityReading {
  func snapshot() throws -> InputSnapshot { snapshotValue }
  var snapshotValue = InputSnapshot(defaultDevice: device, processes: [])
}
private struct NoRecognition: Transcribing {
  func transcribe(url: URL, variety: ReferenceVariety) async throws -> Recognition {
    Recognition(text: "A generated test sentence.")
  }
}
@MainActor private final class Recorder: Recording {
  var starts = 0
  var cancelled = false
  var limit: TimeInterval?
  var permission: CheckedContinuation<Void, Never>?
  var delayed = false
  func start(to url: URL, maximumDuration: TimeInterval) async throws {
    starts += 1
    limit = maximumDuration
    if delayed { await withCheckedContinuation { permission = $0 } }
    if cancelled { throw CancellationError() }
    let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16000)!
    buffer.frameLength = 16000
    for i in 0..<16000 { buffer.floatChannelData![0][i] = Float(sin(Double(i) / 20) * 0.1) }
    let file = try AVAudioFile(forWriting: url, settings: format.settings)
    try file.write(from: buffer)
  }
  func stop() {}
  func cancel() { cancelled = true }
}
@MainActor private func waitFor(_ condition: () -> Bool) async throws {
  for _ in 0..<150 {
    if condition() { return }
    try await Task.sleep(for: .milliseconds(5))
  }
  Issue.record("Expected state was not reached")
}
private func directory() -> URL {
  FileManager.default.temporaryDirectory.appendingPathComponent("CompanionTest-\(UUID())")
}

@Test @MainActor func pauseBeforeQueuedStartNeverOpensMicrophone() async throws {
  let root = directory()
  defer { try? FileManager.default.removeItem(at: root) }
  let recorder = Recorder()
  let session = PracticeSession(
    store: try ClipStore(root: root), recorder: recorder, transcriber: NoRecognition())
  let companion = Companion(
    session: session, reader: EmptyReader(), ownPID: 9, automaticPolling: false)
  companion.configure(CompanionConfiguration(enabled: true))
  companion.consume(snapshot())
  companion.consume(snapshot([process()]))
  companion.configure(CompanionConfiguration())
  try await Task.sleep(for: .milliseconds(20))
  #expect(recorder.starts == 0)
  #expect(!session.recording)
}

@Test @MainActor func pauseDuringPermissionPreventsLateRecording() async throws {
  let root = directory()
  defer { try? FileManager.default.removeItem(at: root) }
  let recorder = Recorder()
  recorder.delayed = true
  let session = PracticeSession(
    store: try ClipStore(root: root), recorder: recorder, transcriber: NoRecognition())
  let companion = Companion(
    session: session, reader: EmptyReader(), ownPID: 9, automaticPolling: false)
  companion.configure(CompanionConfiguration(enabled: true))
  companion.consume(snapshot())
  companion.consume(snapshot([process()]))
  try await waitFor { recorder.permission != nil }
  companion.suspend()
  recorder.permission?.resume()
  try await waitFor { !session.requestingMicrophone }
  #expect(!session.recording)
  #expect(recorder.cancelled)
  #expect(session.clips.isEmpty)
}

@Test @MainActor func activityCreatesOneBoundedClipWithOriginAndNoSelfTrigger() async throws {
  let root = directory()
  defer { try? FileManager.default.removeItem(at: root) }
  let recorder = Recorder()
  let session = PracticeSession(
    store: try ClipStore(root: root), recorder: recorder, transcriber: NoRecognition())
  let companion = Companion(
    session: session, reader: EmptyReader(), ownPID: 9, automaticPolling: false)
  companion.configure(CompanionConfiguration(enabled: true, other: true))
  companion.consume(snapshot())
  companion.consume(snapshot([process()]))
  try await waitFor { session.recording }
  #expect(recorder.limit == 30)
  let own = process("io.github.drmachiavel.PhraseLilt", pid: 9)
  for _ in 0..<70 {
    companion.consume(snapshot([own]))
    if !session.recording { break }
    try await Task.sleep(for: .milliseconds(5))
  }
  #expect(!session.recording)
  #expect(session.clips.count == 1)
  #expect(session.selected?.captureSource == "Wispr Flow")
  #expect(companion.completedCaptures == 1)
  for _ in 0..<5 { companion.consume(snapshot([own])) }
  #expect(recorder.starts == 1)
  companion.stop()
  session.shutdown()
}

@Test @MainActor func metadataFailureCancelsOwnedCapture() async throws {
  let root = directory()
  defer { try? FileManager.default.removeItem(at: root) }
  let recorder = Recorder()
  let session = PracticeSession(
    store: try ClipStore(root: root), recorder: recorder, transcriber: NoRecognition())
  let companion = Companion(
    session: session, reader: UnavailableReader(), ownPID: 9, automaticPolling: false)
  companion.configure(CompanionConfiguration(enabled: true))
  companion.consume(snapshot())
  companion.consume(snapshot([process()]))
  try await waitFor { session.recording }
  companion.poll()
  #expect(!session.recording)
  #expect(companion.error != nil)
  #expect(recorder.cancelled)
  #expect(session.clips.isEmpty)
}

@MainActor private final class Audio: ListeningAudio {
  var calls: [String] = []
  var lastSegment: WordSegment?
  var referenceCompletion: CheckedContinuation<Void, any Error>?
  var recordingCompletion: CheckedContinuation<Void, any Error>?
  func reference(_ text: String, variety: ReferenceVariety, voiceID: String?) async throws {
    calls.append("reference")
    try await withCheckedThrowingContinuation { referenceCompletion = $0 }
  }
  func recording(_ url: URL, segment: WordSegment?) async throws {
    calls.append("you")
    lastSegment = segment
    try await withCheckedThrowingContinuation { recordingCompletion = $0 }
  }
  func stop() {
    referenceCompletion?.resume(throwing: CancellationError())
    referenceCompletion = nil
    recordingCompletion?.resume(throwing: CancellationError())
    recordingCompletion = nil
  }
  func finishReference() {
    referenceCompletion?.resume()
    referenceCompletion = nil
  }
  func finishRecording() {
    recordingCompletion?.resume()
    recordingCompletion = nil
  }
}

@Test @MainActor func referenceNeverAutomaticallyPlaysYourRecording() async throws {
  let audio = Audio()
  let listening = Listening(audio: audio)
  listening.playReference(text: "Test.", variety: .american, voiceID: nil)
  try await waitFor { audio.referenceCompletion != nil }
  #expect(listening.phase == .reference)
  audio.finishReference()
  try await waitFor { listening.phase == .done }
  #expect(audio.calls == ["reference"])
}

@Test @MainActor func switchingToYourRecordingCancelsReferenceWithoutStaleState() async throws {
  let audio = Audio()
  let listening = Listening(audio: audio)
  listening.playReference(text: "Test.", variety: .american, voiceID: nil)
  try await waitFor { audio.referenceCompletion != nil }
  listening.playRecording(url: URL(fileURLWithPath: "/unused.wav"))
  try await waitFor { audio.recordingCompletion != nil }
  #expect(audio.referenceCompletion == nil)
  #expect(listening.phase == .you)
  #expect(listening.error == nil)
  audio.finishRecording()
  try await waitFor { listening.phase == .done }
  #expect(audio.calls == ["reference", "you"])
}

@Test @MainActor func cancellingReferenceNeverStartsYourAudio() async throws {
  let audio = Audio()
  let listening = Listening(audio: audio)
  listening.playReference(
    text: "Test.", variety: .british, voiceID: nil)
  try await waitFor { audio.referenceCompletion != nil }
  listening.stop()
  try await Task.sleep(for: .milliseconds(20))
  #expect(audio.calls == ["reference"])
  #expect(listening.phase == .idle)
  #expect(listening.error == nil)
}

@Test @MainActor func cancellationBeforeListeningTaskStartsIsSilent() async throws {
  let audio = Audio()
  let listening = Listening(audio: audio)
  listening.playReference(
    text: "Test.", variety: .american, voiceID: nil)
  listening.stop()
  try await Task.sleep(for: .milliseconds(20))
  #expect(audio.calls.isEmpty)
}

@Test func shortExcerptRequiresExactAudioBoundaries() {
  let text = "Please open the browser. We can meet tomorrow."
  let words = text.split(separator: " ").enumerated().map {
    WordSegment(text: String($0.element), start: 0.2 + Double($0.offset) * 0.3, duration: 0.3)
  }
  let excerpt = PracticeExcerpt.select(from: Recognition(text: text, words: words))
  #expect(excerpt?.text == "Please open the browser.")
  #expect(abs((excerpt?.start ?? -1) - 0.2) < 0.001)
  #expect(abs((excerpt?.duration ?? -1) - 1.2) < 0.001)
  let chunk = WordSegment(text: text, start: 0, duration: 8)
  #expect(PracticeExcerpt.select(from: Recognition(text: text, words: [chunk])) == nil)
  #expect(PracticeExcerpt.select(from: Recognition(text: text, words: [])) == nil)
  #expect(
    PracticeExcerpt.select(
      from: Recognition(text: "Please open the browser", words: Array(words.prefix(4)))) == nil)
}

@Test func oldHistoryWithoutCaptureFieldsStillDecodes() throws {
  let clip = Clip(audioName: "unused.wav", variety: .american, duration: 1)
  var object = try #require(
    JSONSerialization.jsonObject(with: JSONEncoder().encode(clip)) as? [String: Any])
  object.removeValue(forKey: "captureSource")
  object.removeValue(forKey: "practiceSegment")
  let decoded = try JSONDecoder().decode(
    Clip.self, from: JSONSerialization.data(withJSONObject: object))
  #expect(decoded.captureSource == nil)
  #expect(decoded.practiceSegment == nil)
}

@Test @MainActor func ownRecordingPlaysOnlyTheSelectedExcerptWithoutReference() async throws {
  let audio = Audio()
  let listening = Listening(audio: audio)
  let segment = WordSegment(text: "Please open the browser.", start: 2, duration: 3)
  listening.playRecording(url: URL(fileURLWithPath: "/unused.wav"), segment: segment)
  try await waitFor { audio.recordingCompletion != nil }
  #expect(audio.calls == ["you"])
  #expect(audio.lastSegment == segment)
  listening.stop()
}
