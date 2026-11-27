import XCTest
@testable import Valora
import ReferenceCore

final class DeviceBatterySelectionTests: XCTestCase {
    private func device(left: Int?, right: Int?, single: Int?) -> AudioDevice {
        AudioDevice(id: "fixture", name: "AirPods", left: left, right: right, single: single,
                    active: true, isAirPods: true, modelUID: "2013 4c")
    }

    func testEarbudValuesDoNotLetSinglePlaceholderMaskThem() {
        XCTAssertEqual(device(left: 80, right: 70, single: 0).battery, 70)
        XCTAssertEqual(device(left: 0, right: 70, single: 0).battery, 0,
                       "0 is a real possible earbud value")
        XCTAssertEqual(device(left: nil, right: nil, single: 45).battery, 45)
        XCTAssertNil(device(left: nil, right: nil, single: 0).battery,
                     "The single-device channel alone cannot establish an empty earbud")
        XCTAssertNil(device(left: nil, right: nil, single: nil).battery)
        XCTAssertEqual(AirPodsModel.identify(modelUID: "2013 4c"), .airPods3)
    }

    func testMaxUsesOnlyItsWholeDeviceReadingIncludingZero() {
        var max = device(left: 0, right: 0, single: 82)
        max.productID = 0x200a
        XCTAssertEqual(max.battery, 82)
        max.single = nil
        XCTAssertNil(max.battery)
        max.single = 0
        XCTAssertEqual(max.battery, 0)
    }

    func testUnclassifiedHeadphonesRetainTheirReportedSingleZero() {
        var headset = device(left: nil, right: nil, single: 0)
        headset.modelUID = ""
        headset.isAirPods = false
        XCTAssertEqual(headset.battery, 0)
    }
}
