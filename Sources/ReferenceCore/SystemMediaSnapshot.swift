import Foundation

/// Normalized full snapshot from the bundled adapter's --micros stream.
public struct SystemMediaSnapshot: Sendable {
    public let bundleIdentifier: String
    public let title: String
    public let artist: String
    public let album: String
    public let playing: Bool
    public let duration: Double
    public let elapsed: Double
    public let rate: Double
    public let timestamp: Double?
    public let artwork: Data?
    public let prohibitsSkip: Bool
    public let contentItemIdentifier: String
    public let identity: String
    /// Stable media-source revision supplied by the system payload. Falls back
    /// to the full identity for clients without contentItemIdentifier.
    public var revisionIdentity: String {
        contentItemIdentifier.isEmpty ? identity : bundleIdentifier + "\u{0}" + contentItemIdentifier
    }

    public init?(_ payload: [String: Any]) {
        guard let bundle = payload["bundleIdentifier"] as? String, !bundle.isEmpty,
              let title = payload["title"] as? String, !title.isEmpty else { return nil }
        bundleIdentifier = bundle; self.title = title
        artist = payload["artist"] as? String ?? ""; album = payload["album"] as? String ?? ""
        playing = payload["playing"] as? Bool ?? false
        func seconds(_ key: String) -> Double {
            let value = (payload[key] as? NSNumber)?.doubleValue ?? 0
            return value.isFinite ? max(0, value / 1_000_000) : 0
        }
        duration = seconds("durationMicros")
        elapsed = MediaProgressState.clamp(seconds("elapsedTimeMicros"), duration: duration)
        let rawRate = (payload["playbackRate"] as? NSNumber)?.doubleValue ?? 1
        rate = playing && rawRate.isFinite ? max(0, rawRate) : 0
        let rawTimestamp = (payload["timestampEpochMicros"] as? NSNumber)?.doubleValue
        timestamp = rawTimestamp.flatMap { $0.isFinite ? $0 / 1_000_000 : nil }
        artwork = (payload["artworkData"] as? String).flatMap { $0.count <= 12_000_000 ? Data(base64Encoded: $0) : nil }
        prohibitsSkip = payload["prohibitsSkip"] as? Bool ?? false
        contentItemIdentifier = payload["contentItemIdentifier"] as? String ?? ""
        // Some clients reuse IDs; text changes must also invalidate cover/seek state.
        identity = [bundle, contentItemIdentifier, title, artist, album].joined(separator: "\u{0}")
    }
    public func position(at epoch: Double) -> Double {
        let delta = timestamp.map { max(0, epoch - $0) } ?? 0
        return MediaProgressState.clamp(elapsed + delta * rate, duration: duration)
    }
}

/// QQ may publish playing=false without changing elapsed/timestamp. Preserve
/// the interpolated position across such state-only events instead of rewinding.
public struct SystemMediaTimeline: Sendable {
    public enum Purpose: Sendable {
        case playback, lyrics
    }

    private let purpose: Purpose
    private var last: SystemMediaSnapshot?
    private var anchorPosition = 0.0
    private var anchorEpoch = 0.0
    private var awaitingLyricTimeReport = false
    public private(set) var correctionHold: DateInterval?
    public init(for purpose: Purpose = .playback) {
        self.purpose = purpose
    }

    public enum SeekEvent: Sendable {
        case confirmed, restoreSource
    }

