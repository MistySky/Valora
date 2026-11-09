import Combine
import Foundation
import XCTest
import ReferenceCore
@testable import Valora

/// Desktop idle first pass: a paused media tick and an unchanged connectivity
/// snapshot must not invalidate the views that observe `AppModel`. These tests
/// count real `@Published` emissions (the thing SwiftUI reacts to), not timer
/// callbacks, and keep the existing business behaviour under test.

// MARK: - Media

@MainActor
final class ManualMediaScheduler: MediaTickScheduling {
    final class Token: MediaTickToken {
        private(set) var running = true
        var isRunning: Bool { running }
        func cancel() { running = false }
    }

    private(set) var tokens: [(token: Token, action: @MainActor () -> Void)] = []

    func schedule(_ action: @escaping @MainActor () -> Void) -> any MediaTickToken {
        let token = Token()
        tokens.append((token, action))
        return token
    }

    var liveCount: Int { tokens.filter { $0.token.running }.count }

    /// Runs the live 0.25s action exactly as the timer would.
    func fire() {
        for item in tokens where item.token.running { item.action() }
    }
}

@MainActor
final class PushSystem: SystemMediaProviding {
    var onSnapshot: (@MainActor (SystemMediaSnapshot?) -> Void)?
    var onError: (@MainActor (String) -> Void)?
    var initial: SystemMediaSnapshot?
    private(set) var starts = 0
    private(set) var commands: [[String]] = []

    func start() {
        starts += 1
        if let initial { onSnapshot?(initial) }
    }

    func stop() {}

    func perform(_ arguments: [String], expected: SystemMediaSnapshot, requireSameTrack: Bool,
                 completion: @escaping @MainActor (Bool) -> Void) {
        commands.append(arguments)
        completion(true)
    }

    func push(_ snapshot: SystemMediaSnapshot?) { onSnapshot?(snapshot) }
    func fail(_ message: String) { onError?(message) }
}

@MainActor
final class DesktopIdleMediaPublishTests: XCTestCase {
    private func snapshot(playing: Bool, elapsed: Double, identity: String = "track") -> SystemMediaSnapshot {
        SystemMediaSnapshot([
            "bundleIdentifier": "com.test.player", "title": "Track", "artist": "Artist",
            "album": "Album", "durationMicros": 236_000_000,
            "elapsedTimeMicros": Int(elapsed * 1_000_000),
            "timestampEpochMicros": Date().timeIntervalSince1970 * 1_000_000,
            "playing": playing, "playbackRate": 1.0,
            "contentItemIdentifier": identity
        ])!
    }

    private func make(initial: SystemMediaSnapshot?)
        -> (model: AppModel, controller: MediaController, scheduler: ManualMediaScheduler,
            system: PushSystem, suite: String) {
        let suite = "com.wangqing.valora.desktop-idle-media.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(true, forKey: "enableNowPlaying")
        let settings = RevivalSettings(defaults: defaults)
        let model = AppModel(settings: settings)
        let scheduler = ManualMediaScheduler()
        let system = PushSystem()
        system.initial = initial
        let controller = MediaController(model, system: system, retryInterval: 0,
                                         tickScheduler: scheduler)
        return (model, controller, scheduler, system, suite)
    }

    func testPausedTickDoesNotRepublishTheSameElapsedValue() {
        let (model, controller, scheduler, _, suite) = make(initial: snapshot(playing: false, elapsed: 12))
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        withExtendedLifetime(model) {
            controller.start()
            XCTAssertFalse(model.playing)
            XCTAssertEqual(model.elapsed, 12, accuracy: 0.001)
            var publishes = 0
            var invalidations = 0
            let token = model.$elapsed.dropFirst().sink { _ in publishes += 1 }
            let invalidated = model.objectWillChange.sink { _ in invalidations += 1 }
            for _ in 0..<8 { scheduler.fire() }
            XCTAssertEqual(publishes, 0, "a paused tick must not invalidate views with an identical value")
            XCTAssertEqual(invalidations, 0, "no SwiftUI invalidation while the paused value is unchanged")
            XCTAssertEqual(model.elapsed, 12, accuracy: 0.001)
            XCTAssertEqual(scheduler.liveCount, 1, "the tick itself must keep running")
            token.cancel()
            invalidated.cancel()
            controller.stop()
        }
    }

