import CoreAudio
import Foundation

public struct InputProcess: Equatable, Sendable {
  public var processID: Int32
  public var bundleID: String
  public var devices: Set<UInt32>
  public init(processID: Int32, bundleID: String, devices: Set<UInt32>) {
    self.processID = processID
    self.bundleID = bundleID
    self.devices = devices
  }
}

public struct InputSnapshot: Equatable, Sendable {
  public var defaultDevice: UInt32
  public var processes: [InputProcess]
  public init(defaultDevice: UInt32, processes: [InputProcess]) {
    self.defaultDevice = defaultDevice
    self.processes = processes
  }
}

public protocol InputActivityReading: Sendable {
  func snapshot() throws -> InputSnapshot
}

public enum ActivityError: LocalizedError {
  case unavailable
  public var errorDescription: String? {
    "Couldn’t read microphone activity. Companion capture is paused. Try enabling it again."
  }
}

/// Reads public Core Audio metadata only. Does not open a microphone or register a shortcut.
public struct CoreAudioInputActivity: InputActivityReading {
  public init() {}
  private func address(
    _ selector: AudioObjectPropertySelector,
    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
  ) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(
      mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
  }
  private func number(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) throws
    -> UInt32
  {
    var address = address(selector)
    var value: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else {
      throw ActivityError.unavailable
    }
    return value
  }
  private func objects(
    _ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
  ) throws -> [UInt32] {
    var address = address(selector, scope: scope)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr,
      size <= 65_536, size % 4 == 0
    else { throw ActivityError.unavailable }
    guard size > 0 else { return [] }
    var values = [UInt32](repeating: 0, count: Int(size) / 4)
    let status = values.withUnsafeMutableBytes { bytes in
      AudioObjectGetPropertyData(object, &address, 0, nil, &size, bytes.baseAddress!)
    }
    guard status == noErr, Int(size) / 4 <= values.count else { throw ActivityError.unavailable }
    return Array(values.prefix(Int(size) / 4))
  }
  private func bundleID(_ object: AudioObjectID) -> String? {
    var address = address(kAudioProcessPropertyBundleID)
    var value: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else {
      return nil
    }
    return value?.takeRetainedValue() as String?
  }
  public func snapshot() throws -> InputSnapshot {
    let system = AudioObjectID(kAudioObjectSystemObject)
    let device = try number(system, kAudioHardwarePropertyDefaultInputDevice)
    var active: [InputProcess] = []
    for object in try objects(system, kAudioHardwarePropertyProcessObjectList) {
      // A process may disappear between reading the list and its metadata. Never keep stale activity.
      guard let running = try? number(object, kAudioProcessPropertyIsRunningInput), running != 0,
        let pid = try? number(object, kAudioProcessPropertyPID),
        let bundle = bundleID(object), !bundle.isEmpty
      else { continue }
      active.append(
        InputProcess(
          processID: Int32(bitPattern: pid), bundleID: bundle,
          devices: Set(
            (try? objects(
              object, kAudioProcessPropertyDevices,
              scope: kAudioObjectPropertyScopeInput)) ?? [])))
    }
    return InputSnapshot(defaultDevice: device, processes: active)
  }
}

public struct CaptureSource: Hashable, Sendable {
  public enum Kind: Hashable, Sendable {
    case wispr, granola
    case other(String)
  }
  public var kind: Kind
  public var device: UInt32
  public var name: String {
    switch kind {
    case .wispr: "Wispr Flow"
    case .granola: "Granola"
    case .other: "Another microphone app"
    }
  }
}

public struct CompanionConfiguration: Equatable, Sendable {
  public var enabled: Bool
  public var wispr: Bool
  public var granola: Bool
  public var other: Bool
  public init(enabled: Bool = false, wispr: Bool = true, granola: Bool = false, other: Bool = false)
  {
    self.enabled = enabled
    self.wispr = wispr
    self.granola = granola
    self.other = other
  }
  public func source(for process: InputProcess, defaultDevice: UInt32, ownPID: Int32)
    -> CaptureSource?
  {
    let id = process.bundleID.lowercased()
    guard enabled, process.processID != ownPID, defaultDevice != 0,
      process.devices.contains(defaultDevice),
      id != "io.github.drmachiavel.phraselilt", !id.hasPrefix("io.github.drmachiavel.phraselilt.")
    else { return nil }
    let kind: CaptureSource.Kind
    if id == "com.electron.wispr-flow" || id.hasPrefix("com.electron.wispr-flow.") {
      guard wispr else { return nil }
      kind = .wispr
    } else if id == "ai.granola" || id.hasPrefix("ai.granola.") {
      guard granola else { return nil }
      kind = .granola
    } else {
      guard other else { return nil }
      kind = .other(id)
    }
    return CaptureSource(kind: kind, device: defaultDevice)
  }
}

/// Pure edge/ownership policy. Every source must become idle before it can trigger again.
public struct CapturePolicy {
  public enum Action: Equatable {
    case none
    case start(CaptureSource)
    case finish, cancel
  }
  public private(set) var owner: CaptureSource?
  public private(set) var active: Set<CaptureSource> = []
  private var blocked: Set<CaptureSource> = []
  private var baselineNeeded = true
  private var defaultDevice: UInt32?
  public init() {}
  public mutating func reset() { self = CapturePolicy() }
  public mutating func recordingEnded() {
    owner = nil
    blocked.formUnion(active)
  }
  public mutating func consume(_ sources: Set<CaptureSource>, defaultDevice device: UInt32)
    -> Action
  {
    active = sources
    if let old = defaultDevice, old != device {
      let wasRecording = owner != nil
      reset()
      defaultDevice = device
      active = sources
      blocked = sources
      baselineNeeded = false
      return wasRecording ? .cancel : .none
    }
    defaultDevice = device
    blocked.formIntersection(sources)
    if baselineNeeded {
      baselineNeeded = false
      blocked = sources
      return .none
    }
    if let owner {
      if sources.contains(owner) { return .none }
      self.owner = nil
      blocked.formUnion(sources)
      return .finish
    }
    guard let source = sources.subtracting(blocked).sorted(by: { $0.name < $1.name }).first else {
      return .none
    }
    owner = source
    blocked.formUnion(sources)
    return .start(source)
  }
}