    public mutating func update(_ snapshot: SystemMediaSnapshot, at epoch: Double, seek: SeekEvent? = nil) {
        let previous = last
        let presented = position(at: epoch)
        let oldHold = correctionHold
        let source = snapshot.position(at: epoch)
        let date = Date(timeIntervalSince1970: epoch)
        last = snapshot
        // Some players assign a fresh item identifier to each time report
        // during a song. Only lyric timing may span such an identifier change.
        let rotatedLyricItem = purpose == .lyrics && previous.map {
            $0.contentItemIdentifier != snapshot.contentItemIdentifier
                && $0.bundleIdentifier == snapshot.bundleIdentifier && $0.title == snapshot.title
                && $0.artist == snapshot.artist && $0.album == snapshot.album
                && $0.duration == snapshot.duration
        } == true
        let sameItem = previous?.identity == snapshot.identity || rotatedLyricItem
        // A failed seek can fall back to the very same timeless report. Its
        // existing interpolated (or state-only paused) anchor is still valid.
        let reuseSameAnchor = seek == nil || (seek == .restoreSource && oldHold == nil && !awaitingLyricTimeReport)
        if reuseSameAnchor, let previous, sameItem,
           previous.elapsed == snapshot.elapsed, previous.timestamp == snapshot.timestamp {
            if previous.playing == snapshot.playing, previous.rate == snapshot.rate,
               previous.duration == snapshot.duration {
                return // Metadata-only packet. It must never extend an existing correction.
            }
            // A state-only pause/resume retains the position reached by the old rate.
            awaitingLyricTimeReport = false
            correctionHold = nil
            anchorPosition = presented
            anchorEpoch = epoch
            return
        }
        let hadUnconfirmedReport = awaitingLyricTimeReport
        awaitingLyricTimeReport = false
        anchorEpoch = epoch
        anchorPosition = source
        correctionHold = nil
        guard seek == nil, let previous, sameItem,
              previous.rate == 1, snapshot.rate == 1, previous.duration == snapshot.duration,
              previous.elapsed.rounded() == previous.elapsed, snapshot.elapsed.rounded() == snapshot.elapsed,
              snapshot.elapsed > previous.elapsed,
              let priorTime = previous.timestamp, let time = snapshot.timestamp,
              time > priorTime, time <= epoch else { return }

        // At 1x some sources report an advancing whole-second counter one
        // second behind, then catch up in the following packet. Keep drawing
        // normally for that packet. If it never arrives, briefly hold the
        // displayed position until the authoritative clock catches up.
        let lag = presented - source
        // Whole-second source counters lagged by up to 1.335 s across item
        // identifiers in the loop replay. A larger change remains authoritative.
        let maxLyricCorrection = 1.5
        let oneSecondLate = abs(lag - 1) <= 0.02
        if let oldHold, date < oldHold.end, lag > 0 {
            let start = max(oldHold.start, date)
            let remaining = oldHold.end.timeIntervalSince(start)
            let duration: TimeInterval
            if purpose == .lyrics && lag <= maxLyricCorrection {
                // A further advancing report can be late even after the hold
                // starts. Preserve its start and repay the new lag in place.
                duration = lag
            } else if lag <= remaining + 0.02 {
                duration = min(lag, remaining)
            } else {
                return
            }
            correctionHold = DateInterval(start: start, duration: duration)
            anchorPosition = source + duration
        } else if rotatedLyricItem && oneSecondLate && !hadUnconfirmedReport {
            // A replacement item can miss a whole counter tick. The next
            // independent report may arrive minutes later, back on the original
            // clock. A lone such reading is insufficient reason to stop a word.
            awaitingLyricTimeReport = true
            anchorPosition = presented
        } else if oneSecondLate || ((rotatedLyricItem || hadUnconfirmedReport) && lag > 0 && lag <= maxLyricCorrection) {
            correctionHold = DateInterval(start: date.addingTimeInterval(1.25), duration: lag)
            anchorPosition = presented
        }
    }
    public func position(at epoch: Double) -> Double {
        guard let last else { return 0 }
        let clock = LyricsPlaybackClock(anchorElapsed: anchorPosition, anchorDate: Date(timeIntervalSince1970: anchorEpoch),
                                       rate: last.rate, playing: last.playing, correctionHold: correctionHold)
        return MediaProgressState.clamp(clock.elapsed(at: Date(timeIntervalSince1970: epoch)), duration: last.duration)
    }
}
