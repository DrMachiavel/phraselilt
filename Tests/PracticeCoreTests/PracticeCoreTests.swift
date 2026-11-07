import AVFoundation
import Foundation
import Testing

@testable import PracticeCore

private func fixture(in dir: URL, seconds: Double = 1, silence: Bool = false) throws -> URL {
  try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
  let url = dir.appendingPathComponent("fixture-\(UUID()).wav")
  let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
  let count = AVAudioFrameCount(seconds * 16000)
  let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count)!
  buffer.frameLength = count
  for i in 0..<Int(count) {
    buffer.floatChannelData![0][i] = silence ? 0 : Float(sin(Double(i) * 0.08) * 0.2)
  }
  let file = try AVAudioFile(forWriting: url, settings: format.settings)
  try file.write(from: buffer)
  return url
}

private func temporary() -> URL {
  FileManager.default.temporaryDirectory.appendingPathComponent("PhraseLiltTest-\(UUID())")
}

@MainActor private final class FakeRecorder: Recording {
  var starts = 0
  var stops = 0
  var cancelled = false
  var permission: CheckedContinuation<Void, Never>?
  var waitForPermission = false
  func start(to url: URL, maximumDuration: TimeInterval) async throws {
    starts += 1
    if waitForPermission { await withCheckedContinuation { permission = $0 } }
    if cancelled { throw CancellationError() }
    let source = try fixture(in: url.deletingLastPathComponent())
    // Fake recording is only for lifecycle tests; cancellation never imports this disguised file.
    try FileManager.default.copyItem(at: source, to: url)
    try FileManager.default.removeItem(at: source)
  }
  func stop() { stops += 1 }
  func cancel() {
    cancelled = true
    stops += 1
  }
}

private actor DeferredTranscriber: Transcribing {
  var continuation: CheckedContinuation<Recognition, any Error>?
  var requests = 0
  func transcribe(url: URL, variety: ReferenceVariety) async throws -> Recognition {
    requests += 1
    return try await withCheckedThrowingContinuation { continuation = $0 }
  }
  func ready() -> Bool { continuation != nil }
  func succeed(_ value: Recognition) {
    continuation?.resume(returning: value)
    continuation = nil
  }
  func fail() {
    continuation?.resume(throwing: PracticeError.modelsMissing)
    continuation = nil
  }
}

@MainActor private func until(_ condition: () async -> Bool) async throws {
  for _ in 0..<200 {
    if await condition() { return }
    try await Task.sleep(for: .milliseconds(5))
  }
  Issue.record("Timed out waiting for test state")
}

@Test func referencesAndIndependentIntent() {
  #expect(ReferenceVariety.american.locale == "en-US")
  #expect(ReferenceVariety.british.locale == "en-GB")
  var clip = Clip(audioName: "unused.wav", variety: .american, duration: 1)
  clip.rawRecognition = "brother"
  clip.intendedText = "browser"
  clip.intentConfirmed = true
  clip.words = [WordSegment(text: "brother", start: 0, duration: 0.5)]
  #expect(!clip.canUseWordTiming)
  #expect(clip.rawRecognition == "brother")
  #expect(clip.assessmentNote.contains("unavailable"))
  clip.intendedText = "brother"
  #expect(clip.canUseWordTiming)
}

@Test func audioBoundsAndSilence() throws {
  let dir = temporary()
  defer { try? FileManager.default.removeItem(at: dir) }
  let audio = try fixture(in: dir)
  let info = try AudioValidator.inspect(audio)
  #expect(info.duration == 1)
  #expect(info.caution == nil)
  let quiet = try fixture(in: dir, silence: true)
  #expect(try AudioValidator.inspect(quiet).caution != nil)
  let long = try fixture(in: dir, seconds: 60.1)
  #expect(throws: PracticeError.tooLong) { try AudioValidator.inspect(long) }
  let bad = dir.appendingPathComponent("bad.wav")
  try Data("not audio".utf8).write(to: bad)
  #expect(throws: (any Error).self) { try AudioValidator.inspect(bad) }
  let huge = dir.appendingPathComponent("huge.wav")
  try Data(count: AudioValidator.maxBytes + 1).write(to: huge)
  #expect(throws: PracticeError.tooLarge) { try AudioValidator.inspect(huge) }
  let link = dir.appendingPathComponent("link.wav")
  try FileManager.default.createSymbolicLink(at: link, withDestinationURL: audio)
  #expect(throws: PracticeError.invalidAudio) { try AudioValidator.inspect(link) }
}

