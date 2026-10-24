import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// Manual, explicit QQ Music lyrics probe for V0010/V0010-R1.
// Only the public sample file is read; never current playback, cookies, accounts,
// local libraries or private metadata. Ordinary tests never run this network path.

struct ProbeSample: Decodable {
    let label: String
    let title: String
    let artist: String
    let album: String
    let duration: Double?
}

struct ProbeInput: Decodable {
    let samples: [ProbeSample]
}

struct HTTPResult {
    let status: Int
    let data: Data
    let contentType: String?
}

private struct ProbeError: Error, CustomStringConvertible {
    let description: String
}

struct QQMusicLyricsProbe {
    static let searchEndpoint = "https://c.y.qq.com/soso/fcgi-bin/client_search_cp"
    static let lyricEndpoint = "https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg"
    static let qrcEndpoint = "https://c.y.qq.com/qqmusic/fcgi-bin/lyric_download.fcg"
    static let timeout: TimeInterval = 10

    static func runFromCommandLine() async {
        let args = CommandLine.arguments
        guard let inputPath = value(after: "--input", in: args),
              let outputPath = value(after: "--out", in: args) else {
            fputs("usage: qq-lyrics-probe --input sample.json --out output-directory\n", stderr)
            exit(2)
        }
        do {
            let code = try await run(inputPath: inputPath, outputPath: outputPath)
            if code != 0 { exit(Int32(code)) }
        } catch {
            fputs("qq lyrics probe failed: \(error)\n", stderr)
            exit(1)
        }
    }

