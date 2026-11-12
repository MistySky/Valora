#if VALORA_LYRICS_EXPERIMENT
import AppKit
import SwiftUI
import XCTest
import ReferenceCore
@testable import Valora

/// Independent behavior regressions for the line-switch driver: progress must
/// follow an injectable monotonic clock, so dropped, merged or late callbacks
/// reach the fixed 0.2s end on schedule instead of stretching the animation.
/// No test depends on timer punctuality; the live 60Hz timer is stepped either
/// through the debug seam (host level) or through the real run loop (hosted),
/// while its lifecycle is observed throughout.
@MainActor
final class IndependentLyricsTransitionClockTests: XCTestCase {
    // MARK: Fixture

    private final class FakeClock {
        var now: Double = 0
    }

    private func solidImage() -> CGImage {
        let ctx = CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8,
                            bytesPerRow: 16, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.8, green: 0.1, blue: 0.1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        return ctx.makeImage()!
    }

    private func staticLine(_ key: String) -> NativeLyricsStaticLine {
        NativeLyricsStaticLine(lineKey: key, base: solidImage(), accent: solidImage(),
                               pointSize: CGSize(width: 60, height: 17), maskWidth: 60,
                               viewportWidth: 60, positionX: 0, positionY: 0,
                               imageScale: 2)
    }

    private func startedHost(_ clock: FakeClock, first: LyricLine, second: LyricLine,
                             outgoingKey: String = "0.0-")
        -> LyricsRowExperimentHost {
        let host = LyricsRowExperimentHost()
        host.debugMonotonicClock = { [clock] in clock.now }
        host.debugUsesTimer = true
        host.begin(identity: "a")
        host.reportLine(first, outgoing: nil, generation: host.generation, identity: "a")
        XCTAssertEqual(host.displayedLine, first, "fixture: the row must mount on the first line")
        host.reportLine(second, outgoing: staticLine(outgoingKey),
                        generation: host.generation, identity: "a")
        XCTAssertEqual(host.displayedLine, second, "fixture: the switch must be reported")
        XCTAssertNotNil(host.outgoing, "fixture: the transition must be in flight")
        XCTAssertFalse(host.isSettled, "fixture: the transition must start unsettled")
        XCTAssertEqual(host.incomingOffset, 26, "fixture: start at the incoming offset")
        XCTAssertEqual(host.incomingOpacity, 0, "fixture: start fully transparent")
        XCTAssertTrue(host.debugTransitionTimerActive,
                      "fixture: the 60Hz driver must live during the transition")
        return host
    }

    /// cubic-bezier(0.42, 0, 0.58, 1), the production easeInOut curve.
    private func easeInOut(_ x: Double) -> Double {
        guard x > 0, x < 1 else { return x }
        func curve(_ t: Double, _ p1: Double, _ p2: Double) -> Double {
            let mt = 1 - t
            return 3 * mt * mt * t * p1 + 3 * mt * t * t * p2 + t * t * t
        }
        var low = 0.0, high = 1.0
        for _ in 0..<24 {
            let mid = (low + high) / 2
            if curve(mid, 0.42, 0.42) < x { low = mid } else { high = mid }
        }
        return curve((low + high) / 2, 0, 1)
    }

    // MARK: Behavior

