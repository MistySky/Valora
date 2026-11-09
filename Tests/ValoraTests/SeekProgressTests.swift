import Combine
import Foundation
import XCTest
import ReferenceCore
@testable import Valora

/// Dragging the progress bar must keep the thumb where the user dropped it.
/// The adapter's pre-seek position can arrive after the seek command, so the
/// controller anchors the dragged position locally until the source confirms
/// it (or the command fails / the confirmation window expires).
@MainActor
final class SeekProgressTests: XCTestCase {
    private final class SeekSystem: SystemMediaProviding {
        var onSnapshot: (@MainActor (SystemMediaSnapshot?) -> Void)?
        var onError: (@MainActor (String) -> Void)?
        var initial: SystemMediaSnapshot?
        var commandResult = true
        var deferCompletion = false
        private(set) var commands: [[String]] = []
        private var pendingCompletions: [@MainActor (Bool) -> Void] = []

        func start() { if let initial { onSnapshot?(initial) } }
        func stop() {}
        func perform(_ arguments: [String], expected: SystemMediaSnapshot, requireSameTrack: Bool,
                     completion: @escaping @MainActor (Bool) -> Void) {
            commands.append(arguments)
            if deferCompletion {
                pendingCompletions.append(completion)
            } else {
                completion(commandResult)
            }
        }
        func push(_ snapshot: SystemMediaSnapshot?) { onSnapshot?(snapshot) }
        func finishPending(_ ok: Bool) {
            let list = pendingCompletions
            pendingCompletions = []
            for completion in list { completion(ok) }
        }
        func finishNextPending(_ ok: Bool) {
            guard !pendingCompletions.isEmpty else { return }
            pendingCompletions.removeFirst()(ok)
        }
    }

    private func snapshot(playing: Bool, elapsed: Double, identity: String = "track",
                          duration: Double = 236) -> SystemMediaSnapshot {
        SystemMediaSnapshot([
            "bundleIdentifier": "com.test.player", "title": "Track", "artist": "Artist",
            "album": "Album", "durationMicros": Int(duration * 1_000_000),
            "elapsedTimeMicros": Int(elapsed * 1_000_000),
            "timestampEpochMicros": Date().timeIntervalSince1970 * 1_000_000,
            "playing": playing, "playbackRate": 1.0,
            "contentItemIdentifier": identity
        ])!
    }

    private func make(playing: Bool = false, elapsed: Double = 30,
                      confirmationWindow: TimeInterval = 1.5)
        -> (model: AppModel, controller: MediaController, system: SeekSystem,
            scheduler: ManualMediaScheduler, suite: String) {
        let suite = "com.wangqing.valora.seek.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(true, forKey: "enableNowPlaying")
        let model = AppModel(settings: RevivalSettings(defaults: defaults))
        let system = SeekSystem()
        system.initial = snapshot(playing: playing, elapsed: elapsed)
        let scheduler = ManualMediaScheduler()
        let controller = MediaController(model, system: system, retryInterval: 0,
                                         tickScheduler: scheduler,
                                         seekConfirmationWindow: confirmationWindow)
        return (model, controller, system, scheduler, suite)
    }

    func testSeekShowsTheDroppedPositionImmediately() {
        let (model, controller, system, _, suite) = make()
        defer { controller.stop(); UserDefaults().removePersistentDomain(forName: suite) }
        withExtendedLifetime(model) {
            controller.start()
            XCTAssertEqual(model.elapsed, 30, accuracy: 0.01)
            controller.seek(90)
            XCTAssertEqual(model.elapsed, 90, accuracy: 0.001,
                           "the thumb must stay where the drag ended")
            XCTAssertEqual(system.commands, [["seek", "90000000"]])
        }
    }

    func testStaleSourcePositionDoesNotRewindTheThumb() {
        let (model, controller, system, _, suite) = make()
        defer { controller.stop(); UserDefaults().removePersistentDomain(forName: suite) }
        withExtendedLifetime(model) {
            controller.start()
            controller.seek(90)
            // A pre-seek update that was already in flight when the command ran.
            system.push(snapshot(playing: false, elapsed: 30.2))
            XCTAssertEqual(model.elapsed, 90, accuracy: 0.001,
                           "an in-flight pre-seek position must not rewind the bar")
            XCTAssertEqual(model.title, "Track", "metadata still flows")
        }
    }

