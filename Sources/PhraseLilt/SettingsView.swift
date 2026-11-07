import PracticeCore
import SwiftUI

struct SettingsView: View {
  @ObservedObject var model: AppModel
  @ObservedObject var session: PracticeSession
  @AppStorage("variety") private var variety = ReferenceVariety.american.rawValue
  @AppStorage("shortcutKey") private var key = 49
  @AppStorage("retentionDays") private var days = 7
  @AppStorage("voiceUS") private var voiceUS = ""
  @AppStorage("voiceUK") private var voiceUK = ""
  @State private var deleting = false
  var body: some View {
    Form {
      Section("Reference") {
        Picker("English reference", selection: $variety) {
          ForEach(ReferenceVariety.allCases) { Text($0.rawValue).tag($0.rawValue) }
        }.disabled(model.assets.downloading || session.recording || session.requestingMicrophone)
        Text(session.variety.description).font(.callout).foregroundStyle(.secondary)
        Picker("Installed voice", selection: session.variety == .american ? $voiceUS : $voiceUK) {
          Text("System choice").tag("")
          ForEach(Playback.voices(for: session.variety), id: \.identifier) {
            Text($0.name).tag($0.identifier)
          }
        }
        Text(
          "Voice labels describe a reference, not every valid accent. Add downloaded voices in System Settings → Accessibility → Read & Speak. Check unfamiliar names by listening."
        ).font(.caption)
      }
      Section("Recording") {
        Picker("Hold Control–Option +", selection: $key) {
          Text("Space").tag(49)
          Text("R").tag(15)
          Text("P").tag(35)
        }.disabled(session.recording || session.requestingMicrophone)
        Text(
          "Release to stop. Recording also stops before 60 seconds, on sleep, session lock, input change, or quit. No Accessibility permission is needed. Record and Stop buttons are always available."
        ).font(.caption)
        if let error = model.shortcutError { Text(error) }
      }
      Section("Offline setup") { AssetSettings(assets: model.assets, variety: session.variety) }
      Section("Local history") {
        Picker("Delete unsaved clips after", selection: $days) {
          Text("1 day").tag(1)
          Text("7 days").tag(7)
          Text("30 days").tag(30)
        }
        Text(
          "Saved practice clips stay until deleted. Up to 100 clips. Private local storage, without app-level encryption. System backups may retain copies."
        ).font(.caption)
        Button("Delete All…", role: .destructive) { deleting = true }
        Text(
          "Deletes managed audio, wording, timing, and findings. It cannot securely erase SSD blocks or remove backups."
        ).font(.caption)
      }
    }.formStyle(.grouped).frame(width: 520, height: 650)
      .onChange(of: variety) {
        model.playback.stop()
        session.setVariety(ReferenceVariety(rawValue: variety) ?? .american)
        Task { await model.assets.check(session.variety) }
      }
      .onChange(of: key) { model.configureShortcut(key: UInt32(key)) }
      .onChange(of: days) {
        model.playback.stop()
        session.applyRetention(days: days)
      }
      .confirmationDialog(
        "Delete all local clips? Saved clips will also be deleted.", isPresented: $deleting
      ) {
        Button("Delete All", role: .destructive) {
          model.playback.stop()
          session.deleteAll()
        }
      }
  }
}

private struct AssetSettings: View {
  @ObservedObject var assets: ModelSetup
  let variety: ReferenceVariety
  var body: some View {
    Text(assets.status)
    Text(
      "macOS downloads and manages the English model. The API does not report its size before download. Keep at least 2 GB free as a precaution; actual shared storage varies. Apple manages integrity, updates, and partial downloads; this app cannot pin its model version."
    ).font(.caption)
    if assets.downloading {
      ProgressView(value: assets.fraction)
      Button("Cancel Download") { assets.cancel() }
    } else if !assets.ready {
      Button("Download English Model") { assets.install(variety) }
    }
    Button("Check Readiness") { Task { await assets.check(variety) } }.disabled(assets.downloading)
    if let error = assets.error { Text(error).font(.callout) }
    Text(
      "After setup, recording, transcription, reference speech and storage run on this Mac. No cloud fallback. You can enter wording manually without a model."
    ).font(.caption)
      .task(id: variety) { await assets.check(variety) }
  }
}
