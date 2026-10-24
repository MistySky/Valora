import Foundation

public struct LyricsTrackIdentity: Hashable, Sendable, Equatable {
    public let title: String
    public let artist: String
    public let album: String
    public let durationSeconds: Int

    public init(title: String, artist: String, album: String, duration: Double) {
        self.title = title
        self.artist = artist
        self.album = album
        durationSeconds = duration.isFinite && duration > 0 ? Int(duration.rounded()) : 0
    }
}

public struct LyricsRequest: Hashable, Sendable, Equatable {
    public let identity: LyricsTrackIdentity
    public let title: String
    public let artist: String
    public let album: String
    public let duration: Double

    public init(identity: LyricsTrackIdentity, title: String, artist: String,
                album: String, duration: Double) {
        self.identity = identity
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
    }

    public init(title: String, artist: String, album: String, duration: Double) {
        self.init(identity: LyricsTrackIdentity(title: title, artist: artist, album: album,
                                               duration: duration),
                  title: title, artist: artist, album: album, duration: duration)
    }
}

public enum LyricsFetchResult: Sendable, Equatable {
    case timed(LyricTimeline)
    case noLyrics
    case instrumental
    case unsynchronized
}

public enum LyricsFetchError: Error, Equatable, Sendable {
    case requestFailed
    case noMatch
    case invalidResponse
}

public enum LyricsDisplayStatus: String, Sendable, Equatable {
    case idle
    case loading
    case ready
    case noLyrics
    case instrumental
    case unsynchronized
    case unavailable
}

public struct LyricsDisplayState: Sendable, Equatable {
    public var status: LyricsDisplayStatus
    public var timeline: LyricTimeline?
    public var identity: LyricsTrackIdentity?

    public init(status: LyricsDisplayStatus = .idle, timeline: LyricTimeline? = nil,
                identity: LyricsTrackIdentity? = nil) {
        self.status = status
        self.timeline = timeline
        self.identity = identity
    }

    public var isLoading: Bool { status == .loading }
    public var hasTimedLyrics: Bool { status == .ready && timeline != nil }
}

public struct LyricTimeline: Sendable, Equatable {
    public let lines: [LyricLine]

    public init(lines: [LyricLine]) {
        // LRC files may contain multiple timestamps out of source order. Sort by
        // time with the original index as a stable tie breaker; never average
        // text into invented word timing.
        self.lines = lines.enumerated()
            .sorted {
                if $0.element.start == $1.element.start { return $0.offset < $1.offset }
                return $0.element.start < $1.element.start
            }
            .map(\.element)
    }

    /// Returns the last line at or before the supplied playback time. A line
    /// with empty text is a real interstitial marker and intentionally clears
    /// the previous line instead of being skipped.
    public func line(at time: TimeInterval) -> LyricLine? {
        guard time.isFinite, !lines.isEmpty else { return nil }
        var current: LyricLine?
        for line in lines {
            guard line.start <= time else { break }
            current = line
        }
        return current
    }

    public func index(at time: TimeInterval) -> Int? {
        guard time.isFinite else { return nil }
        var index: Int?
        for (offset, line) in lines.enumerated() {
            guard line.start <= time else { break }
            index = offset
        }
        return index
    }
}
