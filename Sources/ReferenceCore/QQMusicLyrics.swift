import Foundation

// V0010: pure QQ Music search / lyric parsing and conservative matching.
// No network code lives here so ordinary tests never depend on an online service.
// Protocol shape was checked against public responses; no third-party source was
// copied into this file.

public struct QQMusicSample: Sendable, Equatable {
    public let label: String
    public let title: String
    public let artist: String
    public let album: String
    public let duration: Double?

    public init(label: String = "", title: String, artist: String,
                album: String = "", duration: Double? = nil) {
        self.label = label
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
    }
}

public struct QQMusicCandidate: Sendable, Equatable {
    public let songmid: String
    public let songID: Int64?
    public let title: String
    public let artist: String
    public let album: String
    public let duration: Double?

    public init(songmid: String, songID: Int64? = nil, title: String,
                artist: String, album: String = "", duration: Double? = nil) {
        self.songmid = songmid
        self.songID = songID
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
    }
}

public enum QQMusicMatchFailure: String, Sendable, Equatable {
    case missingRequest
    case noCandidates
    case noTitleMatch
    case versionMismatch
    case artistMismatch
    case albumMismatch
    case durationMismatch
    case ambiguous
}

public enum QQMusicMatchResult: Sendable, Equatable {
    case matched(QQMusicCandidate)
    case noMatch(QQMusicMatchFailure)
}

/// Request/response failures are distinct from a valid no-lyrics or no-match
/// business outcome. The probe maps all cases before classifying content.
public enum QQMusicResponseFailure: Error, Equatable, Sendable {
    case httpStatus(Int)
    case apiCode(code: Int, retcode: Int?, subcode: Int?)
    case businessCode(String)
    case invalidJSON
    case missingStructure
    case invalidPayload
}

public enum QQMusicSearchEvaluation: Sendable, Equatable {
    case success([QQMusicCandidate])
    case failure(QQMusicResponseFailure)
}

public enum QQMusicSearchEvaluator {
    public static func evaluate(status: Int, data: Data) -> QQMusicSearchEvaluation {
        guard (200..<300).contains(status) else { return .failure(.httpStatus(status)) }
        do {
            return .success(try QQMusicSearchParser.parse(data))
        } catch let QQMusicSearchParseError.apiCode(code) {
            return .failure(.apiCode(code: code, retcode: nil, subcode: nil))
        } catch QQMusicSearchParseError.missingSongList {
            return .failure(.missingStructure)
        } catch QQMusicSearchParseError.missingCode {
            return .failure(.missingStructure)
        } catch {
            return .failure(.invalidJSON)
        }
    }
}

public enum QQMusicMatcher {
    public static let durationTolerance: Double = 3

