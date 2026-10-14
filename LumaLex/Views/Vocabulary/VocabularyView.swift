import SwiftData
import SwiftUI

private enum VocabularyFilter: String, CaseIterable {
    case learning = "Learning"
    case learned = "Learned"
    case all = "All"
}

struct VocabularyView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \VocabularyItem.createdAt, order: .reverse) private var words: [VocabularyItem]
    @Query private var reviews: [ReviewRecord]
    @State private var searchText = ""
    @State private var filter: VocabularyFilter = .learning
    @State private var errorMessage: String?

    private var visibleWords: [VocabularyItem] {
        words.filter { item in
            let matchesStatus = filter == .all || item.statusRaw == filter.rawValue.lowercased()
            let matchesSearch = searchText.isEmpty ||
                item.word.localizedCaseInsensitiveContains(searchText) ||
                item.chineseMeaning.localizedCaseInsensitiveContains(searchText)
            return matchesStatus && matchesSearch
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Status", selection: $filter) {
                ForEach(VocabularyFilter.allCases, id: \.self) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)

            if words.isEmpty && searchText.isEmpty {
                ContentUnavailableView("No Words Yet", systemImage: "text.book.closed",
                                       description: Text("Words you save while listening will appear here."))
            } else if visibleWords.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                List {
                    ForEach(visibleWords) { item in
                        NavigationLink {
                            VocabularyDetailView(item: item)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.word)
                                    .font(.headline)
                                Text(item.chineseMeaning)
                                    .foregroundStyle(.secondary)
                                if !item.originalSentence.isEmpty {
                                    HighlightedExample(sentence: item.originalSentence, word: item.word, lemma: item.lemma).font(.subheadline)
                                        .foregroundStyle(.secondary).lineLimit(3)
                                }
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                    .onDelete(perform: deleteWords)
                }
            }
        }
        .navigationTitle("Vocabulary")
        .toolbar {
            NavigationLink {
                DictionarySearchView()
            } label: { Label("Look Up Word", systemImage: "magnifyingglass") }
        }
        .searchable(text: $searchText)
        .alert("Could Not Delete Word", isPresented: Binding(get: { errorMessage != nil },
                                                              set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private func deleteWords(at offsets: IndexSet) {
        let selected = offsets.map { visibleWords[$0] }
        let ids = Set(selected.map(\.id))
        for review in reviews where ids.contains(review.vocabularyID) { modelContext.delete(review) }
        for word in selected { modelContext.delete(word) }
        do { try modelContext.save() }
        catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
    }
}
