import XCTest
@testable import Valora

final class NotchDiagnosticPolicyTests: XCTestCase {
    func testIdenticalStateIsDeduplicated() {
        var policy = NotchDiagnosticPolicy(totalLimit: 10, normalLimit: 4, lockLimit: 6)
        XCTAssertTrue(policy.shouldRecord(key: "hidden|same", locked: false))
        XCTAssertFalse(policy.shouldRecord(key: "hidden|same", locked: false))
        XCTAssertEqual(policy.totalCount, 1)
    }

    func testNormalBudgetLeavesReservedSpaceForLockLifecycle() {
        var policy = NotchDiagnosticPolicy(totalLimit: 10, normalLimit: 2, lockLimit: 5)
        XCTAssertTrue(policy.shouldRecord(key: "hidden-1", locked: false))
        XCTAssertTrue(policy.shouldRecord(key: "hidden-2", locked: false))
        XCTAssertFalse(policy.shouldRecord(key: "hidden-3", locked: false))
        XCTAssertTrue(policy.shouldRecord(key: "lock-1", locked: true))
        XCTAssertTrue(policy.shouldRecord(key: "lock-2", locked: true))
        XCTAssertTrue(policy.shouldRecord(key: "lock-3", locked: true))
        XCTAssertEqual(policy.totalCount, 5)
    }

    func testTotalHardLimitStillWins() {
        var policy = NotchDiagnosticPolicy(totalLimit: 3, normalLimit: 2, lockLimit: 2)
        XCTAssertTrue(policy.shouldRecord(key: "hidden", locked: false))
        XCTAssertTrue(policy.shouldRecord(key: "lock-1", locked: true))
        XCTAssertTrue(policy.shouldRecord(key: "lock-2", locked: true))
        XCTAssertFalse(policy.shouldRecord(key: "lock-3", locked: true))
        XCTAssertEqual(policy.totalCount, 3)
    }

    func testHostTopRespectsFlippedAndInternalOrigin() {
        let bounds = CGRect(x: 8, y: 20, width: 200, height: 300)
        XCTAssertEqual(NotchDiagnosticCoordinate.hostTop(bounds: bounds, isFlipped: false), 320)
        XCTAssertEqual(NotchDiagnosticCoordinate.hostTop(bounds: bounds, isFlipped: true), 20)
    }

    func testLogicalScreenPointHandlesNegativeScreenOrigin() {
        let point = NotchDiagnosticCoordinate.logicalScreenPoint(
            windowPoint: CGPoint(x: 12, y: 34),
            screenOrigin: CGPoint(x: -1920, y: -200))
        XCTAssertEqual(point, CGPoint(x: -1908, y: -166))
    }

    func testDifferentLockBoundaryAlwaysHasItsOwnKey() {
        var policy = NotchDiagnosticPolicy(totalLimit: 20, normalLimit: 1, lockLimit: 10)
        XCTAssertTrue(policy.shouldRecord(key: "hidden", locked: false))
        XCTAssertTrue(policy.shouldRecord(key: "locking", locked: true))
        XCTAssertTrue(policy.shouldRecord(key: "neutralizing", locked: true))
        XCTAssertTrue(policy.shouldRecord(key: "locked", locked: true))
        XCTAssertTrue(policy.shouldRecord(key: "unlocking", locked: true))
        XCTAssertTrue(policy.shouldRecord(key: "restoring", locked: true))
        XCTAssertTrue(policy.shouldRecord(key: "hidden-after-unlock", locked: true))
    }
}
