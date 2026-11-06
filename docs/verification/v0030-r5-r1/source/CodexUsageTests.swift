import Foundation
import XCTest
@testable import Valora

final class CodexUsageParserTests: XCTestCase {
    private func parse(_ json: String, now: Date = Date(timeIntervalSince1970: 1_700_000_000)) throws -> CodexRateLimits {
        try CodexRateLimitsParser.parse(data: Data(json.utf8), now: now)
    }

    func testAuthoritativeEmptyBucketMapDoesNotFallbackToLegacy() throws {
        let reading = try parse("""
        {"rateLimits":{"primary":{"usedPercent":99,"windowDurationMins":300,"resetsAt":1700003600}},
         "rateLimitsByLimitId":{},"rateLimitResetCredits":{"availableCount":2,"credits":[]}}
        """)
        XCTAssertNil(reading.fiveHour)
        XCTAssertNil(reading.week)
        XCTAssertEqual(reading.resetAvailableCount, 2)
        XCTAssertEqual(reading.resetCredits, [])
    }

    func testCodexBucketIsPreferredAndOtherBucketsAreIgnored() throws {
        let reading = try parse("""
        {"rateLimitsByLimitId":{
          "codex":{"primary":{"usedPercent":42,"windowDurationMins":300,"resetsAt":1700003600},
                   "secondary":{"usedPercent":68,"windowDurationMins":10080,"resetsAt":1700600000}},
          "spark":{"primary":{"usedPercent":99,"windowDurationMins":300}}}}
        """)
        XCTAssertEqual(reading.fiveHour?.usedPercent, 42)
        XCTAssertEqual(reading.week?.usedPercent, 68)
        XCTAssertEqual(reading.fiveHour?.resetsAt, Date(timeIntervalSince1970: 1_700_003_600))
    }

    func testLegacyBucketIsUsedOnlyWhenMapIsAbsent() throws {
        let reading = try parse("""
        {"rateLimits":{"primary":{"usedPercent":0,"windowDurationMins":300},
                       "secondary":{"usedPercent":100,"windowDurationMins":10080}}}
        """)
        XCTAssertEqual(reading.fiveHour?.usedPercent, 0)
        XCTAssertEqual(reading.week?.usedPercent, 100)
    }

    func testMissingOrInvalidPercentIsNotFabricatedAsZero() throws {
        let reading = try parse("""
        {"rateLimitsByLimitId":{"codex":{"primary":{"windowDurationMins":300},
          "secondary":{"usedPercent":101,"windowDurationMins":10080}}}}
        """)
        XCTAssertNil(reading.fiveHour?.usedPercent)
        XCTAssertNil(reading.week?.usedPercent)
        XCTAssertEqual(reading.fiveHour?.resetsAt, nil)
    }

    func testUnrelatedWindowDurationIsIgnored() throws {
        let reading = try parse("""
        {"rateLimitsByLimitId":{"codex":{"primary":{"usedPercent":10,"windowDurationMins":60},
          "secondary":{"usedPercent":20,"windowDurationMins":43200}}}}
        """)
        XCTAssertNil(reading.fiveHour)
        XCTAssertNil(reading.week)
    }

    func testResetCreditsCountIsAuthoritativeAndExpirySorted() throws {
        let reading = try parse("""
        {"rateLimitsByLimitId":{"codex":{}},
         "rateLimitResetCredits":{"availableCount":5,"credits":[
           {"id":"late","expiresAt":1700600000},
           {"id":"none"},
           {"id":"early","expiresAt":1700000001}
         ]}}
        """)
        XCTAssertEqual(reading.resetAvailableCount, 5)
        XCTAssertEqual(reading.resetCredits.map(\.id), ["early", "late", "none"])
        XCTAssertNil(reading.resetCredits.last?.expiresAt)
    }

    func testZeroAvailableCountIsPreserved() throws {
        let reading = try parse("""
        {"rateLimitsByLimitId":{"codex":{}},"rateLimitResetCredits":{"availableCount":0}}
        """)
        XCTAssertEqual(reading.resetAvailableCount, 0)
        XCTAssertEqual(reading.resetCredits, [])
    }


    func testMalformedAuthoritativeCodexBucketFailsInsteadOfLegacyOrEmpty() {
        let json = """
        {"rateLimitsByLimitId":{"codex":"bad","other":{"primary":{"usedPercent":1,"windowDurationMins":300}}},
         "rateLimits":{"primary":{"usedPercent":88,"windowDurationMins":300}}}
        """
        XCTAssertThrowsError(try parse(json))
    }

