import XCTest
@testable import ReferenceCore
final class SystemMediaTests: XCTestCase {
    private var payload: [String: Any] { ["bundleIdentifier":"com.tencent.QQMusicMac", "title":"歌曲", "artist":"歌手", "durationMicros":219_000_000, "elapsedTimeMicros":58_000_000, "timestampEpochMicros":1_000_000_000, "playing":true, "playbackRate":1] }
    func testProgressUsesTimestampAndFreezesWhenPaused() {
        XCTAssertEqual(SystemMediaSnapshot(payload)!.position(at:1003),61)
        var paused = payload; paused["playing"] = false
        XCTAssertEqual(SystemMediaSnapshot(paused)!.position(at:1100),58)
        XCTAssertEqual(SystemMediaSnapshot(payload)!.position(at:2000),219)
        XCTAssertEqual(SystemMediaSnapshot(payload)!.position(at:999),58)
    }
    func testMissingOrInvalidTimingDoesNotInventProgress() {
        var invalid = payload; invalid["durationMicros"] = Double.nan
        XCTAssertEqual(SystemMediaSnapshot(invalid)!.position(at:1003),0)
        invalid = payload; invalid.removeValue(forKey:"timestampEpochMicros")
        XCTAssertEqual(SystemMediaSnapshot(invalid)!.position(at:1003),58)
        XCTAssertNil(SystemMediaSnapshot([:]))
    }
    func testSameTitleDifferentSourceAlbumOrTrackInvalidatesIdentity() {
        let a = SystemMediaSnapshot(payload)!
        for key in ["bundleIdentifier", "album", "contentItemIdentifier"] {
            var changed = payload; changed[key] = "different"
            XCTAssertNotEqual(a.identity,SystemMediaSnapshot(changed)!.identity)
        }
        var changed = payload; changed["elapsedTimeMicros"] = 70_000_000
        XCTAssertEqual(a.identity,SystemMediaSnapshot(changed)!.identity)
    }
    func testStateOnlyPauseDoesNotJumpBackAndResumeDoesNotCountPausedTime() {
        var timeline = SystemMediaTimeline()
        timeline.update(SystemMediaSnapshot(payload)!,at:1003)
        var paused = payload; paused["playing"] = false
        timeline.update(SystemMediaSnapshot(paused)!,at:1010)
        XCTAssertEqual(timeline.position(at:1020),68)
        timeline.update(SystemMediaSnapshot(payload)!,at:1020)
        XCTAssertEqual(timeline.position(at:1025),73)
        var seek = payload;seek["elapsedTimeMicros"] = 120_000_000;seek["timestampEpochMicros"] = 1_026_000_000
        timeline.update(SystemMediaSnapshot(seek)!,at:1026)
        XCTAssertEqual(timeline.position(at:1027),121)
    }

    private func point(_ elapsed: Double, _ stamp: Double, rate: Double = 1,
                       title: String = "fixture") -> SystemMediaSnapshot {
        var event = payload
        event["title"] = title
        event["playing"] = rate > 0
        event["playbackRate"] = rate
        event["elapsedTimeMicros"] = elapsed * 1e6
        event["timestampEpochMicros"] = stamp * 1e6
        return SystemMediaSnapshot(event)!
    }

    func testObservedWholeSecondAnchorsCrossTheLyricBoundaryOnce() {
        // Relative source/arrival times from the observed 70 → 124 → 126 sequence.
        var timeline = SystemMediaTimeline()
        timeline.update(point(70, 1000), at: 1008.710)
        timeline.update(point(70, 1000), at: 1008.744)
        let lyrics = LyricTimeline(lines: [LyricLine(start: 113.58, text: "A"),
                                          LyricLine(start: 124.66, text: "B")])
        var lines: [String] = []
        func observe(_ time: Double) {
            let text = lyrics.line(at: timeline.position(at: time))?.text
            if let text, lines.last != text { lines.append(text) }
        }
        observe(1054.6)
        observe(1054.7)
        timeline.update(point(124, 1055.000164), at: 1055.064)
        observe(1055.064)
        XCTAssertEqual(timeline.position(at: 1055.564), 125.564, accuracy: 0.00001)
        timeline.update(point(126, 1056.000152), at: 1056.088)
        observe(1056.088)
        XCTAssertEqual(lines, ["A", "B"])
        XCTAssertEqual(timeline.position(at: 1058), 127.999848, accuracy: 0.00001)
    }

    func testMissingAndRepeatedReportsConvergeWithoutRestartingTheHold() throws {
        for continuedUpdates in [false, true] {
            var timeline = SystemMediaTimeline()
            timeline.update(point(70, 1000), at: 1000)
            let lagging = point(124, 1055)
            timeline.update(lagging, at: 1055.06)
            let hold = try XCTUnwrap(timeline.correctionHold)
            timeline.update(lagging, at: 1055.9)
            XCTAssertEqual(timeline.correctionHold, hold)
            if continuedUpdates {
                timeline.update(point(125, 1056), at: 1056.06)
                timeline.update(point(126, 1057), at: 1057.06)
            }
            XCTAssertEqual(timeline.position(at: 1057.15), 126.31, accuracy: 0.00001)
            XCTAssertEqual(timeline.position(at: 1058), 127, accuracy: 0.00001)
        }
    }

    func testSeekStateRatePreciseTimesAndOtherTracksRemainAuthoritative() {
        let otherEvents = [
            point(69, 1055), point(110, 1055), point(124.125, 1055),
            point(124, 1055, rate: 0), point(124, 1055, rate: 2),
            point(124, 1055, title: "another track")
        ]
        for event in otherEvents {
            var timeline = SystemMediaTimeline()
            timeline.update(point(70, 1000), at: 1000)
            timeline.update(event, at: 1055.06)
            XCTAssertNil(timeline.correctionHold)
            XCTAssertEqual(timeline.position(at: 1055.06), event.position(at: 1055.06), accuracy: 0.00001)
        }
        var timeline = SystemMediaTimeline()
        timeline.update(point(70, 1000), at: 1000)
        timeline.update(point(124, 1055), at: 1055.06, seek: .confirmed)
        XCTAssertNil(timeline.correctionHold)
        XCTAssertEqual(timeline.position(at: 1055.06), 124.06, accuracy: 0.00001)
    }

    func testRestoringIdenticalTimelessOrPausedSourceKeepsItsExistingPosition() {
        var noTimestamp = payload
        noTimestamp.removeValue(forKey: "timestampEpochMicros")
        let playing = SystemMediaSnapshot(noTimestamp)!
        var timeline = SystemMediaTimeline()
        timeline.update(playing, at: 1000)
        timeline.update(playing, at: 1010, seek: .restoreSource)
        XCTAssertEqual(timeline.position(at: 1010), 68)
        noTimestamp["playing"] = false
        let paused = SystemMediaSnapshot(noTimestamp)!
        timeline.update(paused, at: 1011)
        timeline.update(paused, at: 1013, seek: .restoreSource)
        XCTAssertEqual(timeline.position(at: 1013), 69)
    }
}
