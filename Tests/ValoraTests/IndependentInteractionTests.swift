import AppKit
import XCTest
import ReferenceCore
@testable import Valora

private actor InteractionLyrics: LyricsProviding {
    private(set) var requests: [String] = []
    func lyrics(for request: LyricsRequest) async throws -> LyricsFetchResult {
        requests.append(request.title)
        return .timed(LyricTimeline(lines: [LyricLine(start: 0, text: request.title + " 歌词")]))
    }
}

@MainActor
final class IndependentInteractionTests: XCTestCase {
    private var suite = ""
    private var defaults: UserDefaults!
    private var settings: RevivalSettings!
    private var model: AppModel!
    private var devices: ConnectivityController!
    private var lyrics: LyricsController!
    private var coordinator: WindowCoordinator!
    private var provider: InteractionLyrics!
    private var sound: ConnectivitySoundSpy!

    override func setUp() {
        super.setUp()
        suite = "com.wangqing.valora.interaction.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.set(["showLyrics": true, "showOnDisplay": "All displays"], forKey: "referenceSettingsUI")
        settings = RevivalSettings(defaults: defaults)
        settings.bluetoothEnabled = true
        settings.nowPlayingEnabled = true
        settings.showNotch = true
        settings.forceSimulatedNotch = true
        settings.autoCollapse = false
        model = AppModel(settings: settings)
        model.title = "First"
        model.artist = "QA"
        model.duration = 180
        model.playing = true
        model.elapsed = 1
        provider = InteractionLyrics()
        lyrics = LyricsController(model: model, provider: provider)
        sound = ConnectivitySoundSpy()
        devices = ConnectivityController(model, source: EmptyConnectivitySource(), sound: sound)
        let a = DisplayDescriptor(id: "a", name: "A", frame: CGRect(x: 0, y: 0, width: 1440, height: 900), safeAreaTop: 0,
            auxiliaryLeftWidth: nil, auxiliaryRightWidth: nil, menuBarHeight: 24)
        let b = DisplayDescriptor(id: "b", name: "B", frame: CGRect(x: 1440, y: 0, width: 1440, height: 900), safeAreaTop: 0,
            auxiliaryLeftWidth: nil, auxiliaryRightWidth: nil, menuBarHeight: 24)
        coordinator = WindowCoordinator(model, displayProvider: { [a, b] })
        coordinator.start(trackPointer: false)
        devices.start(polling: false)
        lyrics.start()
        devices.verificationApply(snapshot([]))
    }

    override func tearDown() {
        lyrics.cancel()
        devices.stop()
        coordinator.cancelPendingHover()
        coordinator.collapse()
        coordinator.panel.orderOut(nil)
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    private func snapshot(_ items: [AudioDevice]) -> ConnectedAudioSnapshot {
        ConnectedAudioSnapshot(devices: items, output: "fake")
    }
    private func device(_ id: String, battery: Int = 80) -> AudioDevice {
        AudioDevice(id: id, name: "QA AirPods", left: battery, right: battery, single: nil,
                    active: true, isAirPods: true, modelUID: "2014 4c")
    }
    private func settle() async { try? await Task.sleep(nanoseconds: 180_000_000) }

    func testArrivalTrackChangeExpandedVolumeThenDisableRestoresLatestLyrics() async {
        await settle()
        XCTAssertTrue(model.showsCompactLyrics)
        devices.verificationApply(snapshot([device("new")]))
        XCTAssertFalse(model.showsCompactLyrics)
        model.title = "Second"
        await settle()
        XCTAssertEqual(model.currentLyricLine?.text, "Second 歌词")
        XCTAssertNotNil(model.connectionToast)
        XCTAssertFalse(model.showsCompactLyrics)
        coordinator.expand()
        model.showsOutputVolume = true
        await settle()
        XCTAssertTrue(model.expanded)
        XCTAssertTrue(model.showsLyricsInExpanded)
        XCTAssertTrue(model.showsOutputVolume)
        settings.bluetoothEnabled = false
        await settle()
        XCTAssertNil(model.connectionToast)
        XCTAssertTrue(model.expanded, "device off must not collapse the music controls")
        XCTAssertTrue(model.showsOutputVolume, "device off must not reset the volume presentation")
        XCTAssertEqual(model.currentLyricLine?.text, "Second 歌词")
        model.showsOutputVolume = false
        coordinator.collapse()
        await settle()
        XCTAssertTrue(model.showsCompactLyrics)
        let requests = await provider.requests
        XCTAssertEqual(requests, ["First", "Second"], "notification/expand/volume must not refetch unchanged lyrics")
    }

    func testDeviceToastSwitchScreenAndMusicDisableRemainIndependent() async {
        await settle()
        devices.verificationApply(snapshot([device("new")]))
        coordinator.verificationActivateScreen("b")
        coordinator.expand()
        await settle()
        XCTAssertEqual(coordinator.verificationActiveScreenID, "b")
        XCTAssertEqual(coordinator.verificationSecondaryPanels.count, 1)
        XCTAssertNotNil(model.connectionToast)
        coordinator.verificationActivateScreen("a")
        await settle()
        XCTAssertFalse(model.expanded)
        XCTAssertNotNil(model.connectionToast, "changing interaction owner must not discard the prompt")
        settings.nowPlayingEnabled = false
        await settle()
        XCTAssertFalse(model.showsCompactLyrics)
        XCTAssertFalse(model.showsLyricsInExpanded)
        XCTAssertNotNil(model.connectionToast, "music switch must not disable the independent device module")
        settings.bluetoothEnabled = false
        await settle()
        XCTAssertNil(model.connectionToast)
        XCTAssertFalse(model.hasActiveNotification)
        XCTAssertFalse(model.showsCompactLyrics)
        settings.nowPlayingEnabled = true
        await settle()
        XCTAssertTrue(model.showsCompactLyrics)
        XCTAssertEqual(coordinator.verificationActiveScreenID, "a")
    }

    func testPauseAndLowBatteryPromptExpiryCannotRestoreExpiredMusic() async {
        await settle()
        devices.verificationApply(snapshot([device("existing")]))
        devices.verificationApply(snapshot([device("existing", battery: 20)]))
        XCTAssertTrue(model.connectionLowBattery)
        XCTAssertEqual(sound.plays, 1)
        model.playing = false
        model.presenter.mediaStateChanged()
        try? await Task.sleep(nanoseconds: 5_400_000_000)
        XCTAssertNil(model.connectionToast)
        XCTAssertFalse(model.mediaIdle.visible)
        XCTAssertFalse(model.showsCompactLyrics, "toast expiry must not revive music after the pause idle deadline")
        XCTAssertFalse(model.showsLyricsInExpanded)
        model.playing = true
        model.presenter.mediaStateChanged()
        await settle()
        XCTAssertTrue(model.showsCompactLyrics)
        XCTAssertEqual(sound.plays, 1, "resuming music must not replay the device alert")
    }
}
