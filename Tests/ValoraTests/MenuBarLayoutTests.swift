import XCTest
@testable import Valora

@MainActor
final class MenuBarLayoutTests: XCTestCase {
    func testUnifiedMenuBarPopoverWidthAndCalendarGrid() {
        XCTAssertEqual(UIStyle.Metrics.menuBarPopoverWidth, 400)
        XCTAssertEqual(UIStyle.Metrics.calendarPanelWidth, 400)
        XCTAssertEqual(UIStyle.Metrics.calendarGridWidth,
                       UIStyle.Metrics.menuBarPopoverWidth - UIStyle.Metrics.contentMargin * 2)
        XCTAssertEqual(UIStyle.Metrics.calendarGridWidth, 368)
        XCTAssertEqual(UIStyle.Metrics.monitoringPanelWidth, 400)
    }
}
