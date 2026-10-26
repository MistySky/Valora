import AppKit
import XCTest
@testable import Valora

@MainActor
final class ArtworkGapTransitionTests: XCTestCase {
    private func cover(_ color: NSColor) -> NSImage {
        let image = NSImage(size: NSSize(width: 24, height: 24))
        image.lockFocus()
        color.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 24, height: 24)).fill()
        image.unlockFocus()
        return image
    }

    func testLateArtworkAfterMissingFrameStillPerformsTransition() async {
        let transition = ArtworkTransitionController()
        transition.update(image: cover(.systemRed), identity: "first", animated: true)
        XCTAssertEqual(transition.state.phase, .idle)
        transition.update(image: nil, identity: "", animated: true)
        XCTAssertNil(transition.image, "missing artwork must not display the previous song's image")
        transition.update(image: cover(.systemBlue), identity: "second", animated: true)
        XCTAssertEqual(transition.state.phase, .outgoing, "late artwork is a replacement, not an initial appearance")
        try? await Task.sleep(nanoseconds: 220_000_000)
        XCTAssertEqual(transition.state.phase, .incoming)
        XCTAssertEqual(transition.state.current, "second")
        try? await Task.sleep(nanoseconds: 700_000_000)
        XCTAssertEqual(transition.state.phase, .idle)
        transition.stop()
    }

    func testDirectCoverChangeMovesThroughBothPhases() async {
        let transition = ArtworkTransitionController()
        transition.update(image: cover(.systemRed), identity: "direct-a", animated: true)
        transition.update(image: cover(.systemBlue), identity: "direct-b", animated: true)
        XCTAssertEqual(transition.state.phase, .outgoing)
        XCTAssertNotNil(transition.image)
        try? await Task.sleep(nanoseconds: 180_000_000)
        XCTAssertEqual(transition.state.phase, .incoming)
        XCTAssertEqual(transition.state.current, "direct-b")
        try? await Task.sleep(nanoseconds: 700_000_000)
        XCTAssertEqual(transition.state.phase, .idle)
        XCTAssertEqual(transition.state.current, "direct-b")
        transition.stop()
    }

    func testSameArtworkIdentityDoesNotRestartTransition() async {
        let transition = ArtworkTransitionController()
        let red = cover(.systemRed)
        transition.update(image: red, identity: "same", animated: true)
        transition.update(image: red, identity: "same", animated: true)
        XCTAssertEqual(transition.state.phase, .idle)
        transition.update(image: cover(.systemBlue), identity: "next", animated: true)
        let generation = transition.state.generation
        transition.update(image: cover(.systemBlue), identity: "next", animated: true)
        XCTAssertEqual(transition.state.generation, generation)
        transition.stop()
    }

    func testStopAndFailureClearWithoutDisplayingOldCover() async {
        let transition = ArtworkTransitionController()
        transition.update(image: cover(.systemRed), identity: "red", animated: true)
        transition.update(image: cover(.systemBlue), identity: "blue", animated: true)
        transition.stop()
        XCTAssertNil(transition.state.current)
        XCTAssertNil(transition.image)
        transition.update(image: cover(.systemGreen), identity: "green", animated: true)
        transition.update(image: nil, identity: "", animated: true)
        XCTAssertNil(transition.image, "a failed/missing snapshot must not resurrect old artwork")
        XCTAssertNotEqual(transition.state.current, "green")
        transition.stop()
    }

    func testRapidLateArtworkSettlesOnNewestCoverAndStopRejectsOldCompletion() async {
        let transition = ArtworkTransitionController()
        transition.update(image: cover(.systemRed), identity: "first", animated: true)
        transition.update(image: nil, identity: "", animated: true)
        transition.update(image: cover(.systemBlue), identity: "second", animated: true)
        transition.update(image: cover(.systemGreen), identity: "third", animated: true)
        try? await Task.sleep(nanoseconds: 1_850_000_000)
        XCTAssertEqual(transition.state.current, "third")
        XCTAssertEqual(transition.state.phase, .idle)
        transition.update(image: cover(.systemOrange), identity: "fourth", animated: true)
        transition.stop()
        try? await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertNil(transition.image)
        XCTAssertNil(transition.state.current)
    }

    func testDisabledAnimationAndFirstArtworkRemainImmediate() {
        let transition = ArtworkTransitionController()
        transition.update(image: nil, identity: "", animated: true)
        transition.update(image: cover(.systemRed), identity: "first", animated: true)
        XCTAssertEqual(transition.state.phase, .idle)
        transition.update(image: nil, identity: "", animated: false)
        XCTAssertNil(transition.image)
        transition.update(image: cover(.systemBlue), identity: "second", animated: false)
        XCTAssertEqual(transition.state.phase, .idle)
        XCTAssertEqual(transition.state.current, "second")
        transition.stop()
    }
}
