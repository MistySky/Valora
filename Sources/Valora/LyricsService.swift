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

/// Production QQ Music lyrics service. It reuses the V0010 evaluators so
/// HTTP/API failures are rejected before any lyric classification, then tries
/// real QRC word timing first and falls back to timed LRC. No local QQ database,
/// account, cookie or script subprocess is used. QRC decoding is the MIT-
/// licensed QQMusicDecoder Swift adaptation in `QQMusicQRC`.
actor QQMusicLyricsService: LyricsProviding {
    private struct InFlight {
        let id: UInt64
        let task: Task<LyricsFetchResult, Error>
    }

    private let client: any LyricsHTTPClient
    private let cache: LyricsCache
    private var inFlight: [LyricsRequest: InFlight] = [:]
    private var nextID: UInt64 = 0

    init(client: any LyricsHTTPClient = URLSessionLyricsHTTPClient(),
         cache: LyricsCache = LyricsCache()) {
        self.client = client
        self.cache = cache
    }

    func lyrics(for request: LyricsRequest) async throws -> LyricsFetchResult {
        let key = Self.cacheKey(request)
        if let cached = await cache.get(key) { return cached }

        // A canceled old A must not be joined by a fresh A. The ID check below
        // also prevents an old completion from deleting the replacement entry.
        if let existing = inFlight[request], !existing.task.isCancelled {
            return try await existing.task.value
        }
        if inFlight[request]?.task.isCancelled == true { inFlight[request] = nil }

        nextID &+= 1
        let id = nextID
        let task = Task { try await Self.fetch(request, client: client) }
        inFlight[request] = InFlight(id: id, task: task)
        do {
            let result = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
            guard !Task.isCancelled, !task.isCancelled,
                  inFlight[request]?.id == id else {
                if inFlight[request]?.id == id { inFlight[request] = nil }
                throw CancellationError()
            }
            inFlight[request] = nil
            await cache.put(key, result: result)
            return result
        } catch {
            if inFlight[request]?.id == id { inFlight[request] = nil }
            throw error
        }
    }

    private static func cacheKey(_ request: LyricsRequest) -> String {
        let identity = request.identity
        return [identity.title, identity.artist, identity.album,
                String(identity.durationSeconds)].joined(separator: "\u{0}")
    }

    private static func fetch(_ request: LyricsRequest,
                              client: any LyricsHTTPClient) async throws -> LyricsFetchResult {
        let searchURL = try makeSearchURL(request)
        let (searchData, searchStatus) = try await client.data(for: URLRequest(url: searchURL))
        guard !Task.isCancelled else { throw CancellationError() }
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
                guard !Task.isCancelled else { throw CancellationError() }
                if let songID = candidate.songID,
                   let wordTimed = try await fetchQRC(songID: songID, client: client) {
                    return wordTimed
                }
                guard !Task.isCancelled else { throw CancellationError() }
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

    private static func fetchQRC(songID: Int64,
                                 client: any LyricsHTTPClient) async throws -> LyricsFetchResult? {
        var request = URLRequest(url: URL(string: "https://c.y.qq.com/qqmusic/fcgi-bin/lyric_download.fcg")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("https://y.qq.com/", forHTTPHeaderField: "Referer")
        request.setValue("Valora/0.1", forHTTPHeaderField: "User-Agent")
        request.httpBody = Data("version=15&miniversion=82&lrctype=4&musicid=\(songID)".utf8)
        let fetched: (Data, Int)
        do {
            fetched = try await client.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return nil
        }
        guard !Task.isCancelled else { throw CancellationError() }
        let (data, status) = fetched
        guard (200..<300).contains(status),
              let body = String(data: data, encoding: .utf8),
              let result = tagValue("result", in: body), result == "0",
              let hex = QQMusicQRC.contentHex(from: body),
              let decrypted = QQMusicQRC.decrypt(hex: hex),
              let lines = QQMusicQRC.parseLyrics(decrypted: decrypted), !lines.isEmpty else {
            return nil
        }
        return .wordTimed(LyricTimeline(lines: lines))
    }

    private static func tagValue(_ tag: String, in body: String) -> String? {
        guard let start = body.range(of: "<\(tag)>"),
              let end = body.range(of: "</\(tag)>", range: start.upperBound..<body.endIndex) else {
            return nil
        }
        return String(body[start.upperBound..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
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
