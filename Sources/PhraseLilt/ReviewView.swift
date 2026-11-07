import PracticeCore
import SwiftUI

struct ReviewView: View {
  @ObservedObject var model: AppModel
  @ObservedObject var session: PracticeSession
  let compact: Bool
  @State private var selectedWord: WordSegment?
  @State private var deleteConfirmation = false
  @AppStorage("voiceUS") private var voiceUS = ""
  @AppStorage("voiceUK") private var voiceUK = ""
  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Label("PhraseLilt", systemImage: "waveform.bubble").font(.headline)
        Spacer()
        if compact {
          Button("Practice") {
            model.showPractice()
            NSApp.activate()
          }
        }
        SettingsLink { Label("Settings", systemImage: "gearshape") }.labelStyle(.iconOnly).help(
          "Settings")
      }.padding()
      Divider()
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          if session.recording || session.requestingMicrophone {
            recordingView
          } else if let clip = session.selected {
            review(clip)
          } else {
            ContentUnavailableView {
              Label("A little clearer, each time", systemImage: "waveform")
            } description: {
              Text(
                "Record a sentence you actually use. Listen, compare, and practise at your own pace."
              )
            } actions: {
              Button("Record", systemImage: "mic") { record() }.buttonStyle(.borderedProminent)
              Button("Import Audio…") { model.importAudio() }
            }
            Text(
              "Hold Control–Option–your chosen key to record from another app. Release to stop. You can also click Record."
            )
            .font(.callout).foregroundStyle(.secondary)
            Text("American or British reference? Choose in Settings. Your accent is not a defect.")
              .font(.callout)
            modelSetup
          }
          if let message = session.message {
            Label(message, systemImage: "info.circle").font(.callout).textSelection(.enabled)
          }
          if let error = model.shortcutError { Text(error).font(.callout) }
        }.padding(24)
      }
      Divider()
      HStack {
        if !session.clips.isEmpty {
          Menu("History (\(session.clips.count))") {
            ForEach(session.clips) { clip in
              Button(historyTitle(clip)) {
                model.playback.stop()
                selectedWord = nil
                session.select(clip.id)
              }
            }
          }
        }
        Spacer()
        Button("Import…") { model.importAudio() }.disabled(
          session.recording || session.requestingMicrophone)
        if session.recording || session.requestingMicrophone {
          Button("Stop", systemImage: "stop.fill") { session.finishRecording() }.keyboardShortcut(
            ".", modifiers: .command)
        } else {
          Button("Record", systemImage: "mic") { record() }
        }
        Menu("More") {
          Button("Quit PhraseLilt") {
            session.shutdown()
            NSApp.terminate(nil)
          }.keyboardShortcut("q")
        }.menuStyle(.borderlessButton).fixedSize()
      }.padding()
    }
    .frame(
      minWidth: compact ? 420 : 380, idealWidth: compact ? 450 : 560,
      maxWidth: compact ? 450 : .infinity,
      minHeight: 400, idealHeight: 580, maxHeight: compact ? 650 : .infinity
    )
    .onChange(of: session.selectedID) {
      model.playback.stop()
      selectedWord = nil
    }
    .onChange(of: session.variety) {
      model.playback.stop()
      selectedWord = nil
    }
    .onChange(of: session.selected?.intendedText) {
      model.playback.stop()
      selectedWord = nil
    }
    .confirmationDialog("Delete this clip and its local data?", isPresented: $deleteConfirmation) {
      Button("Delete Clip", role: .destructive) {
        model.playback.stop()
        session.deleteSelected()
      }
    }
  }
  private var recordingView: some View {
    VStack(spacing: 20) {
      Label(
        session.recording ? "Recording" : "Waiting for microphone permission…",
        systemImage: "record.circle"
      )
      .font(.title2).accessibilityAddTraits(.updatesFrequently)
      Text(session.retryContext?.intendedText ?? "Say one sentence, in your own words.")
        .font(.title3).multilineTextAlignment(.center)
      Text("Stops automatically before 60 seconds.").font(.callout).foregroundStyle(.secondary)
      HStack {
        Button("Cancel", role: .cancel) { session.cancelRecording() }.keyboardShortcut(
          .escape, modifiers: [])
        Button("Stop", systemImage: "stop.fill") { session.finishRecording() }.buttonStyle(
          .borderedProminent)
      }
    }.frame(maxWidth: .infinity).padding(.vertical, 24)
  }
  @ViewBuilder private func review(_ clip: Clip) -> some View {
    HStack {
      Text(clip.createdAt, format: .dateTime.month(.abbreviated).day().hour().minute()).font(
        .caption
      ).foregroundStyle(.secondary)
      Spacer()
      Text(session.variety.rawValue).font(.caption)
    }
    if session.processing {
      HStack {
        ProgressView().controlSize(.small)
        Text("Transcribing on this Mac…")
        Spacer()
        Button("Cancel") { session.cancelAnalysis() }
      }
    }
    if clip.intentConfirmed {
      Text(clip.intendedText).font(.title2).fixedSize(horizontal: false, vertical: true)
        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
    } else {
      TextEditor(
        text: Binding(
          get: { session.selected?.intendedText ?? "" }, set: { session.editIntent($0) })
      )
      .font(.title2).scrollContentBackground(.hidden).frame(height: 100)
      .accessibilityLabel("Intended sentence").disabled(session.processing)
      .overlay(alignment: .topLeading) {
        if clip.intendedText.isEmpty {
          Text("What did you mean to say?").font(.title3).foregroundStyle(.secondary)
            .padding(.top, 5).allowsHitTesting(false).accessibilityHidden(true)
        }
      }
    }
    HStack {
      if clip.intentConfirmed {
        Label("Wording confirmed", systemImage: "checkmark.circle").font(.callout)
        Button("Edit Wording") { session.editIntent(clip.intendedText) }
      } else {
        Button("Confirm Wording") { session.confirmIntent() }.disabled(
          clip.intendedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || session.processing)
      }
      Spacer()
      Button(clip.saved ? "Saved" : "Save", systemImage: clip.saved ? "bookmark.fill" : "bookmark")
      { session.toggleSaved() }
    }
    if clip.canUseWordTiming {
      Text("Select a timed word or phrase to replay it.").font(.caption).foregroundStyle(.secondary)
      // A wrapping adaptive grid keeps every segment reachable in small windows.
      LazyVGrid(
        columns: [GridItem(.adaptive(minimum: 84), alignment: .leading)], alignment: .leading,
        spacing: 6
      ) {
        ForEach(clip.words) { word in
          TimedWordButton(
            playback: model.playback, word: word, selected: selectedWord?.id == word.id
          ) {
            selectedWord = selectedWord?.id == word.id ? nil : word
          }
        }
      }
    } else if clip.intentConfirmed {
      Text("Word timing isn’t available for this wording. Replay the whole sentence.").font(
        .caption
      )
      .foregroundStyle(.secondary)
    }
    playbackControls(clip)
    if selectedWord != nil {
      Button("Whole Sentence") {
        selectedWord = nil
        model.playback.stop()
      }.font(.callout)
    }
    if let caution = session.caution { Label(caution, systemImage: "mic.slash").font(.callout) }
    VStack(alignment: .leading, spacing: 8) {
      Text("Listen & practise").font(.headline)
      Text(PracticeGuidance.tip)
      Text(PracticeGuidance.disclaimer).font(.caption).foregroundStyle(.secondary)
    }
    Text("Experimental assessment · no pronunciation diagnosis is available.").font(.caption)
      .foregroundStyle(.secondary)
    Button("Try Again", systemImage: "arrow.clockwise") {
      model.playback.stop()
      Task { await session.startRecording(retry: true) }
    }
    .buttonStyle(.borderedProminent).controlSize(.large).disabled(
      !clip.intentConfirmed || session.processing)
    let attempts = session.clips.filter { $0.groupID == clip.groupID && $0.id != clip.id }
    if !attempts.isEmpty {
      Menu("Compare Attempts (\(attempts.count + 1))") {
        ForEach(attempts) { attempt in
          Button(historyTitle(attempt)) {
            model.playback.stop()
            session.select(attempt.id)
          }
        }
      }
    }
    DisclosureGroup("Details") {
      VStack(alignment: .leading, spacing: 10) {
        Text(
          "Raw recognition: \(clip.rawRecognition.isEmpty ? "Unavailable" : clip.rawRecognition)"
        ).textSelection(.enabled)
        Text("Timing locates replay segments. It does not assess pronunciation.")
        Text(clip.assessmentNote)
        Button("Transcribe Again") { session.retryTranscription() }.disabled(session.processing)
        Button("Delete Clip…", role: .destructive) { deleteConfirmation = true }
      }.font(.callout).padding(.top, 8)
    }
  }
  private func playbackControls(_ clip: Clip) -> some View {
    PlaybackControls(
      playback: model.playback,
      you: {
        do {
          try model.playback.play(url: session.store.audioURL(for: clip), segment: selectedWord)
        } catch { session.message = "Couldn’t play this clip. Try importing the original again." }
      },
      reference: {
        do {
          try model.playback.speak(
            selectedWord?.text ?? clip.intendedText, variety: session.variety,
            voiceID: session.variety == .american ? voiceUS : voiceUK)
        } catch { session.message = error.localizedDescription }
      }, enabled: clip.intentConfirmed)
  }
  private var modelSetup: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Setup").font(.headline)
      Text(
        "Local speech models and reference voices may need a first download. Open Settings to prepare offline practice."
      )
      SettingsLink { Text("Open Settings") }
    }.font(.callout)
  }
  private func record() {
    model.playback.stop()
    Task { await session.startRecording() }
  }
  private func historyTitle(_ clip: Clip) -> String {
    let sentence =
      clip.intendedText.isEmpty ? "Untitled clip" : String(clip.intendedText.prefix(48))
    return
      "\(clip.saved ? "★ " : "")\(sentence) · \(clip.createdAt.formatted(date: .omitted, time: .shortened))"
  }
}

