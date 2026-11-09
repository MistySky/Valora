import AppKit
import SwiftUI
import XCTest
import ReferenceCore
@testable import Valora

/// The conservative hover prefilter must never change the exact result; it may
/// only skip `NotchShape.path(in:)` for points strictly outside a superset of
/// the shape. These tests compare against the original path decision directly.
@MainActor
final class NotchHitTestPrefilterTests: XCTestCase {
    private struct Probe {
        let name: String
        let size: CGSize
        let contour: NotchContour
    }

    private func contours() -> [Probe] {
        let physical = NotchGeometry.calculate(screenWidth: 312, safeAreaTop: 32,
                                               auxiliaryLeftWidth: 90, auxiliaryRightWidth: 90,
                                               menuBarHeight: 24, simulated: false)
        let simulated = NotchGeometry.calculate(screenWidth: 1512, safeAreaTop: 0,
                                                auxiliaryLeftWidth: nil, auxiliaryRightWidth: nil,
                                                menuBarHeight: 24, simulated: true)
        func notch(_ geometry: NotchGeometry, simulated: Bool, active: Bool,
                   expanded: Bool, expandedCorners: Bool, height: CGFloat) -> NotchContour {
            NotchContour.stationary(geometry: geometry, simulated: simulated,
                                    expanded: expanded, expandedCorners: expandedCorners,
                                    active: active, visibleHeight: height)
        }
        let pillIdle = NotchContour.stationary(geometry: simulated, simulated: false,
                                               expanded: false, expandedCorners: false,
                                               active: false, visibleHeight: 19.5)
        let pillTall = NotchContour.stationary(geometry: simulated, simulated: false,
                                               expanded: false, expandedCorners: false,
                                               active: false, visibleHeight: 31)
        let pillExpanded = NotchContour.stationary(geometry: simulated, simulated: false,
                                                   expanded: true, expandedCorners: false,
                                                   active: false, visibleHeight: 19.5)
        return [
            Probe(name: "physical-idle-32", size: CGSize(width: 132, height: 32),
                  contour: notch(physical, simulated: false, active: false,
                                 expanded: false, expandedCorners: false, height: 32)),
            Probe(name: "physical-active-32", size: CGSize(width: 132, height: 32),
                  contour: notch(physical, simulated: false, active: true,
                                 expanded: false, expandedCorners: false, height: 32)),
            Probe(name: "physical-active-18", size: CGSize(width: 132, height: 18),
                  contour: notch(physical, simulated: false, active: true,
                                 expanded: false, expandedCorners: false, height: 18)),
            Probe(name: "physical-expanded", size: CGSize(width: 312, height: 40),
                  contour: notch(physical, simulated: false, active: true,
                                 expanded: true, expandedCorners: true, height: 40)),
            Probe(name: "simulated-active-23", size: CGSize(width: 140, height: 23),
                  contour: notch(simulated, simulated: true, active: true,
                                 expanded: false, expandedCorners: false, height: 23)),
            Probe(name: "simulated-narrow-17", size: CGSize(width: 60, height: 17),
                  contour: notch(simulated, simulated: true, active: false,
                                 expanded: false, expandedCorners: false, height: 17)),
            Probe(name: "simulated-tall-90", size: CGSize(width: 100, height: 90),
                  contour: notch(simulated, simulated: true, active: true,
                                 expanded: false, expandedCorners: false, height: 90)),
            Probe(name: "pill-idle", size: CGSize(width: 140, height: 19.5), contour: pillIdle),
            Probe(name: "pill-tall", size: CGSize(width: 140, height: 31), contour: pillTall),
            Probe(name: "pill-expanded", size: CGSize(width: 345, height: 175), contour: pillExpanded)
        ]
    }

    /// Mirrors NotchShape's own radius clamp without building the path.
    private func shoulders(_ size: CGSize, _ contour: NotchContour) -> (b: CGFloat, t: CGFloat) {
        let b = max(0, min(contour.bottomRadius, min(size.width / 2, size.height)))
        let t = max(0, min(contour.topRadius, min(24, size.height - b)))
        return (b, t)
    }

