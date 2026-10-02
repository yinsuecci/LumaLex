import SwiftData
import XCTest
@testable import LumaLex

@MainActor
final class BatchImportServiceTests: XCTestCase {
    func testImportAndRetryPreserveExistingTranscript() async throws {
        let container = try ModelContainer(for: AudioDocument.self, Transcript.self, SubtitleSegment.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let job = root.appendingPathComponent("Imports/test")
        let id = UUID()
        func stage() throws {
            try FileManager.default.createDirectory(at: job, withIntermediateDirectories: true)
            let demo = try XCTUnwrap(Bundle.main.url(forResource: "Demo", withExtension: "wav"))
            try FileManager.default.copyItem(at: demo, to: job.appendingPathComponent("audio.wav"))
            try "1\n00:00:00,000 --> 00:00:02,000\nHello world.\n你好世界。\n".write(
                to: job.appendingPathComponent("subtitle.srt"), atomically: true, encoding: .utf8)
            let manifest = BatchImportManifest(items: [.init(id: id, title: "Batch test",
                audio: "audio.wav", subtitle: "subtitle.srt")])
            try JSONEncoder().encode(manifest).write(to: job.appendingPathComponent("manifest.json"))
        }
        try stage()
        try await BatchImportService.run(in: container.mainContext, documentsDirectory: root)
        let audio = try container.mainContext.fetch(FetchDescriptor<AudioDocument>())
        XCTAssertEqual(audio.count, 1)
        defer { if let path = audio.first?.localRelativePath { try? FileManager.default.removeItem(at: AudioStorage.url(for: path)) } }
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<SubtitleSegment>()).first?.chinese, "你好世界。")
        XCTAssertFalse(FileManager.default.fileExists(atPath: job.path))
        try stage()
        try await BatchImportService.run(in: container.mainContext, documentsDirectory: root)
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<AudioDocument>()).count, 1)
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<Transcript>()).count, 1)
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<SubtitleSegment>()).count, 1)
    }

    func testRejectsPathTraversalAndRetainsFailedJob() async throws {
        let container = try ModelContainer(for: AudioDocument.self, Transcript.self, SubtitleSegment.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let job = root.appendingPathComponent("Imports/test")
        try FileManager.default.createDirectory(at: job, withIntermediateDirectories: true)
        let manifest = BatchImportManifest(items: [.init(id: UUID(), title: "Invalid",
            audio: "../audio.wav", subtitle: "subtitle.srt")])
        try JSONEncoder().encode(manifest).write(to: job.appendingPathComponent("manifest.json"))
        try await BatchImportService.run(in: container.mainContext, documentsDirectory: root)
        XCTAssertTrue(FileManager.default.fileExists(atPath: job.path))
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<AudioDocument>()).isEmpty)
        let data = try Data(contentsOf: root.appendingPathComponent("ImportReports/test.json"))
        let report = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual((report["errors"] as? [String])?.count, 1)
    }
}
