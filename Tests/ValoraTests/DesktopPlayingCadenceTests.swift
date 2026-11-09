import AppKit
import Combine
import Foundation
import XCTest
import ReferenceCore
@testable import Valora

/// Desktop playing second pass: the 4Hz progress sample must follow the real
/// progress surface (expanded player / lock card) instead of running while the
/// collapsed notch shows nothing that depends on it, and a hidden panel must
/// not keep the waveform animation clock alive.

@MainActor
final class DesktopPlayingCadenceTests: XCTestCase {
    private func snapshot(playing: Bool, elapsed: Double) -> SystemMediaSnapshot {
        SystemMediaSnapshot([
            "bundleIdentifier": "com.test.player", "title": "Track", "artist": "Artist",
            "album": "Album", "durationMicros": 236_000_000,
            "elapsedTimeMicros": Int(elapsed * 1_000_000),
            "timestampEpochMicros": Date().timeIntervalSince1970 * 1_000_000,
            "playing": playing, "playbackRate": 1.0,
            "contentItemIdentifier": "track"
        ])!
    }

    private func make(playing: Bool = true)
        -> (model: AppModel, controller: MediaController, scheduler: ManualMediaScheduler, suite: String) {
        let suite = "com.wangqing.valora.playing-cadence.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(true, forKey: "enableNowPlaying")
        let model = AppModel(settings: RevivalSettings(defaults: defaults))
        let scheduler = ManualMediaScheduler()
        let system = PushSystem()
        system.initial = snapshot(playing: playing, elapsed: 20)
        let controller = MediaController(model, system: system, retryInterval: 0,
                                         tickScheduler: scheduler)
        return (model, controller, scheduler, suite)
    }

    func testCollapsedPlayingPublishesOneAnchorPerSecond() {
        let (model, controller, scheduler, suite) = make()
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        withExtendedLifetime(model) {
            controller.start()
            var values: [Double] = []
            let token = model.$elapsed.dropFirst().sink { values.append($0) }
            for _ in 0..<8 { scheduler.fire() }
            XCTAssertEqual(values.count, 2, "collapsed playback samples at 1Hz, not 4Hz")
            token.cancel()
            controller.stop()
        }
    }

    func testExpandedPlayerKeepsTheFourHertzSample() {
        let (model, controller, scheduler, suite) = make()
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        withExtendedLifetime(model) {
            controller.start()
            _ = model.presentation.begin(expanding: true)
            XCTAssertTrue(model.presentation.retainsExpandedContent)
            var values: [Double] = []
            let token = model.$elapsed.dropFirst().sink { values.append($0) }
            for _ in 0..<4 { scheduler.fire() }
            XCTAssertEqual(values.count, 4, "the visible progress bar keeps its existing 4Hz update")
            token.cancel()
            controller.stop()
        }
    }

    func testLockCardKeepsTheFourHertzSample() {
        let (model, controller, scheduler, suite) = make()
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        withExtendedLifetime(model) {
            controller.start()
            model.lockMusicCardVisible = true
            var values: [Double] = []
            let token = model.$elapsed.dropFirst().sink { values.append($0) }
            for _ in 0..<4 { scheduler.fire() }
            XCTAssertEqual(values.count, 4, "the lock card progress bar keeps 4Hz")
            token.cancel()
            controller.stop()
        }
    }

    func testExpandingPublishesAFreshAnchorImmediately() {
        let (model, controller, scheduler, suite) = make()
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        withExtendedLifetime(model) {
            controller.start()
            scheduler.fire()                 // collapsed anchor
            let before = model.elapsed
            var values: [Double] = []
            let token = model.$elapsed.dropFirst().sink { values.append($0) }
            _ = model.presentation.begin(expanding: true)
            XCTAssertEqual(values.count, 1, "expanding must not wait up to a second for the next sample")
            XCTAssertGreaterThanOrEqual(values.first ?? 0, before)
            token.cancel()
            controller.stop()
        }
    }

