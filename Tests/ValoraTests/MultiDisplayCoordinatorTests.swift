import AppKit
import XCTest
@testable import Valora
import ReferenceCore

@MainActor
final class MultiDisplayCoordinatorTests: XCTestCase {
    private var suite = ""
    private var defaults: UserDefaults!
    private var settings: RevivalSettings!
    private var model: AppModel!
    private var coordinator: WindowCoordinator!

    override func setUp() {
        super.setUp()
        suite = "com.wangqing.valora.multidisplay.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defaults.set(["showOnDisplay": "All displays"], forKey: "referenceSettingsUI")
        settings = RevivalSettings(defaults: defaults)
        settings.forceSimulatedNotch = true
        model = AppModel(settings: settings)
        model.title = "Track"
        model.artist = "Artist"
        model.playing = true
        let builtIn = DisplayDescriptor(id: "builtin", name: "Built-in display",
            frame: CGRect(x: 0, y: 0, width: 1728, height: 1117), safeAreaTop: 32,
            auxiliaryLeftWidth: 600, auxiliaryRightWidth: 600, menuBarHeight: 32,
            isBuiltIn: true)
        let external = DisplayDescriptor(id: "external", name: "External display",
            frame: CGRect(x: -1920, y: -200, width: 1920, height: 1080), safeAreaTop: 0,
            auxiliaryLeftWidth: nil, auxiliaryRightWidth: nil, menuBarHeight: 24)
        coordinator = WindowCoordinator(model, displayProvider: { [builtIn, external] })
        coordinator.start(trackPointer: false)
    }