    public static func match(_ request: QQMusicSample,
                             candidates: [QQMusicCandidate]) -> QQMusicMatchResult {
        guard !normalized(request.title).isEmpty, !normalized(request.artist).isEmpty else {
            return .noMatch(.missingRequest)
        }
        guard !candidates.isEmpty else { return .noMatch(.noCandidates) }

        let requestTitle = SplitTitle(request.title)
        let requestAlbum = normalized(request.album)

        let titleMatches = candidates.filter {
            let candidateTitle = SplitTitle($0.title)
            return candidateTitle.base == requestTitle.base
        }
        guard !titleMatches.isEmpty else { return .noMatch(.noTitleMatch) }

        let versionMatches = titleMatches.filter {
            SplitTitle($0.title).versionTags == requestTitle.versionTags
        }
        guard !versionMatches.isEmpty else { return .noMatch(.versionMismatch) }

        let requestArtists = artistComponents(request.artist)
        let artistMatches = versionMatches.filter {
            let candidateArtists = artistComponents($0.artist)
            return !requestArtists.isEmpty && requestArtists.isSubset(of: candidateArtists)
        }
        guard !artistMatches.isEmpty else { return .noMatch(.artistMismatch) }

        let albumMatches = artistMatches.filter { candidate in
            guard !requestAlbum.isEmpty else { return true }
            // A missing album is not evidence for a different release. Prefer
            // exact album agreement; otherwise reject rather than guess.
            return normalized(candidate.album) == requestAlbum
        }
        guard !albumMatches.isEmpty else { return .noMatch(.albumMismatch) }

        let durationMatches = albumMatches.filter { candidate in
            guard let requested = request.duration, let actual = candidate.duration,
                  requested.isFinite, actual.isFinite else { return true }
            return abs(requested - actual) <= durationTolerance
        }
        guard !durationMatches.isEmpty else { return .noMatch(.durationMismatch) }

        // Multiple equally valid candidates are not resolved by picking the first.
        guard durationMatches.count == 1, let match = durationMatches.first else {
            return .noMatch(.ambiguous)
        }
        guard !match.songmid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .noMatch(.noCandidates)
        }
        return .matched(match)
    }

    // MARK: - Conservative title/version handling

    private struct SplitTitle {
        let base: String
        let versionTags: Set<String>

        init(_ raw: String) {
            let split = Self.split(raw)
            base = normalized(split.base)
            var tags = Set(split.contents.map(normalized).filter { !$0.isEmpty })
            let baseLower = split.base.lowercased()
            for token in Self.knownVersionTokens where baseLower.contains(token) {
                tags.insert(token)
            }
            versionTags = tags
        }

        private static func split(_ raw: String) -> (base: String, contents: [String]) {
            var base = "", contents: [String] = []
            var depth = 0
            var current = ""
            let pairs: [Character: Character] = ["(": ")", "（": "）", "[": "]", "【": "】"]
            let closers = Set(pairs.values)
            for character in raw {
                if let close = pairs[character] {
                    if depth == 0 { current.removeAll(keepingCapacity: true) }
                    depth += 1
                    _ = close
                    continue
                }
                if closers.contains(character), depth > 0 {
                    depth -= 1
                    if depth == 0 {
                        contents.append(current)
                        current.removeAll(keepingCapacity: true)
                    }
                    continue
                }
                if depth > 0 { current.append(character) } else { base.append(character) }
            }
            if depth > 0, !current.isEmpty { base.append(current) }
            return (base, contents)
        }

        private static let knownVersionTokens: [String] = [
            "live", "现场", "演唱会", "remix", "混音", "伴奏", "instrumental",
            "纯音乐", "karaoke", "acoustic", "不插电", "demo", "片段", "剪辑",
            "cover", "翻唱", "女声", "男声"
        ]
    }

    /// QQ often reports a collaboration as "A / B" while system metadata only
    /// carries "A". Accept that incomplete request only when every requested
    /// artist appears in the candidate; the reverse direction is not enough.
    /// Version tags, album and duration still have to pass first.
    private static func artistComponents(_ raw: String) -> Set<String> {
        var pieces: [String] = []
        var current = ""
        let separators = CharacterSet(charactersIn: "/&,，、;；+")
        let lower = raw.lowercased()
        let featRange = lower.range(of: " feat.")
        let withoutFeat = featRange.map { String(raw[..<$0.lowerBound]) } ?? raw
        for scalar in withoutFeat.unicodeScalars {
            if separators.contains(scalar) {
                if !current.isEmpty { pieces.append(current); current.removeAll(keepingCapacity: true) }
            } else {
                current.unicodeScalars.append(scalar)
            }
        }
        if !current.isEmpty { pieces.append(current) }
        return Set(pieces.map(normalized).filter { !$0.isEmpty })
    }

    private static func normalized(_ raw: String) -> String {
        let folded = raw.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                                 locale: Locale(identifier: "en_US_POSIX"))
        var scalars = String.UnicodeScalarView()
        for scalar in folded.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                scalars.append(scalar)
            }
        }
        return String(scalars)
    }
}

public enum QQMusicSearchParseError: Error, Equatable, Sendable {
    case invalidJSON
    case apiCode(Int)
    case missingCode
    case missingSongList
}

