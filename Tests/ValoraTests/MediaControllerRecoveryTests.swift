import XCTest
@testable import Valora
import ReferenceCore

@MainActor
final class MediaControllerRecoveryTests: XCTestCase {
    private var suite = ""
    private var defaults: UserDefaults!
    private var settings: RevivalSettings!
    private var model: AppModel!
    private var fake: FakeSystemMediaSource!
    private var controller: MediaController!

    override func setUp() {
        super.setUp()
        suite = "com.wangqing.valora.media-recovery.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        settings = RevivalSettings(defaults: defaults)
        model = AppModel(settings: settings)
        fake = FakeSystemMediaSource()
    }

    override func tearDown() {
        controller?.stop()
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    private func makeController(retryInterval: TimeInterval = 0) {
        controller = MediaController(model, system: fake, retryInterval: retryInterval)
    }

    private func snapshot(title: String = "Track", duration: Double = 236) -> SystemMediaSnapshot {
        SystemMediaSnapshot([
            "bundleIdentifier": "com.test.player",
            "title": title,
            "artist": "Artist",
            "album": "Album",
            "durationMicros": duration * 1_000_000,
            "elapsedTimeMicros": 74_000_000,
            "timestampEpochMicros": Date().timeIntervalSince1970 * 1_000_000,
            "playing": true,
            "playbackRate": 1,
            "contentItemIdentifier": "track-" + title
        ])!
    }

    func testInitialStartFailureRecoversThroughExistingRefresh() {
        makeController()
        fake.failStarts = 1
        controller.start()
        XCTAssertEqual(fake.startCount, 1)
        XCTAssertEqual(model.title, "暂无播放")
        XCTAssertNotNil(model.mediaError)

        fake.snapshot = snapshot()
        controller.refresh()
        XCTAssertEqual(fake.startCount, 2)
        XCTAssertEqual(model.title, "Track")
        XCTAssertTrue(model.mediaCanControl)
        XCTAssertNil(model.mediaError)
    }

    func testRunningStreamExitRecoversThroughExistingRefresh() {
        makeController()
        fake.snapshot = snapshot(title: "Before")
        controller.start()
        XCTAssertEqual(model.title, "Before")

        fake.exitStream()
        XCTAssertEqual(model.title, "暂无播放")
        XCTAssertNotNil(model.mediaError)

        fake.snapshot = snapshot(title: "After")
        controller.refresh()
        XCTAssertEqual(fake.startCount, 2)
        XCTAssertEqual(model.title, "After")
        XCTAssertTrue(model.mediaCanControl)
    }

    func testFailureRetryIsRateLimitedAndNotAReentrantLoop() {
        makeController(retryInterval: 60)
        fake.failStarts = 1
        controller.start()
        XCTAssertEqual(fake.startCount, 1)

        for _ in 0..<100 { controller.refresh() }
        XCTAssertEqual(fake.startCount, 1, "failed start must not be retried in a tight loop")

        fake.snapshot = snapshot()
        for _ in 0..<100 { controller.refresh() }
        XCTAssertEqual(fake.startCount, 1, "backoff must also prevent parallel recovery attempts")
    }

    func testRepeatedRefreshDoesNotStartDuplicateAdapters() {
        makeController()
        fake.snapshot = snapshot()
        controller.start()
        XCTAssertEqual(fake.startCount, 1)

        for _ in 0..<100 { controller.refresh() }
        XCTAssertEqual(fake.startCount, 1)
        XCTAssertEqual(fake.doubleStarts, 0)

        fake.exitStream()
        for _ in 0..<100 { controller.refresh() } // retryInterval=0: first may restart once
        XCTAssertEqual(fake.startCount, 2)
        XCTAssertEqual(fake.doubleStarts, 0)
    }

    func testStopPreventsFurtherReconnects() {
        makeController()
        fake.snapshot = snapshot()
        controller.start()
        let started = fake.startCount
        controller.stop()

        for _ in 0..<20 { controller.refresh() }
        XCTAssertEqual(fake.startCount, started)
        XCTAssertEqual(fake.doubleStarts, 0)
    }

    func testDisablePreventsReconnectAndDoesNotLoseSourceStop() {
        makeController()
        fake.snapshot = snapshot()
        controller.start()
        let started = fake.startCount

        model.settings.nowPlayingEnabled = false
        for _ in 0..<20 { controller.refresh() }
        XCTAssertEqual(fake.startCount, started)
        XCTAssertFalse(model.settings.nowPlayingEnabled)
    }

    func testPlaybackCommandsUseSingleSharedFakePlayer() {
        makeController()
        fake.snapshot = snapshot()
        controller.start()
        model.media = controller
        XCTAssertTrue(model.mediaCanControl)
        model.media.command(2)
        model.media.command(4)
        model.media.command(5)
        XCTAssertEqual(fake.performances.suffix(3), [
            ["send", "2"], ["send", "4"], ["send", "5"]
        ])
    }

    func testNormalSeekKeepsClampAndTruncationSemantics() {
        makeController()
        fake.snapshot = snapshot()
        controller.start()

        controller.seek(74.5)
        XCTAssertEqual(fake.performances.last, ["seek", "74500000"])
        controller.seek(1.0000009)
        XCTAssertEqual(fake.performances.last, ["seek", "1000000"])
        controller.seek(-3)
        XCTAssertEqual(fake.performances.last, ["seek", "0"])
        controller.seek(1e300) // clamped to the valid 236 s duration
        XCTAssertEqual(fake.performances.last, ["seek", "236000000"])
    }

    func testSeekRejectsUnrepresentableAndInvalidValuesWithoutCallingRunner() {
        makeController()
        fake.snapshot = snapshot()
        controller.start()
        let before = fake.performances.count

        model.duration = 1e308
        model.mediaCanSeek = true
        controller.seek(1e300)
        XCTAssertEqual(fake.performances.count, before)

        model.duration = 236
        controller.seek(.nan)
        controller.seek(.infinity)
        controller.seek(-.infinity)
        XCTAssertEqual(fake.performances.count, before)

        model.duration = Double(Int64.max) / 1_000_000
        controller.seek(model.duration)
        XCTAssertEqual(fake.performances.count, before)

        model.duration = Double(Int64.max / 2) / 1_000_000
        controller.seek(model.duration)
        XCTAssertEqual(fake.performances.count, before + 1)
        XCTAssertNotNil(Int64(fake.performances.last?.last ?? ""))
    }

    func testSeekMicrosBoundariesAreSafe() {
        XCTAssertEqual(MediaController.seekMicros(74.5), 74_500_000)
        XCTAssertEqual(MediaController.seekMicros(1.0000009), 1_000_000)
        XCTAssertEqual(MediaController.seekMicros(0), 0)
        XCTAssertNil(MediaController.seekMicros(-1))
        XCTAssertNil(MediaController.seekMicros(.nan))
        XCTAssertNil(MediaController.seekMicros(.infinity))
        XCTAssertNil(MediaController.seekMicros(-.infinity))
        XCTAssertNil(MediaController.seekMicros(.greatestFiniteMagnitude))
        XCTAssertNil(MediaController.seekMicros(Double(Int64.max) / 1_000_000))
        XCTAssertNotNil(MediaController.seekMicros(Double(Int64.max / 2) / 1_000_000))
    }
}

@MainActor
private final class FakeSystemMediaSource: SystemMediaProviding {
    var onSnapshot: (@MainActor (SystemMediaSnapshot?) -> Void)?
    var onError: (@MainActor (String) -> Void)?

    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var doubleStarts = 0
    private(set) var performances: [[String]] = []
    var failStarts = 0
    var snapshot: SystemMediaSnapshot?
    private var running = false

    func start() {
        startCount += 1
        if running { doubleStarts += 1 }
        if failStarts > 0 {
            failStarts -= 1
            running = false
            onError?("fake start failure")
            return
        }
        running = true
        if let snapshot { onSnapshot?(snapshot) }
    }

    func stop() {
        stopCount += 1
        running = false
    }

    func exitStream() {
        running = false
        onError?("fake stream exit")
    }

    func perform(_ arguments: [String], expected: SystemMediaSnapshot, requireSameTrack: Bool,
                 completion: @escaping @MainActor (Bool) -> Void) {
        performances.append(arguments)
        completion(true)
    }
}
