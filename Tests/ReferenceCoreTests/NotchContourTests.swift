import XCTest
@testable import ReferenceCore

final class NotchContourTests: XCTestCase {
    private let floating = NotchGeometry.calculate(screenWidth: 1920, safeAreaTop: 0,
        auxiliaryLeftWidth: nil, auxiliaryRightWidth: nil, menuBarHeight: 31, simulated: false)
    private let physical = NotchGeometry.calculate(screenWidth: 1728, safeAreaTop: 32,
        auxiliaryLeftWidth: 771.5, auxiliaryRightWidth: 771.5, menuBarHeight: 32, simulated: false)

    func testFloatingScreenUsesPillAndIgnoresDelayedNotchCornerFlag() {
        let compact = NotchContour.stationary(geometry: floating, simulated: false, expanded: false,
            expandedCorners: false, active: true, visibleHeight: 25.5)
        XCTAssertEqual(compact.style, .pill)
        XCTAssertEqual(compact.bottomRadius, 12.75)
        XCTAssertEqual(compact.topInset, 2.5)
        let expanded = NotchContour.stationary(geometry: floating, simulated: false, expanded: true,
            expandedCorners: false, active: true, visibleHeight: 175)
        XCTAssertEqual(expanded.bottomRadius, 36)
        XCTAssertEqual(expanded.topRadius, 36)
    }

    func testPhysicalCornersRequireBothExpandedFlags() {
        let early = NotchContour.stationary(geometry: physical, simulated: false, expanded: true,
            expandedCorners: false, active: true, visibleHeight: 175)
        XCTAssertEqual(early.style, .notch)
        XCTAssertEqual(early.topInset, 0)
        XCTAssertEqual(early.topRadius, 8)
        let settled = NotchContour.stationary(geometry: physical, simulated: false, expanded: true,
            expandedCorners: true, active: true, visibleHeight: 175)
        XCTAssertEqual(settled.topRadius, 20)
        XCTAssertEqual(settled.bottomRadius, 35.5)
        let collapsing = NotchContour.stationary(geometry: physical, simulated: false, expanded: false,
            expandedCorners: true, active: true, visibleHeight: 32)
        XCTAssertEqual(collapsing.topRadius, 8)
        XCTAssertEqual(collapsing.bottomRadius, 11.5)
    }

    func testSimulatedNotchKeepsShouldersOnExternalScreen() {
        let contour = NotchContour.stationary(geometry: floating, simulated: true, expanded: false,
            expandedCorners: false, active: false, visibleHeight: 30)
        XCTAssertEqual(contour.style, .notch)
        XCTAssertEqual(contour.topInset, 0)
        XCTAssertEqual(contour.topRadius, 5)
        XCTAssertEqual(contour.bottomRadius, 10)
    }
}

final class NotchContourLyricPillTests: XCTestCase {
    func testPillRadiusDoesNotGrowWithLyricHeight() {
        let geometry = NotchGeometry.calculate(screenWidth: 1920, safeAreaTop: 0,
            auxiliaryLeftWidth: nil, auxiliaryRightWidth: nil, menuBarHeight: 24, simulated: false)
        let normal = NotchContour.stationary(geometry: geometry, simulated: false, expanded: false,
            expandedCorners: false, active: true, visibleHeight: geometry.compact.height)
        let lyric = NotchContour.stationary(geometry: geometry, simulated: false, expanded: false,
            expandedCorners: false, active: true, visibleHeight: geometry.compact.height + 32)
        XCTAssertEqual(normal.bottomRadius, geometry.compact.height / 2)
        XCTAssertEqual(lyric.bottomRadius, normal.bottomRadius)
        XCTAssertLessThan(lyric.bottomRadius, (geometry.compact.height + 32) / 2)
    }
}
