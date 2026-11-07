import Foundation

public enum ReferenceVariety: String, Codable, CaseIterable, Sendable, Identifiable {
  case american = "American English"
  case british = "British English"
  public var id: String { rawValue }
  public var locale: String { self == .american ? "en-US" : "en-GB" }
  public var description: String {
    self == .american
      ? "US system voice: a General American-oriented practice reference. Regional US accents are also valid."
      : "UK system voice: a southern British-oriented practice reference. Regional UK accents are also valid."
  }
}

public struct WordSegment: Codable, Equatable, Sendable, Identifiable {
  public var id: UUID = UUID()
  public var text: String
  public var start: Double
  public var duration: Double
  public init(text: String, start: Double, duration: Double) {
    self.text = text
    self.start = start
    self.duration = duration
  }
}

public struct Recognition: Sendable {
  public var text: String
  public var words: [WordSegment]
  public init(text: String, words: [WordSegment] = []) {
    self.text = text
    self.words = words
  }
}

public struct Clip: Codable, Identifiable, Equatable, Sendable {
  public var id: UUID
  public var groupID: UUID
  public var createdAt: Date
  public var audioName: String
  public var rawRecognition = ""
  public var intendedText = ""
  public var intentConfirmed = false
  public var words: [WordSegment] = []
  public var saved = false
  public var captureSource: String?
  public var practiceSegment: WordSegment?
  public var variety: ReferenceVariety
  public var duration: Double
  // Assessment is separate from recognition and intent. No diagnostic findings are emitted in v1.
  public var assessmentNote =
    "Pronunciation assessment is experimental and unavailable in this build."
  public init(
    id: UUID = UUID(), groupID: UUID? = nil, audioName: String,
    variety: ReferenceVariety, duration: Double, createdAt: Date = Date()
  ) {
    self.id = id
    self.groupID = groupID ?? id
    self.audioName = audioName
    self.variety = variety
    self.duration = duration
    self.createdAt = createdAt
  }
  /// Expand only untouched auto-selected wording; never replace a user's correction.
  @discardableResult public mutating func expandAutomaticExcerpt() -> Bool {
    guard captureSource != nil, let excerpt = practiceSegment,
      intendedText == excerpt.text, !rawRecognition.isEmpty
    else { return false }
    if intendedText != rawRecognition { intentConfirmed = false }
    intendedText = rawRecognition
    practiceSegment = nil
    return true
  }
  public var canUseWordTiming: Bool {
    intentConfirmed && intendedText == rawRecognition && !words.isEmpty
  }
}

public struct WorkToken: Equatable, Sendable {
  public var clipID: UUID
  public var revision: UUID
  public var variety: ReferenceVariety
  public init(clipID: UUID, variety: ReferenceVariety) {
    self.clipID = clipID
    revision = UUID()
    self.variety = variety
  }
}

public enum PracticeError: LocalizedError, Equatable {
  case invalidAudio, tooLarge, tooLong, storage, historyFull, modelsMissing, unsupported, noVoice,
    microphone
  public var errorDescription: String? {
    switch self {
    case .invalidAudio:
      "Couldn’t read this audio. Import a WAV or M4A file with up to two channels."
    case .tooLarge: "This file is too large. Choose a file smaller than 25 MB."
    case .tooLong: "Choose a clip between 0.2 and 60 seconds."
    case .historyFull: "History is full. Delete a clip before recording or importing another."
    case .storage: "Couldn’t save locally. Check free disk space and try again."
    case .modelsMissing:
      "Install the English speech model in Settings, or enter the sentence yourself."
    case .unsupported:
      "Local speech recognition isn’t available on this Mac. Enter the sentence yourself."
    case .noVoice:
      "No reference voice is installed for this variety. Add one in System Settings → Accessibility → Read & Speak."
    case .microphone:
      "Microphone access is unavailable. Allow PhraseLilt in System Settings → Privacy & Security → Microphone."
    }
  }
}

public enum PracticeGuidance {
  public static let tip =
    "Listen for the stressed words in Reference, then repeat the whole sentence."
  public static let disclaimer =
    "Practice advice, not a finding about your recording. Your accent is not a defect."
}