    /// One driver callback arriving after the whole 0.2s window has elapsed
    /// must jump straight to the end point: settled immediately, old line
    /// released, driver stopped, and further stale ticks are no-ops.
    func testSingleLateTickReachesTheEndPointAndReleasesTheOldLine() {
        let clock = FakeClock()
        let host = startedHost(clock, first: LyricLine(start: 0, text: "第一句"),
                               second: LyricLine(start: 1, text: "第二句"))
        clock.now = 0.25   // the whole window plus 50ms is already gone
        host.debugFireTransitionTick()
        XCTAssertTrue(host.isSettled, "a callback at 0.25s must settle immediately")
        XCTAssertNil(host.outgoing, "the outgoing line must be released")
        XCTAssertFalse(host.debugTransitionTimerActive, "the driver must stop")
        XCTAssertEqual(host.incomingOffset, 0)
        XCTAssertEqual(host.incomingOpacity, 1)
        XCTAssertEqual(host.outgoingOffset, 0)
        XCTAssertEqual(host.outgoingOpacity, 1)
        XCTAssertEqual(host.displayedLine, LyricLine(start: 1, text: "第二句"))
        // Stale ticks after the end must not restart anything.
        clock.now = 0.30
        host.debugFireTransitionTick()
        host.debugFireTransitionTick()
        XCTAssertTrue(host.isSettled)
        XCTAssertNil(host.outgoing)
        XCTAssertFalse(host.debugTransitionTimerActive)
    }

    /// The presented state must equal the easeInOut curve of the real elapsed
    /// monotonic time, not of the number of callbacks.
    func testProgressMatchesTheElapsedMonotonicTime() {
        let clock = FakeClock()
        let host = startedHost(clock, first: LyricLine(start: 0, text: "第一句"),
                               second: LyricLine(start: 1, text: "第二句"))
        // 0.1s elapsed → exactly half the window, curve-eased.
        clock.now = 0.1
        host.debugFireTransitionTick()
        let half = easeInOut(0.5)
        XCTAssertEqual(host.incomingOffset, 26 * (1 - half), accuracy: 0.2)
        XCTAssertEqual(host.incomingOpacity, half, accuracy: 0.01)
        XCTAssertEqual(host.outgoingOffset, -26 * half, accuracy: 0.2)
        XCTAssertEqual(host.outgoingOpacity, 1 - half, accuracy: 0.01)
        XCTAssertFalse(host.isSettled)
        XCTAssertNotNil(host.outgoing)
        // A duplicate callback at the same clock reading is idempotent.
        host.debugFireTransitionTick()
        XCTAssertEqual(host.incomingOffset, 26 * (1 - half), accuracy: 0.2)
        // 0.199s is still mid-flight.
        clock.now = 0.199
        host.debugFireTransitionTick()
        XCTAssertFalse(host.isSettled, "progress must not run ahead of the clock")
        // The end point is reached exactly when the window has elapsed.
        clock.now = 0.2
        host.debugFireTransitionTick()
        XCTAssertTrue(host.isSettled)
        XCTAssertNil(host.outgoing)
        XCTAssertFalse(host.debugTransitionTimerActive)
    }

    /// Uneven, sparse callbacks must track time: progress after a tick at time
    /// t is the ease of t/0.2, regardless of how many callbacks happened, and
    /// the switch still finishes on schedule (no stretched duration).
    func testUnevenIntervalsFollowTimeNotCallbackCount() {
        let clock = FakeClock()
        let host = startedHost(clock, first: LyricLine(start: 0, text: "第一句"),
                               second: LyricLine(start: 1, text: "第二句"))
        // Callbacks bunched within the first 0.12s, like dropped or merged
        // frames under load.
        let samples: [Double] = [0.03, 0.06, 0.09, 0.12]
        for (index, time) in samples.enumerated() {
            clock.now = time
            host.debugFireTransitionTick()
            let fraction = time / 0.2
            let eased = easeInOut(fraction)
            XCTAssertEqual(host.incomingOffset, 26 * (1 - eased), accuracy: 0.2,
                           "sample \(index): offset must follow elapsed time")
            XCTAssertEqual(host.incomingOpacity, eased, accuracy: 0.01,
                           "sample \(index): opacity must follow elapsed time")
            XCTAssertFalse(host.isSettled, "sample \(index): still mid-flight")
            // Sanity for the assertion above: the old per-tick accumulation
            // would sit at tick i of 12 and differs from the time-based state
            // by more than the 0.2pt tolerance at every sample in this cadence.
            for ticksSoFar in 1...index + 1 {
                let tickBasedOffset = 26 * (1 - easeInOut(Double(ticksSoFar) / 12.0))
                XCTAssertGreaterThan(abs(host.incomingOffset - tickBasedOffset), 0.2,
                                     "sample \(index): the state must not equal a tick-count prediction")
            }
        }
        clock.now = 0.21
        host.debugFireTransitionTick()
        XCTAssertTrue(host.isSettled, "the switch must finish on schedule")
        XCTAssertNil(host.outgoing)
        XCTAssertFalse(host.debugTransitionTimerActive)
    }

