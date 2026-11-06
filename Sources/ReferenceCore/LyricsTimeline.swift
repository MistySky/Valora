import Foundation

public struct LyricsTrackIdentity: Hashable, Sendable, Equatable, Codable {
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

public struct LyricsRequest: Hashable, Sendable, Equatable, Codable {
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

public enum LyricsFetchResult: Sendable, Equatable, Codable {
    case timed(LyricTimeline)
    case wordTimed(LyricTimeline)
    case noLyrics
    case instrumental
    case unsynchronized
}

public enum LyricsFetchError: Error, Equatable, Sendable {
    case requestFailed
    case noMatch
    case invalidResponse
    case timedOut
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

public struct LyricTimeline: Sendable, Equatable, Codable {
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

    /// Progress within a line's real QRC words. Returns nil for plain LRC or
    /// before the line begins. Fraction is 0...1 for the current word only.
    public func wordProgress(in line: LyricLine, at time: TimeInterval) -> (index: Int, fraction: Double)? {
        guard !line.words.isEmpty, time.isFinite, time >= line.start else { return nil }
        var index: Int?
        for (offset, word) in line.words.enumerated() {
            guard word.start <= time else { break }
            index = offset
        }
        guard let index else { return nil }
        let word = line.words[index]
        let fraction: Double
        if word.duration > 0 {
            fraction = min(1, max(0, (time - word.start) / word.duration))
        } else {
            fraction = 0
        }
        return (index, fraction)
    }
}

/// Pure geometry for the real-word reading window. The view supplies measured
/// prefix/word widths; this helper only enforces the 65% right edge and the
/// 0...overflow clamp so the sentence tail is never pushed out artificially.
public enum LyricsLineLayout {
    public static func horizontalOffset(currentWordCenter: CGFloat,
                                        totalWidth: CGFloat,
                                        availableWidth: CGFloat) -> CGFloat {
        guard totalWidth > availableWidth, availableWidth > 0 else { return 0 }
        let target = max(0, currentWordCenter - availableWidth * 0.65)
        return min(target, max(0, totalWidth - availableWidth))
    }

    /// Continuous reading-window offset inside a word. Source QRC words can
    /// contain multiple characters; their fraction is still the only timing
    /// evidence, so the window follows that fraction rather than jumping at a
    /// word center.
    public static func followingOffset(prefixWidth: CGFloat, currentWordWidth: CGFloat,
                                       fraction: Double, totalWidth: CGFloat,
                                       availableWidth: CGFloat) -> CGFloat {
        let f = fraction.isFinite ? min(1, max(0, fraction)) : 0
        let center = max(0, prefixWidth) + max(0, currentWordWidth) * f
        return horizontalOffset(currentWordCenter: center, totalWidth: totalWidth,
                                availableWidth: availableWidth)
    }

    /// Line-only LRC fallback: one explainable reading-slide over the real
    /// line lifetime. It is not word timing and never drives colored fill.
    public static func lineOnlyOffset(progress: Double, totalWidth: CGFloat,
                                      availableWidth: CGFloat) -> CGFloat {
        guard totalWidth > availableWidth, availableWidth > 0 else { return 0 }
        let p = progress.isFinite ? min(1, max(0, progress)) : 0
        return (totalWidth - availableWidth) * p
    }

    public static func fillWidth(prefixWidth: CGFloat, currentWordWidth: CGFloat,
                                 fraction: Double, totalWidth: CGFloat) -> CGFloat {
        let f = fraction.isFinite ? min(1, max(0, fraction)) : 0
        return min(max(0, totalWidth), max(0, prefixWidth) + max(0, currentWordWidth) * f)
    }
}

/// Local interpolation anchor for the visible lyric row. It extrapolates from
/// the player's last real elapsed sample with the player's rate; it never uses
/// the network response time or an independent accumulating stopwatch.
public struct LyricsPlaybackClock: Sendable, Equatable {
    public let anchorElapsed: TimeInterval
    public let anchorDate: Date
    public let rate: Double
    public let playing: Bool

    public init(anchorElapsed: TimeInterval, anchorDate: Date,
                rate: Double, playing: Bool) {
        self.anchorElapsed = anchorElapsed
        self.anchorDate = anchorDate
        self.rate = rate
        self.playing = playing
    }

    public func elapsed(at date: Date) -> TimeInterval {
        guard playing, rate.isFinite, rate > 0 else { return anchorElapsed }
        return anchorElapsed + max(0, date.timeIntervalSince(anchorDate)) * rate
    }
}
