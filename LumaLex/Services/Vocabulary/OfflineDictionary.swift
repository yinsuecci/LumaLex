import Foundation

struct OfflineDictionaryEntry: Codable {
    let word: String
    let phonetic: String
    let translation: String
    let definition: String
    let pos: String
    let exchange: String
}

final class OfflineDictionary {
    static let shared = OfflineDictionary()
    private let entries: [String: OfflineDictionaryEntry]
    private let aliases: [String: String]

    init() {
        let data = Bundle.main.url(forResource: "OfflineDictionary", withExtension: "json")
            .flatMap { try? Data(contentsOf: $0) }
        let values = data.flatMap { try? JSONDecoder().decode([OfflineDictionaryEntry].self, from: $0) } ?? []
        var entries: [String: OfflineDictionaryEntry] = [:]
        var aliases: [String: String] = [:]
        for entry in values {
            let lemma = Self.normalize(entry.word)
            if entries[lemma] == nil { entries[lemma] = entry }
            for exchange in entry.exchange.split(separator: "/") {
                let parts = exchange.split(separator: ":", maxSplits: 1)
                guard parts.count == 2 else { continue }
                if parts[0] == "0" { aliases[lemma] = Self.normalize(String(parts[1])) }
                else if ["p", "d", "i", "3", "r", "t", "s"].contains(String(parts[0])) {
                    for form in parts[1].split(separator: ",") {
                        let key = Self.normalize(String(form))
                        if aliases[key] == nil { aliases[key] = lemma }
                    }
                }
            }
        }
        self.entries = entries
        self.aliases = aliases
    }

    static func normalize(_ word: String) -> String {
        word.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: .punctuationCharacters)
    }

    func lemma(for word: String) -> String {
        let key = Self.normalize(word)
        return aliases[key] ?? key
    }

    func lookup(_ word: String) -> OfflineDictionaryEntry? {
        entries[lemma(for: word)] ?? entries[Self.normalize(word)]
    }
}