@Test @MainActor func persistenceCopyRetentionAndDeletion() throws {
  let dir = temporary()
  defer { try? FileManager.default.removeItem(at: dir) }
  let original = try fixture(in: dir)
  let originalData = try Data(contentsOf: original)
  let store = try ClipStore(root: dir.appendingPathComponent("managed"))
  var old = try store.add(from: original, variety: .american)
  old.createdAt = Date().addingTimeInterval(-8 * 86400)
  old.rawRecognition = "private"
  old.intendedText = "private"
  try store.update(old)
  var saved = try store.add(from: original, variety: .british)
  saved.saved = true
  saved.createdAt = old.createdAt
  try store.update(saved)
  let reloaded = try ClipStore(root: store.root)
  #expect(reloaded.clips.count == 2)
  try reloaded.retain(days: 7)
  #expect(reloaded.clips.map(\.id) == [saved.id])
  #expect(!FileManager.default.fileExists(atPath: reloaded.audioURL(for: old).path))
  #expect(try Data(contentsOf: original) == originalData)
  let attrs = try FileManager.default.attributesOfItem(atPath: reloaded.audioURL(for: saved).path)
  #expect((attrs[.posixPermissions] as? NSNumber)?.intValue == 0o600)
  try reloaded.delete([saved.id])
  #expect(reloaded.clips.isEmpty)
  #expect(!FileManager.default.fileExists(atPath: reloaded.audioURL(for: saved).path))
  #expect(
    !String(
      decoding: try Data(contentsOf: store.root.appendingPathComponent("clips.json")), as: UTF8.self
    ).contains("private"))
}

@Test @MainActor func corruptIndexIsNotResetAndOrphansAreRecovered() throws {
  let dir = temporary()
  defer { try? FileManager.default.removeItem(at: dir) }
  let store = try ClipStore(root: dir)
  let orphan = try fixture(in: dir)
  _ = try ClipStore(root: dir)
  #expect(!FileManager.default.fileExists(atPath: orphan.path))
  let index = store.root.appendingPathComponent("clips.json")
  try Data("broken".utf8).write(to: index)
  #expect(throws: (any Error).self) { try ClipStore(root: dir) }
  #expect(try String(contentsOf: index, encoding: .utf8) == "broken")
}

@Test @MainActor func staleResultAfterDeletion() async throws {
  let dir = temporary()
  defer { try? FileManager.default.removeItem(at: dir) }
  let source = try fixture(in: dir)
  let store = try ClipStore(root: dir.appendingPathComponent("managed"))
  let engine = DeferredTranscriber()
  let session = PracticeSession(store: store, recorder: FakeRecorder(), transcriber: engine)
  session.importAudio(source)
  try await until { await engine.ready() }
  session.deleteAll()
  await engine.succeed(Recognition(text: "must never return"))
  try await Task.sleep(for: .milliseconds(20))
  #expect(session.clips.isEmpty)
  #expect(!session.processing)
}

@Test @MainActor func varietyChangeRejectsOldWork() async throws {
  let dir = temporary()
  defer { try? FileManager.default.removeItem(at: dir) }
  let source = try fixture(in: dir)
  let engine = DeferredTranscriber()
  let session = PracticeSession(
    store: try ClipStore(root: dir.appendingPathComponent("managed")), recorder: FakeRecorder(),
    transcriber: engine)
  session.importAudio(source)
  try await until { await engine.ready() }
  session.setVariety(.british)
  await engine.succeed(Recognition(text: "old reference"))
  try await Task.sleep(for: .milliseconds(20))
  #expect(session.selected?.rawRecognition == "")
  #expect(session.selected?.variety == .british)
}

@Test @MainActor func correctionsAndRetryKeepIntentSeparate() async throws {
  let dir = temporary()
  defer { try? FileManager.default.removeItem(at: dir) }
  let source = try fixture(in: dir)
  let store = try ClipStore(root: dir.appendingPathComponent("managed"))
  let engine = DeferredTranscriber()
  let session = PracticeSession(store: store, recorder: FakeRecorder(), transcriber: engine)
  session.importAudio(source)
  try await until { await engine.ready() }
  await engine.succeed(
    Recognition(text: "brother", words: [WordSegment(text: "brother", start: 0, duration: 0.5)]))
  try await until { !session.processing }
  session.editIntent("browser")
  session.confirmIntent()
  #expect(session.selected?.rawRecognition == "brother")
  #expect(session.selected?.intendedText == "browser")
  #expect(session.selected?.canUseWordTiming == false)
  let original = try #require(session.selected)
  let attempt = try store.add(from: source, variety: .american, retry: original)
  #expect(attempt.groupID == original.groupID)
  #expect(attempt.intendedText == "browser")
  #expect(attempt.intentConfirmed)
  #expect(attempt.rawRecognition.isEmpty)
}

