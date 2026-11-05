import XCTest
import Foundation
import ReferenceCore
@testable import Valora

/// V0095: lock-screen lyric demand. Fake provider only — no network, no real
/// track change, no lock, no real player control.
private final class RecordingLyricsProvider: LyricsProviding, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var requestedTitles: [String] = []
    /// Titles that should answer slowly, so a stale result can be observed.
    var slowTitles: Set<String> = []

    private func record(_ title: String) {
        lock.lock(); requestedTitles.append(title); lock.unlock()
    }

    var count: Int {
        lock.lock(); defer { lock.unlock() }
        return requestedTitles.count
    }

    func lyrics(for request: LyricsRequest) async throws -> LyricsFetchResult {
        record(request.title)
        if slowTitles.contains(request.title) {
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
        return .timed(LyricTimeline(lines: [LyricLine(start: 0, text: "line-\(request.title)")]))
    }
}

@MainActor
final class LockLyricsTrackChangeTests: XCTestCase {
    private func makeModel(showLyrics: Bool = true) -> (AppModel, RevivalSettings, String) {
        let suite = "com.wangqing.valora.lock-lyrics.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(["showLyrics": showLyrics], forKey: "referenceSettingsUI")
        let settings = RevivalSettings(defaults: defaults)
        let model = AppModel(settings: settings)
        model.title = "A"; model.artist = "Artist"; model.duration = 200
        model.elapsed = 1; model.playing = true
        return (model, settings, suite)
    }

    private func cleanup(_ suite: String) {
        UserDefaults().removePersistentDomain(forName: suite)
    }

    /// The reported bug: locked + track change used to clear the timeline and
    /// never request the new song because `showsMusicActivity` is false.
    func testLockedTrackChangeRequestsTheNewSongAndShowsLyrics() async {
        let (model, _, suite) = makeModel()
        defer { cleanup(suite) }
        let provider = RecordingLyricsProvider()
        let controller = LyricsController(model: model, provider: provider, budget: 2)
        controller.start()

        model.lockMusicCardVisible = true
        model.isSessionLocked = true            // desknotch surface is now false
        XCTAssertFalse(model.showsMusicActivity)
        try? await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(provider.requestedTitles, ["A"])
        XCTAssertNotNil(model.lyrics.timeline)

        model.title = "B"
        try? await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertEqual(provider.requestedTitles, ["A", "B"], "locked change must request B")
        XCTAssertEqual(model.lyrics.timeline?.lines.first?.text, "line-B")
        controller.cancel()
    }

    /// Crossing the lock both ways with the same song must not refetch or clear
    /// the loaded timeline.
    func testSameSongAcrossLockAndUnlockIsNotRefetched() async {
        let (model, _, suite) = makeModel()
        defer { cleanup(suite) }
        let provider = RecordingLyricsProvider()
        let controller = LyricsController(model: model, provider: provider, budget: 2)
        controller.start()
        model.lockMusicCardVisible = true
        model.isSessionLocked = true
        try? await Task.sleep(nanoseconds: 200_000_000)
        let first = model.lyrics.timeline

        model.lockMusicCardVisible = true        // stays visible while locked
        model.isSessionLocked = true
        try? await Task.sleep(nanoseconds: 120_000_000)
        model.isSessionLocked = false             // unlock, card hides
        model.lockMusicCardVisible = false
        try? await Task.sleep(nanoseconds: 120_000_000)
        XCTAssertEqual(provider.count, 1, "same track must not be requested again")
        XCTAssertEqual(model.lyrics.timeline, first, "valid timeline must survive the crossing")
        controller.cancel()
    }

    /// A hidden desktop surface must not suppress a visible lock card.
    func testHiddenNotchDoesNotCancelTheLockCardDemand() async {
        let (model, _, suite) = makeModel()
        defer { cleanup(suite) }
        let provider = RecordingLyricsProvider()
        let controller = LyricsController(model: model, provider: provider, budget: 2)
        controller.start()
        model.screenHidden = true
        model.lockMusicCardVisible = true
        model.isSessionLocked = true
        try? await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertEqual(provider.count, 1, "lock card keeps its demand while the desktop is hidden")
        XCTAssertNotNil(model.lyrics.timeline)
        controller.cancel()
    }

