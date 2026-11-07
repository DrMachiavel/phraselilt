import Combine
import Foundation

@MainActor public protocol ListeningAudio: AnyObject {
  func reference(_ text: String, variety: ReferenceVariety, voiceID: String?) async throws
  func recording(_ url: URL, segment: WordSegment?) async throws
  func stop()
}

@MainActor public final class Listening: ObservableObject {
  public enum Phase: Equatable { case idle, reference, you, done }
  @Published public private(set) var phase = Phase.idle
  @Published public private(set) var error: String?
  public var isPlaying: Bool { phase == .reference || phase == .you }
  private let audio: any ListeningAudio
  private var task: Task<Void, Never>?
  private var generation = UUID()
  public init(audio: any ListeningAudio) { self.audio = audio }
  public func playReference(text: String, variety: ReferenceVariety, voiceID: String?) {
    stop()
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    start(phase: .reference) { [audio] in
      try await audio.reference(text, variety: variety, voiceID: voiceID)
    }
  }
  public func playRecording(url: URL, segment: WordSegment? = nil) {
    stop()
    start(phase: .you) { [audio] in
      try await audio.recording(url, segment: segment)
    }
  }
  private func start(phase: Phase, operation: @escaping @MainActor () async throws -> Void) {
    let current = generation
    self.phase = phase
    task = Task { [weak self] in
      guard let self, self.generation == current, !Task.isCancelled else { return }
      do {
        try await operation()
        guard self.generation == current, !Task.isCancelled else { return }
        self.phase = .done
      } catch {
        guard self.generation == current, !Task.isCancelled else { return }
        self.phase = .idle
        self.error =
          phase == .reference
          ? "Couldn’t play the reference. Check the installed voice in Settings and try again."
          : "Couldn’t play your recording. Try importing the original again."
      }
    }
  }
  public func stop() {
    generation = UUID()
    task?.cancel()
    task = nil
    audio.stop()
    phase = .idle
    error = nil
  }
}
