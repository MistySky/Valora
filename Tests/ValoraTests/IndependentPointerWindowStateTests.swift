import AppKit
import XCTest
@testable import Valora
import ReferenceCore

/// Independent regressions for the per-event window mouse-receive-state dedup:
/// repeated mouse moves must not re-issue `NSWindow.ignoresMouseEvents`
/// assignments when the window's live property already matches, every state
/// change must still reach the setter exactly once, and external/visibility
/// modifications must be corrected by the next event. Counters are only
/// incremented at the real assignment site — never inside the assertions.
/// A few driven calls per test; no stress loops, no flashing windows.
@MainActor
final class IndependentPointerWindowStateTests: XCTestCase {
    private var suite = ""
    private var defaults: UserDefaults!
    private var settings: RevivalSettings!
    private var model: AppModel!
    private var coordinator: WindowCoordinator!

    override func setUp() {
        super.setUp()
        suite = "com.wangqing.valora.pointer-state.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defaults.set(["showOnDisplay": "All displays"], forKey: "referenceSettingsUI")
        settings = RevivalSettings(defaults: defaults)
        settings.forceSimulatedNotch = true
        settings.hoverEnabled = false
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
        coordinator = nil
        super.tearDown()
    }

    private var outsidePoint: CGPoint { CGPoint(x: 200, y: 500) }
    private var builtInInsidePoint: CGPoint {
        CGPoint(x: 1728 / 2, y: 1117 - 10)   // top-center of the built-in notch
    }

    // The idempotent helper reads the real NSPanel property; an injected
    // counting subclass proves the actual setter is skipped on no-change.
    private final class CountingIgnoresEventsPanel: NSPanel {
        var setterCalls = 0
        override var ignoresMouseEvents: Bool { didSet { setterCalls += 1 } }
    }

    private func makeIsolatedPanel() -> CountingIgnoresEventsPanel {
        let panel = CountingIgnoresEventsPanel(
            contentRect: NSRect(x: -20000, y: -20000, width: 100, height: 40),
            styleMask: .borderless, backing: .buffered, defer: false)
        panel.setFrameOrigin(NSPoint(x: -20000, y: -20000))
        return panel
    }

    func testHelperSkipsTheSetterWhenTheLivePropertyAlreadyMatches() {
        let panel = makeIsolatedPanel()
        panel.ignoresMouseEvents = true
        XCTAssertEqual(panel.setterCalls, 1)
        // Same target: the live property is read and the setter is not touched.
        XCTAssertFalse(WindowCoordinator.setIgnoresMouseEvents(of: panel, true))
        XCTAssertEqual(panel.setterCalls, 1, "an unchanged value must not re-issue the setter")
        XCTAssertEqual(panel.ignoresMouseEvents, true)
        // A real change reaches the setter exactly once.
        XCTAssertTrue(WindowCoordinator.setIgnoresMouseEvents(of: panel, false))
        XCTAssertEqual(panel.setterCalls, 2)
        XCTAssertEqual(panel.ignoresMouseEvents, false)
        // Another path changes the property again; the next dedup call reads
        // the live value and skips — no cache, no drift.
        panel.ignoresMouseEvents = true
        XCTAssertEqual(panel.setterCalls, 3)
        XCTAssertFalse(WindowCoordinator.setIgnoresMouseEvents(of: panel, true))
        XCTAssertEqual(panel.setterCalls, 3)
        XCTAssertEqual(panel.ignoresMouseEvents, true)
    }

    func testSessionLockedBranchAssignsIgnoresOncePerScreen() {
        let ids = coordinator.verificationScreenIDs
        model.isSessionLocked = true
        // Panel 0 is drifted before the lock branch runs; panel 1 already
        // carries the locked target.
        coordinator.verificationSetIgnoresMouseEvents(screenID: ids[0], false)
        #if VALORA_DEVELOPMENT
        PointerStateDiagnostics.reset()
        #endif
        coordinator.verificationTrackMouse(at: builtInInsidePoint)
        XCTAssertEqual(coordinator.verificationIgnoresMouseEvents(screenID: ids[0]), true,
                       "a locked session must set every panel to ignore mouse events")
        XCTAssertEqual(coordinator.verificationIgnoresMouseEvents(screenID: ids[1]), true)
        XCTAssertFalse(model.isPointerInside)
        #if VALORA_DEVELOPMENT
        XCTAssertEqual(PointerStateDiagnostics.assignments, 1,
                       "only the not-yet-locked panel may receive the assignment")
        #endif
    }

    func testFarPointerSkipsModelGeometryAndPathConstruction() {
        let ids = coordinator.verificationScreenIDs
        NotchHitTestDiagnostics.reset()
        coordinator.verificationTrackMouse(at: outsidePoint)
        XCTAssertGreaterThan(NotchHitTestDiagnostics.coarseExclusions, 0,
                             "far pointer must be excluded in screen space before model geometry")
        XCTAssertEqual(NotchHitTestDiagnostics.pathConstructions, 0,
                       "far pointer must not construct a notch path")
        XCTAssertEqual(coordinator.verificationIgnoresMouseEvents(screenID: ids[0]), true)
        XCTAssertEqual(coordinator.verificationIgnoresMouseEvents(screenID: ids[1]), true)
    }

    func testExactPathIsCachedForRepeatedInsideQueries() {
        let id = coordinator.verificationScreenIDs[0]
        NotchHitTestDiagnostics.reset()
        XCTAssertTrue(coordinator.verificationContains(screenID: id, point: builtInInsidePoint))
        XCTAssertTrue(coordinator.verificationContains(screenID: id, point: builtInInsidePoint))
        XCTAssertEqual(NotchHitTestDiagnostics.pathConstructions, 1,
                       "the second query must reuse the exact path for unchanged geometry")
    }

    func testHiddenVisibilityBranchKeepsItsDirectAssignment() {
        let ids = coordinator.verificationScreenIDs
        #if VALORA_DEVELOPMENT
        PointerStateDiagnostics.reset()
        #endif
        settings.showNotch = false
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        // The hidden path keeps its own direct assignment semantics (not routed
        // through the per-event helper, therefore not counted).
        XCTAssertEqual(coordinator.verificationIgnoresMouseEvents(screenID: ids[0]), true)
        XCTAssertEqual(coordinator.verificationIgnoresMouseEvents(screenID: ids[1]), true)
        #if VALORA_DEVELOPMENT
        XCTAssertEqual(PointerStateDiagnostics.assignments, 0)
        #endif
    }
}
