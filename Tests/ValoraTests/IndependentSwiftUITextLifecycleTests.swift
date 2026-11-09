import AppKit
import XCTest
import ReferenceCore
@testable import Valora

@MainActor
final class IndependentSwiftUITextLifecycleTests: XCTestCase {
    func testEmptyTimelineClearsPixelsAndStopReleasesCaptureWindow() {
        let app = NSApplication.shared
        let existing = Set(app.windows.map(ObjectIdentifier.init))
        let row = NativeLyricsRowView(frame: NSRect(x: 0, y: 0, width: 260, height: 17))
        defer {
            row.stop()
            // Clean up only windows created inside this isolated XCTest case.
            for window in app.windows where !existing.contains(ObjectIdentifier(window)) {
                window.close()
            }
        }
        var input = NativeLyricsRowSnapshot(
            identity: nil,
            timeline: LyricTimeline(lines: [LyricLine(start: 0, text: "旧歌词")]),
            elapsed: 1, sampledAt: Date(), rate: 1, playing: false,
            duration: 100, width: 260, textBackend: .swiftUI)
        row.apply(input)
        XCTAssertTrue(row.debugUsesImageContents, "fixture must have rendered text")
        XCTAssertTrue(row.debugHostingViewInWindow)

        input.timeline = nil
        row.apply(input)
        XCTAssertNil(row.debugLine)
        XCTAssertFalse(row.debugUsesImageContents,
                       "cleared lyrics must not leave the old bitmap visible")

        row.stop()
        XCTAssertFalse(row.debugHostingViewInWindow,
                       "stop must release the capture window and its hosting content")
        let ordered = app.windows.filter {
            !existing.contains(ObjectIdentifier($0)) && $0.isVisible
        }
        XCTAssertTrue(ordered.isEmpty, "stopped row must leave no ordered capture window")
    }
}
