import Foundation
import SwiftData

@MainActor
enum MediaCleanupService {
    private static let upgradeKey = "clearedExistingMediaOctober2026"
    private static let mediaExtensions: Set<String> = ["mp3", "m4a", "wav", "aac", "flac", "aiff",
                                                       "caf", "mp4", "ogg", "opus", "srt", "vtt",
                                                       "lrc", "ass", "ssa"]

    static func clearExistingMediaOnce(in context: ModelContext) throws {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: upgradeKey) else { return }
        let hasExistingLibrary = !((try context.fetch(FetchDescriptor<AudioDocument>())).isEmpty)
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let rootMedia = (try? FileManager.default.contentsOfDirectory(at: documents,
            includingPropertiesForKeys: nil))?.contains { mediaExtensions.contains($0.pathExtension.lowercased()) } ?? false
        let hasExistingFiles = FileManager.default.fileExists(atPath: AudioStorage.directory.path) ||
            FileManager.default.fileExists(atPath: documents.appendingPathComponent("Imports").path) || rootMedia
        try deleteAll(in: context)
        if defaults.bool(forKey: "didSeedDemo") || hasExistingLibrary || hasExistingFiles {
            defaults.set(true, forKey: "didSeedDemo")
        }
        defaults.set(true, forKey: upgradeKey)
    }

    static func deleteAll(in context: ModelContext,
                          audioDirectory: URL = AudioStorage.directory,
                          documentsDirectory: URL? = nil) throws {
        let files = FileManager.default
        let documents = documentsDirectory ?? files.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let audio = try context.fetch(FetchDescriptor<AudioDocument>())
        let transcripts = try context.fetch(FetchDescriptor<Transcript>())
        let segments = try context.fetch(FetchDescriptor<SubtitleSegment>())
        let vocabulary = try context.fetch(FetchDescriptor<VocabularyItem>())
        let audioIDs = Set(audio.map(\.id))

        for item in vocabulary where item.sourceAudioID.map(audioIDs.contains) == true {
            item.sourceAudioID = nil
            item.originalStartTime = nil
        }
        for item in segments { context.delete(item) }
        for item in transcripts { context.delete(item) }
        for item in audio { context.delete(item) }
        do { try context.save() }
        catch {
            context.rollback()
            throw error
        }

        if files.fileExists(atPath: audioDirectory.path) { try files.removeItem(at: audioDirectory) }
        let imports = documents.appendingPathComponent("Imports", isDirectory: true)
        if files.fileExists(atPath: imports.path) { try files.removeItem(at: imports) }
        guard files.fileExists(atPath: documents.path) else { return }
        for url in try files.contentsOfDirectory(at: documents, includingPropertiesForKeys: [.isRegularFileKey]) {
            guard mediaExtensions.contains(url.pathExtension.lowercased()),
                  (try url.resourceValues(forKeys: [.isRegularFileKey])).isRegularFile == true else { continue }
            try files.removeItem(at: url)
        }
    }
}
