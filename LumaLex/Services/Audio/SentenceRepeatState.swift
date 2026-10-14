import Foundation

struct SentenceRepeatState {
    private(set) var index: Int?
    private(set) var pass = 1

    mutating func reset(at time: TimeInterval, subtitles: [ParsedSubtitle]) {
        index = subtitles.firstIndex { $0.end > time && $0.end > $0.start }
        pass = 1
    }

    // Returns the next sentence start to seek to, or nil when both passes are complete.
    mutating func advance(subtitles: [ParsedSubtitle]) -> TimeInterval? {
        guard let index, subtitles.indices.contains(index) else { return nil }
        if pass == 1 {
            pass = 2
            return subtitles[index].start
        }
        if index + 1 < subtitles.count {
            self.index = index + 1
            pass = 1
            return subtitles[index + 1].start
        }
        self.index = nil
        pass = 1
        return nil
    }
}
