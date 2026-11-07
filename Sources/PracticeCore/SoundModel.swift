import Combine
import CryptoKit
import Foundation

public enum SoundModelFiles {
  public static let revision = "6d4ca8853c7218ee12c0707b3ccde16310551bc3"
  public static let entries = [
    (
      "phonemes.onnx", 355_431_730,
      "c489e989db885c2c73cce4fa4fe38c4c78e49d17983fd1873a64f252ef18da10"
    ),
    ("vocab.json", 4637, "d732ab2456c0c017930001dc9af0b41b3b93d25b2eb9740bf9d925508d7d87d0"),
  ]
  public static var root: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("PhraseLilt/SoundModel", isDirectory: true)
  }
  public static var model: URL { root.appendingPathComponent("phonemes.onnx") }
  public static var vocabulary: URL { root.appendingPathComponent("vocab.json") }
  public static var installed: Bool {
    entries.allSatisfy {
      FileManager.default.fileExists(atPath: root.appendingPathComponent($0.0).path)
    }
  }
  public static func verify() throws {
    for (name, size, hash) in entries {
      try verify(root.appendingPathComponent(name), size: size, hash: hash)
    }
  }
  public static func verify(_ url: URL, size: Int, hash: String) throws {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    guard attributes[.type] as? FileAttributeType == .typeRegular,
      (attributes[.size] as? NSNumber)?.intValue == size
    else { throw PracticeError.modelsMissing }
    let data = try Data(contentsOf: url, options: .mappedIfSafe)
    guard SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == hash else {
      throw PracticeError.modelsMissing
    }
  }
}

private final class DownloadProgress: NSObject, URLSessionDownloadDelegate {
  let maximumBytes: Int64
  let update: @Sendable (Double) -> Void
  init(maximumBytes: Int64, update: @escaping @Sendable (Double) -> Void) {
    self.maximumBytes = maximumBytes
    self.update = update
  }
  func urlSession(
    _ session: URLSession, downloadTask: URLSessionDownloadTask,
    didFinishDownloadingTo location: URL
  ) {}
  func urlSession(
    _ session: URLSession, downloadTask: URLSessionDownloadTask,
    didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64
  ) {
    guard totalBytesWritten <= maximumBytes, totalBytesExpectedToWrite <= maximumBytes else {
      downloadTask.cancel()
      return
    }
    guard totalBytesExpectedToWrite > 0 else { return }
    update(min(1, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)))
  }
}

@MainActor public final class SoundModelSetup: ObservableObject {
  @Published public private(set) var ready = SoundModelFiles.installed
  @Published public private(set) var downloading = false
  @Published public private(set) var progress = 0.0
  @Published public private(set) var error: String?
  private var task: Task<Void, Never>?
  private var generation = UUID()
  public init() {}
  public func install() {
    guard !downloading else { return }
    let current = UUID()
    generation = current
    downloading = true
    progress = 0
    error = nil
    task = Task { [weak self] in
      do {
        let root = SoundModelFiles.root
        try FileManager.default.createDirectory(
          at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let values = try root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        )
        guard (values.volumeAvailableCapacityForImportantUsage ?? 0) > 1_000_000_000 else {
          throw PracticeError.storage
        }
        for (name, size, hash) in SoundModelFiles.entries {
          try Task.checkCancellation()
          let destination = root.appendingPathComponent(name)
          if (try? SoundModelFiles.verify(destination, size: size, hash: hash)) != nil { continue }
          let owner = self
          let delegate = DownloadProgress(maximumBytes: Int64(size)) { fraction in
            Task { @MainActor in
              guard let owner, owner.generation == current else { return }
              owner.progress = name == "phonemes.onnx" ? fraction * 0.99 : 0.99
            }
          }
          let url = URL(
            string:
              "https://huggingface.co/Alimehdi973/wav2vec2-espeak-onnx-int8/resolve/\(SoundModelFiles.revision)/\(name)"
          )!
          let (temporary, response) = try await URLSession.shared.download(
            from: url, delegate: delegate)
          defer { try? FileManager.default.removeItem(at: temporary) }
          try Task.checkCancellation()
          guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw PracticeError.modelsMissing
          }
          try SoundModelFiles.verify(temporary, size: size, hash: hash)
          try Task.checkCancellation()
          // Only complete, verified files reach the model directory. Cancellation retries the current file.
          let staged = root.appendingPathComponent(name + ".verified")
          try? FileManager.default.removeItem(at: staged)
          try FileManager.default.moveItem(at: temporary, to: staged)
          try FileManager.default.setAttributes(
            [.posixPermissions: 0o600], ofItemAtPath: staged.path)
          if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: staged)
          } else {
            try FileManager.default.moveItem(at: staged, to: destination)
          }
        }
        guard let self, self.generation == current, !Task.isCancelled else { return }
        self.ready = true
        self.downloading = false
        self.progress = 1
      } catch {
        guard let self, self.generation == current, !Task.isCancelled else { return }
        self.downloading = false
        self.error = "Download didn’t finish or pass verification. Keep 1 GB free and try again."
      }
    }
  }
  public func cancel() {
    generation = UUID()
    task?.cancel()
    task = nil
    downloading = false
    error = nil
  }
}
