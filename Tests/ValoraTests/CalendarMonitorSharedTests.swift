import XCTest
@testable import Valora

@MainActor
final class CalendarMonitorSharedTests: XCTestCase {
    func testVisibilitySwitchesRemainIndependentForAllFourCombinations() {
        let visibility = MenuBarPanelVisibility()
        XCTAssertTrue(visibility.monitorVisible)
        XCTAssertTrue(visibility.calendarVisible)
        visibility.monitorVisible = false
        XCTAssertFalse(visibility.monitorVisible)
        XCTAssertTrue(visibility.calendarVisible)
        visibility.calendarVisible = false
        XCTAssertFalse(visibility.monitorVisible)
        XCTAssertFalse(visibility.calendarVisible)
        visibility.monitorVisible = true
        XCTAssertTrue(visibility.monitorVisible)
        XCTAssertFalse(visibility.calendarVisible)
        visibility.calendarVisible = true
        XCTAssertTrue(visibility.monitorVisible)
        XCTAssertTrue(visibility.calendarVisible)
    }

    func testSharedPanelRoutingNeverAllowsTwoAnchors() {
        typealias Module = MenuBarModuleController.MenuBarModule
        XCTAssertEqual(MenuBarModuleController.panelRouteDecision(
            isShown: false, lastOpened: nil, clicked: .calendar), .open)
        XCTAssertEqual(MenuBarModuleController.panelRouteDecision(
            isShown: true, lastOpened: .calendar, clicked: .calendar), .close)
        XCTAssertEqual(MenuBarModuleController.panelRouteDecision(
            isShown: true, lastOpened: .calendar, clicked: .systemMonitor), .switchAnchor)
        XCTAssertEqual(MenuBarModuleController.panelRouteDecision(
            isShown: true, lastOpened: .systemMonitor, clicked: .systemMonitor), .close)
    }

    func testMonitorSummaryMissingValuesUseDashesAndDoNotInventZero() {
        XCTAssertEqual(MonitorSummaryFormat.total(nil), "总计 --")
        XCTAssertEqual(MonitorSummaryFormat.remaining(nil), "剩余 --")
        XCTAssertEqual(MonitorSummaryFormat.total("32 GB"), "总计 32 GB")
        XCTAssertEqual(MonitorSummaryFormat.remaining("12 GB"), "剩余 12 GB")
        XCTAssertEqual(MonitorSummaryFormat.uptime(""), "--")
        XCTAssertEqual(MonitorSummaryFormat.uptime("已运行 2 天"), "已运行 2 天")
    }

    func testProductionMonitorHasNoInjectedApplicationReader() {
        XCTAssertFalse(SystemMonitor().hasInjectedApplicationReader,
                       "production construction must not start app-process memory collection")
    }
}