    func testNullAuthoritativeMapUsesLegacyAsNullableFallback() throws {
        let reading = try parse("""
        {"rateLimitsByLimitId":null,"rateLimits":{"primary":{"usedPercent":77,"windowDurationMins":300}}}
        """)
        XCTAssertEqual(reading.fiveHour?.usedPercent, 77)
    }

    func testIntegerBoundaryCannotTrapAndInvalidCountIsMissing() throws {
        // 2^63 is outside Int; it must become nil, not trap Int(Double).
        let reading = try parse("""
        {"rateLimitsByLimitId":{"codex":{}},"rateLimitResetCredits":{"availableCount":9223372036854775808}}
        """)
        XCTAssertNil(reading.resetAvailableCount)
    }

    func testDuplicateCreditIDsRemainDistinctAndCounted() throws {
        let reading = try parse("""
        {"rateLimitsByLimitId":{"codex":{}},"rateLimitResetCredits":{"availableCount":2,"credits":[
          {"id":"same","expiresAt":1700000001},{"id":"same","expiresAt":1700000002}
        ]}}
        """)
        XCTAssertEqual(reading.resetAvailableCount, 2)
        XCTAssertEqual(reading.resetCredits.count, 2)
        XCTAssertEqual(Set(reading.resetCredits.map(\.id)).count, 2)
        XCTAssertEqual(reading.resetCredits.map(\.expiresAt), [Date(timeIntervalSince1970: 1_700_000_001), Date(timeIntervalSince1970: 1_700_000_002)])
    }

    func testMalformedResponseFailsRatherThanBecomingEmptySuccess() {
        XCTAssertThrowsError(try parse("[]"))
    }
}

