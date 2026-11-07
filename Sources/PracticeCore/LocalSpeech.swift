import AVFoundation
import CoreMedia
import Foundation
import Speech

public protocol Transcribing: Sendable {
  func transcribe(url: URL, variety: ReferenceVariety) async throws -> Recognition
}

public struct LocalTranscriber: Transcribing {
  public init() {}
  public static func module(_ variety: ReferenceVariety) -> SpeechTranscriber {
    SpeechTranscriber(
      locale: Locale(identifier: variety.locale), transcriptionOptions: [],
      reportingOptions: [], attributeOptions: [.audioTimeRange])
  }
  public func transcribe(url: URL, variety: ReferenceVariety) async throws -> Recognition {
    guard SpeechTranscriber.isAvailable else { throw PracticeError.unsupported }
    let module = Self.module(variety)
    guard await AssetInventory.status(forModules: [module]) == .installed else {
      throw PracticeError.modelsMissing
    }
    let file = try AVAudioFile(forReading: url)
    let analyzer = SpeechAnalyzer(modules: [module])
    return try await withTaskCancellationHandler {
      let results = Task { () throws -> Recognition in
        var text = ""
        var words: [WordSegment] = []
        for try await result in module.results {
          try Task.checkCancellation()
          if !text.isEmpty { text += " " }
          text += String(result.text.characters)
          for run in result.text.runs {
            guard let time = run.audioTimeRange else { continue }
            let start = CMTimeGetSeconds(time.start)
            let duration = CMTimeGetSeconds(time.duration)
            let label = String(result.text[run.range].characters).trimmingCharacters(
              in: .whitespacesAndNewlines)
            if start.isFinite, duration.isFinite, duration > 0, !label.isEmpty {
              words.append(WordSegment(text: label, start: start, duration: duration))
            }
          }
        }
        return Recognition(text: text.trimmingCharacters(in: .whitespacesAndNewlines), words: words)
      }
      do {
        try await analyzer.start(inputAudioFile: file, finishAfterFile: true)
        let value = try await results.value
        try Task.checkCancellation()
        return value
      } catch {
        results.cancel()
        await analyzer.cancelAndFinishNow()
        throw error
      }
    } onCancel: {
      Task { await analyzer.cancelAndFinishNow() }
    }
  }
}
