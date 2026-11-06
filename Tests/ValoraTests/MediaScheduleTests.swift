import XCTest
import Foundation
import ReferenceCore
@testable import Valora

/// V0099: the 0.25s playback anchor must only exist while the music module is
/// enabled. Fake scheduler + fake source; no real player, no wall-clock waits.
@MainActor
final class MediaScheduleTests: XCTestCase {
    final class FakeScheduler: MediaTickScheduling {
        final class Token: MediaTickToken {
            private(set) var running = true
            var isRunning: Bool { running }
            func cancel() { running = false }
        }
        private(set) var tokens: [Token] = []
        var liveCount: Int { tokens.filter(\.isRunning).count }
        func schedule(_ action: @escaping @MainActor () -> Void) -> any MediaTickToken {
            let token = Token()
            tokens.append(token)
            return token
        }
    }

    final class FakeSystem: SystemMediaProviding {
        var onSnapshot: (@MainActor (SystemMediaSnapshot?) -> Void)?
        var onError: (@MainActor (String) -> Void)?
        private(set) var starts = 0
        private(set) var stops = 0
        func start() { starts += 1 }
        func stop() { stops += 1 }
        func perform(_ arguments: [String], expected: SystemMediaSnapshot, requireSameTrack: Bool,
                     completion: @escaping @MainActor (Bool) -> Void) { completion(false) }
    }

    private func make(enabled: Bool) -> (AppModel, RevivalSettings, MediaController, FakeScheduler, FakeSystem, String) {
        let suite = "com.wangqing.valora.media-schedule.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(enabled, forKey: "enableNowPlaying")
        let settings = RevivalSettings(defaults: defaults)
        let model = AppModel(settings: settings)
        let scheduler = FakeScheduler()
        let system = FakeSystem()
        let controller = MediaController(model, system: system, retryInterval: 0, tickScheduler: scheduler)
        return (model, settings, controller, scheduler, system, suite)
    }

    func testDisabledStartSchedulesNoTickAndNoSource() {
        // The controller holds the model unowned, so the test must keep it alive.
        let (model, _, controller, scheduler, system, suite) = make(enabled: false)
        withExtendedLifetime(model) {
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        controller.start()
        XCTAssertEqual(scheduler.liveCount, 0, "disabled music must not keep a 4Hz timer")
        XCTAssertEqual(system.starts, 0)
        controller.stop()
        }
    }

    func testEnablingStartsExactlyOneTickAndDisablingCancelsIt() {
        let (model, settings, controller, scheduler, system, suite) = make(enabled: false)
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        withExtendedLifetime(model) {
        controller.start()
        settings.nowPlayingEnabled = true
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertEqual(scheduler.liveCount, 1)
        XCTAssertGreaterThanOrEqual(system.starts, 1)

        settings.nowPlayingEnabled = false
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertEqual(scheduler.liveCount, 0, "turning music off must cancel the tick")
        XCTAssertGreaterThanOrEqual(system.stops, 1)
        XCTAssertEqual(model.title, "暂无播放", "state is cleared on disable")

        settings.nowPlayingEnabled = true
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertEqual(scheduler.liveCount, 1, "re-enabling restores exactly one tick")
        XCTAssertEqual(scheduler.tokens.count, 2, "no stacking: one token per enable")
        controller.stop()
        }
    }

    func testRepeatedStartDoesNotStackTicks() {
        let (model, _, controller, scheduler, _, suite) = make(enabled: true)
        withExtendedLifetime(model) {
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        controller.start()
        controller.start()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertEqual(scheduler.liveCount, 1)
        controller.stop()
        }
    }

    func testStoppedControllerDoesNotRestartOnPreferenceChanges() {
        let (model, settings, controller, scheduler, _, suite) = make(enabled: true)
        withExtendedLifetime(model) {
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        controller.start()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        controller.stop()
        let afterStop = scheduler.tokens.count
        settings.nowPlayingEnabled = false
        settings.nowPlayingEnabled = true
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertEqual(scheduler.tokens.count, afterStop, "a stopped controller must stay stopped")
        XCTAssertEqual(scheduler.liveCount, 0)
        }
    }

    /// V0099-R1: each start/stop cycle must leave no handler behind, otherwise a
    /// single disable stops the source once per cycle.
    func testCyclesDoNotAccumulatePreferenceHandlers() {
        let (model, settings, controller, scheduler, system, suite) = make(enabled: true)
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        withExtendedLifetime(model) {
            for _ in 0..<3 {
                controller.start()
                controller.stop()
            }
            controller.start()
            let stopsBefore = system.stops
            settings.nowPlayingEnabled = false
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            XCTAssertEqual(system.stops - stopsBefore, 1,
                           "one disable must stop the source exactly once after several cycles")
            XCTAssertEqual(scheduler.liveCount, 0)
            controller.stop()
        }
    }
}
