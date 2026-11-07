import Foundation

/// Selects a short, complete recognized sentence only when existing audio timings bound it exactly.
/// This locates replay, not pronunciation correctness. The original recording and raw text stay intact.
public enum PracticeExcerpt {
  public static func select(from recognition: Recognition) -> WordSegment? {
    let text = recognition.text
    let raw = text as NSString
    var located: [(WordSegment, NSRange)] = []
    var cursor = 0
    for word in recognition.words {
      guard cursor <= raw.length, word.start.isFinite, word.duration.isFinite,
        word.start >= 0, word.duration > 0
      else { return nil }
      let range = raw.range(
        of: word.text, range: NSRange(location: cursor, length: raw.length - cursor))
      guard range.location != NSNotFound else { return nil }
      located.append((word, range))
      cursor = NSMaxRange(range)
    }
    var selected: WordSegment?
    text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: .bySentences) {
      sentence, range, _, stop in
      guard let sentence else { return }
      let candidate = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
      let ending = candidate.trimmingCharacters(in: CharacterSet(charactersIn: "\"’”"))
      guard (20...180).contains(candidate.count), let last = ending.last, ".!?".contains(last),
        let exact = text.range(of: candidate, range: range)
      else { return }
      let target = NSRange(exact, in: text)
      let matches = located.filter { NSIntersectionRange($0.1, target).length > 0 }
      guard let first = matches.first, let last = matches.last,
        first.1.location == target.location, NSMaxRange(last.1) == NSMaxRange(target)
      else { return }
      let duration = last.0.start + last.0.duration - first.0.start
      guard duration >= 0.2, duration <= 12 else { return }
      selected = WordSegment(text: candidate, start: first.0.start, duration: duration)
      stop = true
    }
    return selected
  }
}