    /// Batch 2 moved the continuous 4Hz sample to the visible-progress case;
    /// the collapsed notch keeps a 1Hz anchor and interpolates locally.
    func testCollapsedPlayingKeepsAOneHertzAnchorAndFreshLyricsClock() {
        let (model, controller, scheduler, _, suite) = make(initial: snapshot(playing: true, elapsed: 20))
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        withExtendedLifetime(model) {
            controller.start()
            XCTAssertTrue(model.playing)
            var values: [Double] = []
            let token = model.$elapsed.dropFirst().sink { values.append($0) }
            for _ in 0..<4 { scheduler.fire() }
            XCTAssertEqual(values.count, 1, "collapsed playback publishes one anchor per second")
            XCTAssertTrue(values.allSatisfy { $0 >= 20 })
            XCTAssertEqual(model.lyricsElapsed(at: Date()), model.elapsed, accuracy: 0.25,
                           "the anchor still yields the current lyric time")
            token.cancel()
            controller.stop()
        }
    }

    func testResumeFromPausePublishesTheNewAnchorImmediately() {
        let (model, controller, scheduler, system, suite) = make(initial: snapshot(playing: false, elapsed: 30))
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        withExtendedLifetime(model) {
            controller.start()
            scheduler.fire()
            XCTAssertEqual(model.elapsed, 30, accuracy: 0.001)
            system.push(snapshot(playing: true, elapsed: 30))
            XCTAssertTrue(model.playing)
            XCTAssertEqual(model.elapsed, 30, accuracy: 0.05,
                           "resume publishes the source anchor immediately, not on the next tick")
            // The collapsed surface then samples at 1Hz; four ticks publish once.
            var publishes = 0
            let token = model.$elapsed.dropFirst().sink { _ in publishes += 1 }
            for _ in 0..<4 { scheduler.fire() }
            XCTAssertEqual(publishes, 1)
            XCTAssertGreaterThanOrEqual(model.elapsed, 30)
            token.cancel()
            controller.stop()
        }
    }

    func testPausedSeekPublishesOnceThenStaysQuiet() {
        let (model, controller, scheduler, system, suite) = make(initial: snapshot(playing: false, elapsed: 12))
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        withExtendedLifetime(model) {
            controller.start()
            system.push(snapshot(playing: false, elapsed: 45))
            XCTAssertEqual(model.elapsed, 45, accuracy: 0.01, "the seek result still lands immediately")
            var publishes = 0
            let token = model.$elapsed.dropFirst().sink { _ in publishes += 1 }
            for _ in 0..<4 { scheduler.fire() }
            XCTAssertEqual(publishes, 0)
            XCTAssertEqual(model.elapsed, 45, accuracy: 0.01)
            token.cancel()
            controller.stop()
        }
    }

    func testTrackChangeWhilePausedPublishesTheNewPosition() {
        let (model, controller, scheduler, system, suite) = make(initial: snapshot(playing: false, elapsed: 0))
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        withExtendedLifetime(model) {
            controller.start()
            system.push(snapshot(playing: false, elapsed: 0, identity: "next-track"))
            XCTAssertEqual(model.mediaRevisionIdentity, "com.test.player\u{0}next-track")
            var publishes = 0
            let token = model.$elapsed.dropFirst().sink { _ in publishes += 1 }
            scheduler.fire()
            XCTAssertEqual(publishes, 0)
            token.cancel()
            controller.stop()
        }
    }

    func testStreamFailureAndReconnectKeepTheExistingRecoverySemantics() {
        let (model, controller, scheduler, system, suite) = make(initial: snapshot(playing: true, elapsed: 10))
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        withExtendedLifetime(model) {
            controller.start()
            system.fail("adapter died")
            XCTAssertEqual(model.title, "暂无播放")
            XCTAssertEqual(model.elapsed, 0, accuracy: 0.001)
            XCTAssertFalse(model.playing)
            var publishes = 0
            let token = model.$elapsed.dropFirst().sink { _ in publishes += 1 }
            for _ in 0..<3 { scheduler.fire() }
            XCTAssertEqual(publishes, 0, "no snapshot means nothing to publish")
            // The existing 1s refresh (every fourth tick) reconnects the dead
            // stream; that path must stay untouched.
            scheduler.fire()
            XCTAssertEqual(publishes, 1)
            XCTAssertGreaterThanOrEqual(system.starts, 2, "the periodic refresh restarts the stream")
            XCTAssertEqual(model.title, "Track")
            XCTAssertTrue(model.playing)
            let afterReconnect = publishes
            scheduler.fire()
            XCTAssertEqual(publishes, afterReconnect + 1, "the recovered stream publishes progress again")
            token.cancel()
            controller.stop()
        }
    }
}

