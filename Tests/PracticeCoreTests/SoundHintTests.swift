import Foundation
import Testing

@testable import PracticeCore

private func soundClip() -> Clip {
  var clip = Clip(audioName: "unused.wav", variety: .american, duration: 2)
  clip.rawRecognition = "Think three things."
  clip.intendedText = clip.rawRecognition
  clip.intentConfirmed = true
  clip.words = [
    WordSegment(text: "Think", start: 0.2, duration: 0.4),
    WordSegment(text: "three", start: 0.7, duration: 0.4),
    WordSegment(text: "things.", start: 1.2, duration: 0.5),
  ]
  return clip
}

@Test func soundCandidatesUseProvisionalWordingAndIndividualWordTiming() {
  var clip = soundClip()
  #expect(SoundHintRules.candidates(for: clip).map(\.word) == ["think", "three", "things"])
  clip.intentConfirmed = false
  #expect(SoundHintRules.candidates(for: clip).count == 3)
  #expect(!clip.intentConfirmed)
  clip.intentConfirmed = true
  clip.intendedText = "Sink all three things."
  #expect(SoundHintRules.candidates(for: clip).isEmpty)
  clip.intendedText = clip.rawRecognition
  clip.words = [WordSegment(text: clip.rawRecognition, start: 0.2, duration: 1.5)]
  #expect(SoundHintRules.candidates(for: clip).isEmpty)
  clip = soundClip()
  clip.variety = .british
  #expect(SoundHintRules.candidates(for: clip).isEmpty)
}

@Test func unrelatedCompoundRunDoesNotDiscardIndividuallyTimedTarget() {
  var clip = soundClip()
  clip.intendedText = "I think my mother-in-law is here."
  clip.rawRecognition = clip.intendedText
  clip.duration = 4
  clip.words = [
    WordSegment(text: "I", start: 0.1, duration: 0.1),
    WordSegment(text: "think", start: 0.25, duration: 0.3),
    WordSegment(text: "my", start: 0.6, duration: 0.2),
    WordSegment(text: "mother-in-law", start: 0.9, duration: 1.1),
    WordSegment(text: "is", start: 2.1, duration: 0.2),
    WordSegment(text: "here.", start: 2.4, duration: 0.4),
  ]
  clip.practiceSegment = WordSegment(text: clip.intendedText, start: 0.1, duration: 2.7)
  clip.intentConfirmed = false
  let candidates = SoundHintRules.candidates(for: clip)
  #expect(candidates.map(\.word) == ["think"])
  #expect(candidates.first?.range == NSRange(location: 2, length: 2))
  clip.words[1].text = "think three"
  #expect(SoundHintRules.candidates(for: clip).isEmpty)
}

@Test func sameWordCountCorrectionUsesAudioWindowsWithoutTreatingMismatchAsEvidence() {
  var clip = soundClip()
  clip.rawRecognition = "Sink three things."
  clip.words[0].text = "Sink"
  let candidates = SoundHintRules.candidates(for: clip)
  #expect(candidates.first?.word == "think")
  #expect(candidates.first.flatMap { SoundHintRules.hint(for: $0, phones: []) } == nil)
}

