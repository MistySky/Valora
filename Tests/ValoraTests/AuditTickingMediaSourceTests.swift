import Foundation
import XCTest
import ReferenceCore
@testable import Valora

/// V0106-R1 targeted logic: the fake anchor actually advances through the real
/// MediaController, and the two display-link gap definitions stay separate.
@MainActor
final class AuditTickingMediaSourceTests: XCTestCase {
    func testSnapshotUsesInjectedClockForElapsedAndTimestamp() {
        var clock = 100.0
        let source = AuditTickingMediaSource(now: { clock })
        source.configure(baseElapsed: 2, playing: true, artworkPNG: nil)
        XCTAssertEqual(source.currentElapsed(), 2, accuracy: 0.001)

        clock = 105
        XCTAssertEqual(source.currentElapsed(), 7, accuracy: 0.001)
        let snapshot = source.snapshot()
        XCTAssertEqual(snapshot.elapsed, 7, accuracy: 0.001)
        XCTAssertEqual(snapshot.timestamp ?? -1, 105, accuracy: 0.001)
        XCTAssertEqual(snapshot.rate, 1, accuracy: 0.001)

        source.setPlaying(false)
        clock = 110
        XCTAssertEqual(source.currentElapsed(), 7, accuracy: 0.001,
                       "paused fixture must freeze elapsed")

        source.seek(to: 6)
        XCTAssertEqual(source.currentElapsed(), 6, accuracy: 0.001)

        source.changeTrack(id: "next", title: "next", artist: "artist", artworkPNG: nil)
        XCTAssertEqual(source.currentElapsed(), 0, accuracy: 0.001)
    }

    func testMediaControllerAdvancesAnchorAndLyricsFromFakeSnapshot() async {
        let suite = "com.wangqing.valora.audit-anchor.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        var values = defaults.dictionary(forKey: "referenceSettingsUI") ?? [:]
        values["showLyrics"] = true
        defaults.set(values, forKey: "referenceSettingsUI")
        let settings = RevivalSettings(defaults: defaults)
        settings.nowPlayingEnabled = true
        settings.reloadPreferences()
        let model = AppModel(settings: settings)
        let source = AuditTickingMediaSource()
        source.configure(baseElapsed: 5, playing: true, artworkPNG: nil)
        let media = MediaController(model, system: source, retryInterval: 0)
        model.media = media
        let lyrics = LyricsController(model: model,
                                      provider: AuditLyricsProvider(result: .wordTimed(FluidityFixtures.timeline())))
        model.lyricsController = lyrics
        lyrics.start()
        media.start()
        defer { media.stop(); lyrics.cancel() }

        for _ in 0..<100 where model.lyrics.status != .ready {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        for _ in 0..<50 where model.elapsed < 5 {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertGreaterThanOrEqual(model.elapsed, 5, "fake snapshot must seed the playback anchor")
        XCTAssertEqual(model.duration, 240, accuracy: 0.001)

        try? await Task.sleep(nanoseconds: 700_000_000)
        source.publish()
        XCTAssertGreaterThan(model.elapsed, 5.4, "the anchor must advance with wall time")

        source.seek(to: 21)
        try? await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(model.currentLyricLine?.text, "第二句短句",
                       "fixture seek must select the later lyric line")

        source.setPlaying(false)
        try? await Task.sleep(nanoseconds: 400_000_000)
        let frozen = model.elapsed
        try? await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertEqual(model.elapsed, frozen, accuracy: 0.02,
                       "paused fixture must not keep advancing")
    }

    func testGapStatsKeepTimestampAndArrivalSeparate() {
        var stats = BaselineGapStats()
        stats.record(timestampGap: 0.008, arrivalGap: 0.012)
        stats.record(timestampGap: 0.010, arrivalGap: 0.020)
        let summary = stats.summary
        XCTAssertEqual(summary["timestampMaxGap"] as? Double ?? -1, 0.010, accuracy: 0.0001)
        XCTAssertEqual(summary["arrivalMaxGap"] as? Double ?? -1, 0.020, accuracy: 0.0001)
        XCTAssertNotEqual(summary["timestampMaxGap"] as? Double,
                          summary["arrivalMaxGap"] as? Double,
                          "arrival latency must not be reported as the display timestamp gap")
        XCTAssertEqual(summary["callbacks"] as? Int, 3)
        let definitions = summary["definitions"] as? [String: String]
        XCTAssertNotNil(definitions?["timestampGap"])
        XCTAssertNotNil(definitions?["arrivalGap"])
    }

    func testEmptyGapStatsAreZeroNotNaN() {
        let summary = BaselineGapStats().summary
        XCTAssertEqual(summary["callbacks"] as? Int, 0)
        XCTAssertEqual(summary["arrivalRateHz"] as? Double ?? -1, 0, accuracy: 0.0001)
    }
}