    func testConfirmedSeekUsesTheSourcePosition() {
        let (model, controller, system, _, suite) = make()
        defer { controller.stop(); UserDefaults().removePersistentDomain(forName: suite) }
        withExtendedLifetime(model) {
            controller.start()
            controller.seek(90)
            system.push(snapshot(playing: false, elapsed: 90.4))
            XCTAssertEqual(model.elapsed, 90.4, accuracy: 0.05,
                           "the confirmation replaces the optimistic target")
            // Later positions are authoritative again.
            system.push(snapshot(playing: false, elapsed: 95))
            XCTAssertEqual(model.elapsed, 95, accuracy: 0.05)
        }
    }

    func testFailedSeekRestoresTheRealPosition() {
        let (model, controller, system, _, suite) = make()
        defer { controller.stop(); UserDefaults().removePersistentDomain(forName: suite) }
        withExtendedLifetime(model) {
            controller.start()
            system.deferCompletion = true
            controller.seek(90)
            XCTAssertEqual(model.elapsed, 90, accuracy: 0.001)
            system.finishPending(false)
            XCTAssertEqual(model.elapsed, 30, accuracy: 0.2,
                           "a rejected seek must return to the source position")
            XCTAssertNotNil(model.mediaError)
        }
    }

    func testTrackChangeDuringSeekDropsTheOptimisticTarget() {
        let (model, controller, system, _, suite) = make()
        defer { controller.stop(); UserDefaults().removePersistentDomain(forName: suite) }
        withExtendedLifetime(model) {
            controller.start()
            controller.seek(90)
            system.push(snapshot(playing: true, elapsed: 5, identity: "other"))
            XCTAssertEqual(model.elapsed, 5, accuracy: 0.05,
                           "a new track owns the position, not the pending seek")
        }
    }

    func testPlayingSeekKeepsAdvancingFromTheDroppedPosition() {
        let (model, controller, system, scheduler, suite) = make(playing: true, elapsed: 20)
        defer { controller.stop(); UserDefaults().removePersistentDomain(forName: suite) }
        withExtendedLifetime(model) {
            controller.start()
            controller.seek(100)
            XCTAssertEqual(model.elapsed, 100, accuracy: 0.001)
            system.push(snapshot(playing: true, elapsed: 21))   // stale pre-seek
            XCTAssertEqual(model.elapsed, 100, accuracy: 0.001)
            // Four ticks advance the local anchor while the seek is pending.
            for _ in 0..<4 { scheduler.fire() }
            XCTAssertGreaterThanOrEqual(model.elapsed, 100)
            XCTAssertLessThan(model.elapsed, 100.2, "progress continues from the drop point")
        }
    }

    func testSecondSeekReplacesTheFirstTargetAndIgnoresTheOldCompletion() {
        let (model, controller, system, _, suite) = make()
        defer { controller.stop(); UserDefaults().removePersistentDomain(forName: suite) }
        withExtendedLifetime(model) {
            controller.start()
            system.deferCompletion = true
            controller.seek(60)
            controller.seek(120)
            XCTAssertEqual(model.elapsed, 120, accuracy: 0.001)
            system.finishNextPending(false)   // completion of the first seek
            XCTAssertEqual(model.elapsed, 120, accuracy: 0.001,
                           "an old seek completion must not restore the old position")
        }
    }

    func testUnconfirmedSeekFallsBackToTheSourceAfterTheWindow() async {
        let (model, controller, _, scheduler, suite) = make(confirmationWindow: 0.2)
        defer { controller.stop(); UserDefaults().removePersistentDomain(forName: suite) }
        controller.start()
        controller.seek(90)
        XCTAssertEqual(model.elapsed, 90, accuracy: 0.001)
        try? await Task.sleep(for: .milliseconds(300))
        scheduler.fire()
        XCTAssertEqual(model.elapsed, 30, accuracy: 0.3,
                       "without confirmation the source position wins again")
        withExtendedLifetime(model) {}
    }
}
