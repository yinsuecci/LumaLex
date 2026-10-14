import SwiftData
import XCTest
@testable import LumaLex

final class ListeningVocabularyFeatureTests: XCTestCase {
    private var subtitles: [ParsedSubtitle] {
        [ParsedSubtitle(start: 1, end: 3, english: "First.", chinese: ""),
         ParsedSubtitle(start: 5, end: 7, english: "Second.", chinese: "")]
    }

    func testEverySentenceGetsExactlyTwoPasses() {
        var state = SentenceRepeatState()
        state.reset(at: 0, subtitles: subtitles)
        XCTAssertEqual(state.index, 0)
        XCTAssertEqual(state.advance(subtitles: subtitles), 1)
        XCTAssertEqual(state.pass, 2)
        XCTAssertEqual(state.advance(subtitles: subtitles), 5)
        XCTAssertEqual(state.pass, 1)
        XCTAssertEqual(state.advance(subtitles: subtitles), 5)
        XCTAssertNil(state.advance(subtitles: subtitles))
        XCTAssertNil(state.index)
    }

    func testSeekingResetsPassAndHandlesGapsAndEnd() {
        var state = SentenceRepeatState()
        state.reset(at: 2, subtitles: subtitles)
        _ = state.advance(subtitles: subtitles)
        state.reset(at: 4, subtitles: subtitles)
        XCTAssertEqual(state.index, 1)
        XCTAssertEqual(state.pass, 1)
        state.reset(at: 7, subtitles: subtitles)
        XCTAssertNil(state.index)
        state.reset(at: 0, subtitles: [])
        XCTAssertNil(state.advance(subtitles: []))
    }

    func testHighlightMarksWholeWordsAndInflections() {
        let sentence = "Invited guests invite friends; inviting is kind. Uninvited is different."
        let ranges = ExampleHighlight.ranges(in: sentence, word: "invite", lemma: "invite")
        XCTAssertEqual(ranges.map { (sentence as NSString).substring(with: $0) }, ["Invited", "invite", "inviting"])
        XCTAssertTrue(ExampleHighlight.ranges(in: "Canada and Canadian", word: "Canada", lemma: "Canada").count == 1)
    }

    func testPhraseAndUnicodePrefixHighlight() {
        let sentence = "你好：The market priced in the cut."
        let ranges = ExampleHighlight.ranges(in: sentence, word: "priced in", lemma: "price in")
        XCTAssertEqual(ranges.map { (sentence as NSString).substring(with: $0) }, ["priced in"])
        XCTAssertTrue(ExampleHighlight.ranges(in: sentence, word: "", lemma: "").isEmpty)
    }

    @MainActor
    func testLookupSaveIsIdempotentAndRetainsExample() throws {
        let container = try ModelContainer(for: VocabularyItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let entry = try XCTUnwrap(OfflineDictionary.shared.lookup("invited"))
        let example = VocabularyExample(sentence: "She invited me.", translation: "她邀请了我。",
                                        audioID: UUID(), startTime: 12)
        let first = try DictionaryVocabularyService.add(entry, in: container.mainContext, example: example)
        let second = try DictionaryVocabularyService.add(entry, in: container.mainContext)
        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(first.originalSentence, example.sentence)
        XCTAssertEqual(first.originalTranslation, example.translation)
        XCTAssertEqual(first.originalStartTime, 12)
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<VocabularyItem>()).count, 1)
    }

    @MainActor
    func testLookupNeverAssignsUnrelatedExample() throws {
        let container = try ModelContainer(for: Transcript.self, SubtitleSegment.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let unrelated = VocabularyExample(sentence: "Hello world.", translation: "", audioID: nil, startTime: nil)
        XCTAssertNil(try DictionaryVocabularyService.example(for: "invite", in: container.mainContext, preferred: unrelated))
        let matching = VocabularyExample(sentence: "She invited me.", translation: "", audioID: nil, startTime: nil)
        XCTAssertEqual(try DictionaryVocabularyService.example(for: "invite", in: container.mainContext, preferred: matching)?.sentence,
                       matching.sentence)
    }
}
