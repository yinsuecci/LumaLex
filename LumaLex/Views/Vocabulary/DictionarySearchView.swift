import SwiftData
import SwiftUI

struct DictionarySearchView: View {
    @Environment(\.modelContext) private var context
    @Query private var words: [VocabularyItem]
    @State private var query = ""
    @State private var entry: OfflineDictionaryEntry?
    @State private var example: VocabularyExample?
    @State private var searched = false
    @State private var error: String?
    var preferredExample: VocabularyExample? = nil

    private var alreadySaved: Bool {
        guard let entry else { return false }
        let dictionary = OfflineDictionary.shared
        return words.contains { dictionary.lemma(for: $0.lemma) == dictionary.lemma(for: entry.word) }
    }

    var body: some View {
        List {
            Section {
                TextField("English word or phrase", text: $query)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .submitLabel(.search).onSubmit(perform: search)
                    .onChange(of: query) { _, _ in entry = nil; example = nil; searched = false }
                Button("Look Up", systemImage: "magnifyingglass", action: search)
                    .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if let entry {
                Section("Offline Dictionary") {
                    Text(entry.word).font(.title2.bold())
                    if !entry.phonetic.isEmpty { Text(entry.phonetic).foregroundStyle(.secondary) }
                    Text(entry.translation.replacingOccurrences(of: "\\n", with: "\n"))
                    if !entry.definition.isEmpty {
                        Text(entry.definition.replacingOccurrences(of: "\\n", with: "\n")).foregroundStyle(.secondary)
                    }
                    Text("ECDICT (offline)").font(.caption).foregroundStyle(.secondary)
                }
                if let example {
                    Section("Original Example") {
                        HighlightedExample(sentence: example.sentence, word: entry.word,
                                           lemma: OfflineDictionary.shared.lemma(for: entry.word))
                        if !example.translation.isEmpty { Text(example.translation).foregroundStyle(.secondary) }
                    }
                }
                Section {
                    Button(alreadySaved ? "Already in Vocabulary" : "Add to Vocabulary") {
                        do { try DictionaryVocabularyService.add(entry, in: context, example: example) }
                        catch { self.error = error.localizedDescription }
                    }.disabled(alreadySaved)
                }
            } else if searched {
                Text("No entry found in the offline dictionary.").foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Dictionary")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Dictionary Error", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) { error = nil }
        } message: { Text(error ?? "") }
    }

    private func search() {
        searched = true
        entry = OfflineDictionary.shared.lookup(query)
        do { example = try DictionaryVocabularyService.example(for: query, in: context, preferred: preferredExample) }
        catch { self.error = error.localizedDescription }
    }
}
