import XCTest
import Foundation
import ReferenceCore
@testable import Valora

private struct IndependentNoncooperativeLyrics: LyricsProviding {
    func lyrics(for request: LyricsRequest) async throws -> LyricsFetchResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.6) {
                continuation.resume(returning: .timed(LyricTimeline(lines: [
                    LyricLine(start: 0, text: "late")
                ])))
            }
        }
    }
}

@MainActor
final class IndependentLyricsDeadlineTests: XCTestCase {
    func testImmediateCancellationDoesNotRetainController() async {
        let suite = "com.wangqing.valora.independent-immediate-cancel.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(["showLyrics": true], forKey: "referenceSettingsUI")
        let settings = RevivalSettings(defaults: defaults)
        let model = AppModel(settings: settings)
        model.title = "Track"; model.artist = "Artist"
        model.duration = 200; model.elapsed = 1; model.playing = true
        var controller: LyricsController? = LyricsController(
            model: model, provider: IndependentNoncooperativeLyrics(), budget: 0.05)
        weak var releasedController = controller
        controller?.start()
        controller?.cancel()
        // Keep the owner alive while its already-cancelled task enters the
        // cancellation handler; then drop the owner after the race attaches.
        try? await Task.sleep(nanoseconds: 20_000_000)
        controller = nil
        try? await Task.sleep(nanoseconds: 850_000_000)
        XCTAssertNil(releasedController,
                     "cancel before deadline continuation attaches must not strand the controller")
    }

    func testDeadlineSettlesWithoutWaitingForNoncooperativeProvider() async {
        let suite = "com.wangqing.valora.independent-deadline.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(["showLyrics": true], forKey: "referenceSettingsUI")
        let settings = RevivalSettings(defaults: defaults)
        let model = AppModel(settings: settings)
        model.title = "Track"; model.artist = "Artist"
        model.duration = 200; model.elapsed = 1; model.playing = true
        let controller = LyricsController(model: model,
                                         provider: IndependentNoncooperativeLyrics(),
                                         budget: 0.05)
        controller.start()
        try? await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(model.lyrics.status, .unavailable,
                       "deadline must settle even when a provider ignores cancellation")
        XCTAssertFalse(model.showsCompactLyrics)
        try? await Task.sleep(nanoseconds: 550_000_000)
        XCTAssertEqual(model.lyrics.status, .unavailable)
        controller.cancel()
    }
}