// MARK: - Connectivity

@MainActor
private final class QuietSound: LowBatterySoundPlaying {
    private(set) var plays = 0
    func playLowBattery() { plays += 1 }
}

@MainActor
final class DesktopIdleConnectivityPublishTests: XCTestCase {
    private func model() -> AppModel {
        let suite = "com.wangqing.valora.desktop-idle-connectivity.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(true, forKey: "bluetoothEnabled")
        return AppModel(settings: RevivalSettings(defaults: defaults))
    }

    private func device(_ id: String, battery: Int? = 80, modelUID: String = "2014 4c") -> AudioDevice {
        AudioDevice(id: id, name: "AirPods \(id)", left: battery, right: battery,
                    single: nil, active: true, isAirPods: true, modelUID: modelUID)
    }

    func testIdenticalSnapshotDoesNotRepublishDevicesOrOutput() {
        let model = model()
        let controller = ConnectivityController(model, source: EmptyConnectivitySource(),
                                                sound: QuietSound())
        controller.start(polling: false)
        defer { controller.stop() }
        let snapshot = ConnectedAudioSnapshot(devices: [device("a")], output: "MacBook Speakers")
        controller.verificationApply(snapshot)

        var devicePublishes = 0
        var outputPublishes = 0
        var invalidations = 0
        let devices = model.$devices.dropFirst().sink { _ in devicePublishes += 1 }
        let output = model.$audioOutput.dropFirst().sink { _ in outputPublishes += 1 }
        let invalidated = model.objectWillChange.sink { _ in invalidations += 1 }
        controller.verificationApply(snapshot)
        controller.verificationApply(snapshot)
        controller.verificationApply(snapshot)
        XCTAssertEqual(devicePublishes, 0, "the 3s poll must not invalidate the device row with equal data")
        XCTAssertEqual(outputPublishes, 0)
        XCTAssertEqual(invalidations, 0, "no SwiftUI invalidation for an unchanged poll result")
        XCTAssertEqual(model.devices.map(\.id), ["a"], "the displayed data is still the latest snapshot")
        devices.cancel()
        output.cancel()
        invalidated.cancel()
    }

    func testChangedSnapshotPublishesImmediatelyAndStillShowsTheArrival() {
        let model = model()
        let controller = ConnectivityController(model, source: EmptyConnectivitySource(),
                                                sound: QuietSound())
        controller.start(polling: false)
        defer { controller.stop() }
        controller.verificationApply(ConnectedAudioSnapshot(devices: [device("a")], output: "out"))
        XCTAssertNil(model.connectionToast)

        var devicePublishes = 0
        let devices = model.$devices.dropFirst().sink { _ in devicePublishes += 1 }
        controller.verificationApply(ConnectedAudioSnapshot(devices: [device("a"), device("b")],
                                                            output: "out"))
        XCTAssertEqual(devicePublishes, 1)
        XCTAssertEqual(model.devices.map(\.id), ["a", "b"])
        XCTAssertEqual(model.connectionToast?.id, "b", "arrival detection is untouched")
        devices.cancel()
    }

    func testOutputChangePublishesOutputWithoutTouchingDevices() {
        let model = model()
        let controller = ConnectivityController(model, source: EmptyConnectivitySource(),
                                                sound: QuietSound())
        controller.start(polling: false)
        defer { controller.stop() }
        controller.verificationApply(ConnectedAudioSnapshot(devices: [device("a")], output: "Built-in"))

        var devicePublishes = 0
        var outputPublishes = 0
        let devices = model.$devices.dropFirst().sink { _ in devicePublishes += 1 }
        let output = model.$audioOutput.dropFirst().sink { _ in outputPublishes += 1 }
        controller.verificationApply(ConnectedAudioSnapshot(devices: [device("a")], output: "AirPods"))
        XCTAssertEqual(devicePublishes, 0)
        XCTAssertEqual(outputPublishes, 1)
        XCTAssertEqual(model.audioOutput, "AirPods")
        devices.cancel()
        output.cancel()
    }