    /// Rapid A→B→C switches restart the clock window for each switch and end
    /// settled on the last line, with the newest outgoing line frozen.
    func testRapidSwitchesRestartTheWindowAndEndOnTheLastLine() {
        let clock = FakeClock()
        let host = startedHost(clock, first: LyricLine(start: 0, text: "第一句"),
                               second: LyricLine(start: 1, text: "第二句"),
                               outgoingKey: "0.0-")
        clock.now = 0.1
        host.debugFireTransitionTick()
        XCTAssertFalse(host.isSettled)
        host.reportLine(LyricLine(start: 2, text: "第三句"), outgoing: staticLine("1.0-"),
                        generation: host.generation, identity: "a")
        XCTAssertEqual(host.displayedLine, LyricLine(start: 2, text: "第三句"))
        XCTAssertEqual(host.outgoing?.lineKey, "1.0-",
                       "the second switch must freeze the newest line")
        XCTAssertTrue(host.debugTransitionTimerActive, "the driver must still be live")
        // A fresh 0.2s window from the second switch: unsettled before it ends.
        clock.now = 0.25
        host.debugFireTransitionTick()
        XCTAssertFalse(host.isSettled, "the restarted window still has 0.05s left")
        clock.now = 0.31
        host.debugFireTransitionTick()
        XCTAssertTrue(host.isSettled)
        XCTAssertEqual(host.displayedLine, LyricLine(start: 2, text: "第三句"))
        XCTAssertNil(host.outgoing)
        XCTAssertFalse(host.debugTransitionTimerActive)
    }

    /// Pause: progress may advance with the clock, but the displayed line must
    /// stay and the switch must settle on that line.
    func testPauseKeepsTheDisplayedLineAndSettlesOnIt() {
        let clock = FakeClock()
        let second = LyricLine(start: 1, text: "第二句")
        let host = startedHost(clock, first: LyricLine(start: 0, text: "第一句"),
                               second: second)
        clock.now = 0.05
        host.debugFireTransitionTick()
        clock.now = 0.1
        host.debugFireTransitionTick()
        XCTAssertEqual(host.displayedLine, second, "no line change while mid-flight")
        clock.now = 0.25
        host.debugFireTransitionTick()
        XCTAssertTrue(host.isSettled)
        XCTAssertEqual(host.displayedLine, second)
        XCTAssertNil(host.outgoing)
    }

    /// A hidden surface ends the presentation immediately: the frozen line is
    /// released, the driver stops, and stale ticks do not restart it.
    func testHideStopsTheDriverAndStaleTicksDoNothing() {
        let clock = FakeClock()
        let host = startedHost(clock, first: LyricLine(start: 0, text: "第一句"),
                               second: LyricLine(start: 1, text: "第二句"))
        clock.now = 0.1
        host.debugFireTransitionTick()
        host.endPresentation()
        XCTAssertTrue(host.isSettled)
        XCTAssertNil(host.outgoing)
        XCTAssertFalse(host.debugTransitionTimerActive)
        clock.now = 0.25
        host.debugFireTransitionTick()
        XCTAssertTrue(host.isSettled, "a stale tick must not restart the transition")
        XCTAssertFalse(host.debugTransitionTimerActive)
    }