    private func probePoints(_ size: CGSize, _ contour: NotchContour) -> [CGPoint] {
        let w = size.width, h = size.height
        let t = shoulders(size, contour).t
        let ext = 2 * t
        let low = max(h, ext)
        return [
            CGPoint(x: w / 2, y: h / 2),
            CGPoint(x: w / 2, y: h * 0.15),
            CGPoint(x: w / 2, y: h * 0.85),
            CGPoint(x: 0.5, y: h / 2),
            CGPoint(x: w - 0.5, y: h / 2),
            CGPoint(x: 0, y: 0), CGPoint(x: w, y: 0),
            CGPoint(x: 0, y: h), CGPoint(x: w, y: h),
            CGPoint(x: w / 2, y: -0.5), CGPoint(x: w / 2, y: h + 0.5),
            CGPoint(x: -0.5, y: h / 2), CGPoint(x: w + 0.5, y: h / 2),
            // Exact conservative bounds: must still use the original path.
            CGPoint(x: -ext, y: ext / 2), CGPoint(x: -ext, y: ext),
            CGPoint(x: w + ext, y: ext / 2), CGPoint(x: w + ext, y: ext),
            CGPoint(x: w / 2, y: low),
            // Shoulder interiors and just-outside points.
            CGPoint(x: -ext * 0.5, y: ext * 0.5),
            CGPoint(x: w + ext * 0.5, y: ext * 0.5),
            CGPoint(x: -ext - 0.5, y: ext / 2),
            CGPoint(x: -ext - 0.5, y: ext),
            CGPoint(x: w + ext + 0.5, y: ext / 2),
            CGPoint(x: w + ext + 0.5, y: ext),
            CGPoint(x: w / 2, y: -0.5 - ext),
            CGPoint(x: w / 2, y: low + 0.5),
            CGPoint(x: -ext - 20, y: h / 2),
            CGPoint(x: w + ext + 20, y: h / 2)
        ]
    }

    private func reference(_ point: CGPoint, _ size: CGSize, _ contour: NotchContour) -> Bool {
        NotchShape(topRadius: contour.topRadius, bottomRadius: contour.bottomRadius,
                   style: contour.style)
            .path(in: CGRect(origin: .zero, size: size)).contains(point)
    }

    func testPrefilterMatchesTheExactPathDecision() {
        for probe in contours() {
            NotchHitTestDiagnostics.reset()
            for point in probePoints(probe.size, probe.contour) {
                let expected = reference(point, probe.size, probe.contour)
                let actual = WindowCoordinator.containsMouse(localPoint: point,
                                                             size: probe.size,
                                                             contour: probe.contour)
                XCTAssertEqual(actual, expected,
                               "\(probe.name) at \(point) must keep the exact result")
            }
            XCTAssertGreaterThan(NotchHitTestDiagnostics.pathConstructions, 0,
                                 "\(probe.name): near/boundary points must use the path")
            XCTAssertGreaterThan(NotchHitTestDiagnostics.prefilterExclusions, 0,
                                 "\(probe.name): at least one representative point is far")
        }
    }

