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
  public func play(
    text: String, url: URL, variety: ReferenceVariety, voiceID: String?, segment: WordSegment? = nil
  ) {
    stop()
    error = nil
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    let current = generation
    phase = .reference
    task = Task { [weak self] in
      guard let self, self.generation == current, !Task.isCancelled else { return }
      do {
        try await self.audio.reference(text, variety: variety, voiceID: voiceID)
        guard self.generation == current, !Task.isCancelled else { return }
        self.phase = .you
        try await self.audio.recording(url, segment: segment)
        guard self.generation == current, !Task.isCancelled else { return }
        self.phase = .done
      } catch {
        guard self.generation == current, !Task.isCancelled else { return }
        self.phase = .idle
        self.error = "Couldn’t finish playback. Check the installed reference voice and try again."
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
