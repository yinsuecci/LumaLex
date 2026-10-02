import Foundation
import SwiftData

struct BatchImportManifest: Codable {
    struct Item: Codable {
        let id: UUID
        let title: String
        let audio: String
        let subtitle: String
    }
    let items: [Item]
}

@MainActor
enum BatchImportService {
    private struct Report: Codable {
        let imported: Int
        let skipped: Int
        let errors: [String]
    }

    static func run(in context: ModelContext, documentsDirectory: URL? = nil) async throws {
        let files = FileManager.default
        let documents = documentsDirectory ?? files.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let inbox = documents.appendingPathComponent("Imports", isDirectory: true)
        guard files.fileExists(atPath: inbox.path) else { return }
        let jobs = try files.contentsOfDirectory(at: inbox, includingPropertiesForKeys: [.isDirectoryKey])
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        for job in jobs {
            let manifestURL = job.appendingPathComponent("manifest.json")
            guard files.fileExists(atPath: manifestURL.path) else { continue }
            let manifest = try JSONDecoder().decode(BatchImportManifest.self, from: Data(contentsOf: manifestURL))
            var imported = 0
            var skipped = 0
            var errors: [String] = []
            for item in manifest.items {
                var copiedPath: String?
                do {
                    let audioURL = try child(item.audio, in: job)
                    let subtitleURL = try child(item.subtitle, in: job)
                    let existing = try context.fetch(FetchDescriptor<AudioDocument>())
                        .first { $0.id == item.id || $0.title == item.title }
                    let document: AudioDocument
                    if let existing {
                        document = existing
                    } else {
                        let audio = try await AudioStorage.importAudio(from: audioURL)
                        copiedPath = audio.path
                        document = AudioDocument(id: item.id, title: item.title,
                                                 localRelativePath: audio.path, duration: audio.duration)
                        context.insert(document)
                    }
                    let hasTranscript = try context.fetch(FetchDescriptor<Transcript>())
                        .contains { $0.audioDocumentID == document.id }
                    if !hasTranscript {
                        let parsed = TranscriptParser.parse(try AudioStorage.readTranscript(from: subtitleURL))
                        guard !parsed.isEmpty else { throw BatchImportError.invalidSubtitle }
                        let transcript = Transcript(audioDocumentID: document.id, source: "usb-batch")
                        context.insert(transcript)
                        for segment in parsed {
                            context.insert(SubtitleSegment(transcriptID: transcript.id,
                                startTime: segment.start, endTime: segment.end,
                                english: segment.english, chinese: segment.chinese,
                                tokens: segment.english.split(separator: " ").map(String.init)))
                        }
                    }
                    try context.save()
                    if existing != nil && hasTranscript { skipped += 1 } else { imported += 1 }
                } catch {
                    context.rollback()
                    if let copiedPath { try? files.removeItem(at: AudioStorage.url(for: copiedPath)) }
                    errors.append("\(item.title): \(error.localizedDescription)")
                }
            }
            let report = Report(imported: imported, skipped: skipped, errors: errors)
            let reports = documents.appendingPathComponent("ImportReports", isDirectory: true)
            try files.createDirectory(at: reports, withIntermediateDirectories: true)
            try JSONEncoder().encode(report).write(to: reports.appendingPathComponent(job.lastPathComponent + ".json"), options: .atomic)
            // Keep failed jobs for retry; remove the staging copies only after every item is saved.
            if errors.isEmpty { try files.removeItem(at: job) }
        }
    }

    private static func child(_ name: String, in directory: URL) throws -> URL {
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains("\\") else {
            throw BatchImportError.invalidFilename
        }
        return directory.appendingPathComponent(name)
    }
}

enum BatchImportError: LocalizedError {
    case invalidFilename, invalidSubtitle
    var errorDescription: String? {
        switch self {
        case .invalidFilename: return "Invalid batch import filename."
        case .invalidSubtitle: return "No valid timed subtitles found."
        }
    }
}