    func testPointOverloadKeepsTopInsetScaleAndNegativeFrames() {
        let physical = NotchGeometry.calculate(screenWidth: 312, safeAreaTop: 32,
                                               auxiliaryLeftWidth: 90, auxiliaryRightWidth: 90,
                                               menuBarHeight: 24, simulated: false)
        let simulated = NotchGeometry.calculate(screenWidth: 1512, safeAreaTop: 0,
                                                auxiliaryLeftWidth: nil, auxiliaryRightWidth: nil,
                                                menuBarHeight: 24, simulated: true)
        let notchContour = NotchContour.stationary(geometry: physical, simulated: false,
                                                   expanded: false, expandedCorners: false,
                                                   active: true, visibleHeight: 32)
        let pillContour = NotchContour.stationary(geometry: simulated, simulated: false,
                                                  expanded: false, expandedCorners: false,
                                                  active: false, visibleHeight: 19.5)
        let frames: [(CGSize, NotchContour)] = [
            (CGSize(width: 132, height: 32), notchContour),
            (CGSize(width: 140, height: 19.5), pillContour)
        ]
        let panelFrame = CGRect(x: -1920, y: -200, width: 624, height: 320)
        for scale in [CGSize(width: 1, height: 1), CGSize(width: 1.075, height: 1.15)] {
            for (size, contour) in frames {
                let points = [
                    CGPoint(x: panelFrame.midX, y: panelFrame.maxY - 5),
                    CGPoint(x: panelFrame.midX, y: panelFrame.maxY - 100),
                    CGPoint(x: panelFrame.midX + 20, y: panelFrame.maxY - 2),
                    CGPoint(x: panelFrame.midX + 200, y: panelFrame.maxY - 10),
                    CGPoint(x: panelFrame.minX + 10, y: panelFrame.maxY - 10),
                    CGPoint(x: panelFrame.midX, y: panelFrame.minY + 10)
                ]
                NotchHitTestDiagnostics.reset()
                for point in points {
                    let local = NotchHoverMetrics.localPoint(
                        centeredX: point.x - panelFrame.midX,
                        topY: panelFrame.maxY - point.y - contour.topInset,
                        size: size, scale: scale)
                    let expected = reference(local, size, contour)
                    let actual = WindowCoordinator.containsMouse(
                        point: point, panelFrame: panelFrame, size: size,
                        contour: contour, scale: scale)
                    XCTAssertEqual(actual, expected,
                                   "point \(point) scale \(scale) must keep the exact result")
                }
                XCTAssertGreaterThan(NotchHitTestDiagnostics.pathConstructions, 0)
                XCTAssertGreaterThan(NotchHitTestDiagnostics.prefilterExclusions, 0,
                                     "a point below the visible surface must be excluded")
            }
        }
    }

    func testFarPointsSkipThePathAndBoundaryPointsDoNot() {
        let physical = NotchGeometry.calculate(screenWidth: 312, safeAreaTop: 32,
                                               auxiliaryLeftWidth: 90, auxiliaryRightWidth: 90,
                                               menuBarHeight: 24, simulated: false)
        let size = CGSize(width: 140, height: 23)
        let contour = NotchContour.stationary(geometry: physical, simulated: false,
                                              expanded: false, expandedCorners: false,
                                              active: true, visibleHeight: 23)
        let ext = 2 * shoulders(size, contour).t
        XCTAssertGreaterThan(ext, 0)

        NotchHitTestDiagnostics.reset()
        XCTAssertFalse(WindowCoordinator.containsMouse(
            localPoint: CGPoint(x: 1000, y: 1000), size: size, contour: contour))
        XCTAssertEqual(NotchHitTestDiagnostics.prefilterExclusions, 1)
        XCTAssertEqual(NotchHitTestDiagnostics.pathConstructions, 0,
                       "a far point must not construct the path")

        XCTAssertTrue(WindowCoordinator.containsMouse(
            localPoint: CGPoint(x: size.width / 2, y: size.height / 2),
            size: size, contour: contour))
        XCTAssertEqual(NotchHitTestDiagnostics.pathConstructions, 1)

        // Exact conservative bounds stay on the original logic.
        for point in [CGPoint(x: -ext, y: ext / 2),
                      CGPoint(x: size.width + ext, y: ext / 2),
                      CGPoint(x: size.width / 2, y: max(size.height, ext))] {
            _ = WindowCoordinator.containsMouse(localPoint: point, size: size, contour: contour)
        }
        XCTAssertEqual(NotchHitTestDiagnostics.pathConstructions, 4)
        XCTAssertEqual(NotchHitTestDiagnostics.prefilterExclusions, 1)

        // Just outside is excluded.
        XCTAssertFalse(WindowCoordinator.containsMouse(
            localPoint: CGPoint(x: -ext - 0.01, y: ext / 2), size: size, contour: contour))
        XCTAssertFalse(WindowCoordinator.containsMouse(
            localPoint: CGPoint(x: size.width / 2, y: max(size.height, ext) + 0.01),
            size: size, contour: contour))
        XCTAssertEqual(NotchHitTestDiagnostics.prefilterExclusions, 3)
        XCTAssertEqual(NotchHitTestDiagnostics.pathConstructions, 4)
    }

