import AppKit
import XCTest
import ReferenceCore
@testable import Valora

/// Finite checks for the actual transparent-canvas overlap reported in 1.0.4.
/// These exercise coordinator state, not real WindowServer mouse delivery.
@MainActor
final class IndependentHoverExitAcceptanceTests: XCTestCase {
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
        XCTAssertFalse(coordinator.verificationHoverExitMonitorsInstalled)
        coordinator.verificationTrackMouse(at: entry)
        XCTAssertTrue(model.isPointerInside)
        XCTAssertEqual(coordinator.verificationIgnoresMouseEvents(screenID: display.id), false)
        XCTAssertTrue(coordinator.verificationHoverExitMonitorsInstalled)
        coordinator.verificationTrackMouse(at: settingsPoint)
        XCTAssertFalse(model.isPointerInside)
        XCTAssertEqual(coordinator.verificationIgnoresMouseEvents(screenID: display.id), true)
        XCTAssertFalse(coordinator.verificationHoverExitMonitorsInstalled)
        coordinator.verificationTrackMouse(at: entry)
        XCTAssertTrue(coordinator.verificationHoverExitMonitorsInstalled)
        coordinator.verificationTrackMouse(at: settingsPoint)
        XCTAssertFalse(coordinator.verificationHoverExitMonitorsInstalled)
        XCTAssertEqual(coordinator.verificationIgnoresMouseEvents(screenID: display.id), true)
    }
}
