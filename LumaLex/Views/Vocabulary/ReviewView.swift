import SwiftData
import SwiftUI
import UIKit

struct ReviewView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var words: [VocabularyItem]
    @State private var queue: [UUID] = []
    @State private var currentIndex = 0
    @State private var isRevealed = false
    @State private var saveError: String?

    private var currentWord: VocabularyItem? {
        guard currentIndex < queue.count else { return nil }
        return words.first { $0.id == queue[currentIndex] }
    }

    var body: some View {
        ScrollView {
        VStack(spacing: 24) {
            if let word = currentWord {
                Text("\(currentIndex + 1) / \(queue.count)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 24)
                Text(word.word)
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                if let pronunciation = word.pronunciation, !pronunciation.isEmpty {
                    Text(pronunciation)
                        .foregroundStyle(.secondary)
                }

                if isRevealed {
                    VStack(spacing: 14) {
                        Text(word.chineseMeaning)
                            .font(.title3)
                        Text(word.englishDefinition)
                            .foregroundStyle(.secondary)
                        Text(word.originalSentence)
                            .italic()
                    }
                    .multilineTextAlignment(.center)
                    .accessibilityElement(children: .combine)
                }
            } else {
                ContentUnavailableView("Review Complete", systemImage: "checkmark.circle",
                                       description: Text("There are no more words due in this session."))
            }
        }
        .padding(24)
        }
        .safeAreaInset(edge: .bottom) {
            if let word = currentWord {
                HStack {
                    if isRevealed {
                        Button("Forgot") { record(.forgot, for: word) }
                            .buttonStyle(.bordered)
                        Button("Remember") { record(.remembered, for: word) }
                            .buttonStyle(.borderedProminent)
                    } else {
                        Button("Reveal") {
                            isRevealed = true
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .padding()
                .background(.regularMaterial)
            }
        }
        .navigationTitle("Review")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: prepareQueue)
        .alert("Could Not Save Review", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK", role: .cancel) { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
    }

    private func prepareQueue() {
        guard queue.isEmpty else { return }
        queue = words
            .filter {
                ReviewScheduler.isDue(
                    ReviewState(stage: $0.reviewStage, nextReviewDate: $0.nextReviewDate, status: $0.status),
                    at: .now
                )
            }
            .sorted { $0.nextReviewDate < $1.nextReviewDate }
            .map(\.id)
    }

    private func record(_ result: ReviewResult, for word: VocabularyItem) {
        let date = Date.now
        let previousStage = word.reviewStage
        let state = ReviewScheduler.transition(
            from: ReviewState(stage: previousStage, nextReviewDate: word.nextReviewDate, status: word.status),
            result: result,
            at: date
        )
        word.reviewStage = state.stage
        word.nextReviewDate = state.nextReviewDate
        word.status = state.status
        modelContext.insert(ReviewRecord(vocabularyID: word.id, date: date, result: result,
                                         previousStage: previousStage, newStage: state.stage))
        do {
            try modelContext.save()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            currentIndex += 1
            isRevealed = false
        } catch {
            modelContext.rollback()
            saveError = error.localizedDescription
        }
    }
}

