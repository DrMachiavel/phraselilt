import AVFoundation
import AppKit
import Combine
import PracticeCore
import SwiftUI

@MainActor final class AppModel: NSObject, ObservableObject, NSPopoverDelegate {
  static let shared = AppModel()
  private var statusItem: NSStatusItem?
  private let popover = NSPopover()
  private var statusSubscription: AnyCancellable?
  @Published var showsSettings = false
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
  func installStatusItem() {
    guard statusItem == nil else { return }
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    statusItem = item
    item.button?.title = "PL"
    item.button?.imagePosition = .imageLeading
    item.button?.target = self
    item.button?.action = #selector(togglePopover)
    popover.behavior = .transient
    popover.delegate = self
    popover.contentSize = NSSize(width: 390, height: 540)
    popover.contentViewController = NSHostingController(rootView: PopoverRoot(model: self))
    if let session {
      statusSubscription = session.$recording.combineLatest($nudgeReady).sink {
        [weak self] recording, ready in
        let symbol = recording ? MenuBarSymbol.recording : ready ? .ready : .idle
        self?.statusItem?.button?.image = NSImage(
          systemSymbolName: symbol.rawValue, accessibilityDescription: "PhraseLilt")
        self?.statusItem?.button?.toolTip =
          recording
          ? "PhraseLilt · recording; click to stop"
          : ready ? "PhraseLilt · practice ready" : "PhraseLilt · click to practise"
        self?.statusItem?.button?.setAccessibilityLabel(
          recording ? "PhraseLilt recording" : "PhraseLilt")
      }
    } else {
      item.button?.image = NSImage(
        systemSymbolName: MenuBarSymbol.unavailable.rawValue,
        accessibilityDescription: "PhraseLilt needs attention")
    }
  }
  @objc func togglePopover() {
    if popover.isShown { popover.performClose(nil) } else { showPopover() }
  }
  func showPopover(settings: Bool = false) {
    installStatusItem()
    guard let button = statusItem?.button else { return }
    nudgeReady = false
    showsSettings = settings
    popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    if !popover.isShown {
      popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }
    popover.contentViewController?.view.window?.makeKey()
    NSApp.activate()
  }
  func openSettings() {
    listening.stop()
    showsSettings = true
  }
  @objc func showSettingsFromMenu() { showPopover(settings: true) }
  func popoverDidClose(_ notification: Notification) {
    listening.stop()
    showsSettings = false
  }
  func importAudio() {
    popover.performClose(nil)
    NSApp.activate()
    defer { showPopover() }
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

struct PopoverRoot: View {
  @ObservedObject var model: AppModel
  var body: some View {
    VStack(spacing: 0) {
      if model.showsSettings {
        HStack {
          Button("Back", systemImage: "chevron.left") { model.showsSettings = false }
          Spacer()
          Text("Settings").font(.headline)
          Spacer()
        }.padding(16)
        Divider()
        if let session = model.session, let companion = model.companion {
          SettingsView(model: model, session: session, companion: companion)
        }
      } else if let session = model.session, let companion = model.companion {
        ReviewView(model: model, session: session, companion: companion, listening: model.listening)
      } else {
        Text(model.startupError ?? "Couldn’t open PhraseLilt").padding()
      }
    }.frame(width: 390, height: 540)
  }
}

@main @MainActor final class LaunchDelegate: NSObject, NSApplicationDelegate {
  static func main() {
    let application = NSApplication.shared
    let delegate = LaunchDelegate()
    application.delegate = delegate
    application.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) { application.run() }
  }
  func applicationDidFinishLaunching(_ notification: Notification) {
    #if DEBUG
      if CommandLine.arguments.contains("--ui-check-light") {
        NSApp.appearance = NSAppearance(named: .aqua)
      }
    #endif
    installAppMenu()
    AppModel.shared.installStatusItem()
    if CommandLine.arguments.contains("--show-practice") { AppModel.shared.showPopover() }
  }
  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool
  {
    AppModel.shared.showPopover()
    return true
  }
  private func installAppMenu() {
    let menu = NSMenu()
    let appItem = NSMenuItem()
    let appMenu = NSMenu()
    let settings = NSMenuItem(
      title: "Settings…", action: #selector(AppModel.showSettingsFromMenu), keyEquivalent: ",")
    settings.target = AppModel.shared
    appMenu.addItem(settings)
    appMenu.addItem(.separator())
    appMenu.addItem(
      withTitle: "Quit PhraseLilt", action: #selector(NSApplication.terminate(_:)),
      keyEquivalent: "q")
    appItem.submenu = appMenu
    menu.addItem(appItem)
    let edit = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
    let editMenu = NSMenu(title: "Edit")
    for (title, action, key) in [
      ("Undo", "undo:", "z"), ("Cut", "cut:", "x"), ("Copy", "copy:", "c"),
      ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a"),
    ] {
      editMenu.addItem(withTitle: title, action: NSSelectorFromString(action), keyEquivalent: key)
    }
    edit.submenu = editMenu
    menu.addItem(edit)
    NSApp.mainMenu = menu
  }
}
