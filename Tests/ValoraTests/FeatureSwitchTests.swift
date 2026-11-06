import AppKit
import SwiftUI
import XCTest
@testable import Valora

@MainActor
final class FeatureSwitchTests: XCTestCase {
    private func calendar() -> CalmonCalendarModel {
        CalmonCalendarModel(readGate: { true }, preview: true)
    }

    func testDefaultsPersistAndFeaturePagesUseRealToggleBindings() throws {
        let suite = "com.wangqing.valora.features.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = SettingsDraft(defaults: defaults)
        XCTAssertTrue(first.value("showApplicationMenuBarIcon", true))
        XCTAssertTrue(first.value("enableSystemMonitor", true))
        first.binding("showApplicationMenuBarIcon", true).wrappedValue = false
        first.binding("enableSystemMonitor", true).wrappedValue = false
        let restored = SettingsDraft(defaults: defaults)
        XCTAssertFalse(restored.value("showApplicationMenuBarIcon", true))
        XCTAssertFalse(restored.value("enableSystemMonitor", true))

        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let view = try String(contentsOf: root.appendingPathComponent("Sources/Valora/SettingsView.swift"), encoding: .utf8)
        XCTAssertTrue(view.contains("showApplicationMenuBarIcon"))
        XCTAssertTrue(view.contains("enableSystemMonitor"))
        XCTAssertTrue(view.contains("SettingsToggleRow(title: \"显示菜单栏图标\""))
        XCTAssertTrue(view.contains("SettingsToggleRow(title: \"系统监控\""))
        XCTAssertFalse(view.contains("enableAIUsage"))
        XCTAssertFalse(view.contains("enableDownloads"))
    }

    func testSystemMonitorOffDoesNotSampleAndOffStopsExistingSampling() async {
        let monitor = SystemMonitor()
        let controller = MenuBarModuleController(monitor: monitor, calendar: calendar(),
                                                 onSettings: {}, onQuit: {})
        controller.setSystemMonitorVisible(false)
        controller.start(startSampling: true)
        defer { controller.stop() }
        try? await Task.sleep(for: .milliseconds(250))
        XCTAssertEqual(monitor.sampleStartCount, 0)
        XCTAssertNil(controller.monitorItem)

        controller.setSystemMonitorVisible(true)
        let deadline = Date().addingTimeInterval(2)
        while monitor.sampleStartCount == 0, Date() < deadline { await Task.yield() }
        XCTAssertGreaterThan(monitor.sampleStartCount, 0)
        controller.setSystemMonitorVisible(false)
        let count = monitor.sampleStartCount
        try? await Task.sleep(for: .milliseconds(3_200))
        XCTAssertEqual(monitor.sampleStartCount, count,
                       "monitor off must prevent further scheduled samples")
        XCTAssertFalse(monitor.isRunning)
    }

    func testPersistedIconOffDoesNotCreateStatusItemAtStartup() throws {
        let delegate = AppDelegate(arguments: ["Valora", "--preview-menu-modules"])
        delegate.settingsDraft.binding("showApplicationMenuBarIcon", true).wrappedValue = false
        delegate.settingsDraft.binding("enableSystemMonitor", true).wrappedValue = true
        defer {
            delegate.settingsDraft.binding("showApplicationMenuBarIcon", true).wrappedValue = true
            delegate.menuBarModulesForVerification?.stop()
            delegate.removeApplicationStatusItemForVerification()
        }
        delegate.setupMenuForVerification()
        XCTAssertNil(delegate.applicationStatusItemForVerification)
        XCTAssertNotNil(delegate.menuBarModulesForVerification?.monitorItem)
        delegate.settingsDraft.binding("showApplicationMenuBarIcon", true).wrappedValue = true
        delegate.applyFeatureSettingsForVerification()
        XCTAssertNotNil(delegate.applicationStatusItemForVerification)
    }

    func testApplicationIconSwitchHidesOnlySoftwareItemAndReusesIt() throws {
        let delegate = AppDelegate(arguments: ["Valora", "--preview-menu-modules"])
        delegate.settingsDraft.binding("showApplicationMenuBarIcon", true).wrappedValue = true
        delegate.settingsDraft.binding("enableSystemMonitor", true).wrappedValue = true
        delegate.setupMenuForVerification()
        defer {
            delegate.settingsDraft.binding("showApplicationMenuBarIcon", true).wrappedValue = true
            delegate.settingsDraft.binding("enableSystemMonitor", true).wrappedValue = true
            delegate.menuBarModulesForVerification?.stop()
            delegate.removeApplicationStatusItemForVerification()
        }
        let original = try XCTUnwrap(delegate.applicationStatusItemForVerification)
        XCTAssertTrue(original.isVisible)
        let identity = ObjectIdentifier(original)
        XCTAssertNotNil(delegate.menuBarModulesForVerification?.monitorItem)
        XCTAssertNotNil(delegate.menuBarModulesForVerification?.calendarItem)

        delegate.settingsDraft.binding("showApplicationMenuBarIcon", true).wrappedValue = false
        delegate.applyFeatureSettingsForVerification()
        XCTAssertFalse(original.isVisible)
        XCTAssertEqual(ObjectIdentifier(try XCTUnwrap(delegate.applicationStatusItemForVerification)), identity)

        delegate.settingsDraft.binding("showApplicationMenuBarIcon", true).wrappedValue = true
        delegate.applyFeatureSettingsForVerification()
        let restored = try XCTUnwrap(delegate.applicationStatusItemForVerification)
        XCTAssertTrue(restored.isVisible)
        XCTAssertEqual(ObjectIdentifier(restored), identity)
    }
}
