import XCTest
@testable import ReferenceCore

final class NonNotchLyricsGeometryTests: XCTestCase {
    private func geometry(simulated: Bool) -> NotchGeometry {
        .calculate(screenWidth: 1920, safeAreaTop: 0, auxiliaryLeftWidth: nil,
                   auxiliaryRightWidth: nil, menuBarHeight: 24, simulated: simulated)
    }

    func testNonNotchBaseAndExpandedWidthsAreUnified() {
        for simulated in [false, true] {
            let g = geometry(simulated: simulated)
            XCTAssertFalse(g.hasPhysicalNotch)
            XCTAssertEqual(g.compact.width, 140)
            XCTAssertEqual(g.expanded.width, 345)
        }
    }

    func testMusicCompactWidthIs214InBothNonNotchForms() {
        for simulated in [false, true] {
            let g = geometry(simulated: simulated)
            let music = PresentationMetrics.stationarySize(geometry: g, simulated: simulated,
                liveActivity: .playing)
            let peek = PresentationMetrics.stationarySize(geometry: g, simulated: simulated,
                quickPeek: .playing)
            let expanded = PresentationMetrics.stationarySize(geometry: g, simulated: simulated,
                expanded: .nowPlaying)
            XCTAssertEqual(music.width, 214)
            XCTAssertEqual(peek.width, 214)
            XCTAssertEqual(expanded.width, 345)
        }
    }

    func testPhysicalNotchWidthIsNotOverriddenByUnifiedNonNotchRule() {
        let physical = NotchGeometry.calculate(screenWidth: 1728, safeAreaTop: 32,
            auxiliaryLeftWidth: 771.5, auxiliaryRightWidth: 771.5,
            menuBarHeight: 32, simulated: false)
        XCTAssertTrue(physical.hasPhysicalNotch)
        XCTAssertEqual(physical.compact.width, 185)
        XCTAssertEqual(physical.expanded.width, 345)
        XCTAssertEqual(PresentationMetrics.stationarySize(geometry: physical, simulated: false,
            liveActivity: .playing).width, 259)
    }
}
