import XCTest
@testable import Valora
import ReferenceCore

private actor FakeLyricsHTTPClient: LyricsHTTPClient {
    enum Failure: Error { case forced }
    var calls: [URL] = []
    var searchStatus = 200
    var lyricStatus = 200
    var searchData: Data
    var lyricData: Data
    var qrcData: Data?
    var qrcDelayNanoseconds: UInt64 = 0
    var delayNanoseconds: UInt64 = 0
    var ignoreCancellation = false
    var failSearch = false

    init(searchData: Data, lyricData: Data, qrcData: Data? = nil) {
        self.searchData = searchData
        self.lyricData = lyricData
        self.qrcData = qrcData
    }

    func data(for request: URLRequest) async throws -> (Data, Int) {
        if let url = request.url { calls.append(url) }
        if delayNanoseconds > 0 {
            if ignoreCancellation {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
            } else {
                try await Task.sleep(nanoseconds: delayNanoseconds)
            }
        }
        if failSearch { throw Failure.forced }
        if request.url?.path.contains("client_search_cp") == true {
            return (searchData, searchStatus)
        }
        if request.url?.path.contains("lyric_download") == true {
            if qrcDelayNanoseconds > 0 { try await Task.sleep(nanoseconds: qrcDelayNanoseconds) }
            return (qrcData ?? Data(), 200)
        }
        return (lyricData, lyricStatus)
    }
}

private func searchFixture(title: String = "Track") -> Data {
    Data("""
    {"code":0,"data":{"song":{"list":[{"mid":"mid-1","id":97773,
    "title":"\(title)","album":{"name":"Album"},"singer":[{"name":"Artist"}],"interval":200}]}}}
    """.utf8)
}

