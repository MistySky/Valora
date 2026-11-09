import XCTest
@testable import Valora

/// Host-wiring regression for the desktop lyric experiment. The renderer
/// itself is covered by the existing isolated prototype suites; these tests
/// only check which path this build selects and the per-view fallback state.
@MainActor
final class LyricsRowExperimentIntegrationTests: XCTestCase {
    func testNormalBuildSelectsProductionRow() throws {
        try XCTSkipIf(LyricsRowBackend.experimentCompiled,
                      "experiment build: the production selection is not expected")
        XCTAssertEqual(LyricsRowBackend.active, .production)
    }

    func testExperimentBuildSelectsExperimentalRow() throws {
        try XCTSkipUnless(LyricsRowBackend.experimentCompiled,
                          "normal build: the experiment selection is not expected")
        XCTAssertEqual(LyricsRowBackend.active, .experiment)
    }

    func testFallbackLatchesUntilANewLyricIdentity() {
        var state = LyricsRowFallbackState()
        XCTAssertFalse(state.failed)
        state.updateIdentity("track-a")
        XCTAssertFalse(state.failed)
        state.reportFailure()
        XCTAssertTrue(state.failed)
        state.reportFailure()
        XCTAssertTrue(state.failed)
        state.updateIdentity("track-a")
        XCTAssertTrue(state.failed, "the same track keeps the fallback")
        state.updateIdentity("track-b")
        XCTAssertFalse(state.failed, "a new track may try the experiment again")
    }

    func testTwoRowsKeepIndependentFallbackState() {
        var first = LyricsRowFallbackState()
        var second = LyricsRowFallbackState()
        first.updateIdentity("a")
        second.updateIdentity("a")
        first.reportFailure()
        XCTAssertTrue(first.failed)
        XCTAssertFalse(second.failed, "each display keeps its own fallback state")
    }

    func testResetClearsFailure() {
        var state = LyricsRowFallbackState()
        state.updateIdentity("a")
        state.reportFailure()
        state.reset()
        XCTAssertFalse(state.failed)
        XCTAssertEqual(state.identity, "a")
    }
}