    func testCollapsingReturnsToOneHertzWithoutStalling() {
        let (model, controller, scheduler, suite) = make()
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        withExtendedLifetime(model) {
            controller.start()
            _ = model.presentation.begin(expanding: true)
            model.presentation.complete(generation: model.presentation.generation)
            _ = model.presentation.begin(expanding: false)
            model.presentation.complete(generation: model.presentation.generation)
            XCTAssertEqual(model.presentation.phase, .collapsed)
            scheduler.fire()
            var values: [Double] = []
            let token = model.$elapsed.dropFirst().sink { values.append($0) }
            for _ in 0..<4 { scheduler.fire() }
            XCTAssertEqual(values.count, 1, "after collapsing only the 1Hz anchor remains")
            token.cancel()
            controller.stop()
        }
    }

    func testPausedStillPublishesOnlyOnChangeInEitherSurface() {
        let (model, controller, scheduler, suite) = make(playing: false)
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        withExtendedLifetime(model) {
            controller.start()
            _ = model.presentation.begin(expanding: true)
            var values = 0
            let token = model.$elapsed.dropFirst().sink { _ in values += 1 }
            for _ in 0..<6 { scheduler.fire() }
            XCTAssertEqual(values, 0, "a paused expanded player still has nothing new to draw")
            token.cancel()
            controller.stop()
        }
    }
}

@MainActor
final class PlayingWaveformVisibilityTests: XCTestCase {
    private func makeWaveform() -> (CompactWaveformView, NSWindow) {
        let waveform = CompactWaveformView(frame: NSRect(x: 0, y: 0, width: 20, height: 20))
        let host = NSView(frame: waveform.frame)
        let window = NSWindow(contentRect: waveform.frame, styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        // Off-screen so the test never flashes a window at the user.
        window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
        window.contentView = host
        host.addSubview(waveform)
        return (waveform, window)
    }

    private func spin(_ seconds: TimeInterval = 0.05) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    func testHiddenPanelStopsTheWaveformClockAndResumesWhenOrderedBack() {
        let (waveform, window) = makeWaveform()
        defer { waveform.stop(); window.close() }
        waveform.configure(image: nil, color: .blue, playing: true,
                           reducedMotion: false, identity: "fixture")
        XCTAssertFalse(waveform.isTicking, "an unordered window is not an on-screen surface")

        // SwiftUI re-configures the representable on the next model update and
        // on every mount; the clock follows `window.isVisible` at that point.
        window.orderFrontRegardless()
        waveform.configure(image: nil, color: .blue, playing: true,
                           reducedMotion: false, identity: "fixture")
        XCTAssertTrue(waveform.isTicking, "a visible playing surface keeps the existing clock")

        window.orderOut(nil)
        waveform.configure(image: nil, color: .blue, playing: true,
                           reducedMotion: false, identity: "fixture")
        XCTAssertFalse(waveform.isTicking, "ordering the panel out must stop the clock")

        window.orderFrontRegardless()
        waveform.configure(image: nil, color: .blue, playing: true,
                           reducedMotion: false, identity: "fixture")
        XCTAssertTrue(waveform.isTicking, "ordering the panel back in must resume immediately")
    }

    func testPausedOrSuspendedWaveformNeverRegisters() {
        let (waveform, window) = makeWaveform()
        defer { waveform.stop(); window.close() }
        window.orderFrontRegardless()
        waveform.configure(image: nil, color: .blue, playing: false,
                           reducedMotion: false, identity: "fixture")
        XCTAssertFalse(waveform.isTicking)
        waveform.configure(image: nil, color: .blue, playing: true,
                           reducedMotion: false, identity: "fixture", suspended: true)
        XCTAssertFalse(waveform.isTicking)
        waveform.configure(image: nil, color: .blue, playing: true, reducedMotion: true,
                           identity: "fixture")
        XCTAssertFalse(waveform.isTicking, "reduce motion keeps the static bars")
    }
}
