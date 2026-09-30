import Foundation
import XCTest
@testable import LumaLex

final class VocabularyServicesTests: XCTestCase {
    func testLearnedWordIsKnown() {
        let context = DifficultyContext(cefr: .a1, estimatedVocabulary: 500,
                                        knownLemmas: ["inevitable"])
        XCTAssertEqual(HeuristicVocabularyDifficultyService().classify("Inevitable,", context: context), .known)
    }

    func testDifficultyChangesWithLevel() {
        let service = HeuristicVocabularyDifficultyService()
        XCTAssertEqual(service.classify("perspective", context: .init(
            cefr: .a2, estimatedVocabulary: 1000, knownLemmas: [])), .difficult)
        XCTAssertEqual(service.classify("perspective", context: .init(
            cefr: .c2, estimatedVocabulary: 12000, knownLemmas: [])), .normal)
    }

    func testTechnicalTermIsSpecialized() {
        let context = DifficultyContext(cefr: .c2, estimatedVocabulary: 12000, knownLemmas: [])
        XCTAssertEqual(HeuristicVocabularyDifficultyService().classify("photosynthesis", context: context),
                       .specialized)
    }

    func testGeminiJSONRejectsMalformedAndIncompleteData() {
        XCTAssertThrowsError(try VocabularyExplanation.decode(Data("not json".utf8)))
        XCTAssertThrowsError(try VocabularyExplanation.decode(Data("{}".utf8)))
    }

    func testGeminiJSONDecodesTypedValue() throws {
        let data = Data("""
        {"word":"price in","lemma":"price in","ipa":"","part_of_speech":"phrase","chinese":"计入价格","definition":"reflect in a price","context_explanation":"expected cut","example":"It is priced in.","collocations":[],"difficulty_cefr":"B2","note":"finance"}
        """.utf8)
        let value = try VocabularyExplanation.decode(data)
        XCTAssertEqual(value.chinese, "计入价格")
        XCTAssertEqual(value.collocations, [])
    }

    func testDemoPhraseHasOfflineExplanationOnlyForDemoAudio() {
        let demo = DemoVocabularyExplanation.lookup("price in", audioID: DemoContentSeeder.audioID)
        XCTAssertEqual(demo?.lemma, "price in")
        XCTAssertNotNil(demo?.chinese)
        XCTAssertNil(DemoVocabularyExplanation.lookup("price in", audioID: UUID()))
    }

}