    static func run(inputPath: String, outputPath: String) async throws -> Int {
        let inputURL = URL(fileURLWithPath: inputPath)
        let inputData = try Data(contentsOf: inputURL)
        let input = try JSONDecoder().decode(ProbeInput.self, from: inputData)
        let outputURL = URL(fileURLWithPath: outputPath, isDirectory: true)
        try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
        let session = makeSession()
        var sampleResults: [[String: Any]] = []

        for sample in input.samples {
            sampleResults.append(await probe(sample: sample, session: session))
        }

        let requestFailures = sampleResults.compactMap { result -> String? in
            guard (result["request_ok"] as? Bool) == false else { return nil }
            return result["label"] as? String
        }
        let qrcFailures = sampleResults.compactMap { result -> String? in
            guard let qrc = result["qrc"] as? [String: Any],
                  (qrc["request_ok"] as? Bool) == false else { return nil }
            return result["label"] as? String
        }
        let statuses = sampleResults.compactMap { $0["status"] as? String }
        let allSamplesSuccess = !sampleResults.isEmpty
            && sampleResults.allSatisfy { ($0["status"] as? String) == "success" }
        let summary: [String: Any] = [
            "generated_at": ISO8601DateFormatter().string(from: Date()),
            "probe": "V0010 explicit public QQ Music sample probe",
            "input": inputURL.path,
            "timeout_seconds": timeout,
            "retry_count": 0,
            "cookies_enabled": false,
            "request_ok": requestFailures.isEmpty,
            "validation_ok": allSamplesSuccess && qrcFailures.isEmpty,
            "request_failures": requestFailures,
            "qrc_failures": qrcFailures,
            "statuses": statuses,
            "samples": sampleResults
        ]
        let summaryData = try JSONSerialization.data(withJSONObject: summary,
                                                     options: [.prettyPrinted, .sortedKeys])
        try summaryData.write(to: outputURL.appendingPathComponent("network-summary.json"))
        // exit 1 only for request/parse failures; no_lyrics and no_match are
        // valid business outcomes and remain visibly distinct in the summary.
        return (requestFailures.isEmpty && qrcFailures.isEmpty) ? 0 : 1
    }

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        return URLSession(configuration: configuration)
    }

    static func probe(sample: ProbeSample, session: URLSession) async -> [String: Any] {
        let requestModel = QQMusicSample(label: sample.label, title: sample.title,
                                         artist: sample.artist, album: sample.album,
                                         duration: sample.duration)
        var result: [String: Any] = [
            "label": sample.label,
            "request_ok": true,
            "sample": ["title": sample.title, "artist": sample.artist,
                       "album": sample.album, "duration": sample.duration as Any]
        ]

        let searchResult: HTTPResult?
        do {
            searchResult = try await search(sample: sample, session: session)
        } catch {
            result["status"] = "failure"
            result["request_ok"] = false
            result["error"] = ["stage": "search", "message": String(describing: error)]
            return result
        }
        guard let searchResult else { return result }

        switch QQMusicSearchEvaluator.evaluate(status: searchResult.status, data: searchResult.data) {
        case .failure(let failure):
            result["status"] = "failure"
            result["request_ok"] = false
            result["search"] = ["http_status": searchResult.status,
                                "failure": failureDescription(failure),
                                "response_bytes": searchResult.data.count]
            result["error"] = ["stage": "search", "message": failureDescription(failure)]
            return result
        case .success(let candidates):
            result["search"] = candidateSummary(candidates, http: searchResult)
            let match = QQMusicMatcher.match(requestModel, candidates: candidates)
            switch match {
            case .matched(let candidate):
                result["match"] = ["matched": true, "songmid": candidate.songmid,
                                   "songID": candidate.songID.map(String.init) as Any? ?? NSNull(),
                                   "title": candidate.title, "artist": candidate.artist,
                                   "album": candidate.album, "duration": candidate.duration as Any]
                let lyric = await fetchLyrics(songmid: candidate.songmid, session: session)
                result["lyrics"] = lyric
                if (lyric["request_ok"] as? Bool) == false {
                    result["status"] = "failure"
                    result["request_ok"] = false
                } else if (lyric["classification"] as? String) == "no_lyrics" {
                    result["status"] = "no_lyrics"
                } else {
                    result["status"] = "success"
                }
                result["qrc"] = await fetchQRCSummary(songID: candidate.songID, session: session)
            case .noMatch(let failure):
                result["match"] = ["matched": false, "reason": failure.rawValue]
                result["status"] = "no_match"
                result["lyrics"] = ["skipped": "no_match"]
                result["qrc"] = ["skipped": "no_match"]
            }
        }
        return result
    }

    static func candidateSummary(_ candidates: [QQMusicCandidate], http: HTTPResult) -> [String: Any] {
        ["http_status": http.status,
         "content_type": http.contentType ?? "unknown",
         "response_bytes": http.data.count,
         "candidate_count": candidates.count,
         "candidates": candidates.prefix(8).map { candidate -> [String: Any] in
             ["songmid": candidate.songmid,
              "songID": candidate.songID.map(String.init) as Any? ?? NSNull(),
              "title": candidate.title, "artist": candidate.artist,
              "album": candidate.album, "duration": candidate.duration as Any]
         }]
    }

    static func search(sample: ProbeSample, session: URLSession) async throws -> HTTPResult? {
        var components = URLComponents(string: searchEndpoint)!
        components.queryItems = [
            URLQueryItem(name: "w", value: "\(sample.title) \(sample.artist)"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "n", value: "10"),
            URLQueryItem(name: "p", value: "1"),
            URLQueryItem(name: "new_json", value: "1")
        ]
        return try await get(components.url!, session: session, referer: nil)
    }

    static func fetchLyrics(songmid: String, session: URLSession) async -> [String: Any] {
        var components = URLComponents(string: lyricEndpoint)!
        components.queryItems = [
            URLQueryItem(name: "songmid", value: songmid),
            URLQueryItem(name: "g_tk", value: "5381"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "nobase64", value: "1")
        ]
        do {
            guard let fetched = try await get(components.url!, session: session,
                                               referer: "https://y.qq.com/portal/player.html") else {
                return ["request_ok": false, "classification": "request_failed",
                        "error": "no_http_response"]
            }
            var summary: [String: Any] = ["http_status": fetched.status,
                                          "content_type": fetched.contentType ?? "unknown",
                                          "response_bytes": fetched.data.count]
            switch QQMusicLyricEvaluator.evaluate(status: fetched.status, data: fetched.data) {
            case .failure(let failure):
                summary["request_ok"] = false
                summary["classification"] = "request_failed"
                summary["failure"] = failureDescription(failure)
                return summary
            case .noLyrics:
                summary["request_ok"] = true
                summary["classification"] = "no_lyrics"
                if let response = QQMusicLyricResponse(data: fetched.data) {
                    summary["retcode"] = response.retcode
                    summary["code"] = response.code
                    summary["subcode"] = response.subcode
                    summary["has_translation"] = response.translation != nil
                }
                return summary
            case .timedLRC(let lines, let metadata):
                summary["request_ok"] = true
                summary["classification"] = "timed_lrc"
                summary["line_count"] = lines.count
                summary["first_timestamp"] = lines.first?.start as Any
                summary["last_timestamp"] = lines.last?.start as Any
                summary["metadata_title"] = metadata.title as Any
                summary["metadata_artist"] = metadata.artist as Any
                if let response = QQMusicLyricResponse(data: fetched.data) {
                    summary["retcode"] = response.retcode
                    summary["code"] = response.code
                    summary["subcode"] = response.subcode
                    summary["has_translation"] = response.translation != nil
                }
                return summary
            case .plainText(let text):
                summary["request_ok"] = true
                summary["classification"] = "plain_text"
                summary["plain_line_count"] = text.split(separator: "\n").count
                return summary
            case .instrumental:
                summary["request_ok"] = true
                summary["classification"] = "instrumental"
                return summary
            }
        } catch {
            return ["request_ok": false, "classification": "request_failed",
                    "error": String(describing: error), "retry_count": 0]
        }
    }

    static func fetchQRCSummary(songID: Int64?, session: URLSession) async -> [String: Any] {
        guard let songID else {
            return ["request_ok": true, "status": "skipped", "reason": "missing_numeric_song_id"]
        }
        var request = URLRequest(url: URL(string: qrcEndpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("https://y.qq.com/", forHTTPHeaderField: "Referer")
        request.setValue("ValoraLyricsProbe/0.1", forHTTPHeaderField: "User-Agent")
        request.httpBody = Data("version=15&miniversion=82&lrctype=4&musicid=\(songID)".utf8)
        do {
            guard let fetched = try await perform(request, session: session) else {
                return ["request_ok": false, "status": "request_failed",
                        "error": "no_http_response"]
            }
            var summary: [String: Any] = ["http_status": fetched.status,
                                          "content_type": fetched.contentType ?? "unknown",
                                          "response_bytes": fetched.data.count,
                                          "decoded": false,
                                          "decryption": "not_implemented"]
            switch QQMusicQRCEvaluator.evaluate(status: fetched.status, data: fetched.data) {
            case .failure(let failure):
                summary["request_ok"] = false
                summary["status"] = "request_failed"
                summary["failure"] = failureDescription(failure)
            case .noContent(let result):
                summary["request_ok"] = true
                summary["status"] = "no_content"
                summary["result"] = result
            case .content(let characterCount, let looksLikeHex):
                summary["request_ok"] = true
                summary["status"] = "content_present"
                summary["result"] = "0"
                summary["content_present"] = true
                summary["content_characters"] = characterCount
                summary["looks_like_hex_cipher"] = looksLikeHex
                summary["reason"] = "QRC payload is encrypted; no byte timing was claimed."
            }
            return summary
        } catch {
            return ["request_ok": false, "status": "request_failed",
                    "error": String(describing: error), "retry_count": 0]
        }
    }

    static func get(_ url: URL, session: URLSession, referer: String?) async throws -> HTTPResult? {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("ValoraLyricsProbe/0.1", forHTTPHeaderField: "User-Agent")
        if let referer { request.setValue(referer, forHTTPHeaderField: "Referer") }
        return try await perform(request, session: session)
    }

    static func perform(_ request: URLRequest, session: URLSession) async throws -> HTTPResult? {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ProbeError(description: "non-http response")
        }
        return HTTPResult(status: http.statusCode, data: data,
                          contentType: http.value(forHTTPHeaderField: "Content-Type"))
    }

    static func failureDescription(_ failure: QQMusicResponseFailure) -> String {
        switch failure {
        case .httpStatus(let status): return "http_status_\(status)"
        case .apiCode(let code, let retcode, let subcode):
            return "api_code_\(code)_retcode_\(retcode.map(String.init) ?? "nil")_subcode_\(subcode.map(String.init) ?? "nil")"
        case .businessCode(let code): return "business_code_\(code)"
        case .invalidJSON: return "invalid_json"
        case .missingStructure: return "missing_structure"
        case .invalidPayload: return "invalid_payload"
        }
    }

    static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }
}

#if QQ_LYRICS_PROBE_MAIN
@main
struct QQMusicLyricsProbeMain {
    static func main() async { await QQMusicLyricsProbe.runFromCommandLine() }
}
#endif
