import AppKit
import Combine
import Foundation
import XCTest
import ReferenceCore
@testable import Valora

// MARK: - Per-frame lyric preparation

@MainActor
final class LyricsLineFrameCacheTests: XCTestCase {
    private func timeline() -> LyricTimeline {
        LyricTimeline(lines: [
            LyricLine(start: 0, text: "第一句"),
            LyricLine(start: 4, text: "第二句很短"),
            LyricLine(start: 8, text: "这是一句没有逐字时间的长歌词，用于确认整行滚动仍然使用真实的行边界")
        ])
    }

    private func identity() -> LyricsTrackIdentity {
        LyricsTrackIdentity(title: "T", artist: "A", album: "B", duration: 240)
    }

    func testRepeatedFramesWithinOneLineReusePreparedData() {
        let cache = LyricsLineFrameCache()
        let metrics = LyricMetricsCache()
        let lines = timeline().lines
        let line = lines[1]
        var first: LyricsLineFrameCache.Frame?
        for step in 0..<30 {
            let frame = cache.frame(for: line, duration: 240, identity: identity(),
                                    timeline: timeline(), width: 300, metricsCache: metrics)
            if let first {
                XCTAssertEqual(frame.key, first.key)
                XCTAssertEqual(frame.label, first.label)
                XCTAssertEqual(frame.lineEnd, first.lineEnd, accuracy: 0.0001)
                XCTAssertEqual(frame.isLong, first.isLong)
            } else {
                first = frame
            }
            _ = step
        }
        XCTAssertEqual(cache.frameRebuilds, 1, "30 frames of one line must prepare once")
        XCTAssertEqual(cache.metricsRebuilds, 1, "word widths and measured text are prepared once per line")
        XCTAssertEqual(first?.label, "歌词，第二句很短")
        XCTAssertEqual(first?.lineEnd ?? 0, 8, accuracy: 0.0001, "the next line start is the line end")
    }

    func testLineChangeRebuildsPreparedDataOnce() {
        let cache = LyricsLineFrameCache()
        let metrics = LyricMetricsCache()
        let lines = timeline().lines
        _ = cache.frame(for: lines[0], duration: 240, identity: identity(),
                        timeline: timeline(), width: 300, metricsCache: metrics)
        _ = cache.frame(for: lines[1], duration: 240, identity: identity(),
                        timeline: timeline(), width: 300, metricsCache: metrics)
        _ = cache.frame(for: lines[1], duration: 240, identity: identity(),
                        timeline: timeline(), width: 300, metricsCache: metrics)
        XCTAssertEqual(cache.frameRebuilds, 2)
        XCTAssertEqual(cache.metricsRebuilds, 2)
    }

    func testWidthChangeRecomputesOverflowWithoutChangingTheLine() {
        let cache = LyricsLineFrameCache()
        let metrics = LyricMetricsCache()
        let line = timeline().lines[2]
        let wide = cache.frame(for: line, duration: 240, identity: identity(),
                               timeline: timeline(), width: 900, metricsCache: metrics)
        let narrow = cache.frame(for: line, duration: 240, identity: identity(),
                                 timeline: timeline(), width: 80, metricsCache: metrics)
        XCTAssertFalse(wide.isLong)
        XCTAssertTrue(narrow.isLong, "a long line still slides when it does not fit")
        XCTAssertEqual(cache.frameRebuilds, 2)
    }

    func testTimelineReplacementInvalidatesTheCachedLineEnd() {
        let cache = LyricsLineFrameCache()
        let metrics = LyricMetricsCache()
        let line = timeline().lines[0]
        let before = cache.frame(for: line, duration: 240, identity: identity(),
                                 timeline: timeline(), width: 300, metricsCache: metrics)
        XCTAssertEqual(before.lineEnd, 4, accuracy: 0.0001)
        let replaced = LyricTimeline(lines: [
            LyricLine(start: 0, text: "第一句"),
            LyricLine(start: 6, text: "第二句很短"),
            LyricLine(start: 9, text: "第三句")
        ])
        let after = cache.frame(for: line, duration: 240, identity: identity(),
                                timeline: replaced, width: 300, metricsCache: metrics)
        XCTAssertEqual(after.lineEnd, 6, accuracy: 0.0001,
                       "a replaced timeline must not keep the old next-line boundary")
    }

    func testTrailingLineFallsBackToTrackDuration() {
        let cache = LyricsLineFrameCache()
        let metrics = LyricMetricsCache()
        let last = timeline().lines[2]
        let frame = cache.frame(for: last, duration: 240, identity: identity(),
                                timeline: timeline(), width: 300, metricsCache: metrics)
        XCTAssertEqual(frame.lineEnd, 240, accuracy: 0.0001)
    }

