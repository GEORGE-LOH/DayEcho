import XCTest
@testable import DayEcho

final class EvidenceTests: XCTestCase {
    private func clip(text: String? = "周五下午三点确认交付") -> Clip {
        let id = UUID()
        return Clip(id: id, sessionID: UUID(), startedAt: Date(), duration: 12,
                    source: "Test", filename: id.uuidString + ".m4a", transcript: text, marked: false)
    }

    func testEmptyTranscriptsCannotBeSent() {
        XCTAssertThrowsError(try EvidenceBundle(clips: [clip(text: nil), clip(text: "")]))
    }

    func testOversizedEvidenceIsRejectedRatherThanSilentlyTruncated() {
        XCTAssertThrowsError(try EvidenceBundle(clips: [clip(text: String(repeating: "字", count: 24_001))]))
    }

    func testOnlyExactKnownCitationsBecomeSourceLinks() throws {
        let source = clip()
        let bundle = try EvidenceBundle(clips: [source])
        XCTAssertEqual(bundle.validatedSourceIDs(in: "待办 [\(source.id.uuidString)]"), [source.id])
        XCTAssertTrue(bundle.validatedSourceIDs(in: "无效 [\(UUID().uuidString)]").isEmpty)
        XCTAssertTrue(bundle.validatedSourceIDs(in: source.id.uuidString).isEmpty)
    }

    func testEndpointRejectsPlaintextAndEmbeddedCredentials() {
        for address in ["http://api.example.com/v1", "https://key@api.example.com/v1", "https://api.example.com/v1?key=secret"] {
            XCTAssertThrowsError(try AIConfiguration(baseURL: address, model: "test").endpoint())
        }
    }

    func testCompatibleEndpointConstruction() throws {
        XCTAssertEqual(try AIConfiguration(baseURL: "https://api.example.com/v1/", model: "test").endpoint().absoluteString,
                       "https://api.example.com/v1/chat/completions")
    }
}

@MainActor
final class LibraryTests: XCTestCase {
    func testDuplicateTransferAndDeletionTombstoneSurviveRelaunch() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceDirectory = root.appendingPathComponent("Incoming")
        try LocalFiles.prepare(sourceDirectory)
        let id = UUID()
        let file = sourceDirectory.appendingPathComponent(id.uuidString + ".m4a")
        try Data("test audio payload".utf8).write(to: file)
        let clip = Clip(id: id, sessionID: id, startedAt: Date(), duration: 1,
                        source: "Test", filename: file.lastPathComponent, marked: false)
        let segment = RecordedSegment(url: file, clip: clip)
        let library = LibraryStore(root: root.appendingPathComponent("Library"))
        try library.add(segment)
        try library.add(segment)
        XCTAssertEqual(library.clips.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: library.url(for: clip).path))
        try library.delete(clip)
        XCTAssertFalse(FileManager.default.fileExists(atPath: library.url(for: clip).path))
        let reloaded = LibraryStore(root: root.appendingPathComponent("Library"))
        try reloaded.add(segment)
        XCTAssertTrue(reloaded.clips.isEmpty)
    }

    func testCorruptIndexIsPreservedAndNotOverwritten() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try LocalFiles.prepare(root)
        let index = root.appendingPathComponent("library.json")
        let corrupt = Data("broken index".utf8)
        try corrupt.write(to: index)
        let library = LibraryStore(root: root)
        XCTAssertNotNil(library.error)
        XCTAssertEqual(try Data(contentsOf: index), corrupt)
    }
}
