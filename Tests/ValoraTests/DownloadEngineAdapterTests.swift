import Foundation
import XCTest
@testable import Valora

@MainActor
final class DownloadEngineAdapterTests: XCTestCase {
    func testPinnedEngineProductIsLinkedWithoutManagerStartup() {
        XCTAssertTrue(DownloadEngineCompatibility.isLinked)
        // Adapter source intentionally contains no DownloadManager/AppSettings
        // singleton access; this test only proves the product can be linked and
        // mapped without touching user paths.
        XCTAssertEqual(DownloadEngineCompatibility.state(.paused), .paused)
        XCTAssertEqual(DownloadEngineCompatibility.state(.completed), .completed)
        XCTAssertEqual(DownloadEngineCompatibility.state(.failed(nil)), .failed)
        XCTAssertEqual(DownloadEngineCompatibility.state(.cancelled), .cancelled)
    }

    func testPureDownloadTaskSnapshotMapping() {
        let snapshot = DownloadEngineCompatibility.verificationSnapshot()
        XCTAssertEqual(snapshot.filename, "fixture.bin")
        XCTAssertEqual(snapshot.state, .paused)
        XCTAssertEqual(snapshot.progress, 0.25, accuracy: 0.0001)
        XCTAssertEqual(snapshot.downloadedBytes, 250)
        XCTAssertEqual(snapshot.totalBytes, 1_000)
        XCTAssertTrue(snapshot.segments.isEmpty)
    }

    func testFakeServiceNeverCreatesAnEngineManager() async throws {
        let service = FakeDownloadService()
        let source = URL(string: "https://example.invalid/file")!
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("fake-download")
        try await service.enqueue(source: source, destination: destination)
        let item = try XCTUnwrap(service.items.first)
        XCTAssertEqual(item.state, .waiting)
        await service.pause(id: item.id)
        XCTAssertEqual(service.items.first?.state, .paused)
        try await service.resume(id: item.id)
        XCTAssertEqual(service.items.first?.state, .downloading)
        await service.cancel(id: item.id)
        XCTAssertTrue(service.items.isEmpty)
    }
}
