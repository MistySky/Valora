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
    private var last: SystemMediaSnapshot?
    private var anchorPosition = 0.0
    private var anchorEpoch = 0.0
    public private(set) var correctionHold: DateInterval?
    public init() {}

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
        // A failed seek can fall back to the very same timeless report. Its
        // existing interpolated (or state-only paused) anchor is still valid.
        let reuseSameAnchor = seek == nil || (seek == .restoreSource && oldHold == nil)
        if reuseSameAnchor, let previous, previous.identity == snapshot.identity,
           previous.elapsed == snapshot.elapsed, previous.timestamp == snapshot.timestamp {
            if previous.playing == snapshot.playing, previous.rate == snapshot.rate,
               previous.duration == snapshot.duration {
                return // Metadata-only packet. It must never extend an existing correction.
            }
            // A state-only pause/resume retains the position reached by the old rate.
            correctionHold = nil
            anchorPosition = presented
            anchorEpoch = epoch
            return
        }
        anchorEpoch = epoch
        anchorPosition = source
        correctionHold = nil
        guard seek == nil, let previous, previous.identity == snapshot.identity,
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
        if let oldHold, date < oldHold.end, lag > 0 {
            let start = max(oldHold.start, date)
            let remaining = oldHold.end.timeIntervalSince(start)
            guard lag <= remaining + 0.02 else { return }
            let duration = min(lag, remaining)
            correctionHold = DateInterval(start: start, duration: duration)
            anchorPosition = source + duration
        } else if abs(lag - 1) <= 0.02 {
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
