import Foundation

enum ExampleHighlight {
    static func ranges(in sentence: String, word: String, lemma: String) -> [NSRange] {
        let expressions = Set([word, lemma].map(OfflineDictionary.normalize)).filter { !$0.isEmpty }
        var ranges: [NSRange] = []
        let full = NSRange(sentence.startIndex..<sentence.endIndex, in: sentence)
        for expression in expressions {
            let pattern = "(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: expression) + "(?![\\p{L}\\p{N}])"
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                ranges += regex.matches(in: sentence, range: full).map(\.range)
            }
        }
        if !lemma.contains(" "), !lemma.isEmpty,
           let regex = try? NSRegularExpression(pattern: "[A-Za-z]+(?:['\u{2019}-][A-Za-z]+)*") {
            let canonical = OfflineDictionary.shared.lemma(for: lemma)
            for match in regex.matches(in: sentence, range: full) {
                guard let range = Range(match.range, in: sentence) else { continue }
                if OfflineDictionary.shared.lemma(for: String(sentence[range])) == canonical {
                    ranges.append(match.range)
                }
            }
        }
        var merged: [NSRange] = []
        for range in ranges.sorted(by: { $0.location < $1.location }) {
            if let last = merged.last, NSMaxRange(last) > range.location {
                merged[merged.count - 1] = NSUnionRange(last, range)
            } else { merged.append(range) }
        }
        return merged
    }
}
