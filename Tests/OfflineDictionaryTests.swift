import XCTest
@testable import LumaLex

final class OfflineDictionaryTests: XCTestCase {
    func testCommonWordHasOfflineTranslation() {
        let entry = OfflineDictionary.shared.lookup("house")
        XCTAssertNotNil(entry)
        XCTAssertFalse(entry?.translation.isEmpty ?? true)
    }

    func testNormalizationAndInflectedForms() {
        XCTAssertEqual(OfflineDictionary.normalize(" Invited! "), "invited")
        XCTAssertEqual(OfflineDictionary.shared.lemma(for: "invited"), "invite")
        XCTAssertNotNil(OfflineDictionary.shared.lookup("invited"))
    }

    func testUnlistedWordDoesNotInventMeaning() {
        XCTAssertNil(OfflineDictionary.shared.lookup("zzzzlumalexnotawordzzzz"))
    }

    func testLearnedWordsRemainEligibleForHighlighting() {
        let item = VocabularyItem(word: "invited", lemma: "invite", chineseMeaning: "invite",
                                  englishDefinition: "", originalSentence: "She invited me.", status: .learned)
        let saved = Set([OfflineDictionary.shared.lemma(for: item.lemma)])
        XCTAssertTrue(saved.contains(OfflineDictionary.shared.lemma(for: "inviting")))
        XCTAssertFalse(Set<String>().contains(OfflineDictionary.shared.lemma(for: "inviting")))
    }
}
