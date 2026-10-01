import SwiftData
import SwiftUI

struct VocabularyDetailView: View {
    @Query(sort: \ReviewRecord.date, order: .reverse) private var allReviews: [ReviewRecord]
    let item: VocabularyItem

    private var reviews: [ReviewRecord] {
        allReviews.filter { $0.vocabularyID == item.id }
    }

    var body: some View {
        List {
            Section {
                Text(item.word).font(.title.bold())
                if let pronunciation = item.pronunciation { Text(pronunciation).foregroundStyle(.secondary) }
                Text(item.chineseMeaning)
                if !item.englishDefinition.isEmpty { Text(item.englishDefinition).foregroundStyle(.secondary) }
                if let source = item.dictionarySource {
                    Text("Dictionary: \(source)").font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Original Example") {
                Text(item.originalSentence).italic()
                if let translation = item.originalTranslation, !translation.isEmpty {
                    Text(translation).foregroundStyle(.secondary)
                }
            }
            Section("Progress") {
                LabeledContent("Status", value: item.status == .learned ? "Learned" : "Learning")
                LabeledContent("Stage", value: "\(item.reviewStage) / 4")
                if item.status == .learning {
                    LabeledContent("Next review", value: item.nextReviewDate.formatted(date: .abbreviated,
                                                                                         time: .omitted))
                }
            }
            if !reviews.isEmpty {
                Section("Review History") {
                    ForEach(reviews) { record in
                        HStack {
                            Text(record.result == .remembered ? "Remembered" : "Forgot")
                            Spacer()
                            Text(record.date, style: .date).foregroundStyle(.secondary)
                        }
                        .font(.subheadline)
                    }
                }
            }
        }
        .navigationTitle(item.word)
        .navigationBarTitleDisplayMode(.inline)
    }
}

