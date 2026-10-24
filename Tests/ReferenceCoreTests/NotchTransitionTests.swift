import XCTest
@testable import ReferenceCore

final class NotchTransitionTests: XCTestCase {
    func testContentSurvivesCollapseAndInteractionWaitsForExpansion() throws {
        var state = NotchTransitionState()
        XCTAssertFalse(state.retainsExpandedContent)
        XCTAssertFalse(state.acceptsExpandedInteraction)
        let expand = try XCTUnwrap(state.begin(expanding: true))
        XCTAssertTrue(state.retainsExpandedContent)
        XCTAssertFalse(state.acceptsExpandedInteraction)
        state.complete(generation: expand)
        XCTAssertTrue(state.acceptsExpandedInteraction)
        let collapse = try XCTUnwrap(state.begin(expanding: false))
        XCTAssertTrue(state.retainsExpandedContent)
        XCTAssertFalse(state.acceptsExpandedInteraction)
        let reopen = try XCTUnwrap(state.begin(expanding: true))
        state.complete(generation: collapse)
        XCTAssertTrue(state.retainsExpandedContent)
        XCTAssertFalse(state.acceptsExpandedInteraction)
        state.complete(generation: reopen)
        XCTAssertTrue(state.acceptsExpandedInteraction)
        let finish = try XCTUnwrap(state.begin(expanding: false))
        state.complete(generation: finish)
        XCTAssertFalse(state.retainsExpandedContent)
        XCTAssertFalse(state.acceptsExpandedInteraction)
    }

    func testInterruptedExpansionCannotRestoreCollapsedVisuals() throws {
        var state = NotchTransitionState()
        let expand = try XCTUnwrap(state.begin(expanding: true))
        state.revealCorners(generation: expand)
        state.setBlur(true, generation: expand)
        let collapse = try XCTUnwrap(state.begin(expanding: false))
        state.setBlur(false, generation: collapse)
        state.complete(generation: collapse)
        let finished = state
        // Each of these may already be queued when cancellation arrives.
        state.revealCorners(generation: expand)
        state.setBackdrop(true, generation: expand)
        state.setBlur(true, generation: expand)
        state.complete(generation: expand)
        XCTAssertEqual(state, finished)
        XCTAssertEqual(state.phase, .collapsed)
        XCTAssertFalse(state.usesExpandedCornerRadius)
        XCTAssertFalse(state.hasExpandedBackdropLuma)
        XCTAssertFalse(state.hasProgressiveBlur)
    }

    func testStaleCollapseCompletionCannotClearReopenedPanel() throws {
        var state = NotchTransitionState()
        let first = try XCTUnwrap(state.begin(expanding: true))
        state.complete(generation: first)
        let collapse = try XCTUnwrap(state.begin(expanding: false))
        let reopen = try XCTUnwrap(state.begin(expanding: true))
        state.revealCorners(generation: reopen)
        state.setBlur(true, generation: reopen)
        let expected = state
        state.setBackdrop(false, generation: collapse)
        state.setBlur(false, generation: collapse)
        state.complete(generation: collapse)
        XCTAssertEqual(state, expected)
        state.complete(generation: reopen)
        XCTAssertEqual(state.phase, .expanded)
        XCTAssertTrue(state.hasExpandedBackdropLuma)
    }

    func testDuplicateRequestsKeepOriginalClockAndGeneration() throws {
        var state = NotchTransitionState()
        XCTAssertNil(state.begin(expanding: false))
        let token = try XCTUnwrap(state.begin(expanding: true))
        state.revealCorners(generation: token)
        let expected = state
        XCTAssertNil(state.begin(expanding: true))
        XCTAssertEqual(state, expected)
        state.complete(generation: token)
        XCTAssertEqual(state.phase, .expanded)
    }

    func testRapidAlternationRejectsEveryOlderGeneration() throws {
        var state = NotchTransitionState()
        var tokens: [UInt64] = []
        for index in 0..<101 {
            tokens.append(try XCTUnwrap(state.begin(expanding: index.isMultiple(of: 2))))
        }
        let expected = state
        for token in tokens.dropLast().reversed() {
            state.complete(generation: token)
            state.revealCorners(generation: token)
            state.setBackdrop(false, generation: token)
            state.setBlur(true, generation: token)
        }
        XCTAssertEqual(state, expected)
        state.complete(generation: try XCTUnwrap(tokens.last))
        XCTAssertEqual(state.phase, .expanded)
        XCTAssertEqual(state.generation, 101)
    }
}
