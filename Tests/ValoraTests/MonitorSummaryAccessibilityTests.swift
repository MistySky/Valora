import XCTest
import ReferenceCore
@testable import Valora

/// V0100: the summary card's VoiceOver text follows exactly what is visible.
final class MonitorSummaryAccessibilityTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let stats = MonitorSummaryAccessibility.Stats(
        memoryTotal: "32 GB", memoryRemaining: "8.2 GB",
        diskTotal: "494.4 GB", diskRemaining: "263.7 GB", uptime: "已运行 2 天")

    private func snapshot(used5h: Double, usedWeek: Double, credits: Int?) -> CodexUsageSnapshot {
        CodexUsageSnapshot(status: .ready,
                           fiveHour: CodexQuotaWindow(usedPercent: used5h, resetsAt: now.addingTimeInterval(3600)),
                           week: CodexQuotaWindow(usedPercent: usedWeek, resetsAt: now.addingTimeInterval(86_400)),
                           resetAvailableCount: credits, resetCredits: [],
                           observedAt: now, message: nil)
    }

    func testMonitorOnly() {
        let text = MonitorSummaryAccessibility.label(showsStats: true, codex: nil, stats: stats, now: now)
        XCTAssertTrue(text.contains("内存 32 GB"))
        XCTAssertTrue(text.contains("磁盘 494.4 GB"))
        XCTAssertTrue(text.contains("已运行 2 天"))
        XCTAssertFalse(text.contains("5H"), "no quota text when the Codex row is absent")
        XCTAssertFalse(text.contains("重置卡"))
    }

    func testCodexOnly() {
        let text = MonitorSummaryAccessibility.label(showsStats: false,
                                                     codex: snapshot(used5h: 21, usedWeek: 3, credits: 2),
                                                     stats: stats, now: now)
        XCTAssertTrue(text.contains("5H 79%"))
        XCTAssertTrue(text.contains("WEEK 97%"))
        XCTAssertTrue(text.contains("重置卡 2 张"))
        XCTAssertFalse(text.contains("内存"), "no fabricated monitor text when its switch is off")
        XCTAssertFalse(text.contains("磁盘"))
    }

    func testBothRows() {
        let text = MonitorSummaryAccessibility.label(showsStats: true,
                                                     codex: snapshot(used5h: 21, usedWeek: 3, credits: 2),
                                                     stats: stats, now: now)
        XCTAssertTrue(text.contains("内存 32 GB"))
        XCTAssertTrue(text.contains("5H 79%"))
        XCTAssertTrue(text.contains("重置卡 2 张"))
    }

    func testNeitherRowProducesNoText() {
        XCTAssertEqual(MonitorSummaryAccessibility.label(showsStats: false, codex: nil,
                                                         stats: stats, now: now), "")
    }
}
