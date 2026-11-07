import AVFoundation
import Foundation

public struct AudioInspection: Sendable {
  public let duration: Double
  public let rms: Double
  public let clippedFraction: Double
  public var caution: String? {
    if rms < 0.001 { return "Very little sound was detected. Check your microphone and try again." }
    if clippedFraction > 0.02 {
      return "The recording may be distorted. Move back from the microphone and try again."
    }
    return nil
  }
}

public enum AudioValidator {
  public static let maxBytes = 25_000_000
  public static let maxDuration = 60.0
  public static func inspect(_ url: URL) throws -> AudioInspection {
    guard ["wav", "m4a"].contains(url.pathExtension.lowercased()) else {
      throw PracticeError.invalidAudio
    }
    let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
    guard attrs[.type] as? FileAttributeType == .typeRegular else {
      throw PracticeError.invalidAudio
    }
    guard let size = attrs[.size] as? NSNumber, size.intValue <= maxBytes else {
      throw PracticeError.tooLarge
    }
    let file: AVAudioFile
    do { file = try AVAudioFile(forReading: url) } catch { throw PracticeError.invalidAudio }
    let format = file.processingFormat
    guard format.sampleRate >= 8000, format.sampleRate <= 192000,
      (1...2).contains(format.channelCount), file.length > 0
    else { throw PracticeError.invalidAudio }
    let duration = Double(file.length) / format.sampleRate
    guard duration >= 0.2, duration <= maxDuration else { throw PracticeError.tooLong }
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096) else {
      throw PracticeError.invalidAudio
    }
    var total = 0
    var clipped = 0
    var squares = 0.0
    while file.framePosition < file.length {
      try file.read(into: buffer)
      guard buffer.frameLength > 0, let channels = buffer.floatChannelData else {
        throw PracticeError.invalidAudio
      }
      for channel in 0..<Int(format.channelCount) {
        for frame in 0..<Int(buffer.frameLength) {
          let value = Double(channels[channel][frame])
          guard value.isFinite else { throw PracticeError.invalidAudio }
          squares += value * value
          total += 1
          if abs(value) >= 0.99 { clipped += 1 }
        }
      }
    }
    return AudioInspection(
      duration: duration, rms: sqrt(squares / Double(max(1, total))),
      clippedFraction: Double(clipped) / Double(max(1, total)))
  }
}

@MainActor public final class ClipStore {
  public let root: URL
  public private(set) var clips: [Clip] = []
  private let fm = FileManager.default
  public init(root: URL? = nil) throws {
    self.root =
      root
      ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("PhraseLilt", isDirectory: true)
    try fm.createDirectory(
      at: self.root, withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
    try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: self.root.path)
    let index = self.root.appendingPathComponent("clips.json")
    if fm.fileExists(atPath: index.path) {
      let data = try Data(contentsOf: index)
      guard data.count < 10_000_000 else { throw PracticeError.storage }
      clips = try JSONDecoder().decode([Clip].self, from: data)
      guard clips.count <= 100, Set(clips.map(\.id)).count == clips.count,
        clips.allSatisfy({
          $0.audioName == "\($0.id.uuidString).wav" || $0.audioName == "\($0.id.uuidString).m4a"
        })
      else { throw PracticeError.storage }
    }
    // Recover interrupted imports/recordings and delete files not referenced by the index.
    let names = Set(clips.map(\.audioName))
    for file in try fm.contentsOfDirectory(at: self.root, includingPropertiesForKeys: nil) {
      if ["wav", "m4a"].contains(file.pathExtension), !names.contains(file.lastPathComponent) {
        try fm.removeItem(at: file)
      }
    }
  }
  public func audioURL(for clip: Clip) -> URL { root.appendingPathComponent(clip.audioName) }
  public func temporaryRecordingURL() -> URL {
    root.appendingPathComponent("\(UUID().uuidString).m4a")
  }
  public func add(from source: URL, variety: ReferenceVariety, retry: Clip? = nil) throws -> Clip {
    guard clips.count < 100 else { throw PracticeError.historyFull }
    let inspection = try AudioValidator.inspect(source)
    let id = UUID()
    let name = "\(id.uuidString).\(source.pathExtension.lowercased())"
    let dest = root.appendingPathComponent(name)
    try fm.copyItem(at: source, to: dest)
    do {
      try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: dest.path)
      var clip = Clip(
        id: id, groupID: retry?.groupID, audioName: name, variety: variety,
        duration: inspection.duration)
      if let retry {
        clip.intendedText = retry.intendedText
        clip.intentConfirmed = retry.intentConfirmed
      }
      let next = [clip] + clips
      try persist(next)
      clips = next
      return clip
    } catch {
      try? fm.removeItem(at: dest)
      throw error
    }
  }
  public func update(_ clip: Clip) throws {
    guard let index = clips.firstIndex(where: { $0.id == clip.id }) else { return }
    var next = clips
    next[index] = clip
    try persist(next)
    clips = next
  }
  public func delete(_ ids: Set<UUID>) throws {
    // Remove audio before dropping metadata so a disk failure remains recoverable.
    for clip in clips where ids.contains(clip.id) {
      let url = audioURL(for: clip)
      if fm.fileExists(atPath: url.path) { try fm.removeItem(at: url) }
    }
    let next = clips.filter { !ids.contains($0.id) }
    try persist(next)
    clips = next
  }
  public func retain(days: Int, now: Date = Date()) throws {
    let threshold = now.addingTimeInterval(-Double(max(1, days)) * 86400)
    try delete(Set(clips.filter { !$0.saved && $0.createdAt < threshold }.map(\.id)))
  }
  private func persist(_ values: [Clip]) throws {
    let url = root.appendingPathComponent("clips.json")
    try JSONEncoder().encode(values).write(to: url, options: .atomic)
    try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
  }
}