@Test @MainActor func releaseDuringPermissionNeverRecords() async throws {
  let dir = temporary()
  defer { try? FileManager.default.removeItem(at: dir) }
  let recorder = FakeRecorder()
  recorder.waitForPermission = true
  let session = PracticeSession(
    store: try ClipStore(root: dir), recorder: recorder, transcriber: DeferredTranscriber())
  let request = Task { await session.startRecording() }
  try await until { recorder.permission != nil }
  #expect(session.requestingMicrophone)
  session.finishRecording()
  recorder.permission?.resume()
  await request.value
  #expect(!session.recording)
  #expect(!session.requestingMicrophone)
  #expect(recorder.cancelled)
  #expect(session.clips.isEmpty)
}

@Test @MainActor func cancelAndShutdownStopRecording() async throws {
  let dir = temporary()
  defer { try? FileManager.default.removeItem(at: dir) }
  let recorder = FakeRecorder()
  let session = PracticeSession(
    store: try ClipStore(root: dir), recorder: recorder, transcriber: DeferredTranscriber())
  await session.startRecording()
  #expect(session.recording)
  await session.startRecording()
  #expect(recorder.starts == 1)
  session.shutdown()
  #expect(!session.recording)
  #expect(recorder.cancelled)
  #expect(session.clips.isEmpty)
}

@Test @MainActor func failureLeavesManualPracticeAvailable() async throws {
  let dir = temporary()
  defer { try? FileManager.default.removeItem(at: dir) }
  let source = try fixture(in: dir)
  let engine = DeferredTranscriber()
  let session = PracticeSession(
    store: try ClipStore(root: dir.appendingPathComponent("managed")), recorder: FakeRecorder(),
    transcriber: engine)
  session.importAudio(source)
  try await until { await engine.ready() }
  await engine.fail()
  try await until { !session.processing }
  #expect(session.message?.contains("Settings") == true)
  session.editIntent("Please open the browser.")
  session.confirmIntent()
  #expect(session.selected?.intentConfirmed == true)
}

@Test @MainActor func intendedEditRejectsPendingRecognition() async throws {
  let dir = temporary()
  defer { try? FileManager.default.removeItem(at: dir) }
  let source = try fixture(in: dir)
  let engine = DeferredTranscriber()
  let session = PracticeSession(
    store: try ClipStore(root: dir.appendingPathComponent("managed")), recorder: FakeRecorder(),
    transcriber: engine)
  session.importAudio(source)
  try await until { await engine.ready() }
  session.editIntent("browser")
  session.confirmIntent()
  await engine.succeed(Recognition(text: "brother"))
  try await Task.sleep(for: .milliseconds(20))
  #expect(session.selected?.intendedText == "browser")
  #expect(session.selected?.rawRecognition.isEmpty == true)
}

@MainActor private final class FakeAssets: ModelAssetProviding {
  var isInstalled = false
  var wasCancelled = false
  var continuation: CheckedContinuation<Void, any Error>?
  var progressCallback: (@MainActor (Double) -> Void)?
  func installed(_ variety: ReferenceVariety) async -> Bool { isInstalled }
  func install(_ variety: ReferenceVariety, progress: @escaping @MainActor (Double) -> Void)
    async throws
  {
    progressCallback = progress
    try await withCheckedThrowingContinuation { continuation = $0 }
  }
  func cancel() { wasCancelled = true }
  func succeed() {
    isInstalled = true
    continuation?.resume()
    continuation = nil
  }
  func fail() {
    continuation?.resume(throwing: PracticeError.storage)
    continuation = nil
  }
}

@Test @MainActor func modelFailureAndRetry() async throws {
  let provider = FakeAssets()
  let setup = ModelSetup(provider: provider)
  await setup.check(.american)
  #expect(!setup.ready)
  setup.install(.american)
  try await until { provider.continuation != nil }
  provider.progressCallback?(0.5)
  #expect(setup.fraction == 0.5)
  provider.fail()
  try await until { !setup.downloading }
  #expect(setup.error != nil)
  #expect(!setup.ready)
  setup.install(.american)
  try await until { provider.continuation != nil }
  provider.succeed()
  try await until { setup.ready }
  #expect(!setup.downloading)
  #expect(setup.error == nil)
}

