import AppKit
import XCTest
@testable import Valora

@MainActor
final class MenuBarModuleControllerTests: XCTestCase {
    private func fixture() -> (SystemMonitor, CalmonCalendarModel, MenuBarModuleController) {
        let monitor = SystemMonitor()
        monitor.verificationApply(snapshot: SystemMonitor.Snapshot(
            cpu: .init(usage: 23),
            memory: .init(total: 32 * 1_073_741_824, used: 20 * 1_073_741_824),
            disk: .init(volumePath: "/", volumeIdentifier: "x", total: 500_000_000_000,
                        available: 200_000_000_000, used: 300_000_000_000),
            device: .init(chip: "Preview", osVersion: "macOS 27"),
            uptime: "已运行 1 天"))
        let calendar = CalmonCalendarModel(
            calendar: Calendar(identifier: .gregorian),
            now: { Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 12))! },
            readGate: { true }, preview: true)
        let controller = MenuBarModuleController(monitor: monitor, calendar: calendar,
                                                 onSettings: {}, onQuit: {})
        return (monitor, calendar, controller)
    }

    func testIndependentStatusItemsAndBasicMenuHaveNoMusicOrDisplayItems() {
        let (monitor, calendar, controller) = fixture()
        controller.start(startSampling: false)
        defer { controller.stop() }
        XCTAssertNotNil(controller.monitorItem)
        XCTAssertNotNil(controller.calendarItem)
        XCTAssertFalse(controller.monitorItem === controller.calendarItem)
        XCTAssertTrue(controller.monitorStatusButton?.target === controller)
        XCTAssertTrue(controller.calendarStatusButton?.target === controller)
        XCTAssertEqual(controller.monitorItem?.autosaveName, "Valora.SystemMonitor")
        XCTAssertEqual(controller.calendarItem?.autosaveName, "Valora.Calendar")
        XCTAssertTrue(controller.monitorItem?.isVisible == true)
        XCTAssertTrue(controller.calendarItem?.isVisible == true)
        XCTAssertEqual(controller.calendarStatusText, "10月25日 周日")
        XCTAssertEqual(controller.makeBasicMenu().items.map(\.title),
                       [AppMenuCommands.versionText, AppMenuCommands.settingsTitle, "", AppMenuCommands.quitTitle])
        XCTAssertFalse(monitor.isRunning)
        XCTAssertTrue(calendar.detail?.festivals.isEmpty ?? true)
    }

    func testPanelsAreIndependentAndSwitchingClosesTheOther() {
        let (_, _, controller) = fixture()
        controller.start(startSampling: false)
        defer { controller.stop() }
        controller.showCalendarPanel()
        XCTAssertEqual(controller.lastOpenedModule, .calendar)
        controller.showMonitorPanel()
        XCTAssertEqual(controller.lastOpenedModule, .systemMonitor)
        controller.closeAllPopovers()
    }

    func testHidingModulesStopsTheirProvidersWithoutLosingTheApplicationEntry() {
        let (monitor, calendar, controller) = fixture()
        controller.start(startSampling: false)
        controller.setSystemMonitorVisible(false)
        XCTAssertNil(controller.monitorItem)
        XCTAssertFalse(monitor.isRunning)
        controller.setCalendarVisible(false)
        XCTAssertNil(controller.calendarItem)
        XCTAssertFalse(calendar.isStartedForTest)
        controller.stop()
    }

    func testStopThenStartRecreatesBothStatusItemsWithoutStaleImageGuard() {
        let (_, _, controller) = fixture()
        controller.start(startSampling: false)
        let firstMonitor = ObjectIdentifier(controller.monitorItem!)
        let firstCalendar = ObjectIdentifier(controller.calendarItem!)
        controller.stop()
        controller.start(startSampling: false)
        defer { controller.stop() }
        XCTAssertNotNil(controller.monitorItem?.button?.image)
        XCTAssertNotNil(controller.calendarItem?.button?.image)
        XCTAssertNotEqual(ObjectIdentifier(controller.monitorItem!), firstMonitor)
        XCTAssertNotEqual(ObjectIdentifier(controller.calendarItem!), firstCalendar)
        XCTAssertEqual(controller.calendarStatusText, "10月25日 周日")
    }

    func testHiddenInheritedStatusItemIsRepairedWithStableAutosaveName() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer { NSStatusBar.system.removeStatusItem(item) }
        item.isVisible = false
        MenuBarModuleController.ensureStatusItemVisible(item, autosaveName: "Valora.Calendar")
        XCTAssertEqual(item.autosaveName, "Valora.Calendar")
        XCTAssertTrue(item.isVisible,
                      "a pre-existing hidden Item-0 status item must be explicitly repaired")
    }

    func testReenablingCalendarRepairsAnExistingHiddenItem() {
        let (_, _, controller) = fixture()
        controller.start(startSampling: false)
        defer { controller.stop() }
        let calendar = controller.calendarItem
        calendar?.isVisible = false
        controller.setCalendarVisible(true)
        XCTAssertEqual(controller.calendarItem?.autosaveName, "Valora.Calendar")
        XCTAssertTrue(controller.calendarItem?.isVisible == true)
    }

    func testVApplicationItemUsesStableAutosaveNameAndIsVisible() {
        let delegate = AppDelegate(arguments: ["Valora", "--preview-menu-modules"])
        defer {
            delegate.menuBarModulesForVerification?.stop()
            delegate.removeApplicationStatusItemForVerification()
        }
        delegate.setupMenuForVerification()
        let item = delegate.applicationStatusItemForVerification
        XCTAssertEqual(item?.autosaveName, "Valora.Application")
        XCTAssertTrue(item?.isVisible == true)
    }

    func testStopRemovesStatusItemsAndProviders() {
        let (monitor, _, controller) = fixture()
        controller.start(startSampling: false)
        controller.stop()
        XCTAssertNil(controller.monitorItem)
        XCTAssertNil(controller.calendarItem)
        XCTAssertFalse(monitor.isRunning)
        XCTAssertFalse(controller.isMonitorPanelShown)
        XCTAssertFalse(controller.isCalendarPanelShown)
    }
}