    func testLowBatteryEdgeStillFiresAfterDeduplicatedSnapshots() {
        let model = model()
        let sound = QuietSound()
        let controller = ConnectivityController(model, source: EmptyConnectivitySource(), sound: sound)
        controller.start(polling: false)
        defer { controller.stop() }
        controller.verificationApply(ConnectedAudioSnapshot(devices: [device("a", battery: 80)],
                                                            output: "out"))
        controller.verificationApply(ConnectedAudioSnapshot(devices: [device("a", battery: 80)],
                                                            output: "out"))
        XCTAssertEqual(sound.plays, 0)
        controller.verificationApply(ConnectedAudioSnapshot(devices: [device("a", battery: 10)],
                                                            output: "out"))
        XCTAssertEqual(sound.plays, 1, "the threshold crossing is still detected on the fresh snapshot")
        controller.verificationApply(ConnectedAudioSnapshot(devices: [device("a", battery: 10)],
                                                            output: "out"))
        XCTAssertEqual(sound.plays, 1, "an unchanged reading must not repeat the alert")
    }

    func testDuplicateSnapshotDoesNotDisturbTheToastLifecycle() {
        let model = model()
        let controller = ConnectivityController(model, source: EmptyConnectivitySource(),
                                                sound: QuietSound())
        controller.start(polling: false)
        defer { controller.stop() }
        controller.verificationApply(ConnectedAudioSnapshot(devices: [device("a")], output: "out"))
        let arrival = ConnectedAudioSnapshot(devices: [device("a"), device("b")], output: "out")
        controller.verificationApply(arrival)
        let generation = model.connectionArrivalGeneration
        let toast = model.connectionToast
        controller.verificationApply(arrival)
        controller.verificationApply(arrival)
        XCTAssertEqual(model.connectionArrivalGeneration, generation,
                       "a duplicate poll neither replays nor extends the arrival")
        XCTAssertEqual(model.connectionToast, toast)
    }

    func testDisconnectStillClearsAfterDuplicates() {
        let model = model()
        let controller = ConnectivityController(model, source: EmptyConnectivitySource(),
                                                sound: QuietSound())
        controller.start(polling: false)
        defer { controller.stop() }
        let present = ConnectedAudioSnapshot(devices: [device("a"), device("b")], output: "out")
        controller.verificationApply(ConnectedAudioSnapshot(devices: [device("a")], output: "out"))
        controller.verificationApply(present)
        XCTAssertEqual(model.connectionToast?.id, "b")
        controller.verificationApply(present)

        var devicePublishes = 0
        let devices = model.$devices.dropFirst().sink { _ in devicePublishes += 1 }
        controller.verificationApply(ConnectedAudioSnapshot(devices: [], output: ""))
        XCTAssertEqual(devicePublishes, 1)
        XCTAssertTrue(model.devices.isEmpty, "disconnect cleanup still empties the row")
        XCTAssertNil(model.connectionToast, "the toast is still dismissed on disconnect")
        XCTAssertEqual(controller.verificationKnownIDs, [])
        devices.cancel()
    }

    func testLateMetadataStillPublishesAndUpdatesTheToast() {
        let model = model()
        let controller = ConnectivityController(model, source: EmptyConnectivitySource(),
                                                sound: QuietSound())
        controller.start(polling: false)
        defer { controller.stop() }
        controller.verificationApply(ConnectedAudioSnapshot(devices: [device("a")], output: "out"))
        var second = device("b", modelUID: "")
        second.isAirPods = false
        controller.verificationApply(ConnectedAudioSnapshot(devices: [device("a"), second], output: "out"))
        XCTAssertNil(model.connectionToast, "a generic early snapshot is not an arrival")

        var secondWithMetadata = second
        secondWithMetadata.modelUID = "2013 4c"
        secondWithMetadata.isAirPods = true
        controller.verificationApply(ConnectedAudioSnapshot(devices: [device("a"), secondWithMetadata],
                                                            output: "out"))
        XCTAssertEqual(model.devices.first { $0.id == "b" }?.airPodsModel, .airPods3)
        XCTAssertEqual(model.connectionToast?.movie, "airpods-3",
                       "late metadata still lands on the current row")
    }
}