    func testNextStartUsesTheRealSuccessorWithDuplicateTimestamps() {
        let lines = [LyricLine(start: 5, text: "a"), LyricLine(start: 5, text: "b"),
                     LyricLine(start: 7, text: "c")]
        XCTAssertEqual(LyricsLineFrameCache.nextStart(in: lines, after: 5), 7,
                       "a line with the same start is never its own successor")
        XCTAssertEqual(LyricsLineFrameCache.nextStart(in: lines, after: 4), 5)
        XCTAssertNil(LyricsLineFrameCache.nextStart(in: lines, after: 7))
        XCTAssertNil(LyricsLineFrameCache.nextStart(in: [], after: 0))
        XCTAssertEqual(LyricsLineFrameCache.nextStart(in: lines, after: -.infinity), 5)
        XCTAssertNil(LyricsLineFrameCache.nextStart(in: lines, after: .infinity))
    }

    func testNoLineProducesTheStaticLabel() {
        let cache = LyricsLineFrameCache()
        let frame = cache.frame(for: nil, duration: 240, identity: identity(),
                                timeline: nil, width: 300, metricsCache: LyricMetricsCache())
        XCTAssertNil(frame.metrics)
        XCTAssertEqual(frame.label, "歌词")
        XCTAssertEqual(frame.key, "")
    }
}

// MARK: - 1Hz anchor with the real clock

@MainActor
final class LyricsAnchorInterpolationTests: XCTestCase {
    private func snapshot(playing: Bool, elapsed: Double, rate: Double = 1) -> SystemMediaSnapshot {
        SystemMediaSnapshot([
            "bundleIdentifier": "com.test.player", "title": "Track", "artist": "Artist",
            "album": "Album", "durationMicros": 236_000_000,
            "elapsedTimeMicros": Int(elapsed * 1_000_000),
            "timestampEpochMicros": Date().timeIntervalSince1970 * 1_000_000,
            "playing": playing, "playbackRate": rate,
            "contentItemIdentifier": "track"
        ])!
    }

    private func make(playing: Bool = true)
        -> (model: AppModel, controller: MediaController, scheduler: ManualMediaScheduler, suite: String) {
        let suite = "com.wangqing.valora.lyrics-anchor.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(true, forKey: "enableNowPlaying")
        let model = AppModel(settings: RevivalSettings(defaults: defaults))
        let scheduler = ManualMediaScheduler()
        let system = PushSystem()
        system.initial = snapshot(playing: playing, elapsed: 30)
        let controller = MediaController(model, system: system, retryInterval: 0,
                                         tickScheduler: scheduler)
        return (model, controller, scheduler, suite)
    }

    /// The batch-2 1Hz anchor must still yield a continuously advancing lyric
    /// time between samples, using the same wall clock the 30Hz timeline reads.
    func testOneHertzAnchorInterpolatesWithTheRealClock() async {
        let (model, controller, scheduler, suite) = make()
        defer { controller.stop(); UserDefaults().removePersistentDomain(forName: suite) }
        controller.start()
        scheduler.fire()
        var publishes = 0
        let token = model.$elapsed.dropFirst().sink { _ in publishes += 1 }
        let anchor = model.elapsed
        try? await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(publishes, 0, "no extra progress sample inside the 1Hz window")
        let interpolated = model.lyricsElapsed(at: Date())
        XCTAssertEqual(interpolated - anchor, 0.4, accuracy: 0.08,
                       "lyrics advance with the clock between 1Hz samples")
        token.cancel()
        withExtendedLifetime(model) {}
    }

    func testRateChangeAndSeekRestartFromTheNewAnchor() async {
        let (model, controller, suite) = {
            let made = make()
            return (made.model, made.controller, made.suite)
        }()
        defer { controller.stop(); UserDefaults().removePersistentDomain(forName: suite) }
        controller.start()
        model.playbackRate = 2
        model.setElapsed(40, sampledAt: Date())
        try? await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(model.lyricsElapsed(at: Date()) - 40, 0.6, accuracy: 0.1,
                       "2x playback doubles the interpolation rate")
        model.setElapsed(90, sampledAt: Date())
        XCTAssertEqual(model.lyricsElapsed(at: Date()), 90, accuracy: 0.05,
                       "a seek re-anchors instead of jumping back")
        withExtendedLifetime(model) {}
    }

    func testPauseFreezesLyricsAtTheAnchor() async {
        let (model, controller, _, suite) = make(playing: false)
        defer { controller.stop(); UserDefaults().removePersistentDomain(forName: suite) }
        controller.start()
        let anchor = model.elapsed
        try? await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(model.lyricsElapsed(at: Date()), anchor, accuracy: 0.001,
                       "paused lyrics stay on the anchor line")
        withExtendedLifetime(model) {}
    }

