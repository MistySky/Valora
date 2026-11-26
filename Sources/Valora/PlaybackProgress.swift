import Combine
import Foundation

/// High-frequency playback anchor kept separate from `AppModel`'s broad
/// observable state. A single snapshot publishes elapsed and the matching
/// wall-clock sample together, so no subscriber can observe a torn pair.
@MainActor
final class PlaybackProgress: ObservableObject {
    struct Snapshot: Equatable, Sendable {
        var elapsed: Double
        var sampledAt: Date
        var correctionHold: DateInterval?
    }

    @Published private(set) var snapshot: Snapshot

    init(elapsed: Double = 0, sampledAt: Date = Date()) {
        snapshot = Snapshot(elapsed: elapsed, sampledAt: sampledAt)
    }

    var elapsed: Double { snapshot.elapsed }
    var sampledAt: Date { snapshot.sampledAt }

    func set(_ elapsed: Double, sampledAt: Date, correctionHold: DateInterval? = nil) {
        let next = Snapshot(elapsed: elapsed, sampledAt: sampledAt, correctionHold: correctionHold)
        guard next != snapshot else { return }
        snapshot = next
    }
}