public enum QQMusicSearchParser {
    public static func parse(_ data: Data) throws -> [QQMusicCandidate] {
        let jsonData = stripJSONP(data)
        guard let root = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            throw QQMusicSearchParseError.invalidJSON
        }
        guard let code = integer(root["code"]) else { throw QQMusicSearchParseError.missingCode }
        guard code == 0 else { throw QQMusicSearchParseError.apiCode(code) }
        guard let dataObject = root["data"] as? [String: Any],
              let songObject = dataObject["song"] as? [String: Any],
              let list = songObject["list"] as? [[String: Any]] else {
            throw QQMusicSearchParseError.missingSongList
        }
        return list.compactMap { item in
            let mid = string(item["mid"]) ?? string(item["songmid"]) ?? ""
            let title = string(item["title"]) ?? string(item["songname"]) ?? ""
            let albumObject = item["album"] as? [String: Any]
            let album = string(albumObject?["name"]) ?? string(item["albumname"]) ?? ""
            let singers = (item["singer"] as? [[String: Any]])?
                .compactMap { string($0["name"]) }
                .filter { !$0.isEmpty } ?? []
            let artist = singers.joined(separator: " / ")
            let id = integer64(item["id"]) ?? integer64(item["songid"])
            let duration = number(item["interval"]) ?? number(item["duration"])
            guard !title.isEmpty else { return nil }
            return QQMusicCandidate(songmid: mid, songID: id, title: title,
                                    artist: artist, album: album, duration: duration)
        }
    }

    private static func stripJSONP(_ data: Data) -> Data {
        guard let text = String(data: data, encoding: .utf8) else { return data }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.hasPrefix("{"), let first = text.firstIndex(of: "{"),
              let last = text.lastIndex(of: "}"), first <= last else { return data }
        return Data(text[first...last].utf8)
    }

    private static func string(_ value: Any?) -> String? {
        if let value = value as? String { return value }
        if let value = value as? NSNumber { return value.stringValue }
        return nil
    }

    private static func integer(_ value: Any?) -> Int? {
        (value as? NSNumber)?.intValue ?? Int(value as? String ?? "")
    }

    private static func integer64(_ value: Any?) -> Int64? {
        if let number = value as? NSNumber { return number.int64Value }
        if let string = value as? String { return Int64(string) }
        return nil
    }

    private static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }
}

public struct QQMusicLyricResponse: Sendable, Equatable {
    public let retcode: Int
    public let code: Int
    public let subcode: Int
    public let rawLyric: String?
    public let lyric: String?
    public let translation: String?

    public init?(data: Data) {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let retcode = (root["retcode"] as? NSNumber)?.intValue,
              let code = (root["code"] as? NSNumber)?.intValue else {
            return nil
        }
        self.retcode = retcode
        self.code = code
        subcode = (root["subcode"] as? NSNumber)?.intValue ?? 0
        rawLyric = (root["lyric"] as? String)
        lyric = Self.decodePayload(rawLyric)
        translation = Self.decodePayload(root["trans"] as? String)
    }

    /// QQ's endpoint returns base64 by default; `nobase64=1` returns plain LRC.
    /// Do not treat an arbitrary plain string as base64 unless it decodes to text
    /// that looks like a lyric document.
    private static func decodePayload(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("[") || trimmed.hasPrefix("{") {
            return trimmed
        }
        guard let decoded = Data(base64Encoded: trimmed, options: .ignoreUnknownCharacters),
              let text = String(data: decoded, encoding: .utf8),
              !text.isEmpty else { return trimmed }
        return text
    }
}

public enum QQMusicLyricEvaluation: Sendable, Equatable {
    case timedLRC(lines: [LyricLine], metadata: LyricMetadata)
    case plainText(String)
    case instrumental
    case noLyrics
    case failure(QQMusicResponseFailure)
}

public enum QQMusicLyricEvaluator {
    public static func evaluate(status: Int, data: Data) -> QQMusicLyricEvaluation {
        guard (200..<300).contains(status) else { return .failure(.httpStatus(status)) }
        guard let response = QQMusicLyricResponse(data: data) else {
            return .failure(.invalidJSON)
        }
        guard response.retcode == 0, response.code == 0 else {
            return .failure(.apiCode(code: response.code, retcode: response.retcode,
                                     subcode: response.subcode))
        }
        guard let raw = response.rawLyric?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return .noLyrics
        }
        guard let payload = response.lyric, !payload.isEmpty else {
            return .failure(.invalidPayload)
        }
        switch LRCParser.parse(payload) {
        case .timed(let lines, let metadata): return .timedLRC(lines: lines, metadata: metadata)
        case .plainText(let text): return .plainText(text)
        case .instrumental: return .instrumental
        case .empty: return .noLyrics
        }
    }
}

public enum QQMusicQRCEvaluation: Sendable, Equatable {
    case content(characterCount: Int, looksLikeHex: Bool)
    case noContent(result: String)
    case failure(QQMusicResponseFailure)
}

public enum QQMusicQRCEvaluator {
    public static func evaluate(status: Int, data: Data) -> QQMusicQRCEvaluation {
        guard (200..<300).contains(status) else { return .failure(.httpStatus(status)) }
        guard let body = String(data: data, encoding: .utf8) else {
            return .failure(.invalidPayload)
        }
        guard let result = tagValue("result", in: body) else {
            return .failure(.missingStructure)
        }
        if result == "-1" { return .noContent(result: result) }
        guard result == "0" else { return .failure(.businessCode(result)) }
        guard let content = contentCDATA(in: body) else {
            return .failure(.missingStructure)
        }
        let hex = content.unicodeScalars.allSatisfy {
            CharacterSet(charactersIn: "0123456789abcdefABCDEF").contains($0)
        }
        return .content(characterCount: content.count, looksLikeHex: hex)
    }