@Test func soundHintsRequireCompetingAcousticsAndMatchingContext() throws {
  let candidate = try #require(SoundHintRules.candidates(for: soundClip()).first)
  let tail = [
    AcousticPhone(sound: "ɪ", peak: 0.9, targetPeak: 0, time: 0.3),
    AcousticPhone(sound: "ŋ", peak: 0.9, targetPeak: 0, time: 0.4),
    AcousticPhone(sound: "k", peak: 0.9, targetPeak: 0, time: 0.5),
  ]
  func onset(_ sound: String, _ peak: Float = 0.95, _ target: Float = 0.01, _ time: Double = 0.21)
    -> AcousticPhone
  {
    AcousticPhone(sound: sound, peak: peak, targetPeak: target, time: time)
  }
  #expect(
    SoundHintRules.hint(for: candidate, phones: [onset("f")] + tail)?.range
      == NSRange(location: 0, length: 2))
  #expect(SoundHintRules.hint(for: candidate, phones: [onset("θ")] + tail) == nil)
  #expect(SoundHintRules.hint(for: candidate, phones: [onset("f", 0.5)] + tail) == nil)
  #expect(SoundHintRules.hint(for: candidate, phones: [onset("f", 0.95, 0.3)] + tail) == nil)
  #expect(SoundHintRules.hint(for: candidate, phones: [onset("f", 0.95, 0.01, 1)] + tail) == nil)
  #expect(SoundHintRules.hint(for: candidate, phones: tail) == nil)
  #expect(SoundHintRules.hint(for: candidate, phones: [onset("f")] + tail.dropLast()) == nil)
}

private actor DelayedSoundAssessor: SoundAssessing {
  var pending: CheckedContinuation<[SoundHint], any Error>?
  func assess(url: URL, candidates: [SoundCandidate]) async throws -> [SoundHint] {
    try await withCheckedThrowingContinuation { pending = $0 }
  }
  func ready() -> Bool { pending != nil }
  func finish() {
    pending?.resume(returning: [SoundHint(range: NSRange(location: 0, length: 2), word: "think")])
    pending = nil
  }
}

@Test @MainActor func soundCancellationRejectsLateFindings() async throws {
  let assessor = DelayedSoundAssessor()
  let hints = SoundHints(assessor: assessor)
  hints.update(
    clip: soundClip(), url: URL(fileURLWithPath: "/unused.wav"), variety: .american, ready: true,
    busy: false)
  for _ in 0..<100 {
    if await assessor.ready() { break }
    try await Task.sleep(for: .milliseconds(5))
  }
  #expect(await assessor.ready())
  hints.cancel()
  await assessor.finish()
  try await Task.sleep(for: .milliseconds(20))
  #expect(hints.hints.isEmpty)
  #expect(!hints.running)
  #expect(hints.status == nil)
}

private actor CountingSoundAssessor: SoundAssessing {
  var calls = 0
  func assess(url: URL, candidates: [SoundCandidate]) async throws -> [SoundHint] {
    calls += 1
    return [SoundHint(range: candidates[0].range, word: candidates[0].word)]
  }
  func count() -> Int { calls }
}

@Test @MainActor func automaticSoundChecksWaitForPreparationAndDeduplicateUnchangedAudio()
  async throws
{
  let assessor = CountingSoundAssessor()
  let hints = SoundHints(assessor: assessor)
  var clip = soundClip()
  clip.intentConfirmed = false
  let url = URL(fileURLWithPath: "/unused.wav")
  hints.update(clip: clip, url: url, variety: .american, ready: true, busy: true)
  #expect(await assessor.count() == 0)
  hints.update(clip: clip, url: url, variety: .american, ready: true, busy: false)
  for _ in 0..<100 {
    if !hints.running { break }
    try await Task.sleep(for: .milliseconds(5))
  }
  #expect(await assessor.count() == 1)
  #expect(!hints.hints.isEmpty)
  #expect(!clip.intentConfirmed)
  clip.saved = true
  clip.intentConfirmed = true
  hints.update(clip: clip, url: url, variety: .american, ready: true, busy: false)
  #expect(await assessor.count() == 1)
  #expect(hints.matches(clip: clip, variety: .american))
  #expect(!hints.matches(clip: clip, variety: .british))
  var replacement = clip
  replacement.id = UUID()
  #expect(!hints.matches(clip: replacement, variety: .american))
  hints.update(clip: replacement, url: url, variety: .american, ready: false, busy: false)
  #expect(hints.hints.isEmpty)
  hints.update(clip: replacement, url: url, variety: .american, ready: true, busy: false)
  for _ in 0..<100 {
    if !hints.running { break }
    try await Task.sleep(for: .milliseconds(5))
  }
  #expect(await assessor.count() == 2)
  hints.update(clip: nil, url: nil, variety: .american, ready: true, busy: false)
  #expect(hints.hints.isEmpty)
  #expect(hints.context == nil)
}

