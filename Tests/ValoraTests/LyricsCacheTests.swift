import Foundation
import XCTest
@testable import Valora
import ReferenceCore

final class LyricsCacheTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("valora-cache-tests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private func result(_ text: String) -> LyricsFetchResult {
        .wordTimed(LyricTimeline(lines: [
            LyricLine(start: 0, text: text, words: [
                LyricWord(text: text, start: 0, duration: 1)
            ])
        ]))
    }

    func testMemoryEntryAndPayloadLimitsEvictOldest() async {
        let cache = LyricsCache(directory: directory, memoryEntryLimit: 2,
                                memoryPayloadLimit: 5 * 1024 * 1024, diskByteLimit: 50 * 1024 * 1024)
        await cache.put("one", result: result("one"))
        await cache.put("two", result: result("two"))
        await cache.put("three", result: result("three"))
        let stats = await cache.memoryStats()
        XCTAssertEqual(stats.count, 2)
        let third = await cache.get("three")
        XCTAssertNotNil(third)
        let after = await cache.memoryStats()
        XCTAssertEqual(after.count, 2, "memory must stay within its entry limit")
    }

    func testPayloadLimitRejectsOversizeEntry() async {
        let cache = LyricsCache(directory: directory, memoryEntryLimit: 50,
                                memoryPayloadLimit: 80, diskByteLimit: 50 * 1024 * 1024)
        await cache.put("oversize", result: result(String(repeating: "长", count: 100)))
        let stats = await cache.memoryStats()
        XCTAssertEqual(stats.count, 0)
        let loaded = await cache.get("oversize")
        XCTAssertNil(loaded)
    }

    func testDiskLimitAndCorruptFileProtection() async throws {
        let cache = LyricsCache(directory: directory, memoryEntryLimit: 50,
                                memoryPayloadLimit: 5 * 1024 * 1024, diskByteLimit: 700)
        await cache.put("one", result: result("one"))
        await cache.put("two", result: result("two"))
        let disk = await cache.diskStats()
        XCTAssertLessThanOrEqual(disk.bytes, 700)
        XCTAssertGreaterThan(disk.count, 0)
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        XCTAssertFalse(files.contains { $0.lastPathComponent.contains("one") || $0.lastPathComponent.contains("two") })
        // Corrupt a disk entry and ensure a fresh cache removes it instead of
        // exposing malformed data.
        let file = try XCTUnwrap(files.first)
        try Data("not-json".utf8).write(to: file)
        let fresh = LyricsCache(directory: directory, memoryEntryLimit: 50,
                                memoryPayloadLimit: 5 * 1024 * 1024, diskByteLimit: 700)
        let loaded = await fresh.get("one")
        XCTAssertNil(loaded)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testFailuresAreNotCachedAndSameVersionOverwrites() async {
        let cache = LyricsCache(directory: directory, memoryEntryLimit: 50,
                                memoryPayloadLimit: 5 * 1024 * 1024, diskByteLimit: 50 * 1024 * 1024)
        await cache.put("key", result: .noLyrics)
        let failed = await cache.get("key")
        XCTAssertNil(failed)
        await cache.put("key", result: result("first"))
        await cache.put("key", result: result("second"))
        let cached = await cache.get("key")
        guard case .wordTimed(let timeline) = cached else {
            return XCTFail("expected cached word timing")
        }
        XCTAssertEqual(timeline.lines.first?.text, "second")
        let stats = await cache.memoryStats()
        XCTAssertEqual(stats.count, 1, "same version must overwrite")
    }
}
