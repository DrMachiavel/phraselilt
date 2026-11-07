import AVFoundation
import Foundation
import PracticeCore
import Speech

@main struct Probe {
  static func main() async {
    if CommandLine.arguments.contains("--observe-wispr") {
      let reader = CoreAudioInputActivity()
      let start = Date()
      var previous: Bool?
      var samples = 0
      var peakRead = 0.0
      while Date().timeIntervalSince(start) < 120 {
        do {
          let began = Date()
          let snapshot = try reader.snapshot()
          peakRead = max(peakRead, Date().timeIntervalSince(began))
          samples += 1
          let active = snapshot.processes.contains {
            $0.bundleID.lowercased().hasPrefix("com.electron.wispr-flow")
          }
          if active != previous {
            let matching = snapshot.processes.filter {
              $0.bundleID.lowercased().hasPrefix("com.electron.wispr-flow")
                && $0.devices.contains(snapshot.defaultDevice)
            }.count
            print("Active Wispr streams on default input: \(matching)")
            print(
              "Wispr microphone activity: \(active ? "active" : "idle") at \(String(format: "%.3f", Date().timeIntervalSince(start))) s"
            )
            fflush(stdout)
            previous = active
          }
          try await Task.sleep(for: .milliseconds(100))
        } catch {
          print("Activity read failed: \(error.localizedDescription)")
          exit(1)
        }
      }
      print(
        "Read-only samples: \(samples); longest metadata read: \(peakRead) s. No microphone was opened."
      )
      return
    }
    let module = LocalTranscriber.module(.american)
    print("Local engine available: \(SpeechTranscriber.isAvailable)")
    print("US asset status: \(await AssetInventory.status(forModules: [module]))")
    print(
      "UK asset status: \(await AssetInventory.status(forModules: [LocalTranscriber.module(.british)]))"
    )
    let voices = AVSpeechSynthesisVoice.speechVoices().filter {
      ["en-US", "en-GB"].contains($0.language)
    }
    print(
      "Installed English reference voices: \(voices.map { "\($0.name) [\($0.language)]" }.joined(separator: ", "))"
    )
    if CommandLine.arguments.contains("--install") {
      do {
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
          print("Installing OS-managed US English assets explicitly for local pipeline testing.")
          try await request.downloadAndInstall()
          print("Installed; progress units: \(request.progress.totalUnitCount) (not assumed bytes)")
        }
      } catch {
        print("Installation failed: \(error.localizedDescription)")
        exit(1)
      }
      return
    }
    guard CommandLine.arguments.count > 1 else { return }
    do {
      let url = URL(fileURLWithPath: CommandLine.arguments[1])
      let info = try AudioValidator.inspect(url)
      print(
        "Duration: \(info.duration); RMS: \(info.rms); clipped fraction: \(info.clippedFraction)")
      let start = Date()
      let recognition = try await LocalTranscriber().transcribe(url: url, variety: .american)
      print(
        "Synthetic pipeline result: \(recognition.text); timed segments: \(recognition.words.count); latency: \(Date().timeIntervalSince(start)) s"
      )
    } catch {
      print("Probe stopped: \(error.localizedDescription)")
      exit(1)
    }
  }
}
