import Foundation
import XCTest
@testable import Valora

@MainActor
final class RemainingQuotaCacheTests: XCTestCase {
    func testIndependentCachedFailureStillHonorsClickCooldown() async {
        let scheduler = ManualRefreshScheduler()
        let clock = QuotaClock(Date(timeIntervalSince1970: 1_700_000_000))
        let shouldFail = QuotaFlag()
        let provider = CodexUsageProvider(readLimits: {
            if shouldFail.value { throw CodexUsageError.timeout }
            return Self.reading(usedFive: 21, usedWeek: 3, now: clock.value)
        }, now: { clock.value }, failureCooldown: 60, scheduler: scheduler)
        provider.start()
        await waitUntil { provider.snapshot.status == .ready }
        clock.advance(46)
        shouldFail.value = true
        scheduler.fireNext()
        await waitUntil { provider.snapshot.refreshErrorMessage != nil }
        let requestsAfterFailure = provider.requestCount
        XCTAssertEqual(requestsAfterFailure, 2)
        provider.refreshOnOpen()
        XCTAssertEqual(provider.requestCount, requestsAfterFailure,
                       "a ready but stale cached snapshot must not bypass the failure cooldown")
        XCTAssertEqual(provider.snapshot.fiveHourRemainingPercentText, "79%")
        provider.stop()
    }

    nonisolated private static func reading(usedFive: Double = 21, usedWeek: Double = 3,
                                            resetOffset: TimeInterval = 3_600,
                                            now: Date = Date(timeIntervalSince1970: 1_700_000_000)) -> CodexRateLimits {
        CodexRateLimits(
            fiveHour: CodexQuotaWindow(usedPercent: usedFive, resetsAt: now.addingTimeInterval(resetOffset)),
            week: CodexQuotaWindow(usedPercent: usedWeek, resetsAt: now.addingTimeInterval(86_400)),
            resetAvailableCount: 2,
            resetCredits: [CodexResetCredit(id: "credit-1", expiresAt: now.addingTimeInterval(86_400))],
            observedAt: now)
    }

