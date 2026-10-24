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
}
