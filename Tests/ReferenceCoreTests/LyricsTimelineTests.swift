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

    func testWordProgressHonorsShortAndLongWordDurations() {
        let line = LyricLine(start: 10, text: "短长", words: [
            LyricWord(text: "短", start: 10, duration: 0.2),
            LyricWord(text: "长", start: 10.2, duration: 1.5)
        ])
        let timeline = LyricTimeline(lines: [line])
        XCTAssertNil(timeline.wordProgress(in: line, at: 9.9))
        let short = timeline.wordProgress(in: line, at: 10.1)
        XCTAssertEqual(short?.index, 0)
        XCTAssertEqual(short?.fraction ?? 0, 0.5, accuracy: 0.001)
        let long = timeline.wordProgress(in: line, at: 10.95)
        XCTAssertEqual(long?.index, 1)
        XCTAssertEqual(long?.fraction ?? 0, 0.5, accuracy: 0.001)
        XCTAssertEqual(timeline.wordProgress(in: line, at: 11.8)?.fraction, 1)
    }

    func testShowLyricsDefaultsOffAndPersistsFromReferenceDictionary() {
        XCTAssertFalse(MusicPreferences().showLyrics)
        XCTAssertTrue(MusicPreferences(values: ["showLyrics": true]).showLyrics)
    }
}

final class LyricsPlaybackClockTests: XCTestCase {
    func testClockInterpolatesWithoutUsingNetworkTime() {
        let start = Date(timeIntervalSinceReferenceDate: 100)
        let clock = LyricsPlaybackClock(anchorElapsed: 10, anchorDate: start,
                                        rate: 1, playing: true)
        XCTAssertEqual(clock.elapsed(at: start), 10, accuracy: 0.0001)
        XCTAssertEqual(clock.elapsed(at: start.addingTimeInterval(0.1)), 10.1, accuracy: 0.0001)
        XCTAssertEqual(clock.elapsed(at: start.addingTimeInterval(0.2)), 10.2, accuracy: 0.0001)
        let fast = LyricsPlaybackClock(anchorElapsed: 10, anchorDate: start,
                                       rate: 2, playing: true)
        XCTAssertEqual(fast.elapsed(at: start.addingTimeInterval(0.1)), 10.2, accuracy: 0.0001)
    }

    func testPausedClockDoesNotAdvance() {
        let start = Date(timeIntervalSinceReferenceDate: 100)
        let clock = LyricsPlaybackClock(anchorElapsed: 15, anchorDate: start,
                                        rate: 1, playing: false)
        XCTAssertEqual(clock.elapsed(at: start.addingTimeInterval(5)), 15, accuracy: 0.0001)
        let zeroRate = LyricsPlaybackClock(anchorElapsed: 15, anchorDate: start,
                                           rate: 0, playing: true)
        XCTAssertEqual(zeroRate.elapsed(at: start.addingTimeInterval(5)), 15, accuracy: 0.0001)
    }

    func testSeekIsAnExplicitAnchorResetInBothDirections() {
        let start = Date(timeIntervalSinceReferenceDate: 100)
        let forward = LyricsPlaybackClock(anchorElapsed: 80, anchorDate: start,
                                          rate: 1, playing: true)
        XCTAssertEqual(forward.elapsed(at: start.addingTimeInterval(0.25)), 80.25, accuracy: 0.0001)
        let backward = LyricsPlaybackClock(anchorElapsed: 12, anchorDate: start,
                                           rate: 1, playing: true)
        XCTAssertEqual(backward.elapsed(at: start.addingTimeInterval(0.25)), 12.25, accuracy: 0.0001)
    }
}
