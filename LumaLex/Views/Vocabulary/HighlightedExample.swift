import SwiftUI

struct HighlightedExample: View {
    let sentence: String
    let word: String
    let lemma: String

    private var highlightedText: Text {
        let string = sentence as NSString
        var result = Text("")
        var offset = 0
        for range in ExampleHighlight.ranges(in: sentence, word: word, lemma: lemma) {
            result = result + Text(string.substring(with: NSRange(location: offset, length: range.location - offset)))
            result = result + Text(string.substring(with: range)).bold().foregroundColor(.blue)
            offset = NSMaxRange(range)
        }
        return result + Text(string.substring(from: offset))
    }

    var body: some View { highlightedText }
}
