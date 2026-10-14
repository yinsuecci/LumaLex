import Foundation
import SwiftData

struct VocabularyExample {
    let sentence: String
    let translation: String
    let audioID: UUID?
    let startTime: TimeInterval?
}

@MainActor
enum DictionaryVocabularyService {
    static func example(for word: String, in context: ModelContext,
                        preferred: VocabularyExample? = nil) throws -> VocabularyExample? {
        let lemma = OfflineDictionary.shared.lemma(for: word)
        func matches(_ sentence: String) -> Bool {
            !ExampleHighlight.ranges(in: sentence, word: word, lemma: lemma).isEmpty
        }
        if let preferred, matches(preferred.sentence) { return preferred }
        let segments = try context.fetch(FetchDescriptor<SubtitleSegment>(sortBy: [SortDescriptor(\SubtitleSegment.startTime)]))
        guard let segment = segments.first(where: { matches($0.english) }) else { return nil }
        let transcript = try context.fetch(FetchDescriptor<Transcript>()).first { $0.id == segment.transcriptID }
        return VocabularyExample(sentence: segment.english, translation: segment.chinese,
                                 audioID: transcript?.audioDocumentID, startTime: segment.startTime)
    }

    @discardableResult
    static func add(_ entry: OfflineDictionaryEntry, in context: ModelContext,
                    example: VocabularyExample? = nil) throws -> VocabularyItem {
        let dictionary = OfflineDictionary.shared
        let lemma = dictionary.lemma(for: entry.word)
        if let existing = try context.fetch(FetchDescriptor<VocabularyItem>()).first(where: {
            dictionary.lemma(for: $0.lemma) == lemma
        }) { return existing }
        let state = ReviewScheduler.initial(at: .now)
        let item = VocabularyItem(word: entry.word, lemma: lemma, pronunciation: entry.phonetic,
            partOfSpeech: entry.pos, chineseMeaning: entry.translation.replacingOccurrences(of: "\\n", with: "\n"),
            englishDefinition: entry.definition.replacingOccurrences(of: "\\n", with: "\n"),
            originalSentence: example?.sentence ?? "", sourceAudioID: example?.audioID,
            reviewStage: state.stage, nextReviewDate: state.nextReviewDate)
        item.originalTranslation = example?.translation
        item.originalStartTime = example?.startTime
        item.dictionarySource = "ECDICT (offline)"
        context.insert(item)
        do { try context.save() }
        catch { context.rollback(); throw error }
        return item
    }
}
