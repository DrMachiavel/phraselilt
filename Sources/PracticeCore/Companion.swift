import Combine
import Foundation

@MainActor public final class Companion: ObservableObject {
  @Published public private(set) var configuration = CompanionConfiguration()
  @Published public private(set) var status = "Companion off"
  @Published public private(set) var error: String?
  @Published public private(set) var sourceName: String?
  @Published public private(set) var lastStartDelay: Double?
  @Published public private(set) var completedCaptures = 0
  public var willCapture: (() -> Void)?
  private let reader: any InputActivityReading
  private let session: PracticeSession
  private let ownPID: Int32
  private let interval: Duration
  private let automaticPolling: Bool
  private var ownerMissingSince: ContinuousClock.Instant?
  private var policy = CapturePolicy()
  private var loop: Task<Void, Never>?
  private var startTask: Task<Void, Never>?
  private var generation = UUID()
  private var enabledAtLeastOnce = false
  private var ownsRecording = false
  public init(
    session: PracticeSession, reader: any InputActivityReading = CoreAudioInputActivity(),
    ownPID: Int32 = ProcessInfo.processInfo.processIdentifier,
    interval: Duration = .milliseconds(100), automaticPolling: Bool = true
  ) {
    self.session = session
    self.reader = reader
    self.ownPID = ownPID
    self.interval = interval
    self.automaticPolling = automaticPolling
    session.recordingDidEnd = { [weak self] completed in self?.recordingEnded(completed: completed)
    }
  }
  public func configure(_ value: CompanionConfiguration) {
    stop()
    configuration = value
    error = nil
    lastStartDelay = nil
    guard value.enabled else {
      status = "Companion off"
      return
    }
    status = "Waiting for your next dictation"
    enabledAtLeastOnce = false
    guard automaticPolling else { return }
    loop = Task { [weak self] in
      while !Task.isCancelled {
        guard let self else { return }
        self.poll()
        try? await Task.sleep(for: self.interval)
      }
    }
  }
  public func stop() {
    generation = UUID()
    loop?.cancel()
    loop = nil
    startTask?.cancel()
    startTask = nil
    if ownsRecording { session.cancelRecording() }
    ownsRecording = false
    sourceName = nil
    policy.reset()
    ownerMissingSince = nil
  }
  public func suspend() {
    stop()
    status = "Companion paused until the session resumes"
  }
  public func poll() {
    guard configuration.enabled else { return }
    do { consume(try reader.snapshot()) } catch {
      stop()
      status = "Companion paused"
      self.error = ActivityError.unavailable.localizedDescription
    }
  }
  public func consume(_ snapshot: InputSnapshot) {
    guard configuration.enabled else { return }
    var sources = Set(
      snapshot.processes.compactMap {
        configuration.source(for: $0, defaultDevice: snapshot.defaultDevice, ownPID: ownPID)
      })
    if let owner = policy.owner, owner.device == snapshot.defaultDevice, !sources.contains(owner) {
      if ownerMissingSince == nil { ownerMissingSince = .now }
      if ownerMissingSince!.duration(to: .now) < .milliseconds(200) { sources.insert(owner) }
    } else {
      ownerMissingSince = nil
    }
    let action = policy.consume(sources, defaultDevice: snapshot.defaultDevice)
    if !enabledAtLeastOnce {
      enabledAtLeastOnce = true
      if !sources.isEmpty { status = "An app is already recording. Waiting for its next session." }
    }
    switch action {
    case .none: break
    case .start(let source):
      guard !session.recording, !session.requestingMicrophone else {
        policy.recordingEnded()
        return
      }
      let current = generation
      let detected = ContinuousClock.now
      error = nil
      ownsRecording = true
      sourceName = source.name
      status = "Capturing alongside \(source.name)"
      willCapture?()
      startTask = Task { [weak self] in
        guard let self, self.generation == current, self.policy.owner == source, !Task.isCancelled
        else { return }
        await self.session.startRecording(origin: source.name, maximumDuration: 30)
        guard self.generation == current, self.policy.owner == source, !Task.isCancelled else {
          return
        }
        let elapsed = detected.duration(to: .now).components
        self.lastStartDelay = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
        if !self.session.recording {
          self.ownsRecording = false
          self.policy.recordingEnded()
          self.sourceName = nil
          self.status = "Couldn’t capture this session"
          self.error = self.session.message
        }
      }
    case .finish:
      startTask?.cancel()
      startTask = nil
      if ownsRecording { session.finishRecording() }
    case .cancel:
      generation = UUID()
      startTask?.cancel()
      startTask = nil
      if ownsRecording { session.cancelRecording() }
      status = "Input changed. Waiting for the next dictation."
    }
  }
  private func recordingEnded(completed: Bool) {
    guard ownsRecording else { return }
    ownsRecording = false
    sourceName = nil
    policy.recordingEnded()
    if completed {
      completedCaptures += 1
      status = "Practice clip ready"
    } else {
      status = configuration.enabled ? "Waiting for your next dictation" : "Companion off"
    }
  }
}
