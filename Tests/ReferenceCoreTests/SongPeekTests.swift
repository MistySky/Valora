import XCTest
@testable import ReferenceCore
final class SongPeekTests: XCTestCase {
    func testOnlySubsequentTrackChangeShowsPeek() {
        var state = SongPeekState()
        XCTAssertFalse(state.observe(identity:"a",eligible:true))
        XCTAssertFalse(state.observe(identity:"a",eligible:true))
        XCTAssertTrue(state.observe(identity:"b",eligible:true))
        XCTAssertTrue(state.visible)
        let token = state.generation
        XCTAssertFalse(state.observe(identity:"b",eligible:true))
        XCTAssertEqual(state.generation,token)
        state.expire(generation:token)
        XCTAssertFalse(state.visible)
    }
    func testRapidChangesIgnoreOldExpiryAndExpansionCancels() {
        var state = SongPeekState()
        state.observe(identity:"a",eligible:true)
        state.observe(identity:"b",eligible:true)
        let old = state.generation
        state.observe(identity:"c",eligible:true)
        state.expire(generation:old)
        XCTAssertTrue(state.visible)
        state.observe(identity:"c",eligible:false)
        XCTAssertFalse(state.visible)
        XCTAssertFalse(state.observe(identity:"c",eligible:true))
    }
    func testDisabledAndSourceResetNeverReplayOldChange() {
        var state = SongPeekState()
        state.observe(identity:"a",eligible:false)
        state.observe(identity:"b",eligible:false)
        XCTAssertFalse(state.observe(identity:"b",eligible:true))
        XCTAssertTrue(state.observe(identity:"c",eligible:true))
        state.reset()
        XCTAssertFalse(state.visible)
        XCTAssertFalse(state.observe(identity:"newSource",eligible:true))
    }
}
