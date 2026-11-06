import AppKit
import Combine
import XCTest
@testable import Valora

@MainActor
final class IndependentMenuBarMigrationTests: XCTestCase {
    func testCalendarHideThenShowRestoresNativeDateImageImmediately() {
        let model = CalmonCalendarModel()
        let controller = MenuBarModuleController(monitor: SystemMonitor(), calendar: model,
                                                 onSettings: {}, onQuit: {})
        controller.start(startSampling: false)
        defer { controller.stop() }
        XCTAssertNotNil(controller.calendarStatusButton?.image)
        controller.setCalendarVisible(false)
        controller.setCalendarVisible(true)
        XCTAssertNotNil(controller.calendarStatusButton?.image,
                        "Recreated date item must render even when the date has not changed")
        XCTAssertEqual(controller.calendarStatusText, model.menuBarText)
    }

    func testMonitorHideThenShowRestoresNativeMetricImageImmediately() {
        let monitor = SystemMonitor()
        let controller = MenuBarModuleController(monitor: monitor, calendar: CalmonCalendarModel(),
                                                 onSettings: {}, onQuit: {})
        controller.start(startSampling: false)
        defer { controller.stop() }
        XCTAssertNotNil(controller.monitorStatusButton?.image)
        controller.setSystemMonitorVisible(false)
        controller.setSystemMonitorVisible(true)
        XCTAssertNotNil(controller.monitorStatusButton?.image,
                        "Recreated metrics item must render before a later asynchronous sample")
    }

    /// The calendar reads only the trusted read-only holiday source. This uses
    /// the production authorization subscription and a fixture transport; no
    /// real EventKit store or personal calendar is touched.
    func testPublishedCalendarAuthorizationRefreshStartsHolidayReadAfterGrant() async {
        let permissions = AppPermissions(bluetooth: .denied, loginItem: .notRegistered,
                                         calendar: .denied)
        let transport = holidayTransport()
        let provider = HolidayProvider(
            authorizationCheck: { permissions.calendar == .fullAccess },
            transportFactory: { transport })
        let model = CalmonCalendarModel(provider: provider,
                                        readGate: { permissions.calendar == .fullAccess })
        model.start()
        model.setPanelVisibility(panel: true, calendarModule: true)
        // This is the production AppDelegate subscription. Published emits in
        // willSet, so reading permissions.calendar synchronously observes the
        // previous authorization instead of the emitted grant.
        let subscription = CalendarAuthorizationRefresh.subscribe(permissions) {
            model.refreshCalendarHolidays()
        }
        permissions.verificationSet(calendar: .fullAccess)
        await waitForRefresh()
        XCTAssertEqual(transport.eventReadCount, 1,
                       "An already-open calendar must load holidays after permission changes without another click")
        subscription.cancel()
        model.stop()
    }
}

@MainActor
extension IndependentMenuBarMigrationTests {
    func testCalendarAuthorizationRevokeClearsAndStopsWithoutRevivingQueuedGrant() async {
        let permissions = AppPermissions(calendar: .denied)
        let transport = holidayTransport()
        let provider = HolidayProvider(
            authorizationCheck: { permissions.calendar == .fullAccess },
            transportFactory: { transport })
        let model = CalmonCalendarModel(provider: provider,
                                        readGate: { permissions.calendar == .fullAccess })
        model.start()
        model.setPanelVisibility(panel: true, calendarModule: true)
        let subscription = CalendarAuthorizationRefresh.subscribe(permissions) {
            model.refreshCalendarHolidays()
        }
        defer { subscription.cancel(); model.stop() }

        permissions.verificationSet(calendar: .fullAccess)
        await waitForRefresh()
        XCTAssertEqual(transport.eventReadCount, 1)

        permissions.verificationSet(calendar: .denied)
        await waitForRefresh()
        XCTAssertEqual(transport.eventReadCount, 1, "denied must not issue another provider read")
        XCTAssertTrue(model.detail?.festivals.isEmpty ?? false)

        // A stop must reject a queued grant callback rather than revive a closed
        // panel/session.
        model.stop()
        permissions.verificationSet(calendar: .fullAccess)
        await waitForRefresh()
        XCTAssertEqual(transport.eventReadCount, 1)
    }

    private func holidayTransport() -> FixtureHolidayTransport {
        FixtureHolidayTransport(calendars: [
            HolidayCalendarDescriptor(id: "fixture-holiday", title: "中国节假日",
                                      sourceTitle: "Fixture", isReadOnly: true)
        ], records: [])
    }

    private func waitForRefresh() async {
        try? await Task.sleep(for: .milliseconds(80))
    }
}
