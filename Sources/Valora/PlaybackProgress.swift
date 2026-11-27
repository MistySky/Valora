import Combine
import Foundation

/// High-frequency playback anchor kept separate from `AppModel`'s broad
/// observable state. A single snapshot publishes elapsed and the matching
/// wall-clock sample together, so no subscriber can observe a torn pair.
@MainActor
final class PlaybackProgress: ObservableObject {
    struct LyricsAnchor: Equatable, Sendable {
        let elapsed: Double
        let correctionHold: DateInterval?
    }

    struct Snapshot: Equatable, Sendable {
        let elapsed: Double
        let sampledAt: Date
        let correctionHold: DateInterval?
        let lyrics: LyricsAnchor

        init(elapsed: Double, sampledAt: Date, correctionHold: DateInterval? = nil,
             lyrics: LyricsAnchor? = nil) {
            self.elapsed = elapsed
            self.sampledAt = sampledAt
            self.correctionHold = correctionHold
            self.lyrics = lyrics ?? LyricsAnchor(elapsed: elapsed, correctionHold: correctionHold)
        }
    }

    @Published private(set) var snapshot: Snapshot

    init(elapsed: Double = 0, sampledAt: Date = Date()) {
        snapshot = Snapshot(elapsed: elapsed, sampledAt: sampledAt)
    }

    var elapsed: Double { snapshot.elapsed }
    var sampledAt: Date { snapshot.sampledAt }

    func set(_ elapsed: Double, sampledAt: Date, correctionHold: DateInterval? = nil,
             lyrics: LyricsAnchor? = nil) {
        let next = Snapshot(elapsed: elapsed, sampledAt: sampledAt, correctionHold: correctionHold, lyrics: lyrics)
        guard next != snapshot else { return }
        snapshot = next
    }
}
