import Foundation
import SwiftData

enum VocabularyStatus: String, CaseIterable, Codable {
    case learning, learned
}

@Model
final class VocabularyItem {
    @Attribute(.unique) var id: UUID
    var word: String
    var lemma: String
    var pronunciation: String?
    var partOfSpeech: String?
    var chineseMeaning: String
    var englishDefinition: String
    var originalSentence: String
    var originalTranslation: String? = nil
    var originalStartTime: TimeInterval? = nil
    var dictionarySource: String? = nil
    var sourceAudioID: UUID?
    var createdAt: Date
    var reviewStage: Int
    var nextReviewDate: Date
    var statusRaw: String

    var status: VocabularyStatus {
        get { VocabularyStatus(rawValue: statusRaw) ?? .learning }
        set { statusRaw = newValue.rawValue }
    }

    init(id: UUID = UUID(), word: String, lemma: String, pronunciation: String? = nil,
         partOfSpeech: String? = nil, chineseMeaning: String, englishDefinition: String,
         originalSentence: String, sourceAudioID: UUID? = nil, createdAt: Date = .now,
         reviewStage: Int = 0, nextReviewDate: Date = .now, status: VocabularyStatus = .learning) {
        self.id = id
        self.word = word
        self.lemma = lemma
        self.pronunciation = pronunciation
        self.partOfSpeech = partOfSpeech
        self.chineseMeaning = chineseMeaning
        self.englishDefinition = englishDefinition
        self.originalSentence = originalSentence
        self.sourceAudioID = sourceAudioID
        self.createdAt = createdAt
        self.reviewStage = reviewStage
        self.nextReviewDate = nextReviewDate
        self.statusRaw = status.rawValue
    }
}