private func lyricFixture() -> Data {
    Data(#"{"retcode":0,"code":0,"lyric":"[00:01.00]first line\n[00:04.00]second line"}"#.utf8)
}

@MainActor
final class LyricsServiceTests: XCTestCase {
    private var suite = ""
    private var defaults: UserDefaults!
    private var settings: RevivalSettings!
    private var model: AppModel!
    private var cacheDirectory: URL!

    override func setUp() {
        super.setUp()
        suite = "com.wangqing.valora.lyrics-service.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defaults.set(["showLyrics": true], forKey: "referenceSettingsUI")
        settings = RevivalSettings(defaults: defaults)
        model = AppModel(settings: settings)
        model.title = "Track"
        model.artist = "Artist"
        model.album = "Album"
        model.duration = 200
        model.playing = true
        model.elapsed = 1
        cacheDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("valora-lyrics-tests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: cacheDirectory)
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    private func makeService(_ client: FakeLyricsHTTPClient) -> QQMusicLyricsService {
        QQMusicLyricsService(client: client,
            cache: LyricsCache(directory: cacheDirectory, memoryEntryLimit: 50,
                               memoryPayloadLimit: 5 * 1024 * 1024,
                               diskByteLimit: 50 * 1024 * 1024))
    }

    private func request(_ title: String = "Track", duration: Double = 200) -> LyricsRequest {
        LyricsRequest(title: title, artist: "Artist", album: "Album", duration: duration)
    }

    func testServiceFetchesTimedLyricsAndCachesOnlySuccess() async throws {
        let client = FakeLyricsHTTPClient(searchData: searchFixture(), lyricData: lyricFixture())
        let service = makeService(client)
        let first = try await service.lyrics(for: request())
        guard case .timed(let timeline) = first else { return XCTFail("expected timed") }
        XCTAssertEqual(timeline.lines.map(\.text), ["first line", "second line"])
        let second = try await service.lyrics(for: request())
        XCTAssertEqual(first, second)
        let calls = await client.calls
        XCTAssertEqual(calls.count, 3, "search + QRC attempt + lyric should be reused from cache")
    }

    func testCanceledInFlightDoesNotTrapFreshSameRequest() async throws {
        let client = FakeLyricsHTTPClient(searchData: searchFixture(), lyricData: lyricFixture())
        await client.setDelay(120_000_000)
        let service = makeService(client)
        let request = request()
        let first = Task { try await service.lyrics(for: request) }
        try? await Task.sleep(nanoseconds: 20_000_000)
        first.cancel()
        try? await Task.sleep(nanoseconds: 20_000_000)
        let second = try await service.lyrics(for: request)
        guard case .timed = second else { return XCTFail("fresh same request must recover") }
        _ = try? await first.value
    }

    func testCanceledNoncooperativeResultDoesNotPopulateCache() async throws {
        let client = FakeLyricsHTTPClient(searchData: searchFixture(), lyricData: lyricFixture())
        await client.setDelay(150_000_000)
        await client.setIgnoreCancellation(true)
        let service = makeService(client)
        let request = request()
        let first = Task { try await service.lyrics(for: request) }
        try? await Task.sleep(nanoseconds: 20_000_000)
        first.cancel()
        try? await Task.sleep(nanoseconds: 300_000_000)
        await client.setDelay(0)
        _ = try await service.lyrics(for: request)
        let calls = await client.calls
        XCTAssertGreaterThan(calls.count, 3, "canceled late response must not satisfy cache")
    }

    func testCanceledQRCPhaseDoesNotFallBackToLRC() async throws {
        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("ReferenceCoreTests/Fixtures/qq-qrc-studio.hex")
        let hex = try String(contentsOf: fixture, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        let qrc = Data(("<result>0</result><content><![CDATA[" + hex + "]]></content>").utf8)
        let client = FakeLyricsHTTPClient(searchData: searchFixture(), lyricData: lyricFixture(), qrcData: qrc)
        await client.setQRCDelay(200_000_000)
        let service = makeService(client)
        let task = Task { try await service.lyrics(for: request()) }
        try? await Task.sleep(nanoseconds: 30_000_000)
        task.cancel()
        try? await Task.sleep(nanoseconds: 300_000_000)
        let calls = await client.calls
        XCTAssertFalse(calls.contains { $0.path.contains("fcg_query_lyric_new") },
                       "canceled QRC must not send the LRC fallback")
    }

    func testServiceDoesNotCacheHTTPFailure() async throws {
        let client = FakeLyricsHTTPClient(searchData: searchFixture(), lyricData: lyricFixture())
        await client.setSearchStatus(503)
        let service = makeService(client)
        do {
            _ = try await service.lyrics(for: request())
            XCTFail("HTTP 503 must throw")
        } catch {
            XCTAssertEqual(error as? LyricsFetchError, .requestFailed)
        }
        await client.setSearchStatus(200)
        let recovered = try await service.lyrics(for: request())
        guard case .timed = recovered else { return XCTFail("failure must not be a permanent negative cache") }
        let calls = await client.calls
        XCTAssertEqual(calls.count, 4, "failed search must be retried by a new explicit request")
    }

    func testServiceDeduplicatesConcurrentIdenticalRequests() async throws {
        let client = FakeLyricsHTTPClient(searchData: searchFixture(), lyricData: lyricFixture())
        await client.setDelay(80_000_000)
        let service = makeService(client)
        let duplicateRequest = request()
        async let first = service.lyrics(for: duplicateRequest)
        async let second = service.lyrics(for: duplicateRequest)
        let results = try await [first, second]
        XCTAssertEqual(results.count, 2)
        let calls = await client.calls
        XCTAssertEqual(calls.count, 3, "concurrent identical requests must share one search+QRC+lyric chain")
    }


    func testServicePrefersRealQRCWordTimingOverLineLRC() async throws {
        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("ReferenceCoreTests/Fixtures/qq-qrc-studio.hex")
        let hex = try String(contentsOf: fixture, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        let qrc = Data(("<result>0</result><content><![CDATA[" + hex + "]]></content>").utf8)
        let client = FakeLyricsHTTPClient(searchData: searchFixture(), lyricData: lyricFixture(), qrcData: qrc)
        let service = makeService(client)
        let result = try await service.lyrics(for: request())
        guard case .wordTimed(let timeline) = result else {
            return XCTFail("expected real QRC word timing")
        }
        XCTAssertEqual(timeline.lines.count, 63)
        XCTAssertEqual(timeline.lines.reduce(0) { $0 + $1.words.count }, 602)
        XCTAssertGreaterThan(timeline.lines.first?.words.first?.duration ?? 0, 0)
        let calls = await client.calls
        XCTAssertTrue(calls.contains { $0.path.contains("lyric_download") })
    }

    func testControllerPublishesLyricsAndClearsWhenDisabled() async {
        let controller = LyricsController(model: model,
                                          provider: StaticLyricsProvider(result: .timed(LyricTimeline(lines: [
                                              LyricLine(start: 1, text: "first line")
                                          ]))))
        controller.start()
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(model.lyrics.status, .ready)
        XCTAssertEqual(model.currentLyricLine?.text, "first line")
        XCTAssertTrue(model.showsCompactLyrics)
        XCTAssertGreaterThan(model.visibleSize.height, model.notchGeometry.compact.height)

        defaults.set(["showLyrics": false], forKey: "referenceSettingsUI")
        settings.reloadPreferences()
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(model.lyrics.status, .idle)
        XCTAssertFalse(model.showsCompactLyrics)
    }

    func testControllerFallsBackWhenProviderFails() async {
        let controller = LyricsController(model: model, provider: FailingLyricsProvider())
        controller.start()
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(model.lyrics.status, .unavailable)
        XCTAssertNil(model.currentLyricLine)
        XCTAssertFalse(model.showsCompactLyrics, "failure must hide the lyric row, not show song info")
    }

    func testDisablingLyricsCancelsInFlightRequest() async {
        let provider = CancellationProbeProvider()
        let controller = LyricsController(model: model, provider: provider)
        controller.start()
        try? await Task.sleep(nanoseconds: 30_000_000)
        let started = await provider.started
        XCTAssertTrue(started)
        defaults.set(["showLyrics": false], forKey: "referenceSettingsUI")
        settings.reloadPreferences()
        try? await Task.sleep(nanoseconds: 100_000_000)
        let cancelled = await provider.cancelled
        XCTAssertTrue(cancelled)
        XCTAssertEqual(model.lyrics.status, .idle)
    }

    func testControllerClearsWhenMusicIsDisabled() async {
        let controller = LyricsController(model: model,
                                          provider: StaticLyricsProvider(result: .timed(LyricTimeline(lines: [
                                              LyricLine(start: 0, text: "line")
                                          ]))))
        controller.start()
        try? await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertEqual(model.lyrics.status, .ready)
        settings.nowPlayingEnabled = false
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(model.lyrics.status, .idle)
        XCTAssertFalse(model.showsCompactLyrics)
    }

    func testElapsedTicksAndPauseDoNotRepeatRequests() async {
        let provider = CountingTimedProvider()
        let controller = LyricsController(model: model, provider: provider)
        controller.start()
        try? await Task.sleep(nanoseconds: 100_000_000)
        let initialCalls = await provider.calls
        XCTAssertEqual(initialCalls, 1)
        for value in [2.0, 3.0, 4.0, 5.0] { model.elapsed = value; try? await Task.sleep(nanoseconds: 20_000_000) }
        model.playing = false; try? await Task.sleep(nanoseconds: 50_000_000)
        model.playing = true; try? await Task.sleep(nanoseconds: 50_000_000)
        let finalCalls = await provider.calls
        XCTAssertEqual(finalCalls, 1)
    }

    func testControllerThreeSecondBudgetHidesLateResult() async {
        let provider = SlowLyricsProvider(delay: 1_000_000_000)
        let controller = LyricsController(model: model, provider: provider, budget: 0.05)
        controller.start()
        try? await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(model.lyrics.status, .unavailable)
        XCTAssertFalse(model.showsCompactLyrics)
        try? await Task.sleep(nanoseconds: 1_100_000_000)
        XCTAssertEqual(model.lyrics.status, .unavailable,
                       "late response must not appear after the identity budget")
    }

    func testHiddenNotchDoesNotStartRequestOnMetadataChange() async {
        model.screenHidden = true
        let provider = CountingLyricsProvider()
        let controller = LyricsController(model: model, provider: provider)
        controller.start()
        try? await Task.sleep(nanoseconds: 80_000_000)
        model.title = "Hidden change"
        model.artist = "Other"
        try? await Task.sleep(nanoseconds: 100_000_000)
        let hiddenCalls = await provider.calls
        XCTAssertTrue(hiddenCalls.isEmpty)
        model.screenHidden = false
        try? await Task.sleep(nanoseconds: 100_000_000)
        let visibleCalls = await provider.calls
        XCTAssertEqual(visibleCalls.count, 1)
    }

    func testControllerDoesNotRequestWhenLyricsAreDisabled() async {
        defaults.set(["showLyrics": false], forKey: "referenceSettingsUI")
        settings.reloadPreferences()
        let provider = CountingLyricsProvider()
        let controller = LyricsController(model: model, provider: provider)
        controller.start()
        try? await Task.sleep(nanoseconds: 100_000_000)
        let calls = await provider.calls
        XCTAssertTrue(calls.isEmpty)
        XCTAssertEqual(model.lyrics.status, .idle)
    }

    func testServiceCacheIsKeyedByVersionIdentity() async throws {
        let client = FakeLyricsHTTPClient(searchData: searchFixture(), lyricData: lyricFixture())
        let service = makeService(client)
        _ = try await service.lyrics(for: request("Track", duration: 200))
        _ = try await service.lyrics(for: request("Track", duration: 201))
        let calls = await client.calls
        XCTAssertEqual(calls.count, 6, "different title/version must not share a timed lyric cache entry")
    }

    func testControllerRejectsStaleTrackResponse() async {
        let provider = DelayedLyricsProvider()
        let controller = LyricsController(model: model, provider: provider)
        model.title = "A"
        controller.start()
        try? await Task.sleep(nanoseconds: 20_000_000)
        model.title = "B"
        try? await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertEqual(model.lyrics.identity?.title, "B")
        XCTAssertEqual(model.currentLyricLine?.text, "B lyric")
    }
}

private actor DelayedLyricsProvider: LyricsProviding {
    func lyrics(for request: LyricsRequest) async throws -> LyricsFetchResult {
        if request.title == "A" {
            try? await Task.sleep(nanoseconds: 120_000_000)
        }
        return .timed(LyricTimeline(lines: [LyricLine(start: 0, text: request.title + " lyric")]))
    }
}

private extension FakeLyricsHTTPClient {
    func setSearchStatus(_ status: Int) { searchStatus = status }
    func setDelay(_ nanoseconds: UInt64) { delayNanoseconds = nanoseconds }
}


private struct FailingLyricsProvider: LyricsProviding {
    func lyrics(for request: LyricsRequest) async throws -> LyricsFetchResult {
        throw LyricsFetchError.requestFailed
    }
}

private actor CountingLyricsProvider: LyricsProviding {
    var calls: [LyricsRequest] = []
    func lyrics(for request: LyricsRequest) async throws -> LyricsFetchResult {
        calls.append(request)
        return .noLyrics
    }
}


private actor CancellationProbeProvider: LyricsProviding {
    private(set) var started = false
    private(set) var cancelled = false
    func lyrics(for request: LyricsRequest) async throws -> LyricsFetchResult {
        started = true
        do {
            try await Task.sleep(nanoseconds: 1_000_000_000)
        } catch {
            cancelled = true
            throw CancellationError()
        }
        return .timed(LyricTimeline(lines: [LyricLine(start: 0, text: "late")]))
    }
}


private struct SlowLyricsProvider: LyricsProviding {
    let delay: UInt64
    func lyrics(for request: LyricsRequest) async throws -> LyricsFetchResult {
        try? await Task.sleep(nanoseconds: delay)
        return .timed(LyricTimeline(lines: [LyricLine(start: 0, text: "late")]))
    }
}


private actor CountingTimedProvider: LyricsProviding {
    private(set) var calls = 0
    func lyrics(for request: LyricsRequest) async throws -> LyricsFetchResult {
        calls += 1
        return .timed(LyricTimeline(lines: [LyricLine(start: 0, text: "line")]))
    }
}


private extension FakeLyricsHTTPClient {
    func setIgnoreCancellation(_ value: Bool) { ignoreCancellation = value }
}


private extension FakeLyricsHTTPClient {
    func setQRCDelay(_ value: UInt64) { qrcDelayNanoseconds = value }
}

@MainActor
final class LyricMetricsCacheTests: XCTestCase {
    func testSameTextAndStartButDifferentWordSegmentationRebuilds() {
        let identity = LyricsTrackIdentity(title: "Track", artist: "Artist",
                                           album: "Album", duration: 200)
        let one = LyricLine(start: 10, text: "你好", words: [
            LyricWord(text: "你好", start: 10, duration: 1)
        ])
        let two = LyricLine(start: 10, text: "你好", words: [
            LyricWord(text: "你", start: 10, duration: 0.5),
            LyricWord(text: "好", start: 10.5, duration: 0.5)
        ])
        let cache = LyricMetricsCache()
        let a = cache.metrics(for: one, identity: identity)
        let b = cache.metrics(for: two, identity: identity)
        XCTAssertEqual(a.wordWidths.count, 1)
        XCTAssertEqual(b.wordWidths.count, 2)
        XCTAssertNotEqual(a, b)
    }

    func testDelayedMountUsesElapsedSampleAge() {
        let start = Date(timeIntervalSinceReferenceDate: 100)
        let model = AppModel(settings: RevivalSettings(defaults: UserDefaults(suiteName:
            "com.wangqing.valora.anchor.\(UUID().uuidString)")!))
        model.setElapsed(10, sampledAt: start)
        model.playing = true
        XCTAssertEqual(model.lyricsElapsed(at: start.addingTimeInterval(0.2)),
                       10.2, accuracy: 0.0001)
        model.playing = false
        XCTAssertEqual(model.lyricsElapsed(at: start.addingTimeInterval(2)), 10,
                       accuracy: 0.0001)
    }
}
