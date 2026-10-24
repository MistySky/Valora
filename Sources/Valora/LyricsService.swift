import Foundation
import ReferenceCore

protocol LyricsHTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> (Data, Int)
}

struct URLSessionLyricsHTTPClient: LyricsHTTPClient, Sendable {
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 10
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        session = URLSession(configuration: configuration)
    }

    func data(for request: URLRequest) async throws -> (Data, Int) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw LyricsFetchError.invalidResponse
        }
        return (data, http.statusCode)
    }
}

protocol LyricsProviding: Sendable {
    func lyrics(for request: LyricsRequest) async throws -> LyricsFetchResult
}

/// Production QQ Music line-lyric service. It reuses the V0010 evaluators so
/// HTTP/API failures are rejected before any lyric classification. No local QQ
/// database, account, cookie, QRC decryption or script subprocess is used.
actor QQMusicLyricsService: LyricsProviding {
    private let client: any LyricsHTTPClient
    private var cache: [LyricsRequest: LyricsFetchResult] = [:]
    private var inFlight: [LyricsRequest: Task<LyricsFetchResult, Error>] = [:]

    init(client: any LyricsHTTPClient = URLSessionLyricsHTTPClient()) {
        self.client = client
    }

    func lyrics(for request: LyricsRequest) async throws -> LyricsFetchResult {
        if let cached = cache[request] { return cached }
        if let task = inFlight[request] { return try await task.value }

        let task = Task { try await Self.fetch(request, client: client) }
        inFlight[request] = task
        do {
            let result = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
            inFlight[request] = nil
            if case .timed = result { cache[request] = result }
            return result
        } catch {
            inFlight[request] = nil
            throw error
        }
    }

    private static func fetch(_ request: LyricsRequest,
                              client: any LyricsHTTPClient) async throws -> LyricsFetchResult {
        let searchURL = try makeSearchURL(request)
        let (searchData, searchStatus) = try await client.data(for: URLRequest(url: searchURL))
        switch QQMusicSearchEvaluator.evaluate(status: searchStatus, data: searchData) {
        case .failure:
            throw LyricsFetchError.requestFailed
        case .success(let candidates):
            switch QQMusicMatcher.match(QQMusicSample(title: request.title, artist: request.artist,
                                                       album: request.album, duration: request.duration),
                                        candidates: candidates) {
            case .noMatch:
                throw LyricsFetchError.noMatch
            case .matched(let candidate):
                let lyricURL = try makeLyricURL(songmid: candidate.songmid)
                var lyricRequest = URLRequest(url: lyricURL)
                lyricRequest.setValue("https://y.qq.com/portal/player.html", forHTTPHeaderField: "Referer")
                let (lyricData, lyricStatus) = try await client.data(for: lyricRequest)
                switch QQMusicLyricEvaluator.evaluate(status: lyricStatus, data: lyricData) {
                case .failure:
                    throw LyricsFetchError.requestFailed
                case .noLyrics:
                    return .noLyrics
                case .instrumental:
                    return .instrumental
                case .plainText:
                    return .unsynchronized
                case .timedLRC(let lines, _):
                    return .timed(LyricTimeline(lines: lines))
                }
            }
        }
    }

    private static func makeSearchURL(_ request: LyricsRequest) throws -> URL {
        var components = URLComponents(string: "https://c.y.qq.com/soso/fcgi-bin/client_search_cp")!
        components.queryItems = [
            URLQueryItem(name: "w", value: "\(request.title) \(request.artist)"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "n", value: "10"),
            URLQueryItem(name: "p", value: "1"),
            URLQueryItem(name: "new_json", value: "1")
        ]
        guard let url = components.url else { throw LyricsFetchError.invalidResponse }
        return url
    }

    private static func makeLyricURL(songmid: String) throws -> URL {
        var components = URLComponents(string: "https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg")!
        components.queryItems = [
            URLQueryItem(name: "songmid", value: songmid),
            URLQueryItem(name: "g_tk", value: "5381"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "nobase64", value: "1")
        ]
        guard let url = components.url else { throw LyricsFetchError.invalidResponse }
        return url
    }
}

/// QA-only provider: no network, no player, no system writes.
struct StaticLyricsProvider: LyricsProviding {
    let result: LyricsFetchResult
    func lyrics(for request: LyricsRequest) async throws -> LyricsFetchResult { result }
}

struct NoLyricsProvider: LyricsProviding {
    func lyrics(for request: LyricsRequest) async throws -> LyricsFetchResult { .noLyrics }
}
