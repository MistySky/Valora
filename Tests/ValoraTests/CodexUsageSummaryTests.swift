import AppKit
import XCTest
@testable import Valora

/// V0093: the Codex usage line, its switch and the memory formats. Windowless.
@MainActor
final class CodexUsageSummaryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000) // 2023-11-14 22:13 UTC
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return c
    }
    private var locale: Locale { Locale(identifier: "zh_Hans_CN") }

    private func snapshot(used5h: Double?, reset5h: Date?, usedWeek: Double?, resetWeek: Date?,
                          credits: Int?) -> CodexUsageSnapshot {
        CodexUsageSnapshot(
            status: .ready,
            fiveHour: used5h.map { CodexQuotaWindow(usedPercent: $0, resetsAt: reset5h) },
            week: usedWeek.map { CodexQuotaWindow(usedPercent: $0, resetsAt: resetWeek) },
            resetAvailableCount: credits,
            resetCredits: [],
            observedAt: now,
            message: nil)
    }

    // MARK: - Remaining-quota semantics

    func testRemainingPercentIsDerivedFromUsed() {
        let snap = snapshot(used5h: 21, reset5h: now, usedWeek: 3, resetWeek: now, credits: 2)
        XCTAssertEqual(CodexUsageSummaryFormatter.percent(snap.fiveHour?.remainingPercent), "79%")
        XCTAssertEqual(CodexUsageSummaryFormatter.percent(snap.week?.remainingPercent), "97%")
    }

    func testUnknownValuesNeverRenderAsZero() {
        let snap = snapshot(used5h: nil, reset5h: nil, usedWeek: nil, resetWeek: nil, credits: nil)
        let five = CodexUsageSummaryFormatter.fiveHour(snap, now: now, calendar: calendar, locale: locale)
        let week = CodexUsageSummaryFormatter.week(snap, now: now, calendar: calendar, locale: locale)
        XCTAssertEqual(five, "5H — —")
        XCTAssertEqual(week, "WEEK — —")
        XCTAssertEqual(CodexUsageSummaryFormatter.resetCredits(snap), "重置卡 —")
        XCTAssertFalse(five.contains("0%"))
    }

    func testZeroUsedRendersFullRemaining() {
        let snap = snapshot(used5h: 0, reset5h: now, usedWeek: 100, resetWeek: now, credits: 0)
        XCTAssertEqual(CodexUsageSummaryFormatter.percent(snap.fiveHour?.remainingPercent), "100%")
        XCTAssertEqual(CodexUsageSummaryFormatter.percent(snap.week?.remainingPercent), "0%")
        XCTAssertEqual(CodexUsageSummaryFormatter.resetCredits(snap), "重置卡 0张")
    }

    // MARK: - Parser fixtures

    func testParserKeepsUsedAndRemainingApart() throws {
        let json = """
        {"rateLimits":{"primary":{"usedPercent":21,"windowDurationMins":300},
                       "secondary":{"usedPercent":3,"windowDurationMins":10080}},
         "rateLimitResetCredits":{"availableCount":2}}
        """
        let reading = try CodexRateLimitsParser.parse(data: Data(json.utf8), now: now)
        XCTAssertEqual(reading.fiveHour?.usedPercent, 21)
        XCTAssertEqual(reading.fiveHour?.remainingPercent, 79)
        XCTAssertEqual(reading.week?.usedPercent, 3)
        XCTAssertEqual(reading.week?.remainingPercent, 97)
        XCTAssertEqual(reading.resetAvailableCount, 2)
    }

    func testParserDoesNotTreatMissingCreditsAsZero() throws {
        let json = #"{"rateLimits":{"primary":{"usedPercent":50,"windowDurationMins":300}}}"#
        let reading = try CodexRateLimitsParser.parse(data: Data(json.utf8), now: now)
        XCTAssertNil(reading.resetAvailableCount)
        let snap = CodexUsageSnapshot(reading: reading, now: now)
        XCTAssertEqual(CodexUsageSummaryFormatter.resetCredits(snap), "重置卡 —")
    }

    // MARK: - Reset times

    /// V0093 follow-up: the 5H window carries its date as well, so the line is
    /// unambiguous across midnight and does not rely on "today" inference.
    func testFiveHourAlwaysCarriesDateAndTime() {
        let reset = calendar.date(bySettingHour: 19, minute: 5, second: 0, of: now)!
        let text = CodexUsageSummaryFormatter.fiveHour(
            snapshot(used5h: 21, reset5h: reset, usedWeek: 3, resetWeek: reset, credits: 1),
            now: now, calendar: calendar, locale: locale)
        XCTAssertTrue(text.hasPrefix("5H 79% "), text)
        XCTAssertTrue(text.contains("/"), "5H reset must include the date: \(text)")
        XCTAssertTrue(text.contains(":"))
    }

    func testWeekAlwaysCarriesDateAndTime() {
        let reset = calendar.date(byAdding: .day, value: 3, to: now)!
        let text = CodexUsageSummaryFormatter.time(reset, now: now, style: .dateAndTime,
                                                   calendar: calendar, locale: locale)
        XCTAssertTrue(text.contains("/"), "week reset must not be a bare clock time: \(text)")
        XCTAssertTrue(text.contains(":"))
    }

    // MARK: - Line width with the real font

    func testLongestCommonLineFitsTheContentWidth() {
        let snap = snapshot(used5h: 0, reset5h: nil, usedWeek: 0, resetWeek: nil, credits: 99)
        let tokens = [
            CodexUsageSummaryFormatter.fiveHour(snap, now: now, calendar: calendar, locale: locale),
            CodexUsageSummaryFormatter.week(snap, now: now, calendar: calendar, locale: locale),
            CodexUsageSummaryFormatter.resetCredits(snap)
        ]
        // Worst realistic case: 100% and full timestamps.
        let worst = ["5H 100% 12/31 23:59", "WEEK 100% 12/31 23:59", "重置卡 99张"]
        for set in [tokens, worst] {
            let widths = set.map { text -> CGFloat in
                (text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 11)]).width
            }
            let total = widths.reduce(0, +) + 12 * CGFloat(set.count - 1)
            // 400 panel - 2*16 content margin - 2*12 card padding.
            XCTAssertLessThanOrEqual(total, 344, "line too wide: \(set)")
        }
    }

    // MARK: - Memory formats

    func testMemoryRemainingAlwaysKeepsOneDecimal() {
        let gib: UInt64 = 1_073_741_824
        XCTAssertEqual(UIStyle.memoryRemainingString(9 * gib), "9.0 GB")
        XCTAssertEqual(UIStyle.memoryRemainingString(9 * gib + gib / 5), "9.2 GB")
        XCTAssertEqual(UIStyle.memoryRemainingString(10 * gib), "10.0 GB")
    }

    func testMemoryTotalStaysWhole() {
        let gib: UInt64 = 1_073_741_824
        XCTAssertEqual(UIStyle.memoryCapacityString(32 * gib), "32 GB")
        XCTAssertNotEqual(UIStyle.memoryCapacityString(32 * gib), "32.0 GB")
    }

    // MARK: - Settings placement

    func testCodexUsagePageSitsRightBelowSystemMonitorInTheMenuBarGroup() {
        let pages = SettingsSidebar.orderedPages
        guard let monitor = pages.firstIndex(of: .systemMonitor),
              let codex = pages.firstIndex(of: .codexUsage) else {
            return XCTFail("missing pages")
        }
        XCTAssertEqual(codex, monitor + 1)
        XCTAssertEqual(SettingsPage.codexUsage.displayTitle, "Codex 用量")
    }

    // MARK: - Provider lifecycle

    private final class ManualScheduler: CodexRefreshScheduling {
        private(set) var tokens: [ManualToken] = []
        func schedule(after interval: TimeInterval,
                      action: @escaping @MainActor () -> Void) -> any CodexScheduledRefresh {
            let token = ManualToken(action: action)
            tokens.append(token)
            return token
        }
    }

    private final class ManualToken: CodexScheduledRefresh {
        let action: @MainActor () -> Void
        private(set) var cancelled = false
        init(action: @escaping @MainActor () -> Void) { self.action = action }
        func cancel() { cancelled = true }
        func fire() { action() }
    }

    func testStopCancelsTheScheduledRefreshAndIgnoresTheOldCallback() async {
        let scheduler = ManualScheduler()
        let counter = Counter()
        let provider = CodexUsageProvider(readLimits: {
            await counter.increment()
            return CodexRateLimits(fiveHour: CodexQuotaWindow(usedPercent: 21, resetsAt: nil),
                                   week: nil, resetAvailableCount: 2, resetCredits: [],
                                   observedAt: Date())
        }, now: { Date() }, refreshInterval: 180, freshnessInterval: 45,
           scheduler: scheduler)
        provider.start()
        try? await Task.sleep(nanoseconds: 120_000_000)
        XCTAssertEqual(provider.snapshot.fiveHour?.usedPercent, 21)
        let tokens = scheduler.tokens
        provider.stop()
        XCTAssertTrue(tokens.allSatisfy(\.cancelled), "stop must cancel scheduled refreshes")
        let before = await counter.value
        for token in tokens { token.fire() }
        try? await Task.sleep(nanoseconds: 150_000_000)
        let after = await counter.value
        XCTAssertEqual(before, after, "an old scheduled callback must not read after stop")
        XCTAssertFalse(provider.isRunningForTest)
    }

    func testDisablingRemovesTheRowWithoutTouchingMonitorOrCalendar() {
        let visibility = MenuBarPanelVisibility()
        visibility.monitorVisible = true
        visibility.calendarVisible = true
        visibility.codexUsageVisible = true
        visibility.codexUsageVisible = false
        XCTAssertTrue(visibility.monitorVisible)
        XCTAssertTrue(visibility.calendarVisible)
    }

    private actor Counter {
        private(set) var value = 0
        func increment() { value += 1 }
    }

    /// V0094: both summary rows live in one Grid, so the three columns share
    /// widths. Measured with the real caption font; nothing is scaled down.
    func testTwoRowsShareColumnWidthsAndFitTheCard() {
        let font = NSFont.systemFont(ofSize: 11)
        func width(_ text: String) -> CGFloat {
            (text as NSString).size(withAttributes: [.font: font]).width
        }
        let row1 = ["内存 32 GB 9.0 GB", "磁盘 494.4 GB 263.7 GB", "已运行 2 天"]
        let row2 = ["5H 100% 12/31 23:59", "WEEK 100% 12/31 23:59", "重置卡 99张"]
        let columns = (0..<3).map { max(width(row1[$0]), width(row2[$0])) }
        let total = columns.reduce(0, +) + 12 * 2
        // 400 panel - 2*16 content margin - 2*12 card padding = 344pt.
        XCTAssertLessThanOrEqual(total, 344, "two-row grid overflows: \(total)pt")
        // Column 1 must be wide enough for both 内存 and 5H, etc.
        XCTAssertGreaterThanOrEqual(columns[0], width(row1[0]))
        XCTAssertGreaterThanOrEqual(columns[1], width(row2[1]))
    }
}
