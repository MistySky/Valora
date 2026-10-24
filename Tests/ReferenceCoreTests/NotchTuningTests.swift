import XCTest
@testable import ReferenceCore

final class NotchTuningTests: XCTestCase {
    private func physical() -> NotchGeometry {
        .calculate(screenWidth: 1728, safeAreaTop: 32, auxiliaryLeftWidth: 771.5,
                   auxiliaryRightWidth: 771.5, menuBarHeight: 32, simulated: false)
    }
    private func floating() -> NotchGeometry {
        .calculate(screenWidth: 1920, safeAreaTop: 0, auxiliaryLeftWidth: nil,
                   auxiliaryRightWidth: nil, menuBarHeight: 24, simulated: false)
    }
    private func simulated() -> NotchGeometry {
        .calculate(screenWidth: 1920, safeAreaTop: 0, auxiliaryLeftWidth: nil,
                   auxiliaryRightWidth: nil, menuBarHeight: 24, simulated: true)
    }

    func testZeroIsBaselineInEveryCompactBranch() {
        for (geometry, simulated) in [(physical(), false), (floating(), false), (simulated(), true)] {
            let base = PresentationMetrics.stationarySize(geometry: geometry, simulated: simulated)
            XCTAssertEqual(PresentationMetrics.stationarySize(geometry: geometry, simulated: simulated, tuning: .zero), base)
        }
    }

    func testPositiveAndNegativeOffsetsApplyToPhysicalCompactOnly() {
        let tuning = NotchTuning(widthOffset: 12, heightOffset: -4)
        let base = PresentationMetrics.stationarySize(geometry: physical(), simulated: false)
        let adjusted = PresentationMetrics.stationarySize(geometry: physical(), simulated: false, tuning: tuning)
        XCTAssertEqual(adjusted.width, base.width + 12)
        XCTAssertEqual(adjusted.height, base.height - 4)

        let expanded = PresentationMetrics.stationarySize(geometry: physical(), simulated: false,
                                                           expanded: .nowPlaying, tuning: tuning)
        XCTAssertEqual(expanded, CGSize(width: 345, height: 175))
    }

    func testPhysicalGateRejectsFloatingAndForcedSimulatedScreens() {
        let tuning = NotchTuning(widthOffset: 20, heightOffset: 6)
        for (geometry, simulated) in [(floating(), false), (simulated(), true)] {
            let base = PresentationMetrics.stationarySize(geometry: geometry, simulated: simulated)
            let tuned = PresentationMetrics.stationarySize(geometry: geometry, simulated: simulated, tuning: tuning)
            XCTAssertEqual(tuned, base, "offsets must be filtered when no physical notch is detected")
        }
        // A physical screen remains eligible when force-simulated is on: the
        // hardware gate, not the simulated presentation flag, controls offsets.
        let physicalBase = PresentationMetrics.stationarySize(geometry: physical(), simulated: false)
        let physicalSimulated = PresentationMetrics.stationarySize(geometry: physical(), simulated: true, tuning: tuning)
        XCTAssertEqual(physicalSimulated.width, physicalBase.width + 20)
        XCTAssertEqual(physicalSimulated.height, physicalBase.height + 6)
    }

    func testNotificationAndQuickPeekReceiveTheSamePhysicalCompactOffset() {
        let tuning = NotchTuning(widthOffset: 8, heightOffset: 5)
        let notification = PresentationMetrics.stationarySize(
            geometry: physical(), simulated: false, notification: .connectedAirPods, tuning: tuning)
        let baseNotification = PresentationMetrics.stationarySize(
            geometry: physical(), simulated: false, notification: .connectedAirPods)
        XCTAssertEqual(notification.width, baseNotification.width + 8)
        XCTAssertEqual(notification.height, baseNotification.height + 5)

        let peek = PresentationMetrics.stationarySize(
            geometry: physical(), simulated: false, quickPeek: .playing, tuning: tuning)
        let basePeek = PresentationMetrics.stationarySize(
            geometry: physical(), simulated: false, quickPeek: .playing)
        XCTAssertEqual(peek.width, basePeek.width + 8)
        XCTAssertEqual(peek.height, basePeek.height + 5)
    }

    func testExtremeFiniteValuesAreClampedToCandidateUIRangeAndNonFiniteIsZero() {
        let extreme = NotchTuning(widthOffset: 1_000_000, heightOffset: -1_000_000)
        XCTAssertEqual(extreme.widthOffset, 40)
        XCTAssertEqual(extreme.heightOffset, -10)
        let invalid = NotchTuning(widthOffset: .nan, heightOffset: .infinity)
        XCTAssertEqual(invalid.widthOffset, 0)
        XCTAssertEqual(invalid.heightOffset, 0)

        let size = PresentationMetrics.stationarySize(geometry: physical(), simulated: false, tuning: extreme)
        XCTAssertEqual(size.width, physical().compact.width + 40)
        XCTAssertEqual(size.height, max(1, physical().compact.height - 10))
    }

    func testPhysicalFloatingAndSimulatedBranchesKeepTheirOwnBaseGeometry() {
        let tuning = NotchTuning(widthOffset: 6, heightOffset: 2)
        let p = PresentationMetrics.stationarySize(geometry: physical(), simulated: false, tuning: tuning)
        let f = PresentationMetrics.stationarySize(geometry: floating(), simulated: false, tuning: tuning)
        let s = PresentationMetrics.stationarySize(geometry: simulated(), simulated: true, tuning: tuning)
        XCTAssertEqual(p.width, physical().compact.width + 6)
        XCTAssertEqual(f, floating().compact)
        XCTAssertEqual(s, simulated().compact)
        XCTAssertEqual(p.height, physical().compact.height + 2)
    }
}
