import XCTest
@testable import ReferenceCore

final class MediaProgressTests: XCTestCase {
    func testDragIsRelativeAndDoesNotJumpWhenPlayerUpdates() {
        var state = MediaProgressState()
        XCTAssertEqual(state.drag(elapsed:60,duration:200,translation:10,trackWidth:100),80)
        // The transport can update elapsed while the finger is still down.
        XCTAssertEqual(state.drag(elapsed:65,duration:200,translation:20,trackWidth:100),100)
        XCTAssertEqual(state.drag(elapsed:65,duration:200,translation:-80,trackWidth:100),0)
        XCTAssertEqual(state.endDrag(at:10),0)
        XCTAssertNil(state.dragValue)
        XCTAssertNil(state.dragOrigin)
    }
    func testTapAfterDragIsSuppressedAndCoordinatesAreClamped() {
        var state = MediaProgressState()
        _ = state.drag(elapsed:60,duration:200,translation:10,trackWidth:100)
        _ = state.endDrag(at:10)
        XCTAssertNil(state.tap(x:50,trackWidth:100,duration:200,at:10.05))
        XCTAssertEqual(state.tap(x:50,trackWidth:100,duration:200,at:10.11),100)
        XCTAssertEqual(state.tap(x:-20,trackWidth:100,duration:200,at:11),0)
        XCTAssertEqual(state.tap(x:120,trackWidth:100,duration:200,at:11),200)
    }
    func testUnknownDurationAndNonFiniteInputsCannotSeek() {
        var state = MediaProgressState()
        for duration in [0, -1, Double.nan, Double.infinity] {
            XCTAssertNil(state.tap(x:10,trackWidth:100,duration:duration,at:1))
            XCTAssertNil(state.drag(elapsed:10,duration:duration,translation:1,trackWidth:100))
        }
        XCTAssertNil(state.tap(x:.nan,trackWidth:100,duration:200,at:1))
        XCTAssertNil(state.drag(elapsed:10,duration:200,translation:.infinity,trackWidth:100))
        XCTAssertNil(state.endDrag(at:1))
        XCTAssertEqual(MediaProgressState.clamp(.nan,duration:200),0)
    }
    func testCancelledDragDoesNotLeakIntoNewTrack() {
        var state = MediaProgressState()
        _ = state.drag(elapsed:60,duration:200,translation:10,trackWidth:100)
        state.cancelDrag()
        XCTAssertNil(state.endDrag(at:1))
        XCTAssertEqual(state.drag(elapsed:5,duration:100,translation:10,trackWidth:100),15)
    }
}
