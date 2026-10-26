import XCTest
@testable import Valora

private actor HeldQuotaReads {
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

@MainActor
final class IndependentCodexUsageTests: XCTestCase {
    func testStopThenRestartDoesNotOverlapAnUnfinishedRead() async {
        let reads = HeldQuotaReads()
        let provider = CodexUsageProvider(readLimits: { await reads.read() })
        provider.start()
        for _ in 0..<30 { await Task.yield() }
        let firstStarts = await reads.starts
        XCTAssertEqual(firstStarts, 1)
        provider.stop()
        provider.start()
        for _ in 0..<30 { await Task.yield() }
        let maximum = await reads.maximumInFlight
        XCTAssertEqual(maximum, 1, "Cancelled work may still be unwinding; restarting must keep the actual in-flight bound")
        provider.stop()
        await reads.finishAll()
        for _ in 0..<30 { await Task.yield() }
    }

    func testRapidPopoverReopenUsesFreshQuotaInsteadOfLaunchingEveryTime() async {
        let provider = CodexUsageProvider(readLimits: { PreviewCodexUsage.reading() },
                                          refreshInterval: 180)
        provider.start()
        for _ in 0..<30 { await Task.yield() }
        XCTAssertEqual(provider.snapshot.status, .ready)
        let initialRequests = provider.requestCount
        for _ in 0..<10 {
            provider.refreshOnOpen()
            for _ in 0..<30 { await Task.yield() }
        }
        XCTAssertEqual(provider.requestCount, initialRequests,
                       "Reopening a fresh panel must not repeatedly spawn an app-server/network read")
        provider.stop()
    }

    func testMalformedAuthoritativeMapCannotResurrectLegacyQuota() throws {
        let json = """
        {"rateLimitsByLimitId": "invalid", "rateLimits": {
          "primary": {"usedPercent":88,"windowDurationMins":300}
        }}
        """
        do {
            let reading = try CodexRateLimitsParser.parse(data: Data(json.utf8))
            XCTAssertNil(reading.fiveHour, "A present invalid authoritative field must not silently select legacy data")
        } catch {
            // An explicit protocol failure is also a valid safe result.
        }
    }
}