    /// At the end of a track the interpolated time may pass `duration`; the
    /// displayed line and word fraction must stay identical to the previous
    /// 4Hz behaviour (last line, fully filled).
    func testEndOfTrackClampKeepsTheLastLineAndFullFill() async {
        let (model, controller, _, suite) = make()
        defer { controller.stop(); UserDefaults().removePersistentDomain(forName: suite) }
        let timeline = LyricTimeline(lines: [
            LyricLine(start: 230, text: "最后一句", words: [
                LyricWord(text: "最后", start: 230, duration: 2),
                LyricWord(text: "一句", start: 232, duration: 2)
            ])
        ])
        model.lyrics = LyricsDisplayState(status: .ready, timeline: timeline, identity: nil)
        model.duration = 236
        controller.start()
        model.setElapsed(236, sampledAt: Date())
        try? await Task.sleep(for: .milliseconds(300))
        let elapsed = model.lyricsElapsed(at: Date())
        XCTAssertGreaterThan(elapsed, 236, "interpolation is not clamped by the anchor")
        XCTAssertEqual(timeline.line(at: elapsed)?.text, "最后一句")
        let fraction = timeline.wordProgress(in: timeline.lines[0], at: elapsed)?.fraction
        XCTAssertEqual(fraction, 1, "the visible fill stays complete")
        withExtendedLifetime(model) {}
    }
}

// MARK: - Waveform lifecycle without manual reconfigure

@MainActor
final class PlayingWaveformLifecycleTests: XCTestCase {
    private func makeWaveform() -> (CompactWaveformView, NSWindow, NSView) {
        let waveform = CompactWaveformView(frame: NSRect(x: 0, y: 0, width: 20, height: 20))
        let host = NSView(frame: waveform.frame)
        let window = NSWindow(contentRect: waveform.frame, styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
        window.contentView = host
        host.addSubview(waveform)
        return (waveform, window, host)
    }

    private func spin(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    func testOrderingOutStopsWithoutAnyReconfigure() {
        let (waveform, window, _) = makeWaveform()
        defer { waveform.stop(); window.close() }
        waveform.configure(image: nil, color: .blue, playing: true,
                           reducedMotion: false, identity: "fixture")
        window.orderFrontRegardless()
        waveform.configure(image: nil, color: .blue, playing: true,
                           reducedMotion: false, identity: "fixture")
        XCTAssertTrue(waveform.isTicking)

        window.orderOut(nil)
        // No configure(): only the clock's own visibility self-check may stop it.
        spin(0.4)
        XCTAssertFalse(waveform.isTicking, "the clock stops itself on an ordered-out panel")
    }

    func testRemountingAResumesWithoutManualConfigure() {
        let (waveform, window, host) = makeWaveform()
        defer { waveform.stop(); window.close() }
        window.orderFrontRegardless()
        waveform.configure(image: nil, color: .blue, playing: true,
                           reducedMotion: false, identity: "fixture")
        XCTAssertTrue(waveform.isTicking)

        waveform.removeFromSuperview()
        XCTAssertFalse(waveform.isTicking, "dismantling releases the clock")
        host.addSubview(waveform)
        XCTAssertTrue(waveform.isTicking,
                      "the SwiftUI mount path resumes the clock without an explicit configure")
    }
}

// MARK: - notchSurfaceOnScreen boundaries

@MainActor
final class NotchSurfaceVisibilityTests: XCTestCase {
    private var suite = ""
    private var defaults: UserDefaults!
    private var settings: RevivalSettings!
    private var model: AppModel!
    private var coordinator: WindowCoordinator!

    override func setUp() {
        super.setUp()
        suite = "com.wangqing.valora.notch-surface.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        settings = RevivalSettings(defaults: defaults)
        settings.forceSimulatedNotch = true
        model = AppModel(settings: settings)
        model.title = "Track"
        model.artist = "Artist"
        model.playing = true
        let display = DisplayDescriptor(id: "builtin", name: "Built-in display",
            frame: CGRect(x: 0, y: 0, width: 1728, height: 1117), safeAreaTop: 32,
            auxiliaryLeftWidth: 600, auxiliaryRightWidth: 600, menuBarHeight: 32,
            isBuiltIn: true)
        coordinator = WindowCoordinator(model, displayProvider: { [display] })
        coordinator.start(trackPointer: false)
    }

    override func tearDown() {
        coordinator?.cancelPendingHover()
        coordinator?.collapse()
        defaults?.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    private func settle() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }

    func testDesktopSurfaceFollowsTheVisibilityIntent() {
        XCTAssertTrue(model.notchSurfaceOnScreen, "a visible notch is on screen after start")
        settings.showNotch = false
        settle()
        XCTAssertFalse(model.notchSurfaceOnScreen)
        settings.showNotch = true
        settle()
        XCTAssertTrue(model.notchSurfaceOnScreen)

        model.screenHidden = true
        model.title = "Track"          // any update re-evaluates visibility
        settle()
        XCTAssertFalse(model.notchSurfaceOnScreen, "fullscreen hiding takes the surface off screen")
        model.screenHidden = false
        model.title = "Track"
        settle()
        XCTAssertTrue(model.notchSurfaceOnScreen)
    }

    func testIdleHidingOnlyHidesWithoutMusicActivity() {
        settings.hideWhenIdle = true
        settle()
        XCTAssertTrue(model.notchSurfaceOnScreen, "playing music keeps the notch visible")

        model.title = "暂无播放"
        model.playing = false
        settle()
        XCTAssertFalse(model.notchSurfaceOnScreen, "idle hiding takes the surface off screen")

        model.title = "Next"
        model.playing = true
        settle()
        XCTAssertTrue(model.notchSurfaceOnScreen)
    }
}
