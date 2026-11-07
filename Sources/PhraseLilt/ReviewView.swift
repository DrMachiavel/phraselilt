import PracticeCore
import SwiftUI

struct ReviewView: View {
  @ObservedObject var model: AppModel
  @ObservedObject var session: PracticeSession
  @ObservedObject var companion: Companion
  @ObservedObject var listening: Listening
  @ObservedObject var soundHints: SoundHints
  @ObservedObject var soundModel: SoundModelSetup
  @AppStorage("voiceUS") private var voiceUS = ""
  @AppStorage("voiceUK") private var voiceUK = ""
  @AppStorage("retentionDays") private var days = 7
  @State private var editing = false
  @State private var draft = ""
  @State private var deleting = false
  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Label("PhraseLilt", systemImage: MenuBarSymbol.idle.rawValue).font(.headline)
        Spacer()
        Button("Settings") { model.openSettings() }
      }.padding(20)
      Divider()
      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          if session.recording || session.requestingMicrophone {
            recording
          } else if let clip = session.selected {
            review(clip)
          } else {
            VStack(alignment: .leading, spacing: 18) {
              Text("Your words. Your usual routine.").font(.title2)
              Text(
                "Keep using dictation as you always do. Enable the companion in Settings, then short practice clips will wait here quietly."
              )
              .foregroundStyle(.secondary)
              Button("Set Up Companion") { model.openSettings() }.buttonStyle(.borderedProminent)
            }.padding(.vertical, 20)
          }
          if let message = session.message {
            Text(message).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
          }
          if let error = listening.error { Text(error).font(.callout) }
          if let error = companion.error { Text(error).font(.callout) }
        }.padding(28)
      }
      if !editing, !session.processing, !session.recording, !session.requestingMicrophone,
        let clip = session.selected
      {
        analysisStatus(clip).frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, 20).padding(.vertical, 12)
      }
      Divider()
      HStack {
        Text("On this Mac · unsaved clips expire in \(days) \(days == 1 ? "day" : "days")")
          .font(.caption).foregroundStyle(.secondary)
        Spacer(minLength: 6)
        Menu("More") {
          if !session.clips.isEmpty {
            Menu("History") {
              ForEach(session.clips) { clip in
                Button(historyTitle(clip)) {
                  listening.stop()
                  session.select(clip.id)
                }
              }
            }
          }
          Button("Import Audio…") { model.importAudio() }.disabled(session.recording)
          Button("Record Practice Clip") { model.recordPractice() }.disabled(
            session.recording || session.processing)
          if session.selected != nil {
            Button("Delete Clip…", role: .destructive) { deleting = true }
          }
          Divider()
          Button(model.companionEnabled ? "Pause Companion" : "Enable Companion…") {
            model.setCompanionEnabled(!model.companionEnabled)
          }
          Button("Quit PhraseLilt") {
            model.companion?.stop()
            session.shutdown()
            NSApp.terminate(nil)
          }.keyboardShortcut("q")
        }.fixedSize()
      }.padding(16)
    }.frame(minWidth: 360, minHeight: 380)
      .onChange(of: session.selectedID) {
        listening.stop()
        editing = false
      }
      .onChange(of: session.variety) {
        listening.stop()
      }
      .onChange(of: session.selected?.intendedText) {
        listening.stop()
      }
      .confirmationDialog("Delete this clip and its local data?", isPresented: $deleting) {
        Button("Delete Clip", role: .destructive) {
          listening.stop()
          session.deleteSelected()
        }
      }
  }
  private var recording: some View {
    VStack(alignment: .leading, spacing: 20) {
      Label(
        session.requestingMicrophone ? "Waiting for microphone permission…" : "Recording",
        systemImage: "record.circle"
      )
      .font(.headline).accessibilityAddTraits(.updatesFrequently)
      Text("Keep speaking your way.").font(.title2)
      Text(
        companion.sourceName.map {
          "Capturing a short local clip alongside \($0). Stops with that app, or after 30 seconds."
        }
          ?? "Recording a practice clip. Stops automatically before 60 seconds."
      ).foregroundStyle(.secondary)
      Button("Stop Capture", systemImage: "stop.fill") { session.finishRecording() }
        .buttonStyle(.borderedProminent).controlSize(.large)
      Button("Cancel", role: .cancel) { session.cancelRecording() }.keyboardShortcut(
        .escape, modifiers: [])
    }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 16)
  }
  @ViewBuilder private func review(_ clip: Clip) -> some View {
    HStack {
      Text(
        clip.practiceSegment == nil
          ? "Full clip · \(Int(clip.duration.rounded())) sec" : "Selected passage")
      Spacer()
      Text(session.variety.rawValue)
    }.font(.caption).foregroundStyle(.secondary)
    if session.processing {
      HStack {
        ProgressView().controlSize(.small)
        Text("Preparing your clip on this Mac…").font(.callout)
        Spacer()
        Button("Cancel") { session.cancelAnalysis() }
      }
    }
    if editing {
      TextEditor(text: $draft).font(.title2).scrollContentBackground(.hidden).frame(height: 120)
        .accessibilityLabel("Intended sentence").onChange(of: draft) {
          if draft.count > 2000 { draft = String(draft.prefix(2000)) }
        }
      Button("Save Wording") {
        listening.stop()
        session.editIntent(draft)
        session.confirmIntent()
        editing = false
      }
      .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    } else {
      Text(
        highlighted(clip.intendedText.isEmpty ? "What did you say?" : clip.intendedText, clip: clip)
      )
      .font(.system(.title, design: .default)).fixedSize(horizontal: false, vertical: true)
      .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
      .accessibilityHint(
        !soundHints.matches(clip: clip, variety: session.variety) || soundHints.hints.isEmpty
          ? ""
          : "Experimental practice target: th in "
            + soundHints.hints.map(\.word).joined(separator: ", "))
      Button(clip.intendedText.isEmpty ? "Enter Wording" : "Edit Wording") {
        listening.stop()
        session.cancelAnalysis()
        draft = clip.intendedText
        editing = true
      }.font(.caption).disabled(session.processing)
    }
    VStack(spacing: 12) {
      Button {
        if listening.phase == .reference {
          listening.stop()
          return
        }
        session.confirmIntent()
        listening.playReference(
          text: clip.intendedText, variety: session.variety,
          voiceID: session.variety == .american ? voiceUS : voiceUK)
      } label: {
        Label(
          listening.phase == .reference ? "Stop Reference" : "Hear Reference",
          systemImage: listening.phase == .reference ? "stop.fill" : "speaker.wave.2"
        ).frame(maxWidth: .infinity)
      }.buttonStyle(.borderedProminent).controlSize(.large)
        .disabled(
          editing || session.processing
            || clip.intendedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      Button {
        if listening.phase == .you {
          listening.stop()
        } else {
          listening.playRecording(
            url: session.store.audioURL(for: clip), segment: clip.practiceSegment)
        }
      } label: {
        Label(
          listening.phase == .you ? "Stop My Recording" : "Hear My Recording",
          systemImage: listening.phase == .you ? "stop.fill" : "play"
        )
      }.buttonStyle(.bordered).disabled(editing || session.processing)
    }
    DisclosureGroup("Details") {
      VStack(alignment: .leading, spacing: 12) {
        if soundHints.matches(clip: clip, variety: session.variety), let status = soundHints.status
        {
          Text(status)
        }
        Text(
          "Automatic hints use the displayed wording as a working assumption. Edit it if recognition got it wrong. Hints can be mistaken; accent variants are valid."
        )
        if let caution = session.caution { Text(caution) }
        Text(
          "Raw recognition: \(clip.rawRecognition.isEmpty ? "Unavailable" : clip.rawRecognition)"
        ).textSelection(.enabled)
        if clip.practiceSegment != nil {
          Text(
            "Practising a short excerpt. The full recording and raw transcript are retained. Timing locates replay; it does not assess pronunciation."
          )
        }
        if let source = clip.captureSource {
          Text(
            "Captured alongside \(source). This is a separate recording, not imported app audio. The first sounds may be missed while capture starts."
          )
        }
        Text("Guided listening is available. Automatic pronunciation diagnosis is not.")
        FullRecordingButton(
          playback: model.playback, listening: listening, url: session.store.audioURL(for: clip))
        Button(clip.saved ? "Unsave Clip" : "Save Clip") { session.toggleSaved() }
        Button("Transcribe Again") { session.retryTranscription() }.disabled(session.processing)
      }.font(.callout).padding(.top, 10)
    }
  }
  @ViewBuilder private func analysisStatus(_ clip: Clip) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      if !model.automaticSoundHints {
        Text("Sound hints paused").font(.callout)
      } else if !soundModel.ready {
        Text("Sound hints need setup in Settings").font(.callout)
      } else if soundHints.matches(clip: clip, variety: session.variety),
        let summary = soundHints.summary
      {
        HStack(spacing: 8) {
          if soundHints.running {
            ProgressView().controlSize(.mini)
          } else {
            Image(systemName: "waveform").accessibilityHidden(true)
          }
          Text(summary).font(.callout)
        }
        if !soundHints.hints.isEmpty, let status = soundHints.status {
          Text(status).font(.caption).foregroundStyle(.secondary)
        }
      }
      Text(
        "Experimental · only six “th” words are supported; most pronunciation is not assessed."
      )
      .font(.caption).foregroundStyle(.secondary)
    }.accessibilityElement(children: .combine)
  }
  private func highlighted(_ text: String, clip: Clip) -> AttributedString {
    var result = AttributedString(text)
    guard soundHints.matches(clip: clip, variety: session.variety), !editing else { return result }
    for hint in soundHints.hints {
      guard let range = Range(hint.range, in: text), let attributedRange = Range(range, in: result)
      else { continue }
      result[attributedRange].foregroundColor = .orange
      result[attributedRange].underlineStyle = .single
    }
    return result
  }
  private func historyTitle(_ clip: Clip) -> String {
    "\(clip.saved ? "★ " : "")\(clip.intendedText.isEmpty ? "Untitled clip" : String(clip.intendedText.prefix(42))) · \(clip.createdAt.formatted(date: .omitted, time: .shortened))"
  }
}

private struct FullRecordingButton: View {
  @ObservedObject var playback: Playback
  var listening: Listening
  var url: URL
  @State private var failed = false
  var body: some View {
    VStack(alignment: .leading) {
      Button(playback.playing ? "Stop Playback" : "Play Full Recording") {
        if playback.playing {
          listening.stop()
          return
        }
        listening.stop()
        do {
          try playback.play(url: url)
          failed = false
        } catch { failed = true }
      }
      if failed { Text("Couldn’t play this recording. Try importing the original again.") }
    }
  }
}
