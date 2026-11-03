import AppKit
import XCTest
@testable import Valora
import ReferenceCore

@MainActor
final class SettingsReductionTests: XCTestCase {
    private var suite = ""
    private var defaults: UserDefaults!
    private var settings: RevivalSettings!
    private var model: AppModel!
    private var coordinator: WindowCoordinator!

    override func setUp() {
        super.setUp()
        suite = "com.wangqing.valora.settings-reduction.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        settings = RevivalSettings(defaults: defaults)
        model = AppModel(settings: settings)
        model.title = "Track"
        model.artist = "Artist"
        model.playing = true
        settings.nowPlayingEnabled = true
        settings.autoCollapse = false
        coordinator = WindowCoordinator(model)
        coordinator.start(trackPointer: false)
    }

    override func tearDown() {
        coordinator?.cancelPendingHover()
        coordinator?.collapse()
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testHoverDelayExpandsAndCanBeCancelledByDisable() async {
        settings.hoverEnabled = true
        settings.hoverDelay = 0.05
        coordinator.pointerChanged(true)
        try? await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertTrue(model.expanded, "hover delay must reach the real expansion consumer")
        coordinator.pointerChanged(false)
        coordinator.collapse()

        settings.hoverEnabled = true
        settings.hoverDelay = 0.15
        coordinator.pointerChanged(true)
        settings.hoverEnabled = false
        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertFalse(model.expanded, "disabling hover must cancel a pending expansion")
    }

    func testPointerExitAndStopCancelPendingHover() async {
        settings.hoverEnabled = true
        settings.hoverDelay = 0.12
        coordinator.pointerChanged(true)
        coordinator.pointerChanged(false)
        try? await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertFalse(model.expanded, "pointer exit must cancel pending hover")

        coordinator.pointerChanged(true)
        coordinator.cancelPendingHover()
        try? await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertFalse(model.expanded, "explicit/teardown cancellation must cancel pending hover")
    }

    func testLegacyGestureCodeIsGoneAndNormalControlsRemain() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        func text(_ relative: String) throws -> String {
            try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
        }
        let models = try text("Sources/Valora/Models.swift")
        let coordinatorText = try text("Sources/Valora/WindowCoordinator.swift")
        let notch = try text("Sources/Valora/NotchView.swift")
        let settingsView = try text("Sources/Valora/SettingsView.swift")
        let progress = try text("Sources/Valora/MediaProgressView.swift")
        let volume = try text("Sources/Valora/OutputVolumeView.swift")
        let compact = try text("Sources/Valora/CompactPlaybackControl.swift")

        for legacy in ["NotchGesture", "handleSwipe", "performGesture", "swipeTo", "enableHaptics"] {
            XCTAssertFalse(models.contains(legacy), "legacy gesture symbol remains in Models: \(legacy)")
        }
        XCTAssertFalse(coordinatorText.contains("scrollWheel"))
        XCTAssertFalse(coordinatorText.contains("scrollGesture"))
        XCTAssertFalse(coordinatorText.contains("swipe"))
        XCTAssertFalse(notch.contains("DragGesture"))
        XCTAssertFalse(notch.contains("handleSwipe"))
        for removedRow in ["Hide in fullscreen", "Hide in mission control", "Hide while gaming",
                           "Hide from screen capture", "Idle Activity", "Most Recent",
                           "Contrast outline", "Progressive blur", "Haptic feedback",
                           "Gestures", "Tuning", "Disable compact waveform",
                           "Disable artwork flip", "Hide while source app is active",
                           "Hide media title extras", "Idle duration", "Peek duration",
                           "songTitleBadge", "Favorite", "Shuffle", "Repeat", "Copy"] {
            XCTAssertFalse(settingsView.contains(removedRow), "removed setting row remains: \(removedRow)")
        }
        for keptRow in ["Launch at login", "Force simulated notch", "Display on",
                        "Expand on hover", "Hover delay", "Now Playing", "Show lyrics"] {
            XCTAssertTrue(settingsView.contains(keptRow), "retained setting row missing: \(keptRow)")
        }
        XCTAssertFalse(settingsView.contains("Use live waveform"), "removed live-waveform row remains")
        XCTAssertFalse(settingsView.contains("Behaviour"), "separate behaviour section remains")
        // Ordinary input capabilities must not be collateral damage.
        XCTAssertTrue(notch.contains("onTapGesture"))
        XCTAssertTrue(compact.contains("command(2)"))
        XCTAssertTrue(progress.contains("DragGesture"))
        XCTAssertTrue(volume.contains("DragGesture"))
        XCTAssertTrue(settingsView.contains("SettingsSliderRow"))
        XCTAssertFalse(settingsView.contains("songTitleBadge"))
        XCTAssertFalse(settingsView.contains("Explicit"))
        XCTAssertFalse(settingsView.contains("Format"))
        XCTAssertTrue(settingsView.contains("Connectivity"))
        XCTAssertFalse(settingsView.contains("connectivityModel"))
        XCTAssertFalse(settingsView.contains("connectivityDuration"))
        XCTAssertFalse(settingsView.contains("warnOnLowConnectBattery"))
        XCTAssertFalse(settingsView.contains("lowConnectBatteryThreshold"))
        XCTAssertFalse(settingsView.contains("playSoundOnLowConnectBattery"))
        XCTAssertTrue(SettingsPage.allCases.contains(.connectivity))
        XCTAssertTrue(coordinatorText.contains(".mouseMoved,.leftMouseDragged"))

    }


