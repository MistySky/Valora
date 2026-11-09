import XCTest
import ReferenceCore
@testable import Valora

@MainActor
final class IndependentLyricsFrameReplacementTests: XCTestCase {
    func testEarlierSuccessorAppearsWithoutChangingOldSuccessorIndex() {
        let cache = LyricsLineFrameCache()
        let metrics = LyricMetricsCache()
        let current = LyricLine(start: 10, text: "current long line")
        let old = LyricTimeline(lines: [LyricLine(start: 0, text: "old"), current,
                                       LyricLine(start: 20, text: "last")])
        let new = LyricTimeline(lines: [current, LyricLine(start: 15, text: "inserted"),
                                       LyricLine(start: 20, text: "last")])
        _ = cache.frame(for: current, duration: 100, identity: nil,
                        timeline: old, width: 40, metricsCache: metrics)
        let frame = cache.frame(for: current, duration: 100, identity: nil,
                                timeline: new, width: 40, metricsCache: metrics)
        XCTAssertEqual(frame.lineEnd, 15, "same count and old successor slot do not prove the next boundary is unchanged")
    }

    func testFormerLastLineGetsSuccessorWithUnchangedCount() {
        let cache = LyricsLineFrameCache()
        let metrics = LyricMetricsCache()
        let current = LyricLine(start: 10, text: "current long line")
        let old = LyricTimeline(lines: [LyricLine(start: 0, text: "old"), current])
        let new = LyricTimeline(lines: [current, LyricLine(start: 15, text: "new")])
        _ = cache.frame(for: current, duration: 100, identity: nil,
                        timeline: old, width: 40, metricsCache: metrics)
        let frame = cache.frame(for: current, duration: 100, identity: nil,
                                timeline: new, width: 40, metricsCache: metrics)
        XCTAssertEqual(frame.lineEnd, 15, "a former last line must not retain the duration fallback after replacement")
    }
}