    private static func tagValue(_ tag: String, in body: String) -> String? {
        guard let start = body.range(of: "<\(tag)>"),
              let end = body.range(of: "</\(tag)>", range: start.upperBound..<body.endIndex) else {
            return nil
        }
        return String(body[start.upperBound..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func contentCDATA(in body: String) -> String? {
        guard let marker = body.range(of: "<content"),
              let open = body.range(of: ">", range: marker.upperBound..<body.endIndex),
              let start = body.range(of: "<![CDATA[", range: open.upperBound..<body.endIndex),
              let end = body.range(of: "]]></content>", range: start.upperBound..<body.endIndex) else {
            return nil
        }
        return String(body[start.upperBound..<end.lowerBound])
    }
}

public struct LyricWord: Sendable, Equatable, Codable {
    public let text: String
    public let start: TimeInterval
    public let duration: TimeInterval
    public init(text: String, start: TimeInterval, duration: TimeInterval) {
        self.text = text; self.start = start; self.duration = duration
    }
}

public struct LyricLine: Sendable, Equatable, Codable {
    public let start: TimeInterval
    public let text: String
    /// Empty for plain LRC. A non-empty array is real QRC word timing, never
    /// generated by evenly dividing a line.
    public let words: [LyricWord]
    public init(start: TimeInterval, text: String, words: [LyricWord] = []) {
        self.start = start
        self.text = text
        self.words = words
    }
}

public struct LyricMetadata: Sendable, Equatable {
    public var title: String?
    public var artist: String?
    public var album: String?
    public var offsetMilliseconds: Int
    public init(title: String? = nil, artist: String? = nil,
                album: String? = nil, offsetMilliseconds: Int = 0) {
        self.title = title; self.artist = artist; self.album = album
        self.offsetMilliseconds = offsetMilliseconds
    }
}

public enum ParsedLyrics: Sendable, Equatable {
    case timed(lines: [LyricLine], metadata: LyricMetadata)
    case plainText(String)
    case instrumental
    case empty
}

public enum LRCParser {
    public static func parse(_ raw: String) -> ParsedLyrics {
        var metadata = LyricMetadata()
        var timed: [LyricLine] = []
        var plainLines: [String] = []
        var sawLyricContent = false

        for rawLine in raw.replacingOccurrences(of: "\r\n", with: "\n")
                            .replacingOccurrences(of: "\r", with: "\n")
                            .split(separator: "\n", omittingEmptySubsequences: false) {
            var line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("\u{FEFF}") { line.removeFirst() }
            guard !line.isEmpty else { continue }

            var timestamps: [Double] = []
            var consumedTags = false
            while line.first == "[" {
                guard let close = line.firstIndex(of: "]") else { break }
                let content = String(line[line.index(after: line.startIndex)..<close])
                if let stamp = parseTimestamp(content) {
                    timestamps.append(stamp)
                    line = String(line[line.index(after: close)...])
                    consumedTags = true
                    continue
                }
                if parseMetadata(content, into: &metadata) {
                    line = String(line[line.index(after: close)...])
                    consumedTags = true
                    continue
                }
                break
            }

            let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !timestamps.isEmpty {
                if !text.isEmpty { sawLyricContent = true }
                for stamp in timestamps {
                    timed.append(LyricLine(start: stamp, text: text))
                }
                continue
            }
            if consumedTags { continue }
            if !text.isEmpty {
                sawLyricContent = true
                plainLines.append(text)
            }
        }

        if !timed.isEmpty {
            // Keep internal blank timestamps as interstitial markers, but trim
            // leading/trailing empty markers. A metadata-only/empty timed file
            // remains no-lyrics rather than a fake song line.
            guard let first = timed.firstIndex(where: { !$0.text.isEmpty }),
                  let last = timed.lastIndex(where: { !$0.text.isEmpty }) else {
                return .empty
            }
            let appliedOffset = Double(metadata.offsetMilliseconds) / 1000
            let adjusted = timed[first...last].map {
                LyricLine(start: max(0, $0.start + appliedOffset), text: $0.text)
            }
            return .timed(lines: adjusted, metadata: metadata)
        }
        guard sawLyricContent else { return .empty }
        let plain = plainLines.joined(separator: "\n")
        let lower = plain.lowercased()
        let instrumentalMarkers = ["纯音乐", "instrumental", "no lyrics", "暂无歌词"]
        if instrumentalMarkers.contains(where: { lower.contains($0) }) {
            return .instrumental
        }
        return .plainText(plain)
    }

    private static func parseMetadata(_ content: String, into metadata: inout LyricMetadata) -> Bool {
        guard let separator = content.firstIndex(of: ":") else { return false }
        let key = content[..<separator].trimmingCharacters(in: .whitespaces).lowercased()
        let value = content[content.index(after: separator)...].trimmingCharacters(in: .whitespaces)
        switch key {
        case "ti": metadata.title = value
        case "ar": metadata.artist = value
        case "al": metadata.album = value
        case "offset": metadata.offsetMilliseconds = Int(value) ?? 0
        default: return ["by", "re", "ve", "length"].contains(key)
        }
        return true
    }

    private static func parseTimestamp(_ content: String) -> Double? {
        let parts = content.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2 || parts.count == 3 else { return nil }
        guard let minutesOrHours = Double(parts[parts.count - 2]),
              let seconds = Double(parts[parts.count - 1]),
              minutesOrHours.isFinite, seconds.isFinite,
              minutesOrHours >= 0, seconds >= 0, seconds < 60 else { return nil }
        let hours = parts.count == 3 ? Double(parts[0]) ?? -1 : 0
        guard hours >= 0, hours.isFinite else { return nil }
        return hours * 3600 + minutesOrHours * 60 + seconds
    }
}

public struct QRCWord: Sendable, Equatable {
    public let text: String
    public let startMilliseconds: Int
    public let durationMilliseconds: Int
    public init(text: String, startMilliseconds: Int, durationMilliseconds: Int) {
        self.text = text; self.startMilliseconds = startMilliseconds
        self.durationMilliseconds = durationMilliseconds
    }
}

public struct QRCLine: Sendable, Equatable {
    public let startMilliseconds: Int
    public let durationMilliseconds: Int
    public let words: [QRCWord]
    public init(startMilliseconds: Int, durationMilliseconds: Int, words: [QRCWord]) {
        self.startMilliseconds = startMilliseconds; self.durationMilliseconds = durationMilliseconds
        self.words = words
    }
}

/// Parser for the public QRC text shape `[lineStart,lineDuration]word(start,duration)`.
/// Live encrypted QRC payloads are decrypted by `QQMusicQRC` before reaching
/// this parser; malformed or invented timing is still rejected.
public enum QRCParser {
    public static func parse(_ raw: String) -> [QRCLine] {
        var result: [QRCLine] = []
        for rawLine in raw.replacingOccurrences(of: "\r\n", with: "\n")
                            .replacingOccurrences(of: "\r", with: "\n")
                            .split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.hasPrefix("["), let close = line.firstIndex(of: "]") else { continue }
            let header = String(line[line.index(after: line.startIndex)..<close])
            let headerParts = header.split(separator: ",")
            guard headerParts.count == 2,
                  let lineStart = Int(headerParts[0]), let lineDuration = Int(headerParts[1]),
                  lineStart >= 0, lineDuration >= 0 else { continue }
            let body = String(line[line.index(after: close)...])
            var words: [QRCWord] = []
            var cursor = body.startIndex
            let pattern = try? NSRegularExpression(pattern: "\\((\\d+),(\\d+)\\)")
            let range = NSRange(body.startIndex..<body.endIndex, in: body)
            let matches = pattern?.matches(in: body, range: range) ?? []
            for match in matches {
                guard match.numberOfRanges == 3,
                      let textRange = Range(match.range(at: 0), in: body),
                      let startRange = Range(match.range(at: 1), in: body),
                      let durationRange = Range(match.range(at: 2), in: body),
                      let start = Int(body[startRange]), let duration = Int(body[durationRange]),
                      start >= 0, duration >= 0 else { continue }
                let text = String(body[cursor..<textRange.lowerBound])
                if !text.isEmpty {
                    words.append(QRCWord(text: text, startMilliseconds: start,
                                         durationMilliseconds: duration))
                }
                cursor = textRange.upperBound
            }
            // A tail without a timing marker is intentionally not turned into
            // a fake lineStart/0 word. Such a payload is not word-synced.
            if !words.isEmpty {
                result.append(QRCLine(startMilliseconds: lineStart,
                                      durationMilliseconds: lineDuration, words: words))
            }
        }
        return result
    }
}
