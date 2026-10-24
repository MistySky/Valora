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
    public init() {}
    public mutating func update(_ snapshot: SystemMediaSnapshot, at epoch: Double) {
        if let last, last.identity == snapshot.identity,
           last.elapsed == snapshot.elapsed, last.timestamp == snapshot.timestamp {
            anchorPosition = position(at: epoch)
        } else { anchorPosition = snapshot.position(at: epoch) }
        anchorEpoch = epoch; last = snapshot
    }
    public func position(at epoch: Double) -> Double {
        guard let last else { return 0 }
        return MediaProgressState.clamp(anchorPosition + max(0, epoch-anchorEpoch)*last.rate, duration:last.duration)
    }
}
