import XCTest
@testable import ReferenceCore

final class LyricsTimelineTests: XCTestCase {
    func testTimelineSortsStableAndFindsCurrentLine() {
        let timeline = LyricTimeline(lines: [
            LyricLine(start: 10, text: "later"),
            LyricLine(start: 2, text: "first"),
            LyricLine(start: 2, text: "tie"),
            LyricLine(start: 5, text: "middle")
        ])
        XCTAssertEqual(timeline.lines.map(\.text), ["first", "tie", "middle", "later"])
        XCTAssertNil(timeline.line(at: 1.9))
        XCTAssertEqual(timeline.line(at: 2)?.text, "tie")
        XCTAssertEqual(timeline.line(at: 4.9)?.text, "tie")
        XCTAssertEqual(timeline.line(at: 99)?.text, "later")
    }

    func testBlankInterstitialClearsPreviousLine() {
        let timeline = LyricTimeline(lines: [
            LyricLine(start: 1, text: "first"),
            LyricLine(start: 4, text: ""),
            LyricLine(start: 7, text: "second")
        ])
        XCTAssertEqual(timeline.line(at: 3.9)?.text, "first")
        XCTAssertEqual(timeline.line(at: 4)?.text, "")
        XCTAssertEqual(timeline.line(at: 7)?.text, "second")
    }

    func testParserPreservesInternalBlankTimestampAndAppliesOffset() {
        guard case .timed(let lines, let metadata) = LRCParser.parse(
            "[offset:500]\n[00:01.00]first\n[00:04.00]\n[00:07.00]second"
        ) else {
            return XCTFail("expected timed lyrics")
        }
        XCTAssertEqual(metadata.offsetMilliseconds, 500)
        XCTAssertEqual(lines.map(\.start), [1.5, 4.5, 7.5])
        XCTAssertEqual(lines.map(\.text), ["first", "", "second"])
    }

    func testParserDropsLeadingAndTrailingBlankTimestamps() {
        guard case .timed(let lines, _) = LRCParser.parse(
            "[00:01.00]\n[00:02.00]first\n[00:03.00]second\n[00:04.00]"
        ) else {
            return XCTFail("expected timed lyrics")
        }
        XCTAssertEqual(lines.map(\.text), ["first", "second"])
    }

    func testShowLyricsDefaultsOffAndPersistsFromReferenceDictionary() {
        XCTAssertFalse(MusicPreferences().showLyrics)
        XCTAssertTrue(MusicPreferences(values: ["showLyrics": true]).showLyrics)
    }
}
