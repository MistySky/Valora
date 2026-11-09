import AppKit
import XCTest
@testable import Valora

@MainActor
final class IndependentPointerDedupAcceptanceTests: XCTestCase {
    private final class CountingPanel: NSPanel {
        var writes = 0
        override var ignoresMouseEvents: Bool { didSet { writes += 1 } }
    }

    func testLiveWindowStateAvoidsRedundantWritesAndCorrectsExternalChanges() {
        let panel = CountingPanel(contentRect: NSRect(x: -20000, y: -20000, width: 10, height: 10),
                                  styleMask: .borderless, backing: .buffered, defer: false)
        defer { panel.close() }
        panel.ignoresMouseEvents = true
        let originalCount = panel.writes
        XCTAssertFalse(WindowCoordinator.setIgnoresMouseEvents(of: panel, true))
        XCTAssertEqual(panel.writes, originalCount)
        XCTAssertTrue(WindowCoordinator.setIgnoresMouseEvents(of: panel, false))
        XCTAssertFalse(panel.ignoresMouseEvents)
        XCTAssertEqual(panel.writes, originalCount + 1)
        panel.ignoresMouseEvents = true // an independent visibility path
        XCTAssertTrue(WindowCoordinator.setIgnoresMouseEvents(of: panel, false))
        XCTAssertFalse(panel.ignoresMouseEvents)
        XCTAssertEqual(panel.writes, originalCount + 3)
    }
}
