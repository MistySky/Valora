import XCTest
@testable import ReferenceCore

final class MarqueeTests: XCTestCase {
    func testOverflowIncludesLeadingInset() {
        XCTAssertFalse(MarqueeMetrics(textWidth:95.5,viewportWidth:100,longestTextWidth:95.5).overflows)
        XCTAssertTrue(MarqueeMetrics(textWidth:95.6,viewportWidth:100,longestTextWidth:95.6).overflows)
    }
    func testTwoRowsShareCycleButUseTheirOwnMovementDuration() {
        let title=MarqueeMetrics(textWidth:300,viewportWidth:150,longestTextWidth:450)
        let artist=MarqueeMetrics(textWidth:450,viewportWidth:150,longestTextWidth:450)
        XCTAssertEqual(title.cycleDuration,16.25)
        XCTAssertEqual(title.cycleDuration,artist.cycleDuration)
        XCTAssertEqual(title.movementDuration,10)
        XCTAssertEqual(artist.movementDuration,15)
        XCTAssertEqual(title.delay,1.25)
        XCTAssertEqual(title.firstOrigin,4.5)
        XCTAssertEqual(title.secondOrigin,324)
        XCTAssertEqual(title.firstDestination,-319.5)
        XCTAssertEqual(title.secondDestination,4.5)
    }
}