@Test @MainActor func cancelledDownloadRejectsLateCompletionAndProgress() async throws {
  let provider = FakeAssets()
  let setup = ModelSetup(provider: provider)
  setup.install(.british)
  try await until { provider.continuation != nil }
  setup.cancel()
  #expect(provider.wasCancelled)
  #expect(!setup.downloading)
  provider.progressCallback?(1)
  provider.succeed()
  try await Task.sleep(for: .milliseconds(20))
  #expect(!setup.ready)
  #expect(setup.fraction == 0)
  #expect(setup.status.contains("cancelled"))
  await setup.check(.british)
  #expect(setup.ready)
}

@Test @MainActor func deadlineStopsRecording() async throws {
  let dir = temporary()
  defer { try? FileManager.default.removeItem(at: dir) }
  let recorder = FakeRecorder()
  let engine = DeferredTranscriber()
  let session = PracticeSession(
    store: try ClipStore(root: dir), recorder: recorder,
    transcriber: engine, recordingLimit: .milliseconds(15))
  await session.startRecording()
  #expect(session.recording)
  try await until { !session.recording }
  #expect(recorder.stops > 0)
  if await engine.ready() { await engine.fail() }
  session.shutdown()
}

@Test @MainActor func companionKeepsAllRecognizedSentencesVisible() async throws {
  let root = temporary()
  defer { try? FileManager.default.removeItem(at: root) }
  let recognizer = DeferredTranscriber()
  let session = PracticeSession(
    store: try ClipStore(root: root), recorder: FakeRecorder(), transcriber: recognizer)
  await session.startRecording(origin: "Wispr Flow")
  session.finishRecording()
  try await until { await recognizer.ready() }
  let text = "Please open the browser. We can meet tomorrow."
  let words = text.split(separator: " ").enumerated().map {
    WordSegment(text: String($0.element), start: 0.05 + Double($0.offset) * 0.1, duration: 0.09)
  }
  await recognizer.succeed(Recognition(text: text, words: words))
  try await until { !session.processing }
  #expect(session.selected?.intendedText == text)
  #expect(session.selected?.rawRecognition == text)
  #expect(session.selected?.practiceSegment == nil)
}

@Test @MainActor func olderAutomaticExcerptsExpandWithoutOverwritingCorrectionsOrAudio() throws {
  let root = temporary()
  defer { try? FileManager.default.removeItem(at: root) }
  let audio = try fixture(in: root.appendingPathComponent("input"))
  let store = try ClipStore(root: root.appendingPathComponent("managed"))
  var clip = try store.add(from: audio, variety: .american)
  clip.captureSource = "Wispr Flow"
  clip.rawRecognition = "Please open the browser. We can meet tomorrow."
  clip.intendedText = "Please open the browser."
  clip.practiceSegment = WordSegment(text: clip.intendedText, start: 0.1, duration: 0.4)
  clip.intentConfirmed = true
  try store.update(clip)
  let original = try Data(contentsOf: store.audioURL(for: clip))
  var corrected = try store.add(from: audio, variety: .american)
  corrected.captureSource = "Wispr Flow"
  corrected.rawRecognition = clip.rawRecognition
  corrected.practiceSegment = clip.practiceSegment
  corrected.intendedText = "Please open the application."
  corrected.intentConfirmed = true
  try store.update(corrected)
  let session = PracticeSession(
    store: store, recorder: FakeRecorder(), transcriber: DeferredTranscriber())
  let expanded = try #require(session.clips.first { $0.id == clip.id })
  #expect(expanded.intendedText == expanded.rawRecognition)
  #expect(expanded.practiceSegment == nil)
  #expect(!expanded.intentConfirmed)
  #expect(try Data(contentsOf: store.audioURL(for: expanded)) == original)
  #expect(session.clips.first { $0.id == corrected.id } == corrected)
  var fullSentence = clip
  fullSentence.intendedText = fullSentence.rawRecognition
  fullSentence.practiceSegment = WordSegment(
    text: fullSentence.rawRecognition, start: 0, duration: 1)
  let removedRange = fullSentence.expandAutomaticExcerpt()
  #expect(removedRange)
  #expect(fullSentence.intentConfirmed)
}
