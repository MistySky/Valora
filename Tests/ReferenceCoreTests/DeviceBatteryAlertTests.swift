import XCTest
@testable import ReferenceCore

final class DeviceBatteryAlertTests: XCTestCase {
    func testCrossingDedupesAndRearms() {
        var state = DeviceBatteryAlertState()
        XCTAssertFalse(state.update(id: "a", battery: 40, threshold: 20))
        XCTAssertTrue(state.update(id: "a", battery: 20, threshold: 20))
        XCTAssertFalse(state.update(id: "a", battery: 19, threshold: 20))
        XCTAssertFalse(state.update(id: "a", battery: 30, threshold: 20))
        XCTAssertTrue(state.update(id: "a", battery: 15, threshold: 20))
    }

    func testInitialLowDoesNotReplay() {
        var state = DeviceBatteryAlertState()
        XCTAssertFalse(state.update(id: "a", battery: 10, threshold: 20))
        XCTAssertFalse(state.update(id: "a", battery: 9, threshold: 20))
    }

    func testRemoveRearms() {
        var state = DeviceBatteryAlertState()
        _ = state.update(id: "a", battery: 30, threshold: 20)
        XCTAssertTrue(state.update(id: "a", battery: 15, threshold: 20))
        state.remove(id: "a")
        XCTAssertFalse(state.update(id: "a", battery: 10, threshold: 20))
        _ = state.update(id: "a", battery: 30, threshold: 20)
        XCTAssertTrue(state.update(id: "a", battery: 12, threshold: 20))
    }

    func testZeroIsARealBatteryValue() {
        var state = DeviceBatteryAlertState()
        XCTAssertFalse(state.update(id: "a", battery: 40, threshold: 20))
        XCTAssertTrue(state.update(id: "a", battery: 0, threshold: 20))
        XCTAssertFalse(state.update(id: "a", battery: nil, threshold: 20))
        XCTAssertFalse(state.update(id: "a", battery: 0, threshold: 20))
    }
}
