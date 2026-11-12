import AppKit
import Combine
import XCTest
import ReferenceCore
@testable import Valora

@MainActor
final class MediaNotificationDedupTests: XCTestCase {
    private func snapshot(elapsed: Double = 12, playing: Bool = true,
                          title: String = "Track", revision: String = "one",
                          prohibitsSkip: Bool = false) -> SystemMediaSnapshot {
        SystemMediaSnapshot([
            "bundleIdentifier": "com.test.player", "title": title,
            "artist": "Artist", "album": "Album", "durationMicros": 200_000_000,
            "elapsedTimeMicros": elapsed * 1_000_000, "playing": playing,
            "playbackRate": 1.0, "contentItemIdentifier": revision,
            "prohibitsSkip": prohibitsSkip
        ])!
    }

    private func withController(_ body: (AppModel, MediaController, PushSystem) -> Void) {
        let suite = "com.wangqing.valora.media-dedup.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(true, forKey: "enableNowPlaying")
        let model = AppModel(settings: RevivalSettings(defaults: defaults))
        let source = PushSystem()
        source.initial = snapshot()
        let controller = MediaController(model, system: source, tickScheduler: ManualMediaScheduler())
        controller.start()
        defer {
            controller.stop()
            defaults.removePersistentDomain(forName: suite)
        }
        withExtendedLifetime(model) { body(model, controller, source) }
    }

    func testProgressOnlySnapshotDoesNotRepublishMetadataButKeepsFreshAnchorAndRouting() {
        withController { model, _, source in
            var publications = 0
            let token = Publishers.MergeMany(
                model.$title.dropFirst().map { _ in () }.eraseToAnyPublisher(),
                model.$artist.dropFirst().map { _ in () }.eraseToAnyPublisher(),
                model.$album.dropFirst().map { _ in () }.eraseToAnyPublisher(),
                model.$playing.dropFirst().map { _ in () }.eraseToAnyPublisher(),
                model.$playbackRate.dropFirst().map { _ in () }.eraseToAnyPublisher(),
                model.$duration.dropFirst().map { _ in () }.eraseToAnyPublisher(),
                model.$source.dropFirst().map { _ in () }.eraseToAnyPublisher(),
                model.$mediaBundleIdentifier.dropFirst().map { _ in () }.eraseToAnyPublisher(),
                model.$mediaRevisionIdentity.dropFirst().map { _ in () }.eraseToAnyPublisher(),
                model.$mediaCanSeek.dropFirst().map { _ in () }.eraseToAnyPublisher(),
                model.$mediaCanSkip.dropFirst().map { _ in () }.eraseToAnyPublisher(),
                model.$mediaCanControl.dropFirst().map { _ in () }.eraseToAnyPublisher(),
                model.$mediaError.dropFirst().map { _ in () }.eraseToAnyPublisher()
            ).sink { publications += 1 }
            var anchors = 0
            let progress = model.progress.$snapshot.dropFirst().sink { _ in anchors += 1 }
            var routes = 0
            model.trackChangedHandler = { _ in routes += 1 }
            source.push(snapshot(elapsed: 48))
            XCTAssertEqual(publications, 0)
            XCTAssertEqual(anchors, 1)
            XCTAssertEqual(model.elapsed, 48, accuracy: 0.01)
            XCTAssertEqual(routes, 1, "preserve multi-display/peek routing even on a progress event")
            token.cancel(); progress.cancel()
        }
    }

    func testSourceCorrectsOptimisticModelEvenWhenItsPreviousSnapshotWasIdentical() {
        withController { model, controller, source in
            controller.command(2)
            XCTAssertFalse(model.playing)
            source.push(snapshot())
            XCTAssertTrue(model.playing, "compare against live model, not only the previous source snapshot")
            XCTAssertEqual(model.playbackRate, 1)
        }
    }

    func testRealMetadataCapabilitiesRevisionAndPauseStillPublishImmediately() {
        withController { model, _, source in
            var titles: [String] = []
            let token = model.$title.dropFirst().sink { titles.append($0) }
            source.push(snapshot(elapsed: 7, playing: false, title: "Next", revision: "two", prohibitsSkip: true))
            XCTAssertEqual(titles, ["Next"])
            XCTAssertEqual(model.title, "Next")
            XCTAssertFalse(model.playing)
            XCTAssertEqual(model.playbackRate, 0)
            XCTAssertFalse(model.mediaCanSkip)
            XCTAssertEqual(model.mediaRevisionIdentity, "com.test.player\u{0}two")
            XCTAssertEqual(model.elapsed, 7, accuracy: 0.01)
            token.cancel()
        }
    }

    func testTrackingAreaIsReusedUntilGeometryChangesAndRecoversAfterExternalRemoval() {
        let suite = "com.wangqing.valora.tracking-dedup.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = RevivalSettings(defaults: defaults)
        let model = AppModel(settings: settings)
        let host = EdgeHostingView(rootView: NotchView(model: model, settings: settings))
        host.frame = CGRect(x: 0, y: 0, width: 624, height: 320)
        host.trackingSize = CGSize(width: 180, height: 32)
        host.updateTrackingAreas()
        let first = host.trackingAreas.first { $0.owner === host && $0.rect.width == 180 }
        XCTAssertNotNil(first)
        host.updateTrackingAreas()
        XCTAssertTrue(host.trackingAreas.contains { $0 === first })
        host.trackingSize = CGSize(width: 240, height: 64)
        host.updateTrackingAreas()
        XCTAssertFalse(host.trackingAreas.contains { $0 === first })
        let second = host.trackingAreas.first { $0.owner === host && $0.rect.width == 240 }
        XCTAssertNotNil(second)
        if let second { host.removeTrackingArea(second) }
        host.updateTrackingAreas()
        XCTAssertTrue(host.trackingAreas.contains { $0.owner === host && $0.rect.width == 240 })
        host.trackingSize = .zero
        host.updateTrackingAreas()
        XCTAssertFalse(host.trackingAreas.contains { $0.owner === host && $0.rect.width == 240 })
    }
}