    func testPointOverloadFarPointSkipsThePath() {
        let physical = NotchGeometry.calculate(screenWidth: 312, safeAreaTop: 32,
                                               auxiliaryLeftWidth: 90, auxiliaryRightWidth: 90,
                                               menuBarHeight: 24, simulated: false)
        let size = CGSize(width: 132, height: 32)
        let contour = NotchContour.stationary(geometry: physical, simulated: false,
                                              expanded: false, expandedCorners: false,
                                              active: true, visibleHeight: 32)
        let panelFrame = CGRect(x: -1920, y: -200, width: 624, height: 320)
        NotchHitTestDiagnostics.reset()
        XCTAssertFalse(WindowCoordinator.containsMouse(
            point: CGPoint(x: panelFrame.midX + 400, y: panelFrame.maxY - 10),
            panelFrame: panelFrame, size: size, contour: contour,
            scale: CGSize(width: 1, height: 1)))
        XCTAssertEqual(NotchHitTestDiagnostics.prefilterExclusions, 1)
        XCTAssertEqual(NotchHitTestDiagnostics.pathConstructions, 0)
    }

    func testAbnormalGeometryAndScaleFallBackToTheExactPath() {
        let physical = NotchGeometry.calculate(screenWidth: 312, safeAreaTop: 32,
                                               auxiliaryLeftWidth: 90, auxiliaryRightWidth: 90,
                                               menuBarHeight: 24, simulated: false)
        let contour = NotchContour.stationary(geometry: physical, simulated: false,
                                              expanded: false, expandedCorners: false,
                                              active: true, visibleHeight: 32)
        let zeroSize = CGSize(width: 0, height: 32)
        NotchHitTestDiagnostics.reset()
        let zeroResult = WindowCoordinator.containsMouse(localPoint: CGPoint(x: 0, y: 10),
                                                         size: zeroSize, contour: contour)
        XCTAssertEqual(zeroResult, reference(CGPoint(x: 0, y: 10), zeroSize, contour))
        XCTAssertEqual(NotchHitTestDiagnostics.pathConstructions, 1,
                       "a non-positive size must use the original path")
        XCTAssertEqual(NotchHitTestDiagnostics.prefilterExclusions, 0)

        let size = CGSize(width: 132, height: 32)
        let panelFrame = CGRect(x: 0, y: 0, width: 624, height: 320)
        let point = CGPoint(x: panelFrame.midX + 10, y: panelFrame.maxY - 5)
        for scale in [CGSize(width: 0, height: 1), CGSize(width: -1, height: 1),
                      CGSize(width: CGFloat.nan, height: 1)] {
            NotchHitTestDiagnostics.reset()
            let local = NotchHoverMetrics.localPoint(
                centeredX: point.x - panelFrame.midX,
                topY: panelFrame.maxY - point.y - contour.topInset,
                size: size, scale: scale)
            let actual = WindowCoordinator.containsMouse(
                point: point, panelFrame: panelFrame, size: size,
                contour: contour, scale: scale)
            XCTAssertEqual(actual, reference(local, size, contour),
                           "abnormal scale \(scale) must keep the exact result")
            XCTAssertEqual(NotchHitTestDiagnostics.pathConstructions, 1,
                           "abnormal scale \(scale) must not be prefiltered")
            XCTAssertEqual(NotchHitTestDiagnostics.prefilterExclusions, 0)
        }

        NotchHitTestDiagnostics.reset()
        XCTAssertFalse(WindowCoordinator.containsMouse(
            localPoint: CGPoint(x: CGFloat.nan, y: 10), size: size, contour: contour))
        XCTAssertEqual(NotchHitTestDiagnostics.pathConstructions, 1,
                       "a non-finite point must use the original path")
    }
}
