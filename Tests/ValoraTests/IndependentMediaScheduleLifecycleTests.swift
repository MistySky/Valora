import XCTest
import Foundation
@testable import Valora

@MainActor
final class IndependentMediaScheduleLifecycleTests: XCTestCase {
    func testRestartMustNotAccumulatePreferenceSubscriptions() {
        let suite = "com.wangqing.valora.independent-media-schedule.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(true, forKey: "enableNowPlaying")
        let settings = RevivalSettings(defaults: defaults)
        let model = AppModel(settings: settings)
        let scheduler = MediaScheduleTests.FakeScheduler()
        let source = MediaScheduleTests.FakeSystem()
        let controller = MediaController(model, system: source, retryInterval: 0,
                                         tickScheduler: scheduler)
        defer { controller.stop(); defaults.removePersistentDomain(forName: suite) }
        withExtendedLifetime(model) {
            controller.start()
            controller.stop()
            controller.start()
            let priorStops = source.stops
            settings.nowPlayingEnabled = false
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            XCTAssertEqual(source.stops - priorStops, 1,
                           "one disable must be processed once after restart; old subscriptions must be cancelled")
            XCTAssertEqual(scheduler.liveCount, 0)
        }
    }
}
