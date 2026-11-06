import XCTest
@testable import Valora

final class IndependentDevelopmentIsolationTests: XCTestCase {
    func testLockCardPreviewDoesNotResolveToLiveProductionStartup() {
        let arguments = ["Valora", "--lock-card-preview"]
        XCTAssertTrue(AppRuntimeDefaults.isQAMode(arguments: arguments),
                      "a development preview must not select normal user preferences")
        XCTAssertNotEqual(AppRuntimeDefaults.startupMode(arguments: arguments), .production,
                          "a development preview must not fall through to live service startup")
    }

    func testExpandMediaInspectionDoesNotResolveToLiveProductionStartup() {
        let arguments = ["Valora", "--expand-media"]
        XCTAssertTrue(AppRuntimeDefaults.isQAMode(arguments: arguments),
                      "development inspection must use isolated preferences")
        XCTAssertNotEqual(AppRuntimeDefaults.startupMode(arguments: arguments), .production,
                          "development inspection must not silently start live services")
    }
}
