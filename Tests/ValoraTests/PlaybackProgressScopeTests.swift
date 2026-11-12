import Combine
import XCTest
@testable import Valora
import ReferenceCore

@MainActor
final class PlaybackProgressScopeTests: XCTestCase {
    private var suite = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suite = "valora.progress.scope.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testProgressSnapshotPublishesConsistentPairWithoutAppModelInvalidation() {
        let settings = RevivalSettings(defaults: defaults)
        let model = AppModel(settings: settings)
        var snapshots: [PlaybackProgress.Snapshot] = []
        var appInvalidations = 0
        let progressToken = model.progress.$snapshot.dropFirst().sink { snapshots.append($0) }
        let appToken = model.objectWillChange.sink { appInvalidations += 1 }
        let sample = Date(timeIntervalSince1970: 1234)
        model.setElapsed(42.5, sampledAt: sample)
        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(snapshots[0].elapsed, 42.5)
        XCTAssertEqual(snapshots[0].sampledAt, sample)
        XCTAssertEqual(model.elapsed, 42.5)
        XCTAssertEqual(model.elapsedSampleDate, sample)
        XCTAssertEqual(appInvalidations, 0,
                       "a pure progress tick must not invalidate AppModel observers")
        progressToken.cancel()
        appToken.cancel()
    }

    func testIdenticalProgressDoesNotPublishAgain() {
        let progress = PlaybackProgress(elapsed: 10, sampledAt: Date(timeIntervalSince1970: 1))
        var count = 0
        let token = progress.$snapshot.dropFirst().sink { _ in count += 1 }
        let same = progress.snapshot.sampledAt
        progress.set(10, sampledAt: same)
        XCTAssertEqual(count, 0)
        progress.set(10, sampledAt: same.addingTimeInterval(0.25))
        XCTAssertEqual(count, 1)
        token.cancel()
    }

    func testMarqueeMeasurementCacheReusesCompleteInputsAndEvicts() {
        let cache = MarqueeMeasurementCache.shared
        cache.resetForTesting()
        let a = MarqueeLabel.measure("A title", size: 13.5, weight: .semibold)
        let b = MarqueeLabel.measure("A title", size: 13.5, weight: .semibold)
        XCTAssertEqual(a, b)
        XCTAssertEqual(cache.hits, 1)
        XCTAssertEqual(cache.misses, 1)

        _ = MarqueeLabel.measure("A title", size: 13, weight: .semibold)
        _ = MarqueeLabel.measure("A title", size: 13.5, weight: .medium)
        XCTAssertEqual(cache.misses, 3, "size and weight are part of the key")

        for index in 0..<(MarqueeMeasurementCache.capacity + 4) {
            _ = MarqueeLabel.measure("evict-\(index)", size: 13, weight: .medium)
        }
        XCTAssertLessThanOrEqual(cache.count, MarqueeMeasurementCache.capacity)
        cache.resetForTesting()
    }
}
