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
                        "Expand on hover", "Hover delay", "Now Playing", "Use live waveform", "Show lyrics"] {
            XCTAssertTrue(settingsView.contains(keptRow), "retained setting row missing: \(keptRow)")
        }
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
