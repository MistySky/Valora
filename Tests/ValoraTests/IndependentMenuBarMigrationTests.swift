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

    func testPublishedCalendarAuthorizationRefreshStartsReadAfterGrant() async {
        let permissions = AppPermissions(bluetooth: .denied, loginItem: .notRegistered,
                                         calendar: .denied)
        let provider = CountingEvents()
        let model = CalmonCalendarModel(eventProvider: provider,
                                        readGate: { permissions.calendar == .fullAccess })
        model.start()
        model.setPanelVisibility(panel: true, calendarModule: true)
        // This is the production AppDelegate subscription. Published emits in
        // willSet, so reading permissions.calendar synchronously observes the
        // previous authorization instead of the emitted grant.
        let subscription = CalendarAuthorizationRefresh.subscribe(permissions) {
            model.refreshEvents()
        }
        permissions.verificationSet(calendar: .fullAccess)
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(provider.readCount, 1,
                       "An already-open calendar must load after permission changes without another click")
        subscription.cancel()
        model.stop()
    }
}

@MainActor
private final class CountingEvents: CalendarEventProviding {
    var readCount = 0
    func events(on day: Date, calendar: Calendar) async -> [CalendarEvent] {
        readCount += 1
        return []
    }
}

@MainActor
extension IndependentMenuBarMigrationTests {
    func testCalendarAuthorizationRevokeClearsAndStopsWithoutRevivingQueuedGrant() async {
        let permissions = AppPermissions(calendar: .denied)
        let provider = CountingEvents()
        let model = CalmonCalendarModel(eventProvider: provider,
                                        readGate: { permissions.calendar == .fullAccess })
        model.start()
        model.setPanelVisibility(panel: true, calendarModule: true)
        let subscription = CalendarAuthorizationRefresh.subscribe(permissions) {
            model.refreshEvents()
        }
        defer { subscription.cancel(); model.stop() }

        permissions.verificationSet(calendar: .fullAccess)
        await waitForRefresh()
        XCTAssertEqual(provider.readCount, 1)

        permissions.verificationSet(calendar: .denied)
        await waitForRefresh()
        XCTAssertEqual(provider.readCount, 1, "denied must not issue another provider read")
        XCTAssertTrue(model.events.isEmpty)
        XCTAssertEqual(model.eventState, .notAvailable)

        // A stop must reject a queued grant callback rather than revive a closed
        // panel/session.
        model.stop()
        permissions.verificationSet(calendar: .fullAccess)
        await waitForRefresh()
        XCTAssertEqual(provider.readCount, 1)
    }

    private func waitForRefresh() async {
        try? await Task.sleep(for: .milliseconds(80))
    }
}
