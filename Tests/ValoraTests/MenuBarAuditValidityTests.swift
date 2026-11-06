import XCTest
@testable import Valora

final class MenuBarAuditValidityTests: XCTestCase {
    func testAllVisibleSamplesComplete() {
        var tracker = ContinuousVisibilityTracker(expectedSeconds: 180, expectedSamples: 37)
        for index in 0...36 { tracker.record(visible: true, elapsed: Double(index * 5)) }
        XCTAssertEqual(tracker.status, .completed)
        XCTAssertEqual(tracker.visibleSamples, 37)
        XCTAssertEqual(tracker.visibleSeconds, 180, accuracy: 0.001)
    }

    func testCloseAfterFirstSampleIsInterruptedNotCompleted() {
        var tracker = ContinuousVisibilityTracker(expectedSeconds: 180, expectedSamples: 37)
        tracker.record(visible: true, elapsed: 0)
        for index in 1...36 { tracker.record(visible: false, elapsed: Double(index * 5)) }
        XCTAssertEqual(tracker.status, .interrupted)
        XCTAssertEqual(tracker.visibleSamples, 1)
        XCTAssertEqual(tracker.visibleSeconds, 0)
        XCTAssertNotEqual(tracker.status, .completed)
    }

    func testNeverVisibleIsInconclusive() {
        var tracker = ContinuousVisibilityTracker(expectedSeconds: 180, expectedSamples: 37)
        for index in 0...36 { tracker.record(visible: false, elapsed: Double(index * 5)) }
        XCTAssertEqual(tracker.status, .inconclusive)
        XCTAssertEqual(tracker.visibleSamples, 0)
    }

    func testInsufficientSamplesAreInconclusive() {
        var tracker = ContinuousVisibilityTracker(expectedSeconds: 180, expectedSamples: 37)
        for index in 0...5 { tracker.record(visible: true, elapsed: Double(index * 5)) }
        XCTAssertEqual(tracker.status, .inconclusive)
        XCTAssertEqual(tracker.visibleSamples, 6)
    }

    func testInterruptedTrackerSummaryCannotBeMisreadAsCompleted() {
        var tracker = ContinuousVisibilityTracker(expectedSeconds: 180, expectedSamples: 37)
        tracker.record(visible: true, elapsed: 0)
        tracker.record(visible: false, elapsed: 5)
        let summary = tracker.summary
        XCTAssertEqual(summary["status"] as? String, "interrupted")
        XCTAssertEqual(summary["firstInvisibleAt"] as? Double, 5)
    }
}
