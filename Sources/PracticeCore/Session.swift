import Combine
import Foundation

@MainActor public protocol Recording: AnyObject {
  func start(to url: URL, maximumDuration: TimeInterval) async throws
  func stop()
  func cancel()
}

@MainActor public final class PracticeSession: ObservableObject {
  @Published public private(set) var clips: [Clip] = []
  @Published public private(set) var selectedID: UUID?
  @Published public private(set) var recording = false
  @Published public private(set) var requestingMicrophone = false
  @Published public private(set) var processing = false
  @Published public var message: String?
  @Published public private(set) var caution: String?
  @Published public private(set) var retryContext: Clip?
  @Published public private(set) var variety: ReferenceVariety
  public var recordingDidEnd: ((Bool) -> Void)?
  public let store: ClipStore
  private let recorder: any Recording
  private let transcriber: any Transcribing
  private let recordingLimit: Duration
  private var work: Task<Void, Never>?
  private var deadline: Task<Void, Never>?
  private var token: WorkToken?
  private var recordRequest: UUID?
  private var recordingURL: URL?
  private var recordingOrigin: String?
  public var selected: Clip? { clips.first { $0.id == selectedID } }
  public init(
    store: ClipStore, recorder: any Recording, transcriber: any Transcribing,
    variety: ReferenceVariety = .american, recordingLimit: Duration = .seconds(59)
  ) {
    self.store = store
    self.recorder = recorder
    self.transcriber = transcriber
    self.recordingLimit = recordingLimit
    self.variety = variety
    clips = store.clips
    selectedID = clips.first?.id
  }
  public func select(_ id: UUID) {
    invalidate()
    selectedID = id
    caution = nil
    message = nil
    retryContext = nil
  }
  public func setVariety(_ value: ReferenceVariety) {
    guard variety != value else { return }
    invalidate()
    variety = value
    // Reference changes never create findings or reuse an old assessment.
    if var clip = selected {
      clip.variety = value
      clip.assessmentNote =
        "Pronunciation assessment is experimental and unavailable in this build."
      save(clip)
    }
  }
  public func startRecording(
    retry: Bool = false, origin: String? = nil, maximumDuration: TimeInterval = 59
  ) async {
    guard !recording, !requestingMicrophone else { return }
    guard clips.count < 100 else {
      message = PracticeError.historyFull.localizedDescription
      return
    }
    invalidate()
    message = nil
    caution = nil
    retryContext = retry ? selected : nil
    let request = UUID()
    recordRequest = request
    requestingMicrophone = true
    let url = store.temporaryRecordingURL()
    recordingURL = url
    recordingOrigin = origin
    do {
      try await recorder.start(to: url, maximumDuration: min(59, max(1, maximumDuration)))
      guard recordRequest == request else {
        try? FileManager.default.removeItem(at: url)
        return
      }
      requestingMicrophone = false
      recording = true
      deadline = Task { [weak self] in
        try? await Task.sleep(
          for: min(self?.recordingLimit ?? .seconds(59), .seconds(maximumDuration)))
        guard !Task.isCancelled else { return }
        self?.finishRecording()
      }
    } catch {
      try? FileManager.default.removeItem(at: url)
      guard recordRequest == request else { return }
      message = error.localizedDescription
      requestingMicrophone = false
      recordingURL = nil
    }
  }
  public func finishRecording() {
    recordRequest = nil
    deadline?.cancel()
    deadline = nil
    guard recording, let url = recordingURL else {
      cancelRecording()
      return
    }
    recorder.stop()
    recording = false
    requestingMicrophone = false
    recordingURL = nil
    defer { try? FileManager.default.removeItem(at: url) }
    let completed = add(url, retry: retryContext, origin: recordingOrigin)
    retryContext = nil
    recordingOrigin = nil
    recordingDidEnd?(completed)
  }
  public func cancelRecording() {
    let wasActive = recording || requestingMicrophone
    recordRequest = nil
    deadline?.cancel()
    deadline = nil
    recorder.cancel()
    recording = false
    requestingMicrophone = false
    retryContext = nil
    if let url = recordingURL { try? FileManager.default.removeItem(at: url) }
    recordingURL = nil
    recordingOrigin = nil
    if wasActive { recordingDidEnd?(false) }
  }
  public func importAudio(_ url: URL) {
    guard !recording, !requestingMicrophone else { return }
    add(url, retry: nil)
  }
  @discardableResult private func add(_ url: URL, retry: Clip?, origin: String? = nil) -> Bool {
    invalidate()
    message = nil
    do {
      let info = try AudioValidator.inspect(url)
      var clip = try store.add(from: url, variety: variety, retry: retry)
      clip.captureSource = origin
      try store.update(clip)
      clips = store.clips
      selectedID = clip.id
      caution = info.caution
      if info.caution == nil { analyze(clip) }
      return true
    } catch {
      message = error.localizedDescription
      return false
    }
  }
  public func retryTranscription() { if let clip = selected { analyze(clip) } }
  private func analyze(_ clip: Clip) {
    invalidate()
    processing = true
    let current = WorkToken(clipID: clip.id, variety: variety)
    token = current
    let url = store.audioURL(for: clip)
    let engine = transcriber
    work = Task { [weak self] in
      do {
        let result = try await engine.transcribe(url: url, variety: current.variety)
        guard !Task.isCancelled else { return }
        self?.accept(result, for: current)
      } catch {
        guard let self, self.token == current, !Task.isCancelled else { return }
        self.processing = false
        self.message = error.localizedDescription
      }
    }
  }
  private func accept(_ result: Recognition, for current: WorkToken) {
    guard token == current, variety == current.variety,
      var clip = store.clips.first(where: { $0.id == current.clipID })
    else { return }
    processing = false
    let mayChooseExcerpt =
      clip.intendedText.isEmpty
      || (!clip.intentConfirmed && clip.intendedText == clip.rawRecognition
        && clip.practiceSegment == nil)
    clip.rawRecognition = result.text
    clip.words = result.words.filter {
      $0.start >= 0 && $0.start + $0.duration <= clip.duration + 0.1
    }
    if mayChooseExcerpt {
      let eligible = Recognition(text: result.text, words: clip.words)
      clip.practiceSegment =
        clip.captureSource == nil ? nil : PracticeExcerpt.select(from: eligible)
      clip.intendedText = clip.practiceSegment?.text ?? result.text
    }
    if result.text.isEmpty {
      message = "Couldn’t find speech. Enter the sentence or try again in a quieter place."
    }
    save(clip)
  }
  public func editIntent(_ text: String) {
    invalidate()
    guard var clip = selected else { return }
    clip.intendedText = String(text.prefix(2000))
    clip.intentConfirmed = false
    save(clip)
  }
  public func confirmIntent() {
    guard var clip = selected,
      !clip.intendedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else { return }
    clip.intentConfirmed = true
    save(clip)
  }
  public func toggleSaved() {
    if var clip = selected {
      clip.saved.toggle()
      save(clip)
    }
  }
  public func deleteSelected() { if let id = selectedID { delete([id]) } }
  public func deleteAll() { delete(Set(clips.map(\.id))) }
  private func delete(_ ids: Set<UUID>) {
    invalidate()
    cancelRecording()
    do {
      try store.delete(ids)
      clips = store.clips
      selectedID = clips.first?.id
      message = nil
      caution = nil
    } catch {
      message = "Couldn’t delete all files. Check storage access and try Delete All again."
    }
  }
  public func applyRetention(days: Int) {
    invalidate()
    do {
      try store.retain(days: days)
      clips = store.clips
      if !clips.contains(where: { $0.id == selectedID }) { selectedID = clips.first?.id }
    } catch { message = "Couldn’t remove expired clips. Check storage access and try again." }
  }
  public func shutdown() {
    cancelRecording()
    invalidate()
  }
  public func cancelAnalysis() { invalidate() }
  private func invalidate() {
    work?.cancel()
    work = nil
    token = nil
    processing = false
  }
  private func save(_ clip: Clip) {
    do {
      try store.update(clip)
      clips = store.clips
    } catch { message = PracticeError.storage.localizedDescription }
  }
}
