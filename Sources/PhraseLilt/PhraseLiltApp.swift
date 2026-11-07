import AVFoundation
import AppKit
import Combine
import PracticeCore
import SwiftUI

@MainActor final class AppModel: NSObject, ObservableObject, NSWindowDelegate {
  static let shared = AppModel()
  private var practiceWindow: NSWindow?
  private(set) var session: PracticeSession?
  private(set) var companion: Companion?
  private(set) var startupError: String?
  let playback: Playback
  let listening: Listening
  let assets = ModelSetup(provider: SystemSpeechAssets())
  let input = InputDeviceObserver()
  private var observers: [NSObjectProtocol] = []
  private var workspaceObservers: [NSObjectProtocol] = []
  private var retentionTimer: Timer?
  private var clipsSubscription: AnyCancellable?
  private var initialized = false
  private var enableRequest = UUID()
  @Published private(set) var enabling = false
  @Published private(set) var companionEnabled = false
  @Published var followWispr = true { didSet { updateConfiguration() } }
  @Published var followGranola = false { didSet { updateConfiguration() } }
  @Published var followOtherApps = false { didSet { updateConfiguration() } }
  @Published var dailyNudge = true {
    didSet {
      UserDefaults.standard.set(dailyNudge, forKey: "dailyNudge")
      if !dailyNudge { nudgeReady = false }
    }
  }
  @Published private(set) var nudgeReady = false
  override init() {
    let playback = Playback()
    self.playback = playback
    listening = Listening(audio: playback)
    super.init()
    let defaults = UserDefaults.standard
    defaults.register(defaults: ["followWispr": true, "dailyNudge": true])
    followWispr = defaults.bool(forKey: "followWispr")
    followGranola = defaults.bool(forKey: "followGranola")
    followOtherApps = defaults.bool(forKey: "followOtherApps")
    dailyNudge = defaults.bool(forKey: "dailyNudge")
    do {
      let store = try ClipStore()
      let recorder = MicrophoneRecorder()
      let variety =
        ReferenceVariety(rawValue: defaults.string(forKey: "variety") ?? "") ?? .american
      let session = PracticeSession(
        store: store, recorder: recorder, transcriber: LocalTranscriber(), variety: variety)
      self.session = session
      let companion = Companion(session: session)
      self.companion = companion
      companion.willCapture = { [weak self] in self?.listening.stop() }
      recorder.finished = { [weak session] in session?.finishRecording() }
      recorder.interrupted = { [weak session] in
        session?.cancelRecording()
        session?.message = "Recording stopped. Check your microphone and try again."
      }
      input.start { [weak self] in
        guard let self else { return }
        self.companion?.suspend()
        self.session?.cancelRecording()
        self.listening.stop()
        self.resumeCompanion()
      }
      for name in [
        NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification,
        NSWorkspace.sessionDidResignActiveNotification,
      ] {
        workspaceObservers.append(
          NSWorkspace.shared.notificationCenter.addObserver(
            forName: name, object: nil, queue: .main
          ) { [weak self] _ in
            MainActor.assumeIsolated {
              self?.companion?.suspend()
              self?.session?.cancelRecording()
              self?.listening.stop()
            }
          })
      }
      for name in [
        NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification,
        NSWorkspace.sessionDidBecomeActiveNotification,
      ] {
        workspaceObservers.append(
          NSWorkspace.shared.notificationCenter.addObserver(
            forName: name, object: nil, queue: .main
          ) { [weak self] _ in
            MainActor.assumeIsolated { self?.resumeCompanion() }
          })
      }
      observers.append(
        NotificationCenter.default.addObserver(
          forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
          MainActor.assumeIsolated {
            self?.companion?.stop()
            self?.session?.shutdown()
            self?.listening.stop()
            self?.assets.cancel()
            self?.input.stop()
          }
        })
      session.applyRetention(days: defaults.integer(forKey: "retentionDays").nonzeroOr(7))
      retentionTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) {
        [weak self] _ in
        MainActor.assumeIsolated {
          guard let self, self.session?.recording != true else { return }
          self.listening.stop()
          self.session?.applyRetention(
            days: UserDefaults.standard.integer(forKey: "retentionDays").nonzeroOr(7))
        }
      }
      clipsSubscription = session.$clips.dropFirst().sink { [weak self] clips in
        guard let self, self.dailyNudge, let latest = clips.first, latest.captureSource != nil,
          !latest.rawRecognition.isEmpty, Calendar.current.isDateInToday(latest.createdAt)
        else { return }
        let last = UserDefaults.standard.object(forKey: "lastNudgeDate") as? Date
        if last.map({ Calendar.current.isDateInToday($0) }) != true {
          self.nudgeReady = true
          UserDefaults.standard.set(Date(), forKey: "lastNudgeDate")
        }
      }
      companionEnabled =
        defaults.bool(forKey: "companionEnabled")
        && AVAudioApplication.shared.recordPermission == .granted
      initialized = true
      updateConfiguration()
    } catch {
      startupError =
        "Couldn’t open local history. Check free space and storage access, then relaunch. Existing history has not been reset."
    }
  }
  func setCompanionEnabled(_ enabled: Bool) {
    enableRequest = UUID()
    let current = enableRequest
    if !enabled {
      enabling = false
      companionEnabled = false
      updateConfiguration()
      return
    }
    guard !companionEnabled else { return }
    enabling = true
    Task { [weak self] in
      let allowed = await AVAudioApplication.requestRecordPermission()
      guard let self, self.enableRequest == current else { return }
      self.enabling = false
      self.companionEnabled = allowed
      if !allowed { self.session?.message = PracticeError.microphone.localizedDescription }
      self.updateConfiguration()
    }
  }
  private func updateConfiguration() {
    guard initialized else { return }
    let defaults = UserDefaults.standard
    defaults.set(companionEnabled, forKey: "companionEnabled")
    defaults.set(followWispr, forKey: "followWispr")
    defaults.set(followGranola, forKey: "followGranola")
    defaults.set(followOtherApps, forKey: "followOtherApps")
    companion?.configure(
      CompanionConfiguration(
        enabled: companionEnabled, wispr: followWispr, granola: followGranola,
        other: followOtherApps))
  }
  private func resumeCompanion() {
    guard companionEnabled else { return }
    updateConfiguration()
  }
  func showPractice() {
    nudgeReady = false
    if let practiceWindow {
      practiceWindow.makeKeyAndOrderFront(nil)
      NSApp.activate()
      return
    }
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 480, height: 550),
      styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false
    )
    window.title = "PhraseLilt"
    window.minSize = NSSize(width: 360, height: 400)
    window.isReleasedWhenClosed = false
    window.delegate = self
    if let session, let companion {
      window.contentView = NSHostingView(
        rootView: ReviewView(
          model: self, session: session, companion: companion, listening: listening))
    } else {
      window.contentView = NSHostingView(
        rootView: Text(startupError ?? "Couldn’t open PhraseLilt").padding())
    }
    #if DEBUG
      if CommandLine.arguments.contains("--ui-check-small") {
        window.setContentSize(NSSize(width: 360, height: 420))
      }
    #endif
    practiceWindow = window
    window.center()
    NSApp.setActivationPolicy(.regular)
    window.makeKeyAndOrderFront(nil)
    NSApp.activate()
  }
  func windowWillClose(_ notification: Notification) {
    listening.stop()
    practiceWindow = nil
    NSApp.setActivationPolicy(.accessory)
  }
  func importAudio() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.wav, .mpeg4Audio]
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    guard panel.runModal() == .OK, let url = panel.url else { return }
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    listening.stop()
    session?.importAudio(url)
  }
  func recordPractice() {
    listening.stop()
    Task { await session?.startRecording(retry: true) }
  }
}

