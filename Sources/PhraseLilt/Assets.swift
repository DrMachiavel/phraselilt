import Foundation
import PracticeCore
import Speech

@MainActor final class SystemSpeechAssets: ModelAssetProviding {
  private var progress: Progress?
  func installed(_ variety: ReferenceVariety) async -> Bool {
    await AssetInventory.status(forModules: [LocalTranscriber.module(variety)]) == .installed
  }
  func install(_ variety: ReferenceVariety, progress update: @escaping @MainActor (Double) -> Void)
    async throws
  {
    let volume = try FileManager.default.urls(
      for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
    if let bytes = volume.volumeAvailableCapacityForImportantUsage, bytes < 2_000_000_000 {
      throw PracticeError.storage
    }
    if let request = try await AssetInventory.assetInstallationRequest(supporting: [
      LocalTranscriber.module(variety)
    ]) {
      try Task.checkCancellation()
      self.progress = request.progress
      let ticker = Task { @MainActor in
        while !Task.isCancelled {
          update(request.progress.fractionCompleted)
          try? await Task.sleep(for: .milliseconds(200))
        }
      }
      defer {
        ticker.cancel()
        if self.progress === request.progress { self.progress = nil }
      }
      try await request.downloadAndInstall()
    }
  }
  func cancel() { progress?.cancel() }
}