    func testSidebarGroupsFollowTheUserApprovedStructure() {
        XCTAssertEqual(SettingsSidebar.groups.map(\.title), [nil, "刘海屏", "菜单栏", "Valora"])
        XCTAssertEqual(SettingsSidebar.groups.map { $0.pages.map(\.displayTitle) }, [
            ["通用"],
            ["音乐", "锁定屏幕", "设备连接"],
            ["日历", "系统监控"],
            ["关于"]
        ])
        XCTAssertEqual(SettingsPage.allCases.map(\.displayTitle),
                       ["通用", "音乐", "锁定屏幕", "设备连接",
                        "日历", "系统监控", "关于"])
        XCTAssertEqual(SettingsSidebar.orderedPages.count, Set(SettingsSidebar.orderedPages).count)
        XCTAssertFalse(SettingsPage.allCases.map(\.displayTitle).contains("刘海屏"))
        XCTAssertFalse(SettingsPage.allCases.map(\.displayTitle).contains("菜单栏"))
        XCTAssertFalse(SettingsPage.allCases.map(\.displayTitle).contains("Valora"))
        XCTAssertEqual(SettingsPage.nowPlaying.symbol, "play.fill")
        XCTAssertEqual(SettingsLayout.titleContentGap, 13, accuracy: 0.001)
        XCTAssertTrue((12...16).contains(SettingsLayout.titleContentGap))
    }

    func testHoverControlsAreInsideGeneralCardAfterDisplayRow() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: root.appendingPathComponent("Sources/Valora/SettingsView.swift"), encoding: .utf8)
        let display = try XCTUnwrap(text.range(of: "Display on"))
        let hover = try XCTUnwrap(text.range(of: "Expand on hover"))
        XCTAssertLessThan(display.lowerBound, hover.lowerBound)
        XCTAssertFalse(text.contains("heading(\"Behaviour\")"))
        XCTAssertFalse(text.contains("sectionTitle(\"Notifications\")"))
        XCTAssertFalse(text.contains("sectionTitle(\"Live Activities\")"))
        XCTAssertFalse(text.contains("Use live waveform"))
    }



    func testLiveWaveformSourceEntryAndPermissionAreRemoved() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources/Valora/AudioTap.swift").path))
        let sourceText = try ["Sources/Valora", "Sources/ReferenceCore"].flatMap { directory in
            try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent(directory),
                                                        includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "swift" }
                .map { try String(contentsOf: $0, encoding: .utf8) }
        }.joined(separator: "\n")
        for removed in ["LiveAudioTap", "AudioTapVerification", "useLiveWaveform"] {
            XCTAssertFalse(sourceText.contains(removed), "removed live-waveform symbol remains: \(removed)")
        }
        let package = try String(contentsOf: root.appendingPathComponent("Package.swift"), encoding: .utf8)
        XCTAssertFalse(package.contains("Accelerate"), "live-waveform-only Accelerate link remains")
        let packageScript = try String(contentsOf: root.appendingPathComponent("scripts/package.py"), encoding: .utf8)
        XCTAssertFalse(packageScript.contains("NSAudioCaptureUsageDescription"),
                       "system-audio usage declaration remains")
        let runtime = try String(contentsOf: root.appendingPathComponent("Sources/Valora/AppRuntimeDefaults.swift"), encoding: .utf8)
        XCTAssertFalse(runtime.contains("verify-audio-tap"), "audio-tap QA command remains")
    }

    func testExistingSettingsWindowIsReused() {
        let delegate = AppDelegate(arguments: ["Valora", "--preview-settings"])
        delegate.showSettings()
        let title = SettingsPage.general.displayTitle
        let first = NSApp.windows.filter { $0.title == title }
        XCTAssertEqual(first.count, 1)
        delegate.showSettings()
        let second = NSApp.windows.filter { $0.title == title }
        XCTAssertEqual(second.count, 1)
        first.forEach { $0.orderOut(nil) }
    }

    func testDisplayChoiceIconsAreDistinctAndMapped() {
        XCTAssertEqual(SettingsDisplayCatalog.symbol(for: "Main display"), "desktopcomputer")
        XCTAssertEqual(SettingsDisplayCatalog.symbol(for: "All displays"), "display.2")
        XCTAssertEqual(SettingsDisplayCatalog.symbol(for: "Built-in display"), "laptopcomputer")
        XCTAssertEqual(SettingsDisplayCatalog.symbol(for: "U2701B"), "display")
        XCTAssertNotEqual(SettingsDisplayCatalog.symbol(for: "Main display"),
                          SettingsDisplayCatalog.symbol(for: "All displays"))
    }
}
