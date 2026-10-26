import XCTest
@testable import Valora

@MainActor
final class MusicSourceActivationTests: XCTestCase {
    func testActivationTracksLatestSourceWithoutSendingMediaCommands() {
        let suite = "com.wangqing.valora.source-activation.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(settings: RevivalSettings(defaults: defaults))
        model.title = "Track"
        var activations: [String] = []
        model.openMediaSourceAction = { activations.append($0) }
        model.mediaBundleIdentifier = "com.test.first"
        model.openCurrentMediaSource()
        model.mediaBundleIdentifier = "com.test.second"
        model.openCurrentMediaSource()
        XCTAssertEqual(activations, ["com.test.first", "com.test.second"])
        // No media controller is installed: opening a source must not invoke one.
        XCTAssertNil(model.media)
    }

    func testPreviewMissingSourceAndDisabledMusicDoNotActivateApplications() {
        let suite = "com.wangqing.valora.source-activation-guards.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = RevivalSettings(defaults: defaults)
        let model = AppModel(settings: settings)
        model.openMediaSourceAction = { _ in XCTFail("invalid source must not activate") }
        model.title = "Track"
        model.openCurrentMediaSource()
        model.mediaBundleIdentifier = "com.test.player"
        model.previewMode = true
        model.openCurrentMediaSource()
        model.previewMode = false
        settings.nowPlayingEnabled = false
        model.openCurrentMediaSource()
        settings.nowPlayingEnabled = true
        model.title = "暂无播放"
        model.openCurrentMediaSource()
    }
}
