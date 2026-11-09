import AppKit
import XCTest
import ReferenceCore
@testable import Valora

@MainActor
final class IndependentNotchPrefilterTests: XCTestCase {
    func testEveryNonFinitePointFallsBackToTheOriginalPath() {
        let geometry = NotchGeometry.calculate(screenWidth: 1512, safeAreaTop: 0,
                                               auxiliaryLeftWidth: nil, auxiliaryRightWidth: nil,
                                               menuBarHeight: 24, simulated: true)
        let contour = NotchContour.stationary(geometry: geometry, simulated: true,
                                              expanded: false, expandedCorners: false,
                                              active: true, visibleHeight: 30)
        let size = CGSize(width: 140, height: 30)
        for point in [CGPoint(x: CGFloat.infinity, y: 10),
                      CGPoint(x: -CGFloat.infinity, y: 10),
                      CGPoint(x: CGFloat.nan, y: 1000),
                      CGPoint(x: 1000, y: CGFloat.nan)] {
            NotchHitTestDiagnostics.reset()
            _ = WindowCoordinator.containsMouse(localPoint: point, size: size, contour: contour)
            XCTAssertEqual(NotchHitTestDiagnostics.pathConstructions, 1,
                           "non-finite coordinates must bypass the prefilter: \(point)")
        }
    }
}
