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
    var delayNanoseconds: UInt64 = 0
    var failSearch = false

    init(searchData: Data, lyricData: Data) {
        self.searchData = searchData
        self.lyricData = lyricData
    }

    func data(for request: URLRequest) async throws -> (Data, Int) {
        if let url = request.url { calls.append(url) }
        if delayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: delayNanoseconds)
        }
        if failSearch { throw Failure.forced }
        if request.url?.path.contains("client_search_cp") == true {
            return (searchData, searchStatus)
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
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    private func request(_ title: String = "Track", duration: Double = 200) -> LyricsRequest {
        LyricsRequest(title: title, artist: "Artist", album: "Album", duration: duration)
    }

    func testServiceFetchesTimedLyricsAndCachesOnlySuccess() async throws {
        let client = FakeLyricsHTTPClient(searchData: searchFixture(), lyricData: lyricFixture())
        let service = QQMusicLyricsService(client: client)
        let first = try await service.lyrics(for: request())
        guard case .timed(let timeline) = first else { return XCTFail("expected timed") }
        XCTAssertEqual(timeline.lines.map(\.text), ["first line", "second line"])
        let second = try await service.lyrics(for: request())
        XCTAssertEqual(first, second)
        let calls = await client.calls
        XCTAssertEqual(calls.count, 2, "search + lyric should be reused from cache")
    }

    func testServiceDoesNotCacheHTTPFailure() async throws {
        let client = FakeLyricsHTTPClient(searchData: searchFixture(), lyricData: lyricFixture())
        await client.setSearchStatus(503)
        let service = QQMusicLyricsService(client: client)
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
        XCTAssertEqual(calls.count, 3, "failed search must be retried by a new explicit request")
    }

    func testServiceDeduplicatesConcurrentIdenticalRequests() async throws {
        let client = FakeLyricsHTTPClient(searchData: searchFixture(), lyricData: lyricFixture())
        await client.setDelay(80_000_000)
        let service = QQMusicLyricsService(client: client)
        let duplicateRequest = request()
        async let first = service.lyrics(for: duplicateRequest)
        async let second = service.lyrics(for: duplicateRequest)
        let results = try await [first, second]
        XCTAssertEqual(results.count, 2)
        let calls = await client.calls
        XCTAssertEqual(calls.count, 2, "concurrent identical requests must share one search+lyric pair")
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
        XCTAssertTrue(model.lyricFallbackText.contains("Track"))
        XCTAssertTrue(model.showsCompactLyrics)
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
        let service = QQMusicLyricsService(client: client)
        _ = try await service.lyrics(for: request("Track", duration: 200))
        _ = try await service.lyrics(for: request("Track", duration: 201))
        let calls = await client.calls
        XCTAssertEqual(calls.count, 4, "different title/version must not share a timed lyric cache entry")
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