private struct PlaybackControls: View {
  @ObservedObject var playback: Playback
  var you: () -> Void
  var reference: () -> Void
  var enabled: Bool
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 12) {
        Button("You", systemImage: "play.fill", action: you).controlSize(.large)
        Button("Reference", systemImage: "speaker.wave.2", action: reference).controlSize(.large)
          .disabled(!enabled)
        Spacer()
        Button("Stop", systemImage: "stop", action: playback.stop).disabled(!playback.playing)
      }
      if playback.playing {
        Text(
          playback.spokenWord.map { "Reference · \($0)" }
            ?? "Playing · listen to the selected segment or sentence"
        ).font(.caption)
          .accessibilityAddTraits(.updatesFrequently)
      }
    }
  }
}

private struct TimedWordButton: View {
  @ObservedObject var playback: Playback
  var word: WordSegment
  var selected: Bool
  var action: () -> Void
  private var active: Bool {
    guard let position = playback.position else { return false }
    return position >= word.start && position < word.start + word.duration
  }
  var body: some View {
    Button(action: action) {
      HStack(spacing: 3) {
        Text(word.text)
        if active {
          Image(systemName: "speaker.wave.2")
        } else if selected {
          Image(systemName: "checkmark")
        }
      }.frame(maxWidth: .infinity)
    }.buttonStyle(.bordered).tint(selected || active ? .accentColor : nil)
      .accessibilityLabel(word.text)
      .accessibilityValue(active ? "Playing" : selected ? "Selected" : "Select segment")
      .accessibilityAddTraits(selected ? [.isSelected] : [])
  }
}