@MainActor
final class CodexUsageProviderTests: XCTestCase {
    func testFixtureLoadsAndStatusItemImageHasFixedWidth() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let provider = CodexUsageProvider(readLimits: { PreviewCodexUsage.reading(now: now) },
                                          now: { now }, refreshInterval: 3_600)
        provider.start()
        try? await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(provider.snapshot.status, .ready)
        XCTAssertEqual(provider.snapshot.fiveHourPercentText, "42%")
        XCTAssertEqual(provider.snapshot.weekPercentText, "68%")
        XCTAssertEqual(provider.snapshot.resetAvailableCount, 3)
        let zero = MenuBarModuleController.codexMetricImage(five: "0%", week: "0%")
        let full = MenuBarModuleController.codexMetricImage(five: "100%", week: "100%")
        let missing = MenuBarModuleController.codexMetricImage(five: "--%", week: "--%")
        XCTAssertEqual(zero.size, full.size)
        XCTAssertEqual(zero.size, missing.size)
        provider.stop()
        XCTAssertEqual(provider.snapshot, .initial)
    }

    func testMissingEngineIsExplicitFailureNotZero() async {
        let provider = CodexUsageProvider(readLimits: { throw CodexUsageError.missingEngine },
                                          refreshInterval: 3_600)
        provider.start()
        try? await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(provider.snapshot.status, .missingEngine)
        XCTAssertNil(provider.snapshot.fiveHour)
        XCTAssertNil(provider.snapshot.week)
        provider.stop()
    }

    func testStopDropsLateResponseAndDoesNotCommit() async {
        let provider = CodexUsageProvider(readLimits: {
            try? await Task.sleep(for: .milliseconds(160))
            return PreviewCodexUsage.reading()
        }, refreshInterval: 3_600)
        provider.start()
        try? await Task.sleep(for: .milliseconds(30))
        provider.stop()
        try? await Task.sleep(for: .milliseconds(220))
        XCTAssertEqual(provider.snapshot, .initial)
        XCTAssertGreaterThanOrEqual(provider.discardedCount, 1)
    }

    func testOpenRefreshCoalescesToOneInFlightRequest() async {
        let provider = CodexUsageProvider(readLimits: {
            try? await Task.sleep(for: .milliseconds(100))
            return PreviewCodexUsage.reading()
        }, refreshInterval: 3_600)
        provider.start()
        provider.refreshOnOpen()
        provider.refreshOnOpen()
        XCTAssertEqual(provider.requestCount, 1)
        try? await Task.sleep(for: .milliseconds(220))
        XCTAssertEqual(provider.requestCount, 1,
                       "clicks during an already-running valid read are covered by that read, not queued again")
        provider.stop()
    }


    func testLocatorFindsBundledEngineAndUsesOnlyConfiguredHome() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("valora-codex-locator-\(UUID().uuidString)")
        let bin = root.appendingPathComponent("Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex")
        try FileManager.default.createDirectory(at: bin.deletingLastPathComponent(), withIntermediateDirectories: true)
        XCTAssertTrue(FileManager.default.createFile(atPath: bin.path, contents: Data("#!/bin/sh\n".utf8)))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bin.path)
        let home = root.appendingPathComponent("home")
        let locator = DefaultCodexEngineLocator(
            home: home,
            applications: root.appendingPathComponent("Applications"),
            environment: ["CODEX_HOME": root.appendingPathComponent("custom-codex").path],
            path: "/usr/bin")
        XCTAssertEqual(locator.find()?.standardizedFileURL, bin.standardizedFileURL)
        XCTAssertEqual(locator.dataDirectory().lastPathComponent, "custom-codex")
        try? FileManager.default.removeItem(at: root)
    }


    func testFailureCooldownBoundsReopenRetryAndThenAllowsOne() async {
        let clock = CodexTestClock(Date(timeIntervalSince1970: 1_700_000_000))
        let calls = Counter()
        let provider = CodexUsageProvider(readLimits: {
            calls.value += 1
            throw CodexUsageError.missingEngine
        }, now: { clock.value }, refreshInterval: 3_600, failureCooldown: 60)
        provider.start()
        try? await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(provider.snapshot.status, .missingEngine)
        XCTAssertEqual(provider.requestCount, 1)
        clock.advance(20)
        provider.refreshOnOpen()
        try? await Task.sleep(for: .milliseconds(60))
        XCTAssertEqual(provider.requestCount, 1, "failure cooldown must not be bypassed by reopening")
        clock.advance(61)
        provider.refreshOnOpen()
        try? await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(provider.requestCount, 2)
        provider.stop()
    }

    func testRestartAfterUnfinishedReadRunsLatestOnlyAfterOldCompletes() async {
        let reads = HeldCodexReads()
        let provider = CodexUsageProvider(readLimits: { await reads.read() })
        provider.start()
        for _ in 0..<20 { await Task.yield() }
        let firstStarts = await reads.starts
        XCTAssertEqual(firstStarts, 1)
        provider.stop()
        provider.start()
        for _ in 0..<20 { await Task.yield() }
        let beforeFinishMax = await reads.maximumInFlight
        XCTAssertEqual(beforeFinishMax, 1)
        await reads.finishAll()
        for _ in 0..<60 { await Task.yield() }
        let afterStarts = await reads.starts
        let afterMax = await reads.maximumInFlight
        XCTAssertEqual(afterStarts, 2)
        XCTAssertEqual(afterMax, 1)
        provider.stop()
        await reads.finishAll()
    }

    func testTransportAllowlistHasNoAccountThreadTurnOrResetMethods() {
        XCTAssertEqual(CodexAppServerClient.allowedMethods,
                       ["initialize", "initialized", "account/rateLimits/read"])
        XCTAssertFalse(CodexAppServerClient.allowedMethods.contains("account/read"))
        XCTAssertFalse(CodexAppServerClient.allowedMethods.contains { $0.contains("thread") || $0.contains("turn") || $0.contains("reset") })
    }
}


private final class CodexTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Date
    init(_ date: Date) { stored = date }
    var value: Date { lock.lock(); defer { lock.unlock() }; return stored }
    func advance(_ seconds: TimeInterval) { lock.lock(); stored = stored.addingTimeInterval(seconds); lock.unlock() }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = 0
    var value: Int {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); stored = newValue; lock.unlock() }
    }
}

private actor HeldCodexReads {
    private var pending: [CheckedContinuation<CodexRateLimits, Never>] = []
    private(set) var maximumInFlight = 0
    private(set) var starts = 0
    func read() async -> CodexRateLimits {
        starts += 1
        return await withCheckedContinuation { continuation in
            pending.append(continuation)
            maximumInFlight = max(maximumInFlight, pending.count)
        }
    }
    func finishAll() {
        let values = pending
        pending.removeAll()
        values.forEach { $0.resume(returning: PreviewCodexUsage.reading()) }
    }
}