    /// A capture failure stops the driver and the late line callback from the
    /// same (failed) presentation must not restart the animation.
    func testFailureStopsTheDriverAndIgnoresLateLineCallbacks() {
        let clock = FakeClock()
        let host = startedHost(clock, first: LyricLine(start: 0, text: "第一句"),
                               second: LyricLine(start: 1, text: "第二句"))
        clock.now = 0.1
        host.debugFireTransitionTick()
        host.reportFailure(generation: host.generation, identity: "a")
        XCTAssertTrue(host.failed)
        XCTAssertTrue(host.isSettled, "failure must settle the row")
        XCTAssertNil(host.outgoing)
        XCTAssertFalse(host.debugTransitionTimerActive)
        clock.now = 0.25
        host.reportLine(LyricLine(start: 2, text: "迟到的行"), outgoing: staticLine("1.0-"),
                        generation: host.generation, identity: "a")
        host.debugFireTransitionTick()
        XCTAssertTrue(host.failed)
        XCTAssertTrue(host.isSettled)
        XCTAssertNil(host.outgoing, "a failed presentation must not restart a transition")
        XCTAssertFalse(host.debugTransitionTimerActive)
    }

    /// Invalidating the view cancels the live driver via the generation token:
    /// already-scheduled timers and late callbacks are inert.
    func testInvalidateCancelsTheLiveDriverAndLateCallbacks() {
        let clock = FakeClock()
        let host = startedHost(clock, first: LyricLine(start: 0, text: "第一句"),
                               second: LyricLine(start: 1, text: "第二句"))
        let staleGeneration = host.generation
        let staleIdentity = host.identity
        clock.now = 0.1
        host.debugFireTransitionTick()
        host.invalidate()
        XCTAssertTrue(host.isSettled)
        XCTAssertFalse(host.debugTransitionTimerActive)
        clock.now = 0.25
        host.reportLine(LyricLine(start: 2, text: "迟到"), outgoing: staticLine("1.0-"),
                        generation: staleGeneration, identity: staleIdentity)
        host.reportFailure(generation: staleGeneration, identity: staleIdentity)
        XCTAssertEqual(host.displayedLine, LyricLine(start: 1, text: "第二句"),
                       "a late callback from the invalidated presentation must not advance the row")
        XCTAssertFalse(host.failed, "a previous presentation's failure must not lock the new state")
        host.debugFireTransitionTick()
        XCTAssertTrue(host.isSettled)
        XCTAssertFalse(host.debugTransitionTimerActive)
    }
}

/// End-to-end through the real hosted view: the transition is triggered by the
/// renderer, the driver is the real 60Hz run-loop timer, and the clock is
/// injected only as a test seam. The switch must settle on schedule without
/// any manual stepping and the timer lifetime must be observable.
@MainActor
final class IndependentLyricsTransitionClockHostingTests: XCTestCase {
    private final class FakeClock {
        var now: Double = 0
    }

    private var clock = FakeClock()

