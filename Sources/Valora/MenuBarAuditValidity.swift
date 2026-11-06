#if VALORA_DEVELOPMENT
import Foundation

/// Pure validity rule for a continuous popover-memory segment.
///
/// A segment is only `completed` when every scheduled sample was actually
/// visible (popover.isShown) and the visible span reached the requested
/// duration. A close after the first visible sample is `interrupted`; a segment
/// that never became/stayed visible is `inconclusive`. Hidden samples must not
/// be counted as a long-open run.
struct ContinuousVisibilityTracker: Equatable {
    enum Status: String, Equatable {
        case completed
        case interrupted
        case inconclusive
    }

    let expectedSeconds: TimeInterval
    let expectedSamples: Int
    private(set) var totalSamples = 0
    private(set) var visibleSamples = 0
    private(set) var firstVisibleAt: TimeInterval?
    private(set) var lastVisibleAt: TimeInterval?
    private(set) var firstInvisibleAt: TimeInterval?
    private(set) var lastSampleAt: TimeInterval?

    init(expectedSeconds: TimeInterval, expectedSamples: Int) {
        self.expectedSeconds = expectedSeconds
        self.expectedSamples = max(1, expectedSamples)
    }

    mutating func record(visible: Bool, elapsed: TimeInterval) {
        totalSamples += 1
        lastSampleAt = elapsed
        if visible {
            visibleSamples += 1
            if firstVisibleAt == nil { firstVisibleAt = elapsed }
            lastVisibleAt = elapsed
        } else if firstInvisibleAt == nil {
            firstInvisibleAt = elapsed
        }
    }

    var visibleSeconds: TimeInterval {
        guard let firstVisibleAt, let lastVisibleAt else { return 0 }
        return max(0, lastVisibleAt - firstVisibleAt)
    }

    var status: Status {
        if firstInvisibleAt != nil {
            // A close immediately after first visibility is an interruption;
            // never convert it into a completed long-open run.
            return firstVisibleAt == nil ? .inconclusive : .interrupted
        }
        guard totalSamples >= expectedSamples,
              visibleSamples >= expectedSamples,
              visibleSeconds >= expectedSeconds else { return .inconclusive }
        return .completed
    }

    var summary: [String: Any] {
        ["status": status.rawValue,
         "expectedSeconds": expectedSeconds,
         "expectedSamples": expectedSamples,
         "totalSamples": totalSamples,
         "visibleSamples": visibleSamples,
         "visibleSeconds": visibleSeconds,
         "firstVisibleAt": firstVisibleAt ?? -1,
         "lastVisibleAt": lastVisibleAt ?? -1,
         "firstInvisibleAt": firstInvisibleAt ?? -1,
         "lastSampleAt": lastSampleAt ?? -1]
    }
}
#endif
