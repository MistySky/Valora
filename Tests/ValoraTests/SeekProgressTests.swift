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
                          duration: Double = 236,
                          timestamp: Double = Date().timeIntervalSince1970) -> SystemMediaSnapshot {
        SystemMediaSnapshot([
            "bundleIdentifier": "com.test.player", "title": "Track", "artist": "Artist",
            "album": "Album", "durationMicros": Int(duration * 1_000_000),
            "elapsedTimeMicros": Int(elapsed * 1_000_000),
            "timestampEpochMicros": timestamp * 1_000_000,
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

    func testSeekTimeoutAndNewTrackWhileDisplaysSleep() async throws {
        let (model, controller, system, scheduler, suite) = make(confirmationWindow: 0.1)
        defer { controller.stop(); UserDefaults().removePersistentDomain(forName: suite) }
        controller.setAllDisplaysAsleep(true)
        controller.start()
        controller.seek(90)
        XCTAssertEqual(model.elapsed, 90, accuracy: 0.001)
        try await Task.sleep(for: .milliseconds(150))
        scheduler.fire()
        XCTAssertEqual(model.elapsed, 30, accuracy: 0.01)

        system.push(snapshot(playing: true, elapsed: 12, identity: "next"))
        XCTAssertTrue(model.playing)
        let playing = model.progress.snapshot
        XCTAssertEqual(playing.elapsed, 12, accuracy: 0.1)
        scheduler.fire()
        XCTAssertEqual(model.progress.snapshot, playing)
        system.push(snapshot(playing: false, elapsed: 15, identity: "next"))
        XCTAssertFalse(model.playing)
        controller.setAllDisplaysAsleep(false)
        XCTAssertEqual(model.elapsed, 15, accuracy: 0.001)
    }

    func testExplicitIntegerSecondSeekConfirmationBypassesClockCorrection() {
        let (model, controller, system, _, suite) = make(playing: true)
        defer { controller.stop(); UserDefaults().removePersistentDomain(forName: suite) }
        let epoch = Date().timeIntervalSince1970 - 0.03
        system.initial = snapshot(playing: true, elapsed: 70, timestamp: epoch - 55)
        controller.start()
        system.push(snapshot(playing: true, elapsed: 124, timestamp: epoch))
        XCTAssertNotNil(model.progress.snapshot.correctionHold)
        XCTAssertGreaterThanOrEqual(model.elapsed, 125)

        controller.seek(124)
        XCTAssertEqual(model.elapsed, 124)
        XCTAssertNil(model.progress.snapshot.correctionHold)
        let confirmation = snapshot(playing: true, elapsed: 124, timestamp: epoch)
        system.push(confirmation)
        XCTAssertEqual(model.elapsed, confirmation.position(at: model.elapsedSampleDate.timeIntervalSince1970), accuracy: 0.001)
        XCTAssertNil(model.progress.snapshot.correctionHold)
    }

    func testLyricCorrectionSurvivesPeriodicSamplesButNotAnExplicitSeek() throws {
        let (model, controller, system, scheduler, suite) = make()
        defer { controller.stop(); UserDefaults().removePersistentDomain(forName: suite) }
        let stamp = Date().timeIntervalSince1970 - 0.05
        system.initial = snapshot(playing: true, elapsed: 19, identity: "a", timestamp: stamp - 63.335)
        controller.start()
        let late = snapshot(playing: true, elapsed: 81, identity: "b", timestamp: stamp)
        system.push(late)
        let hold = try XCTUnwrap(model.progress.snapshot.lyrics.correctionHold)
        for _ in 0..<4 { scheduler.fire() }
        let sample = model.progress.snapshot
        XCTAssertNil(sample.correctionHold)
        XCTAssertEqual(sample.lyrics.correctionHold, hold)
        XCTAssertEqual(sample.elapsed, late.position(at: sample.sampledAt.timeIntervalSince1970), accuracy: 0.00001)
        XCTAssertEqual(model.lyricsElapsed(at: sample.sampledAt), sample.elapsed + 1.335, accuracy: 0.00001)

        controller.seek(80.5)
        XCTAssertEqual(model.progress.snapshot.lyrics.elapsed, 80.5)
        XCTAssertNil(model.progress.snapshot.lyrics.correctionHold)
        system.push(snapshot(playing: true, elapsed: 80.5, identity: "b"))
        XCTAssertEqual(model.progress.snapshot.lyrics.elapsed, model.elapsed)
        XCTAssertNil(model.progress.snapshot.lyrics.correctionHold)
    }

    func testFailedSeekAndLostMediaClearTheLyricCorrection() throws {
        let (model, controller, system, _, suite) = make()
        defer { controller.stop(); UserDefaults().removePersistentDomain(forName: suite) }
        let stamp = Date().timeIntervalSince1970 - 0.05
        system.initial = snapshot(playing: true, elapsed: 0, identity: "a", timestamp: stamp - 5.335)
        controller.start()
        system.push(snapshot(playing: true, elapsed: 4, identity: "b", timestamp: stamp))
        _ = try XCTUnwrap(model.progress.snapshot.lyrics.correctionHold)

        system.deferCompletion = true
        controller.seek(40)
        XCTAssertEqual(model.progress.snapshot.lyrics.elapsed, 40)
        system.finishPending(false)
        XCTAssertEqual(model.progress.snapshot.lyrics.elapsed, model.elapsed)
        XCTAssertNil(model.progress.snapshot.lyrics.correctionHold)
        system.push(nil)
        XCTAssertEqual(model.progress.snapshot.lyrics.elapsed, 0)
        system.push(snapshot(playing: true, elapsed: 4, identity: "c", timestamp: stamp))
        XCTAssertNil(model.progress.snapshot.lyrics.correctionHold)
        XCTAssertEqual(model.progress.snapshot.lyrics.elapsed, model.elapsed)
    }
}
