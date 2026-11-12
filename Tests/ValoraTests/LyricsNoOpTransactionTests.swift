import AppKit
import XCTest
import ReferenceCore
@testable import Valora

@MainActor
final class LyricsNoOpTransactionTests: XCTestCase {
    private let anchor = Date(timeIntervalSince1970: 1_000_000)

    private func input(playing: Bool, backend: NativeLyricsTextBackend = .coreText) -> NativeLyricsRowSnapshot {
        NativeLyricsRowSnapshot(identity: nil,
            timeline: LyricTimeline(lines: [LyricLine(start: 0, text: "保持流畅", words: [
                LyricWord(text: "保持流畅", start: 2, duration: 4)
            ]), LyricLine(start: 10, text: "下一句")]),
            elapsed: 0, sampledAt: anchor, rate: 1, playing: playing,
            duration: 20, width: 260, textBackend: backend)
    }

    func testPausedImageRowSkipsEmptyCommitsWithoutChangingFrozenPixelsOrGeometry() throws {
        let view = NativeLyricsRowView(frame: NSRect(x: 0, y: 0, width: 260, height: 17))
        defer { view.stop() }
        view.debugNow = { self.anchor }
        view.apply(input(playing: false, backend: .swiftUI))
        let before = try XCTUnwrap(view.frozenTransitionLine())
        let commits = view.caTransactionCommits
        let builds = view.textBuilds
        view.render(at: anchor.addingTimeInterval(1))
        view.render(at: anchor.addingTimeInterval(2))
        let after = try XCTUnwrap(view.frozenTransitionLine())
        XCTAssertEqual(view.caTransactionCommits, commits)
        XCTAssertEqual(view.textBuilds, builds)
        XCTAssertEqual(try XCTUnwrap(before.base.dataProvider?.data as Data?),
                       try XCTUnwrap(after.base.dataProvider?.data as Data?))
        XCTAssertEqual(try XCTUnwrap(before.accent.dataProvider?.data as Data?),
                       try XCTUnwrap(after.accent.dataProvider?.data as Data?))
        XCTAssertEqual(before.maskWidth, after.maskWidth)
        XCTAssertEqual(before.positionX, after.positionX)
        XCTAssertEqual(before.positionY, after.positionY)
        XCTAssertEqual(before.pointSize, after.pointSize)
    }

    func testPlayingWordGapSkipsCommitsButHighlightStillAdvancesOnTheSameFrame() {
        let view = NativeLyricsRowView(frame: NSRect(x: 0, y: 0, width: 260, height: 17))
        defer { view.stop() }
        view.debugNow = { self.anchor }
        view.setActive(true)
        view.apply(input(playing: true))
        let initial = view.caTransactionCommits
        view.render(at: anchor.addingTimeInterval(0.5))
        view.render(at: anchor.addingTimeInterval(1))
        XCTAssertEqual(view.caTransactionCommits, initial)
        XCTAssertTrue(view.debugIsClockRunning, "dedup must not stop the animation clock")
        view.render(at: anchor.addingTimeInterval(3))
        XCTAssertGreaterThan(view.debugFill, 0)
        XCTAssertEqual(view.caTransactionCommits, initial + 1)
        let fill = view.debugFill
        view.render(at: anchor.addingTimeInterval(3))
        XCTAssertEqual(view.caTransactionCommits, initial + 1)
        view.render(at: anchor.addingTimeInterval(3 + 1.0 / 30.0))
        XCTAssertGreaterThan(view.debugFill, fill)
        XCTAssertEqual(view.caTransactionCommits, initial + 2)
    }

    func testOpacityAndPositionChangesAreNotMistakenForAnUnchangedHighlight() throws {
        let view = NativeLyricsRowView(frame: NSRect(x: 0, y: 0, width: 260, height: 17))
        defer { view.stop() }
        view.debugNow = { self.anchor }
        view.apply(input(playing: false))
        let initial = view.caTransactionCommits
        view.debugContentOpacity = 0.5
        view.render(at: anchor)
        let container = try XCTUnwrap(view.layer?.sublayers?.first?.sublayers?.first)
        XCTAssertEqual(container.opacity, 0.5)
        XCTAssertEqual(view.caTransactionCommits, initial + 1)
        view.debugSetContainerYOffset(3)
        XCTAssertEqual(view.debugContainerPosition.y, 3)
        XCTAssertEqual(view.caTransactionCommits, initial + 2)
        view.render(at: anchor)
        XCTAssertEqual(view.caTransactionCommits, initial + 2)
    }
}
