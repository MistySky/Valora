import AppKit
import XCTest
import ReferenceCore
@testable import Valora

/// Finite checks for the actual transparent-canvas overlap reported in 1.0.4.
/// These exercise coordinator state, not real WindowServer mouse delivery.
@MainActor
final class IndependentHoverExitAcceptanceTests: XCTestCase {
    private func withOffscreenCoordinator(
        _ body: (AppModel, RevivalSettings, WindowCoordinator, () -> Int, (CGPoint) -> Void, CGPoint, CGPoint) -> Void
    ) {
        let suite = "valora.hover-exit-watchdog.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = RevivalSettings(defaults: defaults)
        settings.forceSimulatedNotch = true
        settings.hoverEnabled = false
        let model = AppModel(settings: settings)
        let display = DisplayDescriptor(id: "offscreen", name: "Offscreen fixture",
            frame: CGRect(x: -20000, y: -20000, width: 1920, height: 1080),
            safeAreaTop: 0, auxiliaryLeftWidth: nil, auxiliaryRightWidth: nil, menuBarHeight: 24)
        let inside = CGPoint(x: display.frame.midX, y: display.frame.maxY - 10)
        let outside = CGPoint(x: display.frame.midX - 250, y: display.frame.maxY - 195)
        var point = inside
        var reads = 0
        let coordinator = WindowCoordinator(model, displayProvider: { [display] },
            pointerLocationProvider: { reads += 1; return point })
        coordinator.start(trackPointer: false)
        withExtendedLifetime(model) {
            body(model, settings, coordinator, { reads }, { point = $0 }, inside, outside)
        }
    }

    func testMissedExitIsRecoveredByActualTimerThenNoFurtherPositionReadsOccur() {
        withOffscreenCoordinator { model, _, coordinator, reads, move, inside, outside in
            let frame = coordinator.panel.frame
            XCTAssertFalse(coordinator.verificationHoverExitTrackingActive)
            coordinator.verificationFireHoverExitCheck()
            XCTAssertEqual(reads(), 0, "no fallback work before entering the notch")
            coordinator.verificationTrackMouse(at: inside)
            XCTAssertTrue(coordinator.verificationHoverExitTrackingActive)
            XCTAssertFalse(coordinator.panel.ignoresMouseEvents)
            // No mouseExited event: the real timer callback must release the
            // transparent canvas before a stale pointer owner can persist.
            move(outside)
            coordinator.verificationFireHoverExitCheck()
            XCTAssertEqual(reads(), 1)
            XCTAssertFalse(model.isPointerInside)
            XCTAssertTrue(coordinator.panel.ignoresMouseEvents)
            XCTAssertFalse(coordinator.verificationHoverExitTrackingActive)
            coordinator.verificationFireHoverExitCheck()
            XCTAssertEqual(reads(), 1, "far-away pointer movement has no polling work")
            XCTAssertEqual(coordinator.panel.frame, frame, "the animation canvas must stay unchanged")
        }
    }

    func testDragOwnershipIsKeptUntilInteractionEndsThenFallbackReleasesIt() {
        withOffscreenCoordinator { model, _, coordinator, _, move, inside, outside in
            coordinator.verificationTrackMouse(at: inside)
            model.beginPointerInteraction()
            move(outside)
            coordinator.verificationFireHoverExitCheck()
            XCTAssertTrue(model.isPointerInside)
            XCTAssertFalse(coordinator.panel.ignoresMouseEvents)
            XCTAssertTrue(coordinator.verificationHoverExitTrackingActive)
            model.endPointerInteraction()
            coordinator.verificationFireHoverExitCheck()
            XCTAssertFalse(model.isPointerInside)
            XCTAssertTrue(coordinator.panel.ignoresMouseEvents)
            XCTAssertFalse(coordinator.verificationHoverExitTrackingActive)
        }
    }

    func testHideAndLockCancelFallbackAndReentryArmsItAgain() {
        withOffscreenCoordinator { model, settings, coordinator, reads, _, inside, _ in
            coordinator.verificationTrackMouse(at: inside)
            XCTAssertTrue(coordinator.verificationHoverExitTrackingActive)
            settings.showNotch = false
            coordinator.verificationUpdateVisibility()
            XCTAssertFalse(coordinator.verificationHoverExitTrackingActive)
            coordinator.verificationFireHoverExitCheck()
            XCTAssertEqual(reads(), 0)
            settings.showNotch = true
            coordinator.verificationUpdateVisibility()
            coordinator.verificationTrackMouse(at: inside)
            XCTAssertTrue(coordinator.verificationHoverExitTrackingActive)
            model.isSessionLocked = true
            coordinator.verificationUpdateVisibility()
            XCTAssertFalse(coordinator.verificationHoverExitTrackingActive)
            XCTAssertTrue(coordinator.panel.ignoresMouseEvents)
        }
    }

    func testLeavingContourWhileStillOverCanvasReleasesInputOnExternalDisplay() {
        let suite = "valora.independent.hover-exit.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = RevivalSettings(defaults: defaults)
        settings.forceSimulatedNotch = true
        settings.hoverEnabled = false
        let model = AppModel(settings: settings)
        let display = DisplayDescriptor(id: "external", name: "External display",
            frame: CGRect(x: 1728, y: 37, width: 1920, height: 1080),
            safeAreaTop: 0, auxiliaryLeftWidth: nil, auxiliaryRightWidth: nil,
            menuBarHeight: 24)
        let coordinator = WindowCoordinator(model, displayProvider: { [display] })
        coordinator.start(trackPointer: false)
        let entry = CGPoint(x: display.frame.midX, y: display.frame.maxY - 10)
        // Both locations lie in the same 624x320 render window. Only entry is
        // inside the visible notch; the second corresponds to the settings top.
        let settingsPoint = CGPoint(x: display.frame.midX - 250,
                                    y: display.frame.maxY - 195)
        let canvas = CGRect(x: display.frame.midX - 312, y: display.frame.maxY - 320,
                            width: 624, height: 320)
        XCTAssertTrue(canvas.contains(settingsPoint))
        XCTAssertFalse(coordinator.verificationContains(screenID: display.id, point: settingsPoint))
        XCTAssertFalse(coordinator.verificationHoverExitTrackingActive)
        coordinator.verificationTrackMouse(at: entry)
        XCTAssertTrue(model.isPointerInside)
        XCTAssertEqual(coordinator.verificationIgnoresMouseEvents(screenID: display.id), false)
        XCTAssertTrue(coordinator.verificationHoverExitTrackingActive)
        coordinator.verificationTrackMouse(at: settingsPoint)
        XCTAssertFalse(model.isPointerInside)
        XCTAssertEqual(coordinator.verificationIgnoresMouseEvents(screenID: display.id), true)
        XCTAssertFalse(coordinator.verificationHoverExitTrackingActive)
        coordinator.verificationTrackMouse(at: entry)
        XCTAssertTrue(coordinator.verificationHoverExitTrackingActive)
        coordinator.verificationTrackMouse(at: settingsPoint)
        XCTAssertFalse(coordinator.verificationHoverExitTrackingActive)
        XCTAssertEqual(coordinator.verificationIgnoresMouseEvents(screenID: display.id), true)
    }
}
