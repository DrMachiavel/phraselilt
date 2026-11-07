import PracticeCore
import SwiftUI

struct SettingsView: View {
  @ObservedObject var model: AppModel
  @ObservedObject var session: PracticeSession
  @ObservedObject var companion: Companion
  @AppStorage("variety") private var variety = ReferenceVariety.american.rawValue
  @AppStorage("retentionDays") private var days = 7
  @AppStorage("voiceUS") private var voiceUS = ""
  @AppStorage("voiceUK") private var voiceUK = ""
  @State private var deleting = false
  var body: some View {
    Form {
      Section("Companion") {
        Text(
          "Keep your usual dictation shortcut. PhraseLilt can save short microphone clips alongside the apps you choose."
        )
        .font(.callout).foregroundStyle(.secondary)
        Toggle(
          "Companion Mode",
          isOn: Binding(get: { model.companionEnabled }, set: { model.setCompanionEnabled($0) })
        )
        .disabled(model.enabling)
        if model.enabling { ProgressView("Waiting for microphone permission…") }
        Text(companion.status).font(.caption)
        Toggle("Wispr Flow", isOn: $model.followWispr)
        Toggle("Granola · experimental", isOn: $model.followGranola)
        Toggle("Other Microphone Apps", isOn: $model.followOtherApps)
        Text(
          "Other apps includes calls. Only the default microphone is supported. Capture stops with the source or at 30 seconds; it won’t restart until that source becomes idle."
        )
        .font(.caption).foregroundStyle(.secondary)
        if let error = companion.error { Text(error).font(.callout) }
      }
      Section("Practice") {
        Picker("Reference", selection: $variety) {
          ForEach(ReferenceVariety.allCases) { Text($0.rawValue).tag($0.rawValue) }
        }.disabled(model.assets.downloading || session.recording || session.requestingMicrophone)
        Text(session.variety.description).font(.caption).foregroundStyle(.secondary)
        Toggle("One Quiet Menu-Bar Nudge a Day", isOn: $model.dailyNudge)
        Text("No notifications, automatic playback, or pasting.").font(.caption).foregroundStyle(
          .secondary)
        DisclosureGroup("Reference Voice & Offline Setup") {
          Picker("Installed voice", selection: session.variety == .american ? $voiceUS : $voiceUK) {
            Text(
              "System choice (\(Playback.defaultVoice(for: session.variety)?.name ?? "unavailable"))"
            ).tag("")
            ForEach(Playback.voices(for: session.variety), id: \.identifier) {
              Text($0.name).tag($0.identifier)
            }
          }
          AssetSettings(assets: model.assets, variety: session.variety)
        }
      }
      Section("Local History") {
        Picker("Delete unsaved clips after", selection: $days) {
          Text("1 day").tag(1)
          Text("7 days").tag(7)
          Text("30 days").tag(30)
        }
        Text(
          "Saved clips stay until deleted. Local files are not encrypted by this app; backups may retain copies."
        ).font(.caption).foregroundStyle(.secondary)
        Button("Delete All…", role: .destructive) { deleting = true }
      }
      DisclosureGroup("Compatibility Check") {
        Text(
          "Use Fn in Wispr Flow as usual. A practice clip should appear without changing dictation. Microphone activity detection is available; concurrent recording and headset behavior require a real check."
        ).font(.caption)
        Text("Clips captured in this run: \(companion.completedCaptures)").font(.caption)
        if let delay = companion.lastStartDelay {
          Text(
            "Last recorder start after detection: \(delay, format: .number.precision(.fractionLength(3))) s. Polling adds up to about 0.1 s; this is not an audio-onset measurement."
          ).font(.caption)
        }
        Text(
          "An ongoing recording is skipped when you enable or resume the companion. No keyboard monitoring, private app APIs, or system audio capture is used."
        ).font(.caption)
      }
    }.formStyle(.grouped).frame(maxWidth: .infinity, maxHeight: .infinity)
      .onChange(of: variety) {
        model.listening.stop()
        session.setVariety(ReferenceVariety(rawValue: variety) ?? .american)
        Task { await model.assets.check(session.variety) }
      }
      .onChange(of: voiceUS) { model.listening.stop() }
      .onChange(of: voiceUK) { model.listening.stop() }
      .onChange(of: days) {
        model.listening.stop()
        session.applyRetention(days: days)
      }
      .confirmationDialog("Delete all local clips, including saved clips?", isPresented: $deleting)
    {
      Button("Delete All", role: .destructive) {
        model.setCompanionEnabled(false)
        model.listening.stop()
        session.deleteAll()
      }
    }
  }
}
private struct AssetSettings: View {
  @ObservedObject var assets: ModelSetup
  let variety: ReferenceVariety
  var body: some View {
    Text(assets.status).font(.callout)
    if assets.downloading {
      ProgressView(value: assets.fraction)
      Button("Cancel Download") { assets.cancel() }
    } else if !assets.ready {
      Button("Prepare English Speech") { assets.install(variety) }
    }
    Text(
      "First-time setup may download English speech data. Keep 2 GB free as a precaution; macOS manages shared assets and does not expose a preflight size or pinned model version. Core features then run locally."
    )
    .font(.caption).foregroundStyle(.secondary)
    if let error = assets.error { Text(error).font(.callout) }
    Text("Additional voices can be downloaded in System Settings → Accessibility → Read & Speak.")
      .font(.caption)
      .task(id: variety) { await assets.check(variety) }
  }
}