    func testUsedPercentDerivesOfficialRemainingWithoutChangingProtocol() {
        let snapshot = CodexUsageSnapshot(reading: Self.reading(usedFive: 21, usedWeek: 3), now: Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(snapshot.fiveHour?.usedPercent, 21)
        XCTAssertEqual(snapshot.week?.usedPercent, 3)
        XCTAssertEqual(snapshot.fiveHourRemainingPercentText, "79%")
        XCTAssertEqual(snapshot.weekRemainingPercentText, "97%")
        XCTAssertEqual(CodexQuotaWindow(usedPercent: 0, resetsAt: nil).remainingPercent, 100)
        XCTAssertEqual(CodexQuotaWindow(usedPercent: 100, resetsAt: nil).remainingPercent, 0)
        XCTAssertNil(CodexQuotaWindow(usedPercent: nil, resetsAt: nil).remainingPercent)
        XCTAssertEqual(CodexUsageSnapshot.initial.fiveHourRemainingPercentText, "--%")
    }

    func testStartRefreshesWithoutOpeningAndTimerUsesLatestSnapshot() async {
        let scheduler = ManualRefreshScheduler()
        let calls = QuotaCounter()
        let provider = CodexUsageProvider(readLimits: {
            calls.value += 1
            return Self.reading(usedFive: Double(20 + calls.value), usedWeek: 3)
        }, refreshInterval: 180, scheduler: scheduler)
        provider.start()
        await waitUntil { provider.snapshot.status == .ready }
        XCTAssertEqual(calls.value, 1)
        XCTAssertEqual(provider.snapshot.fiveHourRemainingPercentText, "79%")
        XCTAssertEqual(provider.snapshot.weekRemainingPercentText, "97%")
        XCTAssertTrue(scheduler.pendingCount > 0, "background schedule must exist without opening a panel")
        scheduler.fireNext()
        await waitUntil { calls.value >= 2 }
        XCTAssertEqual(calls.value, 2)
        provider.stop()
    }

    func testBackgroundFailureKeepsCachedValuesAndMarksStale() async {
        let scheduler = ManualRefreshScheduler()
        let clock = QuotaClock(Date(timeIntervalSince1970: 1_700_000_000))
        let calls = QuotaCounter()
        let shouldFail = QuotaFlag()
        let provider = CodexUsageProvider(readLimits: {
            calls.value += 1
            if shouldFail.value { throw CodexUsageError.timeout }
            return Self.reading(usedFive: 21, usedWeek: 3, now: clock.value)
        }, now: { clock.value }, refreshInterval: 180, scheduler: scheduler)
        provider.start()
        await waitUntil { provider.snapshot.status == .ready }
        let firstSuccess = provider.snapshot.observedAt
        XCTAssertNotNil(firstSuccess)
        shouldFail.value = true
        scheduler.fireNext()
        await waitUntil { provider.snapshot.refreshErrorMessage != nil }
        XCTAssertEqual(provider.snapshot.status, .ready)
        XCTAssertEqual(provider.snapshot.fiveHourRemainingPercentText, "79%")
        XCTAssertEqual(provider.snapshot.weekRemainingPercentText, "97%")
        XCTAssertEqual(provider.snapshot.observedAt, firstSuccess)
        XCTAssertFalse(provider.isRefreshing)
        shouldFail.value = false
        clock.advance(61)
        provider.refreshOnOpen()
        await waitUntil { provider.snapshot.refreshErrorMessage == nil }
        XCTAssertEqual(provider.snapshot.fiveHourRemainingPercentText, "79%")
        XCTAssertEqual(provider.snapshot.status, .ready)
        provider.stop()
    }

    func testClickWhileFreshDoesNotClearCachedSnapshotOrCreateRequest() async {
        let scheduler = ManualRefreshScheduler()
        let calls = QuotaCounter()
        let provider = CodexUsageProvider(readLimits: {
            calls.value += 1
            return Self.reading()
        }, refreshInterval: 180, scheduler: scheduler)
        provider.start()
        await waitUntil { provider.snapshot.status == .ready }
        let cached = provider.snapshot
        provider.refreshOnOpen()
        XCTAssertEqual(provider.snapshot, cached)
        XCTAssertEqual(calls.value, 1)
        provider.stop()
    }

    func testResetBoundaryCanRequestAnEarlierRealRefresh() async {
        let scheduler = ManualRefreshScheduler()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let provider = CodexUsageProvider(readLimits: {
            return Self.reading(usedFive: 21, usedWeek: 3, resetOffset: 10, now: now)
        }, now: { now }, refreshInterval: 180, scheduler: scheduler)
        provider.start()
        await waitUntil { provider.snapshot.status == .ready }
        let delay = scheduler.intervals.last ?? .infinity
        XCTAssertGreaterThan(delay, 0)
        XCTAssertLessThanOrEqual(delay, 11,
                                 "a reset sooner than the normal cadence should schedule a real refresh boundary")
        provider.stop()
    }

    func testStaleClickKeepsCachedValuesWhileRefreshIsInFlight() async {
        let scheduler = ManualRefreshScheduler()
        let clock = QuotaClock(Date(timeIntervalSince1970: 1_700_000_000))
        let calls = QuotaCounter()
        let provider = CodexUsageProvider(readLimits: {
            calls.value += 1
            if calls.value > 1 { try? await Task.sleep(for: .milliseconds(120)) }
            return Self.reading(usedFive: calls.value > 1 ? 40 : 21, usedWeek: 3, now: clock.value)
        }, now: { clock.value }, refreshInterval: 180, scheduler: scheduler)
        provider.start()
        await waitUntil { provider.snapshot.status == .ready }
        let cached = provider.snapshot
        clock.advance(46)
        provider.refreshOnOpen()
        XCTAssertEqual(provider.snapshot, cached,
                       "starting a stale background refresh must retain the old snapshot")
        XCTAssertTrue(provider.isRefreshing)
        await waitUntil { provider.snapshot.fiveHourRemainingPercentText == "60%" }
        XCTAssertEqual(calls.value, 2)
        provider.stop()
    }

    func testStopKeepsNoTimerAndRejectsLateCallback() async {
        let scheduler = ManualRefreshScheduler()
        let calls = QuotaCounter()
        let provider = CodexUsageProvider(readLimits: {
            calls.value += 1
            try? await Task.sleep(for: .milliseconds(180))
            return Self.reading()
        }, refreshInterval: 180, scheduler: scheduler)
        provider.start()
        for _ in 0..<20 { await Task.yield() }
        provider.stop()
        XCTAssertEqual(scheduler.pendingCount, 0)
        try? await Task.sleep(for: .milliseconds(260))
        XCTAssertEqual(provider.snapshot, .initial)
        XCTAssertGreaterThanOrEqual(provider.discardedCount, 1)
    }
}

private final class QuotaClock: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Date
    init(_ date: Date) { stored = date }
    var value: Date { lock.lock(); defer { lock.unlock() }; return stored }
    func advance(_ seconds: TimeInterval) { lock.lock(); stored = stored.addingTimeInterval(seconds); lock.unlock() }
}

private final class QuotaFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = false
    var value: Bool {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); stored = newValue; lock.unlock() }
    }
}

private final class QuotaCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = 0
    var value: Int {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); stored = newValue; lock.unlock() }
    }
}

@MainActor
private final class ManualRefreshScheduler: CodexRefreshScheduling {
    final class Token: CodexScheduledRefresh {
        var action: (@MainActor () -> Void)?
        init(_ action: @escaping @MainActor () -> Void) { self.action = action }
        func cancel() { action = nil }
    }

    private(set) var pending: [Token] = []
    private(set) var intervals: [TimeInterval] = []
    var pendingCount: Int { pending.filter { $0.action != nil }.count }
    func schedule(after interval: TimeInterval,
                  action: @escaping @MainActor () -> Void) -> any CodexScheduledRefresh {
        let token = Token(action)
        pending.append(token)
        intervals.append(interval)
        return token
    }
    func fireNext() {
        guard let index = pending.firstIndex(where: { $0.action != nil }) else { return }
        let token = pending.remove(at: index)
        token.action?()
        token.action = nil
    }
}

@MainActor
private func waitUntil(_ condition: @escaping @MainActor () -> Bool, timeout: TimeInterval = 2) async {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return }
        try? await Task.sleep(for: .milliseconds(10))
    }
}
