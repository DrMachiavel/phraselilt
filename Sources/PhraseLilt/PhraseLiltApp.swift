import AppKit
import PracticeCore
import SwiftUI

@MainActor final class AppModel: NSObject, ObservableObject, NSWindowDelegate {
  static let shared = AppModel()
  private var practiceWindow: NSWindow?
  private(set) var session: PracticeSession?
  private(set) var startupError: String?
  let playback = Playback()
  let assets = ModelSetup(provider: SystemSpeechAssets())
  let shortcut = HoldShortcut()
  let input = InputDeviceObserver()
  private var observers: [NSObjectProtocol] = []
  private var retentionTimer: Timer?
  @Published var shortcutError: String?
  override init() {
    super.init()
    do {
      let store = try ClipStore()
      let recorder = MicrophoneRecorder()
      let variety =
        ReferenceVariety(rawValue: UserDefaults.standard.string(forKey: "variety") ?? "")
        ?? .american
      let session = PracticeSession(
        store: store, recorder: recorder, transcriber: LocalTranscriber(), variety: variety)
      self.session = session
      startupError = nil
      recorder.interrupted = { [weak session] in
        session?.cancelRecording()
        session?.message = "Recording stopped. Check your microphone and try again."
      }
      shortcut.pressed = { [weak self, weak session] in
        Task { @MainActor in
          guard let self, self.shortcut.held else { return }
          self.playback.stop()
          await session?.startRecording()
        }
      }
      shortcut.released = { [weak session] in session?.finishRecording() }
      configureShortcut(
        key: UInt32(UserDefaults.standard.integer(forKey: "shortcutKey").nonzeroOr(49)))
      input.start { [weak session] in
        guard let session, session.recording || session.requestingMicrophone else { return }
        session.cancelRecording()
        session.message = "Input device changed. Start a new recording when you’re ready."
      }
      for name in [
        NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification,
        NSWorkspace.sessionDidResignActiveNotification,
      ] {
        observers.append(
          NSWorkspace.shared.notificationCenter.addObserver(
            forName: name, object: nil, queue: .main
          ) { [weak self] _ in
            MainActor.assumeIsolated {
              self?.session?.cancelRecording()
              self?.playback.stop()
              self?.shortcut.release()
            }
          })
      }
      observers.append(
        NotificationCenter.default.addObserver(
          forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
          MainActor.assumeIsolated {
            self?.session?.shutdown()
            self?.playback.stop()
            self?.assets.cancel()
            self?.shortcut.unregister()
            self?.input.stop()
          }
        })
      session.applyRetention(
        days: UserDefaults.standard.integer(forKey: "retentionDays").nonzeroOr(7))
      retentionTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) {
        [weak session] _ in
        MainActor.assumeIsolated {
          session?.applyRetention(
            days: UserDefaults.standard.integer(forKey: "retentionDays").nonzeroOr(7))
        }
      }
    } catch {
      session = nil
      startupError =
        "Couldn’t open local history. Check storage permissions and free space, then relaunch. Existing files have not been reset."
    }
  }
  func configureShortcut(key: UInt32) {
    shortcutError =
      shortcut.register(key: key)
      ? nil : "This shortcut is unavailable. Choose another key, or use Record."
  }
  func showPractice() {
    if let practiceWindow {
      practiceWindow.makeKeyAndOrderFront(nil)
      NSApp.activate()
      return
    }
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 560, height: 620),
      styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false
    )
    window.title = "Practice — PhraseLilt"
    window.minSize = NSSize(width: 380, height: 420)
    window.isReleasedWhenClosed = false
    window.delegate = self
    if let session {
      window.contentView = NSHostingView(
        rootView: ReviewView(model: self, session: session, compact: false))
    } else {
      window.contentView = NSHostingView(
        rootView: Text(startupError ?? "Couldn’t open PhraseLilt").padding())
    }
    #if DEBUG
      if CommandLine.arguments.contains("--ui-check-small") {
        window.setContentSize(NSSize(width: 380, height: 420))
      }
    #endif
    practiceWindow = window
    window.center()
    NSApp.setActivationPolicy(.regular)
    window.makeKeyAndOrderFront(nil)
    NSApp.activate()
  }
  func windowWillClose(_ notification: Notification) {
    playback.stop()
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
    playback.stop()
    session?.importAudio(url)
  }
}

extension Int { func nonzeroOr(_ fallback: Int) -> Int { self == 0 ? fallback : self } }

@main struct PhraseLiltApp: App {
  @NSApplicationDelegateAdaptor(LaunchDelegate.self) private var delegate
  @StateObject private var model = AppModel.shared
  var body: some Scene {
    MenuBarExtra {
      if let session = model.session {
        ReviewView(model: model, session: session, compact: true)
      } else {
        Text(model.startupError ?? "Couldn’t open PhraseLilt").padding()
      }
    } label: {
      if let session = model.session {
        MenuStatus(session: session)
      } else {
        Label("PhraseLilt", systemImage: "exclamationmark.bubble")
      }
    }.menuBarExtraStyle(.window)
    Settings {
      if let session = model.session {
        SettingsView(model: model, session: session)
      } else {
        Text(model.startupError ?? "Couldn’t open PhraseLilt").padding()
      }
    }.commands {
      CommandGroup(replacing: .appTermination) {
        Button("Quit PhraseLilt") {
          model.session?.shutdown()
          NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
      }
    }
  }
}

struct MenuStatus: View {
  @ObservedObject var session: PracticeSession
  var body: some View {
    Label(
      session.recording
        ? "Recording · Stop in PhraseLilt"
        : session.processing ? "Processing" : session.selected != nil ? "Clip ready" : "PhraseLilt",
      systemImage: session.recording
        ? "record.circle.fill"
        : session.processing
          ? "waveform" : session.selected != nil ? "checkmark.bubble" : "waveform.bubble")
  }
}

@MainActor final class LaunchDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    #if DEBUG
      if CommandLine.arguments.contains("--ui-check-light") {
        NSApp.appearance = NSAppearance(named: .aqua)
      }
    #endif
    AppModel.shared.showPractice()
  }
  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool
  {
    AppModel.shared.showPractice()
    return true
  }
}