@Test func soundModelRejectsWrongSizeAndDigest() throws {
  let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: url) }
  try Data("not a model".utf8).write(to: url)
  #expect(throws: (any Error).self) { try SoundModelFiles.verify(url, size: 1, hash: "bad") }
  #expect(throws: (any Error).self) {
    try SoundModelFiles.verify(url, size: 11, hash: String(repeating: "0", count: 64))
  }
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["PHRASELILT_SOUND_EVIDENCE_DIR"] != nil))
func localAcousticSyntheticSpike() async throws {
  let root = URL(
    fileURLWithPath: try #require(
      ProcessInfo.processInfo.environment["PHRASELILT_SOUND_EVIDENCE_DIR"]))
  let assessor = LocalSoundAssessor(modelDirectory: root)
  for name in ["clear", "substituted", "british", "silence", "noise"] {
    let url = root.appendingPathComponent(name + ".wav")
    let bounds: [(String, Double, Double)] =
      name == "clear"
      ? [
        ("I", 0.02, 0.12), ("think", 0.16, 0.24), ("three", 0.42, 0.2), ("things", 0.66, 0.28),
        ("are", 0.96, 0.12), ("ready.", 1.08, 0.4),
      ]
      : [
        ("I", 0.02, 0.14), ("think", 0.18, 0.26), ("three", 0.48, 0.24), ("things", 0.82, 0.22),
        ("are", 1.06, 0.12), ("ready.", 1.18, 0.4),
      ]
    var clip = Clip(
      audioName: "unused.wav", variety: .american,
      duration: try AudioValidator.inspect(url).duration)
    // These are known synthetic timings, not an ASR result or human-reviewed evaluation.
    clip.rawRecognition = "I think three things are ready."
    clip.intendedText = clip.rawRecognition
    clip.intentConfirmed = true
    clip.words = bounds.map { WordSegment(text: $0.0, start: $0.1, duration: $0.2) }
    let candidates = SoundHintRules.candidates(for: clip)
    let start = Date()
    let hints = try await assessor.assess(url: url, candidates: candidates)
    print(
      "Synthetic \(name): \(candidates.count) candidates, \(hints.count) hints, \(Date().timeIntervalSince(start)) seconds"
    )
    if name != "substituted" { #expect(hints.isEmpty) }
    if name == "substituted" { #expect(hints.map(\.word).contains("think")) }
  }
}

private struct NoSoundFindings: SoundAssessing {
  func assess(url: URL, candidates: [SoundCandidate]) async throws -> [SoundHint] { [] }
}

@Test @MainActor func visibleSummaryDistinguishesNoHintFromNoCoverage() async throws {
  let hints = SoundHints(assessor: NoSoundFindings())
  let clip = soundClip()
  let url = URL(fileURLWithPath: "/unused.wav")
  hints.update(clip: clip, url: url, variety: .american, ready: true, busy: false)
  #expect(hints.summary == "Checking sounds…")
  for _ in 0..<100 {
    if !hints.running { break }
    try await Task.sleep(for: .milliseconds(5))
  }
  #expect(hints.summary == "Checked 3 words · no comparison hint")
  #expect(hints.hints.isEmpty)
  hints.update(clip: clip, url: url, variety: .british, ready: true, busy: false)
  #expect(hints.summary == "Sound hints don’t support this reference yet")
  var unsupported = clip
  unsupported.intendedText = "Say hello."
  hints.update(clip: unsupported, url: url, variety: .american, ready: true, busy: false)
  #expect(hints.summary == "No supported words with usable timing")
  hints.cancel()
  #expect(hints.summary == nil)
}
