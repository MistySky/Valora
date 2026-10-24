import SwiftUI
import XCTest
@testable import Valora
import ReferenceCore

@MainActor
final class RevivalSettingsReloadTests: XCTestCase {
    private let suite = "com.wangqing.valora.review-batch-tests"
    private var defaults: UserDefaults { UserDefaults(suiteName: suite)! }

    override func setUp() {
        super.setUp()
        defaults.removePersistentDomain(forName: suite)
    }
    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testFixedPoliciesIgnoreLegacyValuesAndKeepRetainedDefaults() {
        defaults.set(0.25, forKey: "hoverDelay") // legacy top-level key, now ignored
        defaults.set([
            "hideWhileInFullscreen": false,
            "hideWhileInMissionControl": false,
            "hideWhileGaming": true,
            "hideFromScreenCapture": true,
            "idleActivity": "none",
            "mostRecentActivity": true,
            "contrastOutline": false,
            "progressiveBlur": false,
            "notchWidthOffset": 14.0,
            "notchHeightOffset": -3.0,
            "disableWaveform": true,
            "disableAlbumArtFlip": true,
            "hideWhileSourceIsActive": true,
            "hideSongTitleExtras": true,
            "idleDuration": 9.0,
            "enableQuickPeek": false,
            "whenSongChanges": false,
            "peekDuration": 5.0,
            "useLiveWaveform": true,
            "progressStyle": "Gradient"
        ], forKey: "referenceSettingsUI")

        let settings = RevivalSettings(defaults: defaults)
        XCTAssertTrue(settings.hideWhileInFullscreen)
        XCTAssertTrue(settings.hideWhileInMissionControl)
        XCTAssertFalse(settings.hideWhileGaming)
        XCTAssertFalse(settings.hideFromScreenCapture)
        XCTAssertEqual(settings.hoverDelay, 0, accuracy: 0.0001)

        XCTAssertEqual(settings.musicPreferences.idleDuration, 3)
        XCTAssertFalse(settings.musicPreferences.disableWaveform)
        XCTAssertFalse(settings.musicPreferences.disableArtworkFlip)
        XCTAssertFalse(settings.musicPreferences.hideWhileSourceIsActive)
        XCTAssertFalse(settings.musicPreferences.hideSongTitleExtras)
        XCTAssertTrue(settings.musicPreferences.quickPeekEnabled)
        XCTAssertTrue(settings.musicPreferences.whenSongChanges)
        XCTAssertEqual(settings.musicPreferences.peekDuration, 2)
        // Retained visible setting still reads its stored value.
        XCTAssertEqual(settings.musicPreferences.progressStyle, .gradient)
        XCTAssertTrue(settings.musicPreferences.useLiveWaveform)

        // Old notch offsets are ignored by geometry consumers.
        let model = AppModel(settings: settings)
        model.notchGeometry = .calculate(screenWidth: 1728, safeAreaTop: 32,
                                         auxiliaryLeftWidth: 771.5, auxiliaryRightWidth: 771.5,
                                         menuBarHeight: 32, simulated: false)
        XCTAssertEqual(model.visibleSize, CGSize(width: 185, height: 32))

        // Fixed default activity is the available music activity.
        model.title = "Track"
        XCTAssertEqual(model.requestedExpansionActivity, .nowPlaying)
        XCTAssertTrue(model.canExpandActivity)
    }

    func testHoverDelayIsRetainedAndClamped() {
        let settings = RevivalSettings(defaults: defaults)
        let draft = SettingsDraft(defaults: defaults)
        XCTAssertEqual(settings.hoverDelay, 0, accuracy: 0.0001)
        draft.binding("hoverDelay", 0.0).wrappedValue = 0.35
        settings.reloadPreferences()
        XCTAssertEqual(settings.hoverDelay, 0.35, accuracy: 0.0001)
        draft.binding("hoverDelay", 0.0).wrappedValue = 4.0
        settings.reloadPreferences()
        XCTAssertEqual(settings.hoverDelay, 1.0, accuracy: 0.0001)
    }

    func testConnectivityPolicyIsFixedAndSwitchDefaultsOff() {
        defaults.set([
            "connectivityModel": "Symbols",
            "connectivityDuration": 1.0,
            "warnOnLowConnectBattery": false,
            "lowConnectBatteryThreshold": 30,
            "playSoundOnLowConnectBattery": false
        ], forKey: "referenceSettingsUI")
        let settings = RevivalSettings(defaults: defaults)
        XCTAssertFalse(settings.bluetoothEnabled)
        XCTAssertTrue(settings.connectivityPreferences.uses3DModels, "legacy appearance selection must be ignored")
        XCTAssertEqual(settings.connectivityPreferences.duration, 5)
        XCTAssertEqual(settings.connectivityPreferences.lowBatteryThreshold, 20)
        XCTAssertTrue(settings.connectivityPreferences.warnOnLowBattery)
        XCTAssertTrue(settings.connectivityPreferences.playSoundOnLowBattery)

        settings.bluetoothEnabled = true
        XCTAssertTrue(RevivalSettings(defaults: defaults).bluetoothEnabled)
        settings.reloadPreferences()
        XCTAssertTrue(settings.connectivityPreferences.uses3DModels)
    }

    func testShowLyricsDefaultsOffAndPersists() {
        let settings = RevivalSettings(defaults: defaults)
        XCTAssertFalse(settings.musicPreferences.showLyrics)
        let draft = SettingsDraft(defaults: defaults)
        draft.binding("showLyrics", false).wrappedValue = true
        settings.reloadPreferences()
        XCTAssertTrue(settings.musicPreferences.showLyrics)
        XCTAssertTrue(RevivalSettings(defaults: defaults).musicPreferences.showLyrics)
    }

    func testNowPlayingToggleRemainsUserControlled() {
        defaults.set(false, forKey: "enableNowPlaying")
        let settings = RevivalSettings(defaults: defaults)
        XCTAssertFalse(settings.nowPlayingEnabled)
        settings.nowPlayingEnabled = true
        XCTAssertTrue(RevivalSettings(defaults: defaults).nowPlayingEnabled)
    }
}
