import SwiftData
import XCTest
@testable import LumaLex

@MainActor
final class MediaCleanupServiceTests: XCTestCase {
    func testDeletesOnlyMediaAndKeepsVocabularyAndReviews() throws {
        let container = try ModelContainer(for: AudioDocument.self, Transcript.self,
            SubtitleSegment.self, VocabularyItem.self, ReviewRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let audioDirectory = root.appendingPathComponent("Audio")
        let documents = root.appendingPathComponent("Documents")
        let imports = documents.appendingPathComponent("Imports/job")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: imports, withIntermediateDirectories: true)
        try Data().write(to: audioDirectory.appendingPathComponent("clip.mp3"))
        try Data().write(to: imports.appendingPathComponent("subtitle.srt"))
        try Data().write(to: documents.appendingPathComponent("old.vtt"))
        try Data().write(to: documents.appendingPathComponent("unrelated.txt"))

        let audio = AudioDocument(title: "Clip", localRelativePath: "clip.mp3")
        let transcript = Transcript(audioDocumentID: audio.id, source: "imported")
        let segment = SubtitleSegment(transcriptID: transcript.id, startTime: 0, endTime: 1,
            english: "Hello", chinese: "你好", tokens: ["Hello"])
        let word = VocabularyItem(word: "Hello", lemma: "hello", chineseMeaning: "你好",
            englishDefinition: "greeting", originalSentence: "Hello", sourceAudioID: audio.id)
        word.originalStartTime = 0
        let review = ReviewRecord(vocabularyID: word.id, date: .now, result: .remembered,
            previousStage: 0, newStage: 1)
        context.insert(audio)
        context.insert(transcript)
        context.insert(segment)
        context.insert(word)
        context.insert(review)
        try context.save()

        try MediaCleanupService.deleteAll(in: context, audioDirectory: audioDirectory,
            documentsDirectory: documents)

        XCTAssertTrue(try context.fetch(FetchDescriptor<AudioDocument>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<Transcript>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<SubtitleSegment>()).isEmpty)
        XCTAssertEqual(try context.fetch(FetchDescriptor<VocabularyItem>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ReviewRecord>()).count, 1)
        XCTAssertNil(word.sourceAudioID)
        XCTAssertNil(word.originalStartTime)
        XCTAssertFalse(FileManager.default.fileExists(atPath: audioDirectory.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: imports.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: documents.appendingPathComponent("old.vtt").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: documents.appendingPathComponent("unrelated.txt").path))
    }
}
