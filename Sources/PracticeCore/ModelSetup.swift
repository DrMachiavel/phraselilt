import Combine
import Foundation

@MainActor public protocol ModelAssetProviding: AnyObject {
  func installed(_ variety: ReferenceVariety) async -> Bool
  func install(_ variety: ReferenceVariety, progress: @escaping @MainActor (Double) -> Void)
    async throws
  func cancel()
}

@MainActor public final class ModelSetup: ObservableObject {
  @Published public private(set) var status = "Checking local model…"
  @Published public private(set) var ready = false
  @Published public private(set) var downloading = false
  @Published public private(set) var fraction = 0.0
  @Published public private(set) var error: String?
  private let provider: any ModelAssetProviding
  private var operation: Task<Void, Never>?
  private var generation = UUID()
  public init(provider: any ModelAssetProviding) { self.provider = provider }
  public func check(_ variety: ReferenceVariety) async {
    guard !downloading else { return }
    let current = UUID()
    generation = current
    let installed = await provider.installed(variety)
    guard current == generation else { return }
    ready = installed
    status = ready ? "English model ready · on device" : "English model needed for transcription"
  }
  public func install(_ variety: ReferenceVariety) {
    guard !downloading else { return }
    downloading = true
    error = nil
    fraction = 0
    let current = UUID()
    generation = current
    operation = Task { [weak self] in
      guard let self else { return }
      do {
        try await self.provider.install(variety) { [weak self] value in
          guard let self, current == self.generation else { return }
          self.fraction = min(1, max(0, value.isFinite ? value : 0))
        }
        guard current == self.generation, !Task.isCancelled else { return }
        self.downloading = false
        await self.check(variety)
      } catch {
        guard current == self.generation else { return }
        self.downloading = false
        self.error =
          "Couldn’t install the model. Check your connection and free storage, then try again."
      }
    }
  }
  public func cancel() {
    generation = UUID()
    provider.cancel()
    operation?.cancel()
    operation = nil
    downloading = false
    status = "Download cancelled. Try again when you’re ready."
  }
}
