import AppKit
import XCTest
@testable import Valora

@MainActor
final class NativeTitleDoubleClickTests: XCTestCase {
    func testNativeTextHandlesDoubleClickWithoutOpeningOnSingleClick() throws {
        let label = MarqueeLabelView(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        var requests = 0
        label.onDoubleClick = { requests += 1 }
        XCTAssertTrue(label.acceptsFirstMouse(for: nil))
        func event(_ count: Int) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: .zero,
                modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                eventNumber: 0, clickCount: count, pressure: 1))
        }
        label.mouseDown(with: try event(1))
        XCTAssertEqual(requests, 0)
        label.mouseDown(with: try event(2))
        XCTAssertEqual(requests, 1)
        label.mouseDown(with: try event(3))
        XCTAssertEqual(requests, 1)
        label.onDoubleClick = nil
        XCTAssertFalse(label.acceptsFirstMouse(for: nil))
    }
}