    override func tearDown() {
        coordinator?.cancelPendingHover()
        coordinator?.collapse()
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testAllDisplaysCreatesOneInteractivePanelPerScreen() throws {
        XCTAssertEqual(coordinator.verificationPanelCount, 2)
        let ids = coordinator.verificationScreenIDs
        XCTAssertEqual(ids, ["builtin", "external"])
        XCTAssertEqual(coordinator.verificationSecondaryPanels.count, 1)
        XCTAssertEqual(coordinator.verificationActiveScreenID, ids.first)
    }

    func testActiveScreenSwitchKeepsAtMostOneExpanded() throws {
        let ids = coordinator.verificationScreenIDs
        coordinator.verificationActivateScreen(ids[1])
        XCTAssertEqual(coordinator.verificationActiveScreenID, ids[1])
        coordinator.expand()
        XCTAssertTrue(model.expanded)
        XCTAssertEqual(coordinator.verificationSecondaryPanels.count, ids.count - 1)
        // Switching active collapses the old screen before the new one can expand.
        coordinator.verificationActivateScreen(ids[0])
        XCTAssertEqual(coordinator.verificationActiveScreenID, ids[0])
        XCTAssertFalse(model.expanded)
        XCTAssertEqual(coordinator.verificationSecondaryPanels.count, ids.count - 1)
    }

    func testPassivePanelPointerActivatesAndPeekTargetsIt() async throws {
        let ids = coordinator.verificationScreenIDs
        settings.hoverEnabled = true
        settings.hoverDelay = 0.05
        coordinator.verificationSetPointer(screenID: ids[1], inside: true)
        try? await Task.sleep(nanoseconds: 120_000_000)
        XCTAssertEqual(coordinator.verificationActiveScreenID, ids[1])
        XCTAssertTrue(model.expanded)
        coordinator.collapse()
        coordinator.verificationSetPointer(screenID: ids[1], inside: false)
        coordinator.verificationSetPointer(screenID: ids[1], inside: true)
        model.presenter.cancelPeek(reset: true)
        coordinator.verificationTrackChanged(identity: "first")
        coordinator.verificationTrackChanged(identity: "second")
        XCTAssertEqual(coordinator.verificationActiveScreenID, ids[1])
        XCTAssertTrue(model.songPeek.visible)
    }

    func testExternalPillGetsPeekWhenMultipleDisplaysAreEnabled() async throws {
        let ids = coordinator.verificationScreenIDs
        settings.forceSimulatedNotch = false
        try? await Task.sleep(nanoseconds: 250_000_000)
        coordinator.verificationActivateScreen(ids[1])
        coordinator.verificationSetPointer(screenID: ids[1], inside: true)
        model.presenter.cancelPeek(reset: true)
        coordinator.verificationTrackChanged(identity: "first")
        coordinator.verificationTrackChanged(identity: "second")
        XCTAssertEqual(coordinator.verificationActiveScreenID, ids[1])
        XCTAssertTrue(model.songPeek.visible)
    }

    func testDragOwnershipBlocksScreenSwitch() throws {
        let ids = coordinator.verificationScreenIDs
        coordinator.verificationActivateScreen(ids[0])
        model.beginPointerInteraction()
        coordinator.verificationActivateScreen(ids[1])
        XCTAssertEqual(coordinator.verificationActiveScreenID, ids[0])
        model.endPointerInteraction()
        coordinator.verificationActivateScreen(ids[1])
        XCTAssertEqual(coordinator.verificationActiveScreenID, ids[1])
    }

    func testSelectingMainDisplayConvergesToOnePanel() async throws {
        defaults.set(["showOnDisplay": "Main display"], forKey: "referenceSettingsUI")
        settings.reloadPreferences()
        try? await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertEqual(coordinator.verificationPanelCount, 1)
        XCTAssertEqual(coordinator.verificationSecondaryPanels.count, 0)
        XCTAssertFalse(model.expanded)
    }

    // Independent acceptance regression: changing the display selection during
    // the pause grace period must not strand a pending idle deadline.
    func testPausedIdleDeadlineSurvivesDisplaySelectionChange() async {
        try? await Task.sleep(nanoseconds: 300_000_000)
        model.playing = false
        model.presenter.mediaStateChanged()
        XCTAssertTrue(model.mediaIdle.pending)
        defaults.set(["showOnDisplay": "Main display"], forKey: "referenceSettingsUI")
        settings.reloadPreferences()
        try? await Task.sleep(nanoseconds: 3_600_000_000)
        XCTAssertEqual(coordinator.verificationPanelCount, 1)
        XCTAssertFalse(model.mediaIdle.visible, "Paused activity must expire after its three-second grace period")
        XCTAssertFalse(model.mediaIdle.pending, "No canceled idle deadline may remain pending forever")
    }

    func testSameValueMetadataPollsDoNotPostponePausedIdleDeadline() async {
        try? await Task.sleep(nanoseconds: 300_000_000)
        model.playing = false
        model.presenter.mediaStateChanged()
        XCTAssertTrue(model.mediaIdle.pending)
        for _ in 0..<10 {
            try? await Task.sleep(nanoseconds: 100_000_000)
            model.presenter.mediaStateChanged()
        }
        try? await Task.sleep(nanoseconds: 2_100_000_000)
        XCTAssertFalse(model.mediaIdle.visible, "Identical metadata polls must not move the paused deadline")
        XCTAssertFalse(model.mediaIdle.pending)
    }

    func testPausedIdleDeadlineSurvivesDisableThenEnable() async {
        try? await Task.sleep(nanoseconds: 300_000_000)
        model.playing = false
        model.presenter.mediaStateChanged()
        XCTAssertTrue(model.mediaIdle.pending)
        settings.nowPlayingEnabled = false
        model.presenter.mediaStateChanged()
        XCTAssertFalse(model.mediaIdle.pending)
        settings.nowPlayingEnabled = true
        model.presenter.mediaStateChanged()
        XCTAssertTrue(model.mediaIdle.pending)
        try? await Task.sleep(nanoseconds: 3_500_000_000)
        XCTAssertFalse(model.mediaIdle.visible, "Re-enabling must establish a fresh bounded idle deadline")
        XCTAssertFalse(model.mediaIdle.pending)
    }

    func testPausedIdleDeadlineSurvivesScreenReset() async {
        try? await Task.sleep(nanoseconds: 300_000_000)
        model.playing = false
        model.presenter.mediaStateChanged()
        XCTAssertTrue(model.mediaIdle.pending)
        model.presenter.resetForScreenChange()
        try? await Task.sleep(nanoseconds: 3_500_000_000)
        XCTAssertFalse(model.mediaIdle.visible, "A screen reset must not strand the paused idle deadline")
        XCTAssertFalse(model.mediaIdle.pending)
    }

    func testPausedHoveredActivityExpiresAfterDisplaySelectionClearsPointer() async {
        try? await Task.sleep(nanoseconds: 300_000_000)
        model.playing = false
        model.presenter.pointerEntered(true)
        XCTAssertTrue(model.isPointerInside)
        XCTAssertTrue(model.mediaIdle.visible)
        XCTAssertFalse(model.mediaIdle.pending)
        defaults.set(["showOnDisplay": "Main display"], forKey: "referenceSettingsUI")
        settings.reloadPreferences()
        try? await Task.sleep(nanoseconds: 3_600_000_000)
        XCTAssertFalse(model.isPointerInside)
        XCTAssertFalse(model.mediaIdle.visible, "Clearing the old screen's pointer must establish a paused idle deadline")
    }

    func testPausedHoveredActivityExpiresAfterDirectScreenReset() async {
        try? await Task.sleep(nanoseconds: 300_000_000)
        model.playing = false
        model.presenter.pointerEntered(true)
        XCTAssertTrue(model.mediaIdle.visible)
        XCTAssertFalse(model.mediaIdle.pending)
        model.presenter.resetForScreenChange()
        XCTAssertFalse(model.isPointerInside)
        XCTAssertTrue(model.mediaIdle.pending)
        try? await Task.sleep(nanoseconds: 3_500_000_000)
        XCTAssertFalse(model.mediaIdle.visible, "A direct screen reset must start the hovered paused deadline")
        XCTAssertFalse(model.mediaIdle.pending)
    }


    func testLyricsStayOnTheActiveScreenAfterSwitch() async {
        defaults.set(["showOnDisplay": "All displays", "showLyrics": true],
                     forKey: "referenceSettingsUI")
        settings.reloadPreferences()
        model.title = "晴天"
        model.artist = "周杰伦"
        model.album = "叶惠美"
        model.duration = 269
        model.elapsed = 5
        model.lyrics = LyricsDisplayState(status: .ready,
            timeline: LyricTimeline(lines: [
                LyricLine(start: 5, text: "这是一句需要在紧凑区域里跟随的长歌词", words: [
                    LyricWord(text: "这是一句", start: 5, duration: 1),
                    LyricWord(text: "需要在紧凑区域里跟随的长歌词", start: 6, duration: 1)
                ])
            ]), identity: model.lyrics.identity)
        try? await Task.sleep(nanoseconds: 300_000_000)
        let ids = coordinator.verificationScreenIDs
        XCTAssertTrue(model.showsCompactLyrics)
        XCTAssertEqual(coordinator.verificationActiveScreenID, ids.first)
        coordinator.verificationActivateScreen(ids[1])
        try? await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertEqual(coordinator.verificationActiveScreenID, ids[1])
        XCTAssertTrue(model.showsCompactLyrics)
        XCTAssertEqual(coordinator.verificationSecondaryPanels.count, 1)
    }

    func testOrdinaryDesktopMovementDoesNotMoveTheExpandedPanel() {
        let ids = coordinator.verificationScreenIDs
        coordinator.verificationActivateScreen(ids[1])
        coordinator.expand()
        XCTAssertEqual(coordinator.verificationActiveScreenID, ids[1])
        // Center of the desktop is outside every enabled notch contour.
        coordinator.verificationTrackMouse(at: CGPoint(x: 200, y: 500))
        XCTAssertEqual(coordinator.verificationActiveScreenID, ids[1])
        XCTAssertTrue(model.expanded)
    }

    func testLeavingBeforeHoverDelayCancelsThePendingExpansion() async {
        let ids = coordinator.verificationScreenIDs
        settings.hoverEnabled = true
        settings.hoverDelay = 0.2
        coordinator.verificationSetPointer(screenID: ids[1], inside: true)
        try? await Task.sleep(nanoseconds: 50_000_000)
        coordinator.verificationSetPointer(screenID: ids[1], inside: false)
        try? await Task.sleep(nanoseconds: 350_000_000)
        XCTAssertFalse(model.expanded)
    }

    func testInjectedNegativeFramePanelAcceptsOnlyItsOwnContour() {
        let ids = coordinator.verificationScreenIDs
        coordinator.verificationActivateScreen(ids[1])
        let external = DisplayDescriptor(id: "external", name: "External display",
            frame: CGRect(x: -1920, y: -200, width: 1920, height: 1080), safeAreaTop: 0,
            auxiliaryLeftWidth: nil, auxiliaryRightWidth: nil, menuBarHeight: 24)
        let frame = CGRect(x: external.frame.midX-312, y: external.frame.maxY-320, width: 624, height: 320)
        XCTAssertTrue(coordinator.verificationContains(screenID: ids[1],
            point: CGPoint(x: frame.midX, y: frame.maxY - 10)))
        XCTAssertFalse(coordinator.verificationContains(screenID: ids[1],
            point: CGPoint(x: frame.midX + 500, y: frame.maxY - 10)))
        XCTAssertFalse(coordinator.verificationContains(screenID: ids[1],
            point: CGPoint(x: frame.midX, y: frame.minY + 10)))
    }

    func testNegativeScreenFrameHitTestingUsesPerScreenGeometry() {
        let geometry = NotchGeometry.calculate(screenWidth: 1920, safeAreaTop: 0,
                                               auxiliaryLeftWidth: nil, auxiliaryRightWidth: nil,
                                               menuBarHeight: 24, simulated: true)
        let size = CGSize(width: 140, height: 23)
        let contour = NotchContour.stationary(geometry: geometry, simulated: true,
                                              expanded: false, expandedCorners: false,
                                              active: true, visibleHeight: size.height)
        let frame = CGRect(x: -1920, y: -200, width: 624, height: 320)
        XCTAssertTrue(WindowCoordinator.containsMouse(
            point: CGPoint(x: frame.midX, y: frame.maxY - 10),
            panelFrame: frame, size: size, contour: contour, scale: CGSize(width: 1, height: 1)))
        XCTAssertFalse(WindowCoordinator.containsMouse(
            point: CGPoint(x: frame.midX + 200, y: frame.maxY - 10),
            panelFrame: frame, size: size, contour: contour, scale: CGSize(width: 1, height: 1)))
    }
}
