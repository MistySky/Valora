import Foundation
import XCTest
@testable import ReferenceCore

final class QQMusicQRCTests: XCTestCase {
    private func fixtureHex() throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().appendingPathComponent("Fixtures/qq-qrc-studio.hex")
        return try String(contentsOf: url, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func testRealPublicQRCFixtureDecryptsAndContainsRealWordTiming() throws {
        let hex = try fixtureHex()
        let decrypted = try XCTUnwrap(QQMusicQRC.decrypt(hex: hex))
        XCTAssertTrue(decrypted.contains("QrcInfos"))
        let lines = try XCTUnwrap(QQMusicQRC.parseLyrics(decrypted: decrypted))
        XCTAssertEqual(lines.count, 63)
        let words = lines.reduce(0) { $0 + $1.words.count }
        XCTAssertEqual(words, 602)
        let first = try XCTUnwrap(lines.first?.words.first)
        XCTAssertGreaterThanOrEqual(first.start, 0)
        XCTAssertGreaterThan(first.duration, 0)
        XCTAssertFalse(lines.first?.text.isEmpty ?? true)
    }

    func testMalformedQRCIsRejectedWithoutInventedWords() {
        XCTAssertNil(QQMusicQRC.decrypt(hex: "not-hex"))
        XCTAssertNil(QQMusicQRC.decrypt(hex: "00"))
        XCTAssertNil(QQMusicQRC.parseLyrics(decrypted: "<QrcInfos/>"))
    }

    func testReadingWindowClampsAndFollowsAtSixtyFivePercent() {
        XCTAssertEqual(LyricsLineLayout.horizontalOffset(currentWordCenter: 20, totalWidth: 200,
                                                          availableWidth: 100), 0)
        XCTAssertEqual(LyricsLineLayout.horizontalOffset(currentWordCenter: 90, totalWidth: 200,
                                                          availableWidth: 100), 25)
        XCTAssertEqual(LyricsLineLayout.horizontalOffset(currentWordCenter: 190, totalWidth: 200,
                                                          availableWidth: 100), 100)
        XCTAssertEqual(LyricsLineLayout.fillWidth(prefixWidth: 10, currentWordWidth: 20,
                                                   fraction: 0.5, totalWidth: 200), 20)
        XCTAssertEqual(LyricsLineLayout.fillWidth(prefixWidth: 10, currentWordWidth: 20,
                                                   fraction: 2, totalWidth: 15), 15)
    }
}

final class LyricsContinuousOffsetTests: XCTestCase {
    func testOffsetMovesContinuouslyWithinMultiCharacterWord() {
        let total: CGFloat = 400
        let available: CGFloat = 160
        let early = LyricsLineLayout.followingOffset(prefixWidth: 80, currentWordWidth: 120,
                                                      fraction: 0.1, totalWidth: total,
                                                      availableWidth: available)
        let middle = LyricsLineLayout.followingOffset(prefixWidth: 80, currentWordWidth: 120,
                                                       fraction: 0.5, totalWidth: total,
                                                       availableWidth: available)
        let late = LyricsLineLayout.followingOffset(prefixWidth: 80, currentWordWidth: 120,
                                                     fraction: 0.9, totalWidth: total,
                                                     availableWidth: available)
        XCTAssertLessThanOrEqual(early, middle)
        XCTAssertLessThanOrEqual(middle, late)
        XCTAssertGreaterThan(middle, early)
        XCTAssertGreaterThanOrEqual(early, 0)
        XCTAssertLessThanOrEqual(late, total - available)
    }
}

final class LineOnlyReadingTests: XCTestCase {
    func testLineOnlyOffsetUsesLineProgressAndClampsTail() {
        let total: CGFloat = 400
        let available: CGFloat = 160
        XCTAssertEqual(LyricsLineLayout.lineOnlyOffset(progress: 0, totalWidth: total,
                                                       availableWidth: available), 0)
        XCTAssertEqual(LyricsLineLayout.lineOnlyOffset(progress: 0.5, totalWidth: total,
                                                       availableWidth: available), 120)
        XCTAssertEqual(LyricsLineLayout.lineOnlyOffset(progress: 1, totalWidth: total,
                                                       availableWidth: available), 240)
        XCTAssertEqual(LyricsLineLayout.lineOnlyOffset(progress: 2, totalWidth: total,
                                                       availableWidth: available), 240)
        XCTAssertEqual(LyricsLineLayout.lineOnlyOffset(progress: 1, totalWidth: 100,
                                                       availableWidth: available), 0)
    }

    func testLineOnlyOffsetPauseAndSeekWithPlayerClock() {
        let sample = Date(timeIntervalSinceReferenceDate: 100)
        let total: CGFloat = 400, available: CGFloat = 160
        let clock = LyricsPlaybackClock(anchorElapsed: 12.2, anchorDate: sample,
                                        rate: 1, playing: true)
        let later = clock.elapsed(at: sample.addingTimeInterval(3))
        XCTAssertEqual(later, 15.2, accuracy: 0.0001)
        XCTAssertGreaterThan(LyricsLineLayout.lineOnlyOffset(
            progress: (later - 12) / 8, totalWidth: total, availableWidth: available), 0)
        let paused = LyricsPlaybackClock(anchorElapsed: 18.5, anchorDate: sample,
                                         rate: 1, playing: false)
        XCTAssertEqual(paused.elapsed(at: sample.addingTimeInterval(5)), 18.5, accuracy: 0.0001)
        let seekBack = LyricsPlaybackClock(anchorElapsed: 12.2, anchorDate: sample,
                                           rate: 1, playing: true)
        XCTAssertEqual(LyricsLineLayout.lineOnlyOffset(progress: (seekBack.elapsed(at: sample) - 12) / 8,
                                                       totalWidth: total, availableWidth: available),
                       6, accuracy: 0.001)
    }
}
