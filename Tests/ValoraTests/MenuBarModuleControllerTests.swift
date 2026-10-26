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
            eventProvider: PreviewCalendarEvents(), readGate: { true }, preview: true)
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
        XCTAssertEqual(controller.monitorStatusButton?.action, #selector(MenuBarModuleController.statusItemClicked(_:)))
        XCTAssertEqual(controller.calendarStatusButton?.action, #selector(MenuBarModuleController.statusItemClicked(_:)))
        XCTAssertEqual(controller.calendarStatusText, "10月25日 周日")
        let titles = controller.makeBasicMenu().items.map(\.title)
        XCTAssertEqual(titles, [AppMenuCommands.versionText, AppMenuCommands.settingsTitle, "", AppMenuCommands.quitTitle])
        XCTAssertFalse(titles.contains("显示器"))
        XCTAssertFalse(titles.contains("播放"))
        XCTAssertFalse(titles.contains("上一首"))
        XCTAssertFalse(titles.contains("下一首"))
        XCTAssertFalse(monitor.isRunning)
        XCTAssertTrue(calendar.events.isEmpty)
    }


    func testCodexModuleHasIndependentStatusItemAndBasicMenuNoMusic() async {
        let monitor = SystemMonitor()
        monitor.verificationApply(snapshot: SystemMonitor.Snapshot())
        let calendar = CalmonCalendarModel(calendar: Calendar(identifier: .gregorian))
        let codex = PreviewCodexUsage.provider()
        let controller = MenuBarModuleController(monitor: monitor, calendar: calendar, codexUsage: codex,
                                                 onSettings: {}, onQuit: {})
        controller.start(startSampling: false)
        defer { controller.stop() }
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertNotNil(controller.codexItem)
        XCTAssertNotNil(controller.codexStatusButton?.image)
        XCTAssertEqual(controller.codexStatusText, "Codex 5H 剩余 58%，WEEK 剩余 32%")
        XCTAssertTrue(controller.monitorItem === controller.codexItem,
                      "monitor and Codex share one status item")
        XCTAssertFalse(controller.calendarItem === controller.codexItem)
        XCTAssertEqual(controller.makeBasicMenu().items.map(\.title),
                       [AppMenuCommands.versionText, AppMenuCommands.settingsTitle, "", AppMenuCommands.quitTitle])
        controller.showCodexPanel()
        XCTAssertEqual(controller.lastOpenedModule, .codexUsage)
        controller.closeAllPopovers()
    }

    func testLeftPanelsAreIndependentAndSwitchingClosesTheOther() {
        let (_, _, controller) = fixture()
        controller.start(startSampling: false)
        defer { controller.stop() }
        controller.showCalendarPanel()
        XCTAssertEqual(controller.lastOpenedModule, .calendar)
        controller.showMonitorPanel()
        XCTAssertEqual(controller.lastOpenedModule, .systemMonitor)
        controller.closeAllPopovers()
    }


    func testCombinedMonitorCodexStatusItemAndSections() async {
        let monitor = SystemMonitor()
        monitor.verificationApply(snapshot: SystemMonitor.Snapshot())
        let calendar = CalmonCalendarModel(calendar: Calendar(identifier: .gregorian))
        let codex = PreviewCodexUsage.provider()
        let controller = MenuBarModuleController(monitor: monitor, calendar: calendar, codexUsage: codex,
                                                 onSettings: {}, onQuit: {})
        controller.start(startSampling: false)
        defer { controller.stop(); codex.stop() }
        try? await Task.sleep(for: .milliseconds(80))
        XCTAssertNotNil(controller.combinedItem)
        XCTAssertTrue(controller.monitorItem === controller.codexItem)
        XCTAssertFalse(controller.combinedItem === controller.calendarItem)
        XCTAssertEqual(controller.combinedSections, MenuBarModuleController.CombinedSections(monitor: true, codex: true))
        XCTAssertNotNil(controller.combinedItem?.button?.image)
        XCTAssertEqual(controller.makeBasicMenu().items.map(\.title),
                       [AppMenuCommands.versionText, AppMenuCommands.settingsTitle, "", AppMenuCommands.quitTitle])
        controller.setCodexVisible(false)
        XCTAssertFalse(controller.combinedSections.codex)
        XCTAssertTrue(controller.combinedSections.monitor)
        XCTAssertNil(controller.codexItem)
        XCTAssertNotNil(controller.combinedItem)
        controller.setSystemMonitorVisible(false)
        XCTAssertTrue(controller.combinedSections.isEmpty)
        XCTAssertNil(controller.combinedItem)
        XCTAssertNotNil(controller.calendarItem, "calendar remains independent of the combined entry")
    }

    func testCombinedEntryProvidersDoNotStopEachOther() async {
        let monitor = SystemMonitor()
        monitor.verificationApply(snapshot: SystemMonitor.Snapshot())
        let calendar = CalmonCalendarModel(calendar: Calendar(identifier: .gregorian))
        let codex = PreviewCodexUsage.provider()
        let controller = MenuBarModuleController(monitor: monitor, calendar: calendar, codexUsage: codex,
                                                 onSettings: {}, onQuit: {})
        controller.start(startSampling: true)
        defer { controller.stop(); codex.stop() }
        try? await Task.sleep(for: .milliseconds(80))
        XCTAssertTrue(monitor.isRunning)
        let codexRequests = codex.requestCount
        controller.setCodexVisible(false)
        XCTAssertFalse(codex.isRunningForTest)
        XCTAssertTrue(monitor.isRunning)
        XCTAssertEqual(codex.requestCount, codexRequests)
        controller.setCodexVisible(true)
        XCTAssertNotNil(controller.combinedItem)
        controller.setSystemMonitorVisible(false)
        XCTAssertFalse(monitor.isRunning)
        XCTAssertNotNil(controller.combinedItem)
        XCTAssertNotNil(controller.codexItem)
        XCTAssertEqual(controller.combinedSections, MenuBarModuleController.CombinedSections(monitor: false, codex: true))
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