extension Int { func nonzeroOr(_ fallback: Int) -> Int { self == 0 ? fallback : self } }

@main struct PhraseLiltApp: App {
  @NSApplicationDelegateAdaptor(LaunchDelegate.self) private var delegate
  @StateObject private var model = AppModel.shared
  var body: some Scene {
    MenuBarExtra {
      Button("Open Practice") { model.showPractice() }
      if let session = model.session, let companion = model.companion {
        CompanionMenu(model: model, session: session, companion: companion)
      }
      SettingsLink { Text("Settings…") }
      Divider()
      Button("Quit PhraseLilt") {
        model.companion?.stop()
        model.session?.shutdown()
        NSApp.terminate(nil)
      }.keyboardShortcut("q")
    } label: {
      if let session = model.session {
        MenuStatus(model: model, session: session)
      } else {
        Label("PL", systemImage: MenuBarSymbol.unavailable.rawValue).labelStyle(.titleAndIcon).help(
          "PhraseLilt needs attention")
      }
    }.menuBarExtraStyle(.menu)
    Settings {
      if let session = model.session, let companion = model.companion {
        SettingsView(model: model, session: session, companion: companion)
      } else {
        Text(model.startupError ?? "Couldn’t open PhraseLilt").padding()
      }
    }.commands {
      CommandGroup(replacing: .appTermination) {
        Button("Quit PhraseLilt") {
          model.companion?.stop()
          model.session?.shutdown()
          NSApp.terminate(nil)
        }.keyboardShortcut("q")
      }
    }
  }
}
struct CompanionMenu: View {
  @ObservedObject var model: AppModel
  @ObservedObject var session: PracticeSession
  @ObservedObject var companion: Companion
  var body: some View {
    Text(companion.status)
    if session.recording || session.requestingMicrophone {
      Button("Stop Capture") { session.finishRecording() }
    }
    Button(model.companionEnabled ? "Pause Companion" : "Enable Companion…") {
      model.setCompanionEnabled(!model.companionEnabled)
    }
  }
}
struct MenuStatus: View {
  @ObservedObject var model: AppModel
  @ObservedObject var session: PracticeSession
  var body: some View {
    Label(
      "PL",
      systemImage: session.recording
        ? MenuBarSymbol.recording.rawValue
        : model.nudgeReady ? MenuBarSymbol.ready.rawValue : MenuBarSymbol.idle.rawValue
    )
    .labelStyle(.titleAndIcon)
    .help(
      session.recording
        ? "PhraseLilt · recording; open to stop"
        : session.processing
          ? "PhraseLilt · preparing a clip"
          : model.nudgeReady ? "PhraseLilt · practice ready" : "PhraseLilt · open practice"
    )
    .accessibilityLabel(
      session.recording
        ? "PhraseLilt recording" : model.nudgeReady ? "PhraseLilt practice ready" : "PhraseLilt")
  }
}
@MainActor final class LaunchDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    #if DEBUG
      if CommandLine.arguments.contains("--ui-check-light") {
        NSApp.appearance = NSAppearance(named: .aqua)
      }
    #endif
    let defaults = UserDefaults.standard
    if !defaults.bool(forKey: "companionDesignSeen")
      || CommandLine.arguments.contains("--show-practice")
    {
      defaults.set(true, forKey: "companionDesignSeen")
      AppModel.shared.showPractice()
    }
  }
  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool
  {
    AppModel.shared.showPractice()
    return true
  }
}
