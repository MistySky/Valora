import AppKit
import SwiftUI
import XCTest
@testable import Valora

@MainActor
final class FeatureSwitchTests: XCTestCase {
    private func calendar() -> CalmonCalendarModel {
        CalmonCalendarModel(eventProvider: PreviewCalendarEvents(), readGate: { true }, preview: true)
    }

    func testDefaultsPersistAndFeaturePagesUseRealToggleBindings() throws {
        let suite = "com.wangqing.valora.features.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = SettingsDraft(defaults: defaults)
        XCTAssertTrue(first.value("showApplicationMenuBarIcon", true))
        XCTAssertTrue(first.value("enableSystemMonitor", true))
        XCTAssertTrue(first.value("enableAIUsage", true))
        XCTAssertTrue(first.value("enableDownloads", true))
        first.binding("showApplicationMenuBarIcon", true).wrappedValue = false
        first.binding("enableSystemMonitor", true).wrappedValue = false
        first.binding("enableAIUsage", true).wrappedValue = false
        first.binding("enableDownloads", true).wrappedValue = false
        let restored = SettingsDraft(defaults: defaults)
        XCTAssertFalse(restored.value("showApplicationMenuBarIcon", true))
        XCTAssertFalse(restored.value("enableSystemMonitor", true))
        XCTAssertFalse(restored.value("enableAIUsage", true))
        XCTAssertFalse(restored.value("enableDownloads", true))

        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let view = try String(contentsOf: root.appendingPathComponent("Sources/Valora/SettingsView.swift"), encoding: .utf8)
        for key in ["showApplicationMenuBarIcon", "enableSystemMonitor", "enableAIUsage", "enableDownloads"] {
            XCTAssertTrue(view.contains(key), "feature switch key missing from settings: \(key)")
        }
        XCTAssertTrue(view.contains("SettingsToggleRow(title: \"显示菜单栏图标\""))
        XCTAssertTrue(view.contains("SettingsToggleRow(title: \"系统监控\""))
        XCTAssertTrue(view.contains("SettingsToggleRow(title: \"下载\""))
        XCTAssertTrue(view.contains("AI 用量"))
        XCTAssertFalse(view.contains("case .systemMonitor: placeholderPage"))
        XCTAssertFalse(view.contains("case .downloadMonitor: placeholderPage"))
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

    func testCodexOffCancelsAndIgnoresLateResponse() async {
        let provider = CodexUsageProvider(readLimits: {
            try? await Task.sleep(for: .milliseconds(250))
            return PreviewCodexUsage.reading()
        }, refreshInterval: 3_600)
        let controller = MenuBarModuleController(monitor: SystemMonitor(), calendar: calendar(),
                                                 codexUsage: provider, onSettings: {}, onQuit: {})
        controller.setSystemMonitorVisible(false)
        controller.setCodexVisible(false)
        controller.start(startSampling: false)
        defer { controller.stop(); provider.stop() }
        XCTAssertNil(controller.codexItem)
        XCTAssertEqual(provider.requestCount, 0)

        controller.setCodexVisible(true)
        let startDeadline = Date().addingTimeInterval(1)
        while provider.requestCount == 0, Date() < startDeadline { await Task.yield() }
        XCTAssertEqual(provider.requestCount, 1)
        XCTAssertNotNil(controller.codexItem)
        controller.setCodexVisible(false)
        try? await Task.sleep(for: .milliseconds(350))
        XCTAssertEqual(provider.snapshot, .initial)
        XCTAssertEqual(provider.requestCount, 1, "off must not launch a replacement request")
        XCTAssertGreaterThanOrEqual(provider.discardedCount, 1)
        XCTAssertNil(controller.codexItem)
    }

    func testPersistedIconOffDoesNotCreateStatusItemAtStartup() throws {
        let delegate = AppDelegate(arguments: ["Valora", "--preview-menu-modules"])
        delegate.settingsDraft.binding("showApplicationMenuBarIcon", true).wrappedValue = false
        delegate.settingsDraft.binding("enableSystemMonitor", true).wrappedValue = true
        delegate.settingsDraft.binding("enableAIUsage", true).wrappedValue = true
        defer {
            delegate.settingsDraft.binding("showApplicationMenuBarIcon", true).wrappedValue = true
            delegate.menuBarModulesForVerification?.stop()
            delegate.removeApplicationStatusItemForVerification()
        }
        delegate.setupMenuForVerification()
        XCTAssertNil(delegate.applicationStatusItemForVerification)
        XCTAssertNotNil(delegate.menuBarModulesForVerification?.monitorItem,
                        "module entries remain independent of the software icon switch")
        delegate.settingsDraft.binding("showApplicationMenuBarIcon", true).wrappedValue = true
        delegate.applyFeatureSettingsForVerification()
        XCTAssertNotNil(delegate.applicationStatusItemForVerification)
    }

    func testApplicationIconSwitchHidesOnlySoftwareItemAndReusesIt() throws {
        let delegate = AppDelegate(arguments: ["Valora", "--preview-menu-modules"])
        delegate.settingsDraft.binding("showApplicationMenuBarIcon", true).wrappedValue = true
        delegate.settingsDraft.binding("enableSystemMonitor", true).wrappedValue = true
        delegate.settingsDraft.binding("enableAIUsage", true).wrappedValue = true
        delegate.settingsDraft.binding("enableDownloads", true).wrappedValue = true
        delegate.setupMenuForVerification()
        defer {
            delegate.settingsDraft.binding("showApplicationMenuBarIcon", true).wrappedValue = true
            delegate.settingsDraft.binding("enableSystemMonitor", true).wrappedValue = true
            delegate.settingsDraft.binding("enableAIUsage", true).wrappedValue = true
            delegate.settingsDraft.binding("enableDownloads", true).wrappedValue = true
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
        XCTAssertNotNil(delegate.menuBarModulesForVerification?.monitorItem)
        XCTAssertNotNil(delegate.menuBarModulesForVerification?.calendarItem)

        delegate.settingsDraft.binding("showApplicationMenuBarIcon", true).wrappedValue = true
        delegate.applyFeatureSettingsForVerification()
        let restored = try XCTUnwrap(delegate.applicationStatusItemForVerification)
        XCTAssertTrue(restored.isVisible)
        XCTAssertEqual(ObjectIdentifier(restored), identity,
                       "showing the icon again must reuse the same status item, not create a duplicate")
        XCTAssertNotNil(restored.menu)

        // With every module off, the software icon remains independently
        // controlled and visible.
        delegate.settingsDraft.binding("enableSystemMonitor", true).wrappedValue = false
        delegate.settingsDraft.binding("enableAIUsage", true).wrappedValue = false
        delegate.applyFeatureSettingsForVerification()
        XCTAssertNil(delegate.menuBarModulesForVerification?.monitorItem)
        XCTAssertNil(delegate.menuBarModulesForVerification?.codexItem)
        XCTAssertTrue(try XCTUnwrap(delegate.applicationStatusItemForVerification).isVisible)
        delegate.settingsDraft.binding("showApplicationMenuBarIcon", true).wrappedValue = false
        delegate.applyFeatureSettingsForVerification()
        XCTAssertFalse(try XCTUnwrap(delegate.applicationStatusItemForVerification).isVisible)
    }
}
