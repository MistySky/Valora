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

    func testRepeatedOutsideMovesAssignOnlyWhenStateDiffers() {
        let ids = coordinator.verificationScreenIDs
        // Panels start click-through; accepting events is entered only by the
        // pointer crossing the actual notch contour.
        XCTAssertEqual(coordinator.verificationIgnoresMouseEvents(screenID: ids[0]), true)
        XCTAssertEqual(coordinator.verificationIgnoresMouseEvents(screenID: ids[1]), true)
        #if VALORA_DEVELOPMENT
        PointerStateDiagnostics.reset()
        #endif
        coordinator.verificationTrackMouse(at: outsidePoint)
        #if VALORA_DEVELOPMENT
        XCTAssertEqual(PointerStateDiagnostics.assignments, 0,
                       "an already click-through panel must not receive a setter call")
        #endif
        // Repeating the identical event changes nothing in either window.
        coordinator.verificationTrackMouse(at: outsidePoint)
        coordinator.verificationTrackMouse(at: outsidePoint)
        #if VALORA_DEVELOPMENT
        XCTAssertEqual(PointerStateDiagnostics.assignments, 0,
                       "identical repeats must not reach the setter")
        #endif
        // Another path may modify the property; the next event corrects it once.
        coordinator.verificationSetIgnoresMouseEvents(screenID: ids[0], false)
        coordinator.verificationTrackMouse(at: outsidePoint)
        #if VALORA_DEVELOPMENT
        XCTAssertEqual(PointerStateDiagnostics.assignments, 1,
                       "only the drifted screen may be corrected")
        #endif
        XCTAssertEqual(coordinator.verificationIgnoresMouseEvents(screenID: ids[0]), true)
        XCTAssertEqual(coordinator.verificationIgnoresMouseEvents(screenID: ids[1]), true)
    }

    func testEnterAndLeaveAssignTheCorrectTargetExactlyOnce() {
        let ids = coordinator.verificationScreenIDs
        XCTAssertTrue(coordinator.verificationContains(screenID: ids[0],
                                                       point: builtInInsidePoint),
                      "fixture: the built-in top-center point must hit the notch")
        coordinator.verificationSetIgnoresMouseEvents(screenID: ids[0], true)
        coordinator.verificationSetIgnoresMouseEvents(screenID: ids[1], true)
        #if VALORA_DEVELOPMENT
        PointerStateDiagnostics.reset()
        #endif
        // Entering the built-in notch: its window accepts events immediately,
        // the other screen's windows stop receiving them.
        coordinator.verificationTrackMouse(at: builtInInsidePoint)
        XCTAssertEqual(coordinator.verificationIgnoresMouseEvents(screenID: ids[0]), false)
        XCTAssertEqual(coordinator.verificationIgnoresMouseEvents(screenID: ids[1]), true)
        XCTAssertTrue(model.isPointerInside)
        #if VALORA_DEVELOPMENT
        XCTAssertEqual(PointerStateDiagnostics.assignments, 1)
        #endif
        // Staying inside: both targets already match, nothing is re-assigned.
        coordinator.verificationTrackMouse(at: builtInInsidePoint)
        XCTAssertEqual(coordinator.verificationIgnoresMouseEvents(screenID: ids[0]), false)
        XCTAssertEqual(coordinator.verificationIgnoresMouseEvents(screenID: ids[1]), true)
        XCTAssertTrue(model.isPointerInside)
        #if VALORA_DEVELOPMENT
        XCTAssertEqual(PointerStateDiagnostics.assignments, 1)
        #endif
        // Leaving: only the built-in window flips back to ignoring events.
        coordinator.verificationTrackMouse(at: outsidePoint)
        XCTAssertEqual(coordinator.verificationIgnoresMouseEvents(screenID: ids[0]), true)
        XCTAssertEqual(coordinator.verificationIgnoresMouseEvents(screenID: ids[1]), true)
        XCTAssertFalse(model.isPointerInside)
        #if VALORA_DEVELOPMENT
        XCTAssertEqual(PointerStateDiagnostics.assignments, 2)
        #endif
    }

    func testScreensTrackTheirStateIndependently() {
        let ids = coordinator.verificationScreenIDs
        // First event flips both panels to the outside target.
        coordinator.verificationTrackMouse(at: outsidePoint)
        XCTAssertEqual(coordinator.verificationIgnoresMouseEvents(screenID: ids[0]), true)
        XCTAssertEqual(coordinator.verificationIgnoresMouseEvents(screenID: ids[1]), true)
        // Only the external screen is externally drifted; the same event must
        // correct exactly that screen and leave the untouched one alone.
        coordinator.verificationSetIgnoresMouseEvents(screenID: ids[1], false)
        #if VALORA_DEVELOPMENT
        PointerStateDiagnostics.reset()
        #endif
        coordinator.verificationTrackMouse(at: outsidePoint)
        #if VALORA_DEVELOPMENT
        XCTAssertEqual(PointerStateDiagnostics.assignments, 1,
                       "one event must correct only the drifted screen")
        #endif
        XCTAssertEqual(coordinator.verificationIgnoresMouseEvents(screenID: ids[0]), true)
        XCTAssertEqual(coordinator.verificationIgnoresMouseEvents(screenID: ids[1]), true)
        // Mirror: drift the built-in screen instead.
        coordinator.verificationSetIgnoresMouseEvents(screenID: ids[0], false)
        #if VALORA_DEVELOPMENT
        PointerStateDiagnostics.reset()
        #endif
        coordinator.verificationTrackMouse(at: outsidePoint)
        #if VALORA_DEVELOPMENT
        XCTAssertEqual(PointerStateDiagnostics.assignments, 1)
        #endif
        XCTAssertEqual(coordinator.verificationIgnoresMouseEvents(screenID: ids[0]), true)
        XCTAssertEqual(coordinator.verificationIgnoresMouseEvents(screenID: ids[1]), true)
    }

    func testPointerInteractionStopsTrackingWithoutAssignments() {
        let ids = coordinator.verificationScreenIDs
        // First event puts both panels into the outside state.
        coordinator.verificationTrackMouse(at: outsidePoint)
        XCTAssertEqual(coordinator.verificationIgnoresMouseEvents(screenID: ids[0]), true)
        model.beginPointerInteraction()
        // A drift exists while the interaction guard is active: nothing may
        // touch the real property until tracking resumes.
        coordinator.verificationSetIgnoresMouseEvents(screenID: ids[0], false)
        #if VALORA_DEVELOPMENT
        PointerStateDiagnostics.reset()
        #endif
        coordinator.verificationTrackMouse(at: outsidePoint)
        XCTAssertEqual(coordinator.verificationIgnoresMouseEvents(screenID: ids[0]), false,
                       "the interaction window must keep receiving events unchanged")
        #if VALORA_DEVELOPMENT
        XCTAssertEqual(PointerStateDiagnostics.assignments, 0)
        #endif
        // The very first event after the interaction ends corrects the drift.
        model.endPointerInteraction()
        coordinator.verificationTrackMouse(at: outsidePoint)
        #if VALORA_DEVELOPMENT
        XCTAssertEqual(PointerStateDiagnostics.assignments, 1)
        #endif
        XCTAssertEqual(coordinator.verificationIgnoresMouseEvents(screenID: ids[0]), true)
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

    func testRepeatedOutsideMovesUseCachedWindowState() {
        let ids = coordinator.verificationScreenIDs
        PointerStateDiagnostics.reset()
        coordinator.verificationTrackMouse(at: outsidePoint)
        XCTAssertEqual(PointerStateDiagnostics.assignments, 0,
                       "panels already ignore events while outside")
        coordinator.verificationTrackMouse(at: outsidePoint)
        coordinator.verificationTrackMouse(at: outsidePoint)
        XCTAssertEqual(PointerStateDiagnostics.assignments, 0,
                       "repeated outside events must not touch the window setters")
        coordinator.verificationSetIgnoresMouseEvents(screenID: ids[0], false)
        coordinator.verificationTrackMouse(at: outsidePoint)
        XCTAssertEqual(PointerStateDiagnostics.assignments, 1,
                       "an explicit external write must be reconciled once")
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
