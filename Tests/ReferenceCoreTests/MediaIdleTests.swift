import XCTest
@testable import ReferenceCore

final class MediaIdleTests: XCTestCase {
    func testPausedTrackExpiresWithoutRepeatedPollsExtendingDeadline() {
        var state = MediaIdleState()
        let paused = MediaIdleState.Input(identity:"QQ/song",playing:false)
        XCTAssertTrue(state.update(paused)); let token = state.generation
        for _ in 0..<30 { XCTAssertFalse(state.update(paused)) }
        XCTAssertEqual(state.generation,token)
        XCTAssertTrue(state.visible); XCTAssertTrue(state.expire(generation:token))
        XCTAssertFalse(state.visible); XCTAssertFalse(state.update(paused))
        XCTAssertFalse(state.visible)
    }
    func testResumeAndSecondPauseRejectFirstPauseTimeout() {
        var state = MediaIdleState()
        state.update(.init(identity:"song",playing:false)); let old = state.generation
        state.update(.init(identity:"song",playing:true))
        XCTAssertFalse(state.expire(generation:old)); XCTAssertTrue(state.visible)
        state.update(.init(identity:"song",playing:false))
        XCTAssertFalse(state.expire(generation:old))
        XCTAssertTrue(state.expire(generation:state.generation))
    }
    func testHoverCancelsThenExitStartsFullNewWait() {
        var state = MediaIdleState()
        state.update(.init(identity:"song",playing:false)); let old = state.generation
        state.update(.init(identity:"song",playing:false,pointerInside:true))
        XCTAssertFalse(state.pending); XCTAssertFalse(state.expire(generation:old))
        state.update(.init(identity:"song",playing:false))
        XCTAssertTrue(state.pending); XCTAssertTrue(state.visible)
        XCTAssertFalse(state.expire(generation:old))
        XCTAssertTrue(state.expire(generation:state.generation))
        state.update(.init(identity:"song",playing:false,pointerInside:true))
        XCTAssertFalse(state.visible, "Hover alone must not resurrect an already dismissed activity")
    }
    func testNotificationIsNotDismissedByAnOldMusicTimeout() {
        var state = MediaIdleState()
        state.update(.init(identity:"song",playing:false)); let old = state.generation
        state.update(.init(identity:"song",playing:false,outputNotification:true))
        XCTAssertFalse(state.pending); XCTAssertFalse(state.expire(generation:old))
        state.update(.init(identity:"song",playing:false))
        XCTAssertTrue(state.pending)
    }
    func testTrackSourceAndDisableInvalidateOldTasks() {
        var state = MediaIdleState()
        state.update(.init(identity:"QQ/song",playing:false)); let old = state.generation
        state.update(.init(identity:"Music/song",playing:false))
        XCTAssertFalse(state.expire(generation:old))
        state.update(.init(identity:"Music/song",playing:false,enabled:false))
        XCTAssertFalse(state.visible); XCTAssertFalse(state.pending)
        state.update(.init(identity:nil,playing:false))
        XCTAssertFalse(state.pending)
    }
    func testDurationChangeReplacesTaskAndZeroMeansNoGrace() {
        var state = MediaIdleState()
        state.update(.init(identity:"song",playing:false,duration:3)); let old = state.generation
        state.update(.init(identity:"song",playing:false,duration:0))
        XCTAssertFalse(state.expire(generation:old))
        XCTAssertEqual(state.input?.duration,0); XCTAssertTrue(state.pending)
        XCTAssertTrue(state.expire(generation:state.generation))
        XCTAssertEqual(MediaIdleState.Input(identity:nil,playing:false,duration:.nan).duration,3)
        XCTAssertEqual(MusicPreferences(values:["idleDuration":Double.infinity]).idleDuration,3)
    }
}
