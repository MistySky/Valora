import XCTest
@testable import Valora
import ReferenceCore

@MainActor
final class MediaResponsivenessTests: XCTestCase {
    private final class SlowSource: SystemMediaProviding {
        var onSnapshot: (@MainActor (SystemMediaSnapshot?) -> Void)?
        var onError: (@MainActor (String) -> Void)?
        var snapshot: SystemMediaSnapshot?
        private(set) var commands: [[String]] = []
        func start() { if let snapshot { onSnapshot?(snapshot) } }
        func stop() {}
        func perform(_ arguments: [String], expected: SystemMediaSnapshot,
                     requireSameTrack: Bool,
                     completion: @escaping @MainActor (Bool) -> Void) {
            commands.append(arguments)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { completion(true) }
        }
    }

    private func snapshot() -> SystemMediaSnapshot {
        SystemMediaSnapshot([
            "bundleIdentifier": "com.test.player", "title": "Track", "artist": "Artist",
            "album": "Album", "durationMicros": 236_000_000,
            "elapsedTimeMicros": 74_000_000,
            "timestampEpochMicros": Date().timeIntervalSince1970 * 1_000_000,
            "playing": true, "playbackRate": 1.0, "contentItemIdentifier": "track"
        ])!
    }

    func testPlayPauseFeedbackDoesNotWaitForSlowSystemCommand() async {
        let suite = "com.wangqing.valora.media-response.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = RevivalSettings(defaults: defaults)
        let model = AppModel(settings: settings)
        let source = SlowSource()
        source.snapshot = snapshot()
        let controller = MediaController(model, system: source)
        controller.start()
        defer { controller.stop() }
        XCTAssertTrue(model.playing)
        let started = Date()
        controller.command(2)
        let elapsed = Date().timeIntervalSince(started)
        XCTAssertLessThan(elapsed, 0.1, "button feedback must not wait for adapter I/O")
        XCTAssertFalse(model.playing)
        try? await Task.sleep(for: .milliseconds(380))
        XCTAssertFalse(model.playing)
        XCTAssertEqual(source.commands, [["send", "2"]])
    }
}
