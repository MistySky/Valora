import XCTest
import CoreGraphics
import ReferenceCore

final class ReferenceCoreTests: XCTestCase {
    func testPhysicalNotchOnUsersBuiltInDisplay() {
        let g = NotchGeometry.calculate(screenWidth: 1728, safeAreaTop: 32,
                                       auxiliaryLeftWidth: 771.5, auxiliaryRightWidth: 771.5,
                                       menuBarHeight: 32, simulated: false)
        XCTAssertEqual(g.compact, CGSize(width: 185, height: 32))
        XCTAssertEqual(g.expanded, CGSize(width: 345, height: 175))
        XCTAssertTrue(g.hasPhysicalNotch)
    }

    func testMinimumAndLargerPhysicalGeometry() {
        let small = NotchGeometry.calculate(screenWidth: 1000, safeAreaTop: 28,
                                           auxiliaryLeftWidth: 425, auxiliaryRightWidth: 425,
                                           menuBarHeight: 28, simulated: false)
        XCTAssertEqual(small.expanded, CGSize(width: 345, height: 175))
        let large = NotchGeometry.calculate(screenWidth: 2000, safeAreaTop: 40,
                                           auxiliaryLeftWidth: 890, auxiliaryRightWidth: 890,
                                           menuBarHeight: 40, simulated: false)
        XCTAssertEqual(large.expanded, CGSize(width: 380, height: 182))
    }

    func testNonNotchAndSimulatedBranchesFromArm64Registers() {
        // Reference constants: d0=74/140, d1=menu height-5.5/-1,
        // d2=321/345, d3=175. No menu gap uses d1=19.5/24.
        for (simulated, menu, compact, expanded) in [
            (false, CGFloat(25), CGSize(width: 74, height: 19.5), CGSize(width: 321, height: 175)),
            (false, CGFloat(0), CGSize(width: 74, height: 19.5), CGSize(width: 321, height: 175)),
            (true, CGFloat(25), CGSize(width: 140, height: 24), CGSize(width: 345, height: 175)),
            (true, CGFloat(0), CGSize(width: 140, height: 24), CGSize(width: 345, height: 175)),
            (true, CGFloat(32), CGSize(width: 140, height: 31), CGSize(width: 345, height: 175))
        ] {
            let g = NotchGeometry.calculate(screenWidth: 1920, safeAreaTop: 0,
                                           auxiliaryLeftWidth: nil, auxiliaryRightWidth: nil,
                                           menuBarHeight: menu, simulated: simulated)
            XCTAssertEqual(g.compact, compact)
            XCTAssertEqual(g.expanded, expanded)
            XCTAssertFalse(g.hasPhysicalNotch)
        }
    }

    func testMissingAuxiliaryAreaUsesNonNotchBranch() {
        let g = NotchGeometry.calculate(screenWidth: 1728, safeAreaTop: 32,
                                       auxiliaryLeftWidth: 771.5, auxiliaryRightWidth: nil,
                                       menuBarHeight: 32, simulated: false)
        XCTAssertFalse(g.hasPhysicalNotch)
        XCTAssertEqual(g.compact, CGSize(width: 74, height: 26.5))
    }

    func testObservedModelUIDAndAllReferenceProductAliases() {
        XCTAssertEqual(AirPodsModel.identify(modelUID: "2013 4c"), .airPods3)
        XCTAssertEqual(AirPodsModel.identify(modelUID: "2013 4c")?.uncoloredMovie, "airpods-3")
        let expected: [(String, AirPodsModel)] = [
            ("2002", .airPods), ("200f", .airPods2), ("2013", .airPods3),
            ("201b", .airPods4), ("2019", .airPods4), ("200e", .pro),
            ("2014", .pro2), ("2024", .pro2), ("2027", .pro3),
            ("200a", .max), ("201f", .max2), ("202d", .max2)
        ]
        for (token, model) in expected {
            XCTAssertEqual(AirPodsModel.identify(modelUID: "\(token.uppercased()) 4c"), model)
        }
        XCTAssertNil(AirPodsModel.identify(modelUID: ""))
        XCTAssertNil(AirPodsModel.identify(modelUID: "ffff 4c"))
        XCTAssertNil(AirPodsModel.identify(modelUID: "AirPods Pro"))
    }
}