    private func makeModel(lines: [LyricLine], elapsed: TimeInterval, anchor: Date)
        -> (AppModel, String) {
        let suite = "com.wangqing.valora.transition-clock.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(["nowPlayingEnabled": true, "showLyrics": true],
                     forKey: "referenceSettingsUI")
        defaults.set(true, forKey: "enableNowPlaying")
        let settings = RevivalSettings(defaults: defaults)
        let model = AppModel(settings: settings)
        model.title = "Clock"
        model.duration = 240
        model.lyrics = LyricsDisplayState(status: .ready, timeline: LyricTimeline(lines: lines),
                                          identity: nil)
        let artwork = NSImage(size: NSSize(width: 64, height: 64))
        artwork.lockFocus()
        NSColor.systemBlue.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 64, height: 64)).fill()
        artwork.unlockFocus()
        model.artwork = artwork
        model.playing = true
        model.playbackRate = 1
        model.setElapsed(elapsed, sampledAt: anchor)
        return (model, suite)
    }

    private func waitUntil(_ timeout: TimeInterval = 1.0, _ condition: () -> Bool) {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end, !condition() {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
    }

    private func nativeRow(_ view: NSView) -> NativeLyricsRowView? {
        if let row = view as? NativeLyricsRowView { return row }
        for subview in view.subviews {
            if let row = nativeRow(subview) { return row }
        }
        return nil
    }

    private func countNativeRows(_ view: NSView) -> Int {
        var count = view is NativeLyricsRowView ? 1 : 0
        for subview in view.subviews { count += countNativeRows(subview) }
        return count
    }

    private func staticLineViews(_ view: NSView) -> Int {
        var count = view is StaticLyricsLineNSView ? 1 : 0
        for subview in view.subviews { count += staticLineViews(subview) }
        return count
    }

    private func stopNativeRows(_ view: NSView) {
        if let row = view as? NativeLyricsRowView { row.stop() }
        for subview in view.subviews { stopNativeRows(subview) }
    }

    /// The real run-loop timer (no debug fire, no manual mode) must settle the
    /// switch once the injected clock passes the 0.2s window: a single late
    /// run-loop callback reaches the end immediately and stops the driver.
    func testRealRunLoopTimerSettlesWhenTheInjectedClockPassesTheWindow() {
        let clock = FakeClock()
        let anchor = Date()
        let short = LyricLine(start: 0, text: "短句")
        let long = LyricLine(start: 1, text: String(repeating: "长歌词内容", count: 6))
        let (model, suite) = makeModel(lines: [short, long], elapsed: 0.2, anchor: anchor)
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let hostModel = LyricsRowExperimentHost()
        hostModel.debugMonotonicClock = { [clock] in clock.now }
        let hosting = NSHostingView(rootView: AnyView(ExperimentalDesktopLyricsView(
            model: model, width: 200, rowHeight: 32, showsNote: true, horizontalInset: 18,
            host: hostModel)))
        hosting.frame = NSRect(x: 0, y: 0, width: 200, height: 32)
        let window = NSWindow(contentRect: hosting.frame, styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
        window.contentView = hosting
        window.orderFrontRegardless()
        defer {
            stopNativeRows(hosting)
            window.close()
        }
        waitUntil { hostModel.displayedLine?.start == 0 }
        guard let row = nativeRow(hosting) else {
            XCTFail("native row missing")
            return
        }
        // Trigger the switch through the renderer while the injected clock
        // reads 0: the host starts the real 60Hz driver against that clock.
        let trigger = anchor.addingTimeInterval(1.5)
        row.debugNow = { trigger }
        row.render(at: trigger)
        waitUntil { hostModel.outgoing != nil }
        XCTAssertFalse(hostModel.isSettled, "the switch must be in flight")
        XCTAssertEqual(hostModel.incomingOffset, 26)
        XCTAssertEqual(hostModel.incomingOpacity, 0)
        XCTAssertTrue(hostModel.debugTransitionTimerActive)
        XCTAssertEqual(row.lineSwitchAnimations, 0,
                       "the renderer's own switch animation stays disabled")
        _ = clock
        // A single run-loop callback once the injected clock reads 0.25s must
        // reach the end point; no manual stepping is involved.
        clock.now = 0.25
        waitUntil { hostModel.isSettled }
        XCTAssertNil(hostModel.outgoing, "the outgoing line must be released")
        XCTAssertFalse(hostModel.debugTransitionTimerActive, "the driver must be stopped")
        XCTAssertEqual(hostModel.displayedLine?.start, 1)
        XCTAssertEqual(hostModel.incomingOffset, 0)
        XCTAssertEqual(hostModel.incomingOpacity, 1)
        XCTAssertEqual(staticLineViews(hosting), 0, "the frozen view must be removed")
        XCTAssertEqual(countNativeRows(hosting), 1, "the renderer stays mounted")
    }
}
#endif
