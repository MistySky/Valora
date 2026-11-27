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
                       title: String = "fixture", item: String = "") -> SystemMediaSnapshot {
        var event = payload
        event["title"] = title
        event["contentItemIdentifier"] = item
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

    func testWiderRotatingItemCorrectionProtectsLyricsWithoutChangingTransportTiming() throws {
        let arrival = 1005.395
        let initial = point(0, 1000, item: "a")
        let newer = point(4, 1005.335, item: "b")
        var lyrics = SystemMediaTimeline(for: .lyrics)
        var transport = SystemMediaTimeline()
        lyrics.update(initial, at: 1000)
        transport.update(initial, at: 1000)
        let presented = lyrics.position(at: arrival)
        lyrics.update(newer, at: arrival)
        transport.update(newer, at: arrival)
        XCTAssertEqual(lyrics.position(at: arrival), presented, accuracy: 0.000001)
        XCTAssertEqual(transport.position(at: arrival), 4.06, accuracy: 0.000001)
        let hold = try XCTUnwrap(lyrics.correctionHold)
        XCTAssertEqual(hold.start.timeIntervalSince1970, arrival + 1.25, accuracy: 0.000001)
        XCTAssertEqual(hold.duration, 1.335, accuracy: 0.000001)
        XCTAssertEqual(lyrics.position(at: arrival + 3), newer.position(at: arrival + 3), accuracy: 0.000001)
    }

    func testIsolatedMissedCounterTickKeepsWordClockRunningUntilDistantCatchup() {
        var lyrics = SystemMediaTimeline(for: .lyrics)
        let initial = point(23, 1000, item: "a")
        lyrics.update(initial, at: 1011.180)
        lyrics.update(point(64, 1042.000034, item: "b"), at: 1042.063436)
        lyrics.update(point(64, 1042.000034, item: "c"), at: 1043)
        XCTAssertNil(lyrics.correctionHold)
        for epoch in [1043.3134, 1043.401, 1044.216, 1090, 1141.05] {
            XCTAssertEqual(lyrics.position(at: epoch), initial.position(at: epoch), accuracy: 0.000001)
        }
        let catchup = point(164, 1140.985088, item: "d")
        lyrics.update(catchup, at: 1141.056798)
        XCTAssertNil(lyrics.correctionHold)
        XCTAssertEqual(lyrics.position(at: 1141.056798), catchup.position(at: 1141.056798), accuracy: 0.000001)
    }

    func testSecondIndependentReportCanConfirmMissedTickEvenWithSameItemID() throws {
        var lyrics = SystemMediaTimeline(for: .lyrics)
        lyrics.update(point(19, 1000, item: "a"), at: 1000)
        lyrics.update(point(81, 1063, item: "b"), at: 1063.06)
        lyrics.update(point(81, 1063, item: "c"), at: 1065)
        XCTAssertNil(lyrics.correctionHold)
        for lag in [0.5, 1.0] {
            var updated = lyrics
            let stamp = 1066 + lag
            let confirmed = point(85, stamp, item: "c")
            updated.update(confirmed, at: stamp + 0.06)
            XCTAssertEqual(updated.position(at: stamp + 0.06), 85.06 + lag, accuracy: 0.000001)
            XCTAssertEqual(try XCTUnwrap(updated.correctionHold).duration, lag, accuracy: 0.000001)
            XCTAssertEqual(updated.position(at: 1070), confirmed.position(at: 1070), accuracy: 0.000001)
        }
    }

    func testPendingLyricReportYieldsToSeekRestorationPauseAndLoop() {
        let late = point(64, 1042, item: "b")
        var pending = SystemMediaTimeline(for: .lyrics)
        pending.update(point(23, 1000, item: "a"), at: 1000)
        pending.update(late, at: 1042)
        for reason in [SystemMediaTimeline.SeekEvent.confirmed, .restoreSource] {
            var lyrics = pending
            lyrics.update(late, at: 1044, seek: reason)
            XCTAssertEqual(lyrics.position(at: 1044), 66)
        }
        var paused = pending
        paused.update(point(64, 1042, rate: 0, item: "b"), at: 1044)
        XCTAssertEqual(paused.position(at: 1090), 67)
        var looped = pending
        looped.update(point(0, 1044, item: "c"), at: 1044)
        XCTAssertEqual(looped.position(at: 1044), 0)
        looped.update(point(4, 1049, item: "d"), at: 1049)
        XCTAssertNil(looped.correctionHold)
    }

    func testCatchupAndDuplicateItemPacketsKeepLyricGraceBounded() throws {
        var lyrics = SystemMediaTimeline(for: .lyrics)
        lyrics.update(point(0, 1000, item: "a"), at: 1000)
        lyrics.update(point(4, 1005.35, item: "b"), at: 1005.35)
        let original = try XCTUnwrap(lyrics.correctionHold)
        lyrics.update(point(4, 1005.35, item: "c"), at: 1005.8)
        XCTAssertEqual(lyrics.correctionHold, original)

        let next = point(6, 1006.35, item: "d")
        let before = lyrics.position(at: 1006.4)
        lyrics.update(next, at: 1006.4)
        let shorter = try XCTUnwrap(lyrics.correctionHold)
        XCTAssertEqual(shorter.start, original.start)
        XCTAssertEqual(shorter.duration, 0.35, accuracy: 0.000001)
        XCTAssertEqual(lyrics.position(at: 1006.4), before, accuracy: 0.000001)
        XCTAssertEqual(lyrics.position(at: 1008), next.position(at: 1008), accuracy: 0.000001)
    }

    func testFurtherLateLyricReportDuringHoldConvergesWithoutAnotherGracePeriod() throws {
        var lyrics = SystemMediaTimeline(for: .lyrics)
        lyrics.update(point(0, 1000, item: "a"), at: 1000)
        lyrics.update(point(4, 1005.35, item: "b"), at: 1005.35)
        let before = lyrics.position(at: 1006.85)
        let further = point(5, 1006.65, item: "c")
        lyrics.update(further, at: 1006.85)
        let hold = try XCTUnwrap(lyrics.correctionHold)
        XCTAssertEqual(hold.start.timeIntervalSince1970, 1006.85, accuracy: 0.000001)
        XCTAssertEqual(hold.duration, 1.4, accuracy: 0.000001)
        XCTAssertEqual(lyrics.position(at: 1007.85), before, accuracy: 0.000001)
        XCTAssertEqual(lyrics.position(at: 1010), further.position(at: 1010), accuracy: 0.000001)
    }

    func testLyricsRespectRealSeekLoopTrackChangesAndPreciseClocks() {
        let initial = point(70, 1000, item: "a")
        let arrival = 1005.35
        let changed = point(74, arrival, item: "b")
        let authoritative = [
            point(0, arrival, item: "b"),
            point(69, arrival, item: "b"),
            point(72, arrival, item: "b"),
            point(74.5, arrival, item: "b"),
            point(74, arrival, rate: 0, item: "b"),
            point(74, arrival, rate: 2, item: "b"),
            point(74, arrival, title: "another song", item: "b")
        ]
        for event in authoritative {
            var lyrics = SystemMediaTimeline(for: .lyrics)
            lyrics.update(initial, at: 1000)
            lyrics.update(event, at: arrival)
            XCTAssertNil(lyrics.correctionHold)
            XCTAssertEqual(lyrics.position(at: arrival), event.position(at: arrival), accuracy: 0.000001)
        }
        for reason in [SystemMediaTimeline.SeekEvent.confirmed, .restoreSource] {
            var lyrics = SystemMediaTimeline(for: .lyrics)
            lyrics.update(initial, at: 1000)
            lyrics.update(changed, at: arrival, seek: reason)
            XCTAssertNil(lyrics.correctionHold)
            XCTAssertEqual(lyrics.position(at: arrival), 74, accuracy: 0.000001)
        }
    }
}
