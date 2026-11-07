import AVFoundation
import Foundation
import PracticeCore
import Speech

@main struct Probe {
  static func main() async {
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