    /// When the lock card goes away and nothing else needs lyrics, new metadata
    /// must not start a request.
    func testHiddenCardStopsDemand() async {
        let (model, _, suite) = makeModel()
        defer { cleanup(suite) }
        let provider = RecordingLyricsProvider()
        let controller = LyricsController(model: model, provider: provider, budget: 2)
        controller.start()
        model.lockMusicCardVisible = true
        model.isSessionLocked = true
        try? await Task.sleep(nanoseconds: 200_000_000)
        let count = provider.count

        model.lockMusicCardVisible = false
        model.title = "C"
        try? await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertEqual(provider.count, count, "no surface → no new request")
        controller.cancel()
    }

    func testInterruptedLoadingResumesWhenSameLockCardReturns() async {
        let (model, _, suite) = makeModel()
        defer { cleanup(suite) }
        let provider = RecordingLyricsProvider()
        provider.slowTitles = ["A"]
        model.isSessionLocked = true
        model.lockMusicCardVisible = true
        let controller = LyricsController(model: model, provider: provider, budget: 2)
        defer { controller.cancel() }
        controller.start()
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(model.lyrics.status, .loading)
        model.lockMusicCardVisible = false
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertFalse(controller.verificationTaskIsActive)
        model.lockMusicCardVisible = true
        try? await Task.sleep(for: .milliseconds(450))
        XCTAssertEqual(model.lyrics.timeline?.lines.first?.text, "line-A",
                       "a cancelled load must be eligible again when the same card returns")
        XCTAssertEqual(provider.count, 2, "resume the cancelled load once, without refetching completed lyrics")
    }

    /// Fast A→B→C: only the latest result may be committed.
    func testFastTrackChangesCommitOnlyTheNewestResult() async {
        let (model, _, suite) = makeModel()
        defer { cleanup(suite) }
        let provider = RecordingLyricsProvider()
        provider.slowTitles = ["A", "B"]
        let controller = LyricsController(model: model, provider: provider, budget: 2)
        controller.start()
        model.lockMusicCardVisible = true
        model.isSessionLocked = true
        model.title = "B"
        try? await Task.sleep(nanoseconds: 30_000_000)
        model.title = "C"
        try? await Task.sleep(nanoseconds: 700_000_000)
        XCTAssertEqual(model.lyrics.timeline?.lines.first?.text, "line-C",
                       "only the newest identity may be committed")
        XCTAssertFalse(provider.requestedTitles.suffix(1).isEmpty)
        controller.cancel()
    }

    /// Turning the lyrics switch off clears state and stops requesting.
    func testLyricsSwitchOffClearsAndStops() async {
        let (model, settings, suite) = makeModel()
        defer { cleanup(suite) }
        let provider = RecordingLyricsProvider()
        let controller = LyricsController(model: model, provider: provider, budget: 2)
        controller.start()
        model.lockMusicCardVisible = true
        model.isSessionLocked = true
        try? await Task.sleep(nanoseconds: 200_000_000)
        settings.nowPlayingEnabled = false
        try? await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertNil(model.lyrics.timeline)
        let count = provider.count
        model.title = "D"
        try? await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(provider.count, count)
        controller.cancel()
    }

    /// Negative case: a timed-out load must not be treated as "interrupted".
    /// Repeated metadata ticks for the same song may not retry it.
    func testTimeoutDoesNotRetrySameTrackOnMetadataChurn() async {
        let (model, _, suite) = makeModel()
        defer { cleanup(suite) }
        let provider = RecordingLyricsProvider()
        provider.slowTitles = ["A"]
        let controller = LyricsController(model: model, provider: provider, budget: 0.05)
        defer { controller.cancel() }
        model.lockMusicCardVisible = true
        model.isSessionLocked = true
        controller.start()
        try? await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(model.lyrics.status, .unavailable, "deadline settles as failure")
        let count = provider.count
        for _ in 0..<4 {
            controller.mediaMetadataChanged()
            try? await Task.sleep(for: .milliseconds(60))
        }
        XCTAssertEqual(provider.count, count, "a timed-out track must not be retried automatically")
        XCTAssertEqual(model.lyrics.status, .unavailable)
    }
}
