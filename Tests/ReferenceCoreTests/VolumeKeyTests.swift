import XCTest
@testable import ReferenceCore

final class VolumeKeyTests: XCTestCase {
    func testKeyCodes() {
        XCTAssertEqual(VolumeKeyAction.action(keyCode: 0), .up)
        XCTAssertEqual(VolumeKeyAction.action(keyCode: 1), .down)
        XCTAssertEqual(VolumeKeyAction.action(keyCode: 7), .mute)
        XCTAssertNil(VolumeKeyAction.action(keyCode: 2))
    }
    func testStepsAndClamp() {
        XCTAssertEqual(VolumeStep.target(current: 0.5, action: .up, fine: false), 0.5625, accuracy: 0.0001)
        XCTAssertEqual(VolumeStep.target(current: 0.5, action: .down, fine: true), 0.484375, accuracy: 0.0001)
        XCTAssertEqual(VolumeStep.target(current: 1, action: .up, fine: false), 1)
        XCTAssertEqual(VolumeStep.target(current: 0, action: .down, fine: false), 0)
    }
}
