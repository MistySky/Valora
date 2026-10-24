import XCTest
@testable import ReferenceCore

final class ArtworkTransitionTests: XCTestCase {
    func testInitialAndDuplicateArtworkDoNotFlip() {
        var state = ArtworkTransitionState()
        state.set("A",animated:true)
        XCTAssertEqual(state.phase,.idle)
        let token = state.generation
        state.set("A",animated:true)
        XCTAssertEqual(state.generation,token)
    }
    func testRapidChangesKeepOnlyNewestQueuedArtwork() {
        var state = ArtworkTransitionState(); state.set("A",animated:true)
        state.set("B",animated:true); let token = state.generation
        state.set("C",animated:true); state.set("D",animated:true)
        XCTAssertEqual(state.current,"A"); XCTAssertEqual(state.queued,"D")
        state.finishOutgoing(token); XCTAssertEqual(state.current,"B")
        state.finishIncoming(token)
        XCTAssertEqual(state.target,"D"); XCTAssertEqual(state.phase,.outgoing)
        state.finishOutgoing(token) // stale completion cannot replace D's transition
        XCTAssertEqual(state.current,"B")
        let next = state.generation; state.finishOutgoing(next); state.finishIncoming(next)
        XCTAssertEqual(state.current,"D"); XCTAssertEqual(state.phase,.idle)
    }
    func testReturningToTargetDropsObsoleteQueue() {
        var state = ArtworkTransitionState(); state.set("A",animated:true); state.set("B",animated:true)
        state.set("C",animated:true); state.set("B",animated:true)
        XCTAssertNil(state.queued)
    }
    func testDisableOrMissingArtworkInvalidatesPendingCompletion() {
        var state = ArtworkTransitionState(); state.set("A",animated:true); state.set("B",animated:true)
        let token = state.generation
        state.set("C",animated:false); state.finishOutgoing(token); state.finishIncoming(token)
        XCTAssertEqual(state.current,"C"); XCTAssertEqual(state.phase,.idle)
        state.set(nil,animated:true); XCTAssertNil(state.current); XCTAssertNil(state.queued)
    }
    func testRecoveredScaleEndpointsAndPreferenceFallbacks() {
        XCTAssertEqual(ArtworkFlipMetrics.scale(progress:0,incoming:false),1)
        XCTAssertEqual(ArtworkFlipMetrics.scale(progress:1,incoming:false),0.0825,accuracy:0.00001)
        XCTAssertEqual(ArtworkFlipMetrics.scale(progress:0,incoming:true),0.0825)
        XCTAssertEqual(ArtworkFlipMetrics.scale(progress:1,incoming:true),1)
        XCTAssertEqual(MusicPreferences(values:["progressStyle":"invalid"]).progressStyle,.monochrome)
        XCTAssertEqual(MusicPreferences(values:["progressStyle":"Gradient"]).progressStyle,.gradient)
        XCTAssertTrue(MusicPreferences(values:["disableAlbumArtFlip":true]).disableArtworkFlip)
    }
}
