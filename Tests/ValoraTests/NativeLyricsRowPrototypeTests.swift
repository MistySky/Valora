import AppKit
import Foundation
import SwiftUI
import XCTest
import ReferenceCore
@testable import Valora

/// Isolated verification for the native lyric row prototype. Nothing here is
/// wired into the shipped `CompactLyricsView`; the tests compare the prototype
/// against the current SwiftUI formulas and (opt-in) against its pixels.
@MainActor
final class NativeLyricsRowPrototypeTests: XCTestCase {
    private func timeline() -> LyricTimeline {
        LyricTimeline(lines: [
            LyricLine(start: 0, text: "前奏"),
            LyricLine(start: 4, text: "逐字第一句", words: [
                LyricWord(text: "逐字", start: 4, duration: 0.6),
                LyricWord(text: "第一", start: 4.6, duration: 0.6),
                LyricWord(text: "句", start: 5.2, duration: 0.8)
            ]),
            LyricLine(start: 8, text: "这是一句没有逐字时间的长歌词，用于确认整行滚动仍然使用真实的行边界，并且不会在换行时跳到错误的位置"),
            LyricLine(start: 20, text: "重复", words: [LyricWord(text: "重复", start: 20, duration: 1)]),
            LyricLine(start: 20, text: "同时间戳", words: [LyricWord(text: "同时间戳", start: 20, duration: 1)]),
            LyricLine(start: 30, text: "末句")
        ])
    }

    private func snapshot(elapsed: Double, playing: Bool = false, rate: Double = 1,
                          width: CGFloat, sampledAt: Date) -> NativeLyricsRowSnapshot {
        NativeLyricsRowSnapshot(identity: nil, timeline: timeline(), elapsed: elapsed,
                                sampledAt: sampledAt, rate: rate, playing: playing,
                                duration: 240, width: width, rowHeight: 17,
                                accent: .systemRed)
    }

    /// The shipped SwiftUI row's formulas, kept here as the reference.
    private func expected(line: LyricLine?, metrics: LyricsLineMetrics?, elapsed: Double,
                          lineEnd: TimeInterval, width: CGFloat) -> (fill: CGFloat, offset: CGFloat) {
        guard let line, let metrics else { return (0, 0) }
        let current = metrics.currentWord(at: elapsed, line: line)
        let fill = LyricsLineLayout.fillWidth(
            prefixWidth: current.map { metrics.prefixes[$0.index] } ?? 0,
            currentWordWidth: current.map { metrics.wordWidths[$0.index] } ?? 0,
            fraction: current?.fraction ?? 0,
            totalWidth: metrics.totalWidth)
        let fillContainer = metrics.totalWidth > width
        var offset: CGFloat = 0
        if fillContainer, let current, current.index < metrics.prefixes.count {
            offset = LyricsLineLayout.followingOffset(
                prefixWidth: metrics.prefixes[current.index],
                currentWordWidth: metrics.wordWidths[current.index],
                fraction: current.fraction, totalWidth: metrics.totalWidth,
                availableWidth: width)
        } else if fillContainer, line.words.isEmpty, lineEnd > line.start {
            let raw = min(1, max(0, (elapsed - line.start) / (lineEnd - line.start)))
            let hold = 0.15
            let progress = max(0, min(1, (raw - hold) / (1 - hold)))
            offset = LyricsLineLayout.lineOnlyOffset(progress: progress,
                                                     totalWidth: metrics.totalWidth,
                                                     availableWidth: width)
        }
        return (fill, offset)
    }

    func testGeometryMatchesTheShippedFormulasAcrossTimes() {
        let width: CGFloat = 260
        let fixed = Date(timeIntervalSince1970: 1_000_000)
        let cases: [(Double, String)] = [
            (2, "前奏"),
            (4.0, "行起点"),
            (4.3, "词中点"),
            (4.6, "跨词边界"),
            (5.6, "句内后段"),
            (7.99, "换行前"),
            (8.0, "长句起点"),
            (12.0, "长句滑动"),
            (19.99, "末行前"),
            (20.0, "重复时间戳第一行"),
            (20.5, "重复时间戳内"),
            (30.0, "最后一行")
        ]
        let timeline = timeline()
        for (elapsed, label) in cases {
            var snap = snapshot(elapsed: elapsed, width: width, sampledAt: fixed)
            snap.timeline = timeline
            let view = NativeLyricsRowView(frame: NSRect(x: 0, y: 0, width: width, height: 17))
            view.apply(snap)
            view.render(at: fixed)
            let line = timeline.line(at: elapsed)
            let metrics = line.map { LyricsLineMetrics(line: $0) }
            let next = line.flatMap { LyricsLineFrameCache.nextStart(in: timeline.lines, after: $0.start) }
            let lineEnd = next ?? max((line?.start ?? 0) + 8, 240)
            let want = expected(line: line, metrics: metrics, elapsed: elapsed,
                                lineEnd: lineEnd, width: width)
            XCTAssertEqual(view.debugLine?.text, line?.text, label)
            XCTAssertEqual(view.debugLineEnd, lineEnd, accuracy: 0.0001, label)
            XCTAssertEqual(view.debugFill, want.fill, accuracy: 0.0001, label)
            XCTAssertEqual(view.debugOffset, want.offset, accuracy: 0.0001, label)
            view.stop()
        }
    }

    func testSeekBackwardAndForwardStillSelectsTheRightLine() {
        let width: CGFloat = 260
        let fixed = Date(timeIntervalSince1970: 1_000_000)
        let view = NativeLyricsRowView(frame: NSRect(x: 0, y: 0, width: width, height: 17))
        defer { view.stop() }
        view.apply(snapshot(elapsed: 12, width: width, sampledAt: fixed))
        XCTAssertEqual(view.debugLine?.start, 8)
        view.apply(snapshot(elapsed: 4.6, width: width, sampledAt: fixed))
        XCTAssertEqual(view.debugLine?.start, 4, "backward seek")
        view.apply(snapshot(elapsed: 30, width: width, sampledAt: fixed))
        XCTAssertEqual(view.debugLine?.start, 30, "forward seek")
    }

    func testRateAndPauseKeepTheSameAnchorSemantics() {
        let width: CGFloat = 260
        let fixed = Date(timeIntervalSince1970: 1_000_000)
        let view = NativeLyricsRowView(frame: NSRect(x: 0, y: 0, width: width, height: 17))
        defer { view.stop() }
        view.debugNow = { fixed }
        var snap = snapshot(elapsed: 4, playing: true, rate: 2, width: width, sampledAt: fixed)
        snap.timeline = timeline()
        view.apply(snap)
        view.render(at: fixed.addingTimeInterval(0.5))
        var pausedSnap = snapshot(elapsed: 4, playing: false, rate: 2, width: width, sampledAt: fixed)
        pausedSnap.timeline = timeline()
        let pausedView = NativeLyricsRowView(frame: view.frame)
        pausedView.apply(pausedSnap)
        pausedView.render(at: fixed.addingTimeInterval(0.5))
        XCTAssertGreaterThan(view.debugFill, pausedView.debugFill,
                             "2x playback advances the highlight, pausing holds it")
        pausedView.stop()
    }

    func testThirtyHertzUpdatesTouchOnlyTheMask() {
        let width: CGFloat = 260
        let fixed = Date(timeIntervalSince1970: 1_000_000)
        let view = NativeLyricsRowView(frame: NSRect(x: 0, y: 0, width: width, height: 17))
        defer { view.stop() }
        view.debugNow = { fixed }
        var snap = snapshot(elapsed: 4, playing: true, rate: 1, width: width, sampledAt: fixed)
        snap.timeline = timeline()
        view.setActive(true)
        view.apply(snap)
        XCTAssertTrue(view.debugNeedsContinuousFrames)
        XCTAssertTrue(view.debugIsClockRunning)
        let textBuilds = view.textBuilds
        let layoutPasses = view.layoutPasses
        for step in 1...30 {
            view.render(at: fixed.addingTimeInterval(Double(step) / 30.0))
        }
        XCTAssertEqual(view.textBuilds, textBuilds, "no text rebuild per frame")
        XCTAssertEqual(view.layoutPasses, layoutPasses, "no layout per frame")
        XCTAssertGreaterThan(view.maskUpdates, 5, "the mask advances with the word")
    }

    func testLineSwitchRebuildsOnceAndAnimatesWithTheSameCurve() {
        let width: CGFloat = 260
        let fixed = Date(timeIntervalSince1970: 1_000_000)
        let view = NativeLyricsRowView(frame: NSRect(x: 0, y: 0, width: width, height: 17))
        defer { view.stop() }
        view.debugNow = { fixed }
        view.setActive(true)
        view.apply(snapshot(elapsed: 4, playing: true, width: width, sampledAt: fixed))
        let builds = view.textBuilds
        view.apply(snapshot(elapsed: 8, playing: true, width: width, sampledAt: fixed))
        XCTAssertEqual(view.textBuilds, builds + 1, "one text rebuild per line change")
        XCTAssertEqual(view.lineSwitchAnimations, 1)
    }

    func testPausedHiddenAndStaticContentDoNotKeepTheClock() {
        let width: CGFloat = 260
        let fixed = Date(timeIntervalSince1970: 1_000_000)
        let view = NativeLyricsRowView(frame: NSRect(x: 0, y: 0, width: width, height: 17))
        defer { view.stop() }
        view.debugNow = { fixed }
        view.setActive(true)
        view.apply(snapshot(elapsed: 4, playing: false, width: width, sampledAt: fixed))
        XCTAssertFalse(view.debugIsClockRunning, "paused lyrics do not tick")
        view.apply(snapshot(elapsed: 4, playing: true, width: width, sampledAt: fixed))
        XCTAssertTrue(view.debugIsClockRunning)
        view.setActive(false)
        XCTAssertFalse(view.debugIsClockRunning, "hidden row stops immediately")
        view.setActive(true)
        XCTAssertTrue(view.debugIsClockRunning)
        // A short plain-LRC line is static between boundaries: no 30Hz clock,
        // but a wake at the next line start instead of a missed update.
        view.apply(snapshot(elapsed: 2, playing: true, width: width, sampledAt: Date()))
        XCTAssertFalse(view.debugIsClockRunning)
        XCTAssertTrue(view.debugHasBoundaryWake)
        view.stop()
        XCTAssertFalse(view.debugIsClockRunning)
        XCTAssertFalse(view.debugHasBoundaryWake)
    }

    // MARK: - Clock / boundary transitions

    private func wordLine(_ start: Double, _ text: String) -> LyricLine {
        LyricLine(start: start, text: text,
                  words: [LyricWord(text: text, start: start, duration: 1)])
    }

    private func spin(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    func testContinuousClockSwitchesFromScrollingLRIToShortLine() {
        let width: CGFloat = 60
        let anchor = Date(timeIntervalSince1970: 1_000_000)
        var snap = snapshot(elapsed: 0, playing: true, width: width, sampledAt: anchor)
        snap.timeline = LyricTimeline(lines: [
            LyricLine(start: 0, text: String(repeating: "长歌词", count: 20)),
            LyricLine(start: 1, text: "短句")
        ])
        let view = NativeLyricsRowView(frame: NSRect(x: 0, y: 0, width: width, height: 17))
        defer { view.stop() }
        view.debugNow = { anchor }
        view.setActive(true)
        view.apply(snap)
        XCTAssertTrue(view.debugNeedsContinuousFrames)
        view.render(at: anchor.addingTimeInterval(1.2))
        XCTAssertEqual(view.debugLine?.text, "短句")
        XCTAssertFalse(view.debugNeedsContinuousFrames)
        XCTAssertFalse(view.debugIsClockRunning, "the static line must release the 30Hz clock")
    }

    func testStaticLineWakesIntoAWordTimedLine() {
        // Boundary scheduling is derived from the current wall clock, so this
        // fixture uses a real anchor (production never passes a 1970 anchor).
        let anchor = Date()
        var snap = snapshot(elapsed: 0, playing: true, width: 260, sampledAt: anchor)
        snap.timeline = LyricTimeline(lines: [
            LyricLine(start: 0, text: "短"),
            wordLine(1, "逐字")
        ])
        let view = NativeLyricsRowView(frame: NSRect(x: 0, y: 0, width: 260, height: 17))
        defer { view.stop() }
        view.setActive(true)
        view.apply(snap)
        XCTAssertFalse(view.debugNeedsContinuousFrames)
        XCTAssertFalse(view.debugIsClockRunning)
        XCTAssertTrue(view.debugHasBoundaryWake, "a static line schedules the next boundary")
        if let delay = view.debugBoundaryDelay {
            XCTAssertEqual(delay, 1, accuracy: 0.2, "wake at the next line start")
        }
        view.render(at: anchor.addingTimeInterval(1.05))
        XCTAssertEqual(view.debugLine?.text, "逐字")
        XCTAssertTrue(view.debugNeedsContinuousFrames)
        XCTAssertTrue(view.debugIsClockRunning)
    }

    func testPauseResumeReleasesAndRestoresTheClock() {
        let anchor = Date(timeIntervalSince1970: 1_000_000)
        var snap = snapshot(elapsed: 1.05, playing: true, width: 260, sampledAt: anchor)
        snap.timeline = LyricTimeline(lines: [wordLine(1, "逐字")])
        let view = NativeLyricsRowView(frame: NSRect(x: 0, y: 0, width: 260, height: 17))
        defer { view.stop() }
        view.debugNow = { anchor }
        view.setActive(true)
        view.apply(snap)
        XCTAssertTrue(view.debugIsClockRunning)
        var paused = snap
        paused.playing = false
        view.apply(paused)
        XCTAssertFalse(view.debugIsClockRunning)
        XCTAssertFalse(view.debugHasBoundaryWake, "paused needs no boundary wake")
        view.apply(snap)
        XCTAssertTrue(view.debugIsClockRunning)
    }

    func testSeekWhileContinuousSelectsTheNewLine() {
        let anchor = Date(timeIntervalSince1970: 1_000_000)
        var snap = snapshot(elapsed: 0.2, playing: true, width: 260, sampledAt: anchor)
        snap.timeline = LyricTimeline(lines: [wordLine(0, "第一句"), wordLine(100, "第二句")])
        let view = NativeLyricsRowView(frame: NSRect(x: 0, y: 0, width: 260, height: 17))
        defer { view.stop() }
        view.debugNow = { anchor }
        view.setActive(true)
        view.apply(snap)
        XCTAssertEqual(view.debugLine?.text, "第一句")
        var forward = snap
        forward.elapsed = 100.2
        view.apply(forward)
        XCTAssertEqual(view.debugLine?.text, "第二句")
        view.apply(snap)
        XCTAssertEqual(view.debugLine?.text, "第一句", "backward seek")
    }

    func testBoundaryDeadlineUsesCurrentClockNotTheStaleAnchor() {
        let view = NativeLyricsRowView(frame: .zero)
        defer { view.stop() }
        let current = LyricLine(start: 0, text: "当前")
        var input = snapshot(elapsed: 0, playing: true, width: 260,
                             sampledAt: Date().addingTimeInterval(-0.5))
        input.timeline = LyricTimeline(lines: [current, LyricLine(start: 20, text: "后继")])
        view.setActive(true)
        view.apply(input)
        if let delay = view.debugBoundaryDelay {
            XCTAssertEqual(delay, 19.5, accuracy: 0.2,
                           "a 0.5s-old sample must not restart the full 20s from now")
        } else {
            XCTFail("no boundary scheduled")
        }
    }

    func testBoundaryDeadlineFollowsSeeksInBothDirections() {
        let view = NativeLyricsRowView(frame: .zero)
        defer { view.stop() }
        let current = LyricLine(start: 0, text: "当前")
        var input = snapshot(elapsed: 15, playing: true, width: 260, sampledAt: Date())
        input.timeline = LyricTimeline(lines: [current, LyricLine(start: 20, text: "后继")])
        view.setActive(true)
        view.apply(input)
        if let delay = view.debugBoundaryDelay {
            XCTAssertEqual(delay, 5, accuracy: 0.3, "seek near the boundary keeps the real remaining time")
        } else {
            XCTFail("no boundary scheduled")
        }
        input.elapsed = 19.5
        view.apply(input)
        if let delay = view.debugBoundaryDelay {
            XCTAssertEqual(delay, 0.5, accuracy: 0.3, "forward seek recomputes the deadline")
        } else {
            XCTFail("no boundary scheduled")
        }
        input.elapsed = 1
        view.apply(input)
        if let delay = view.debugBoundaryDelay {
            XCTAssertEqual(delay, 19, accuracy: 0.3, "backward seek recomputes the deadline")
        } else {
            XCTFail("no boundary scheduled")
        }
    }

    func testAutonomousLineSwitchNotifiesTheHostOnce() {
        let anchor = Date()
        var snap = snapshot(elapsed: 0.2, playing: true, width: 260, sampledAt: anchor)
        snap.timeline = LyricTimeline(lines: [wordLine(0, "甲"), wordLine(1, "乙")])
        let view = NativeLyricsRowView(frame: NSRect(x: 0, y: 0, width: 260, height: 17))
        defer { view.stop() }
        view.setActive(true)
        view.apply(snap)                     // initial line, no observer yet
        var labels: [String] = []
        view.onLineChange = { labels.append($0?.text ?? "nil") }
        view.render(at: anchor.addingTimeInterval(1.2))
        XCTAssertEqual(labels, ["乙"], "the host needs one notification for the new line label")
    }

    func testFirstDelayedAnchorShowsTheCurrentLineNotTheStaleSample() {
        let view = NativeLyricsRowView(frame: NSRect(x: 0, y: 0, width: 260, height: 17))
        defer { view.stop() }
        let now = Date()
        var input = snapshot(elapsed: 0, playing: true, width: 260,
                             sampledAt: now.addingTimeInterval(-0.2))
        input.timeline = LyricTimeline(lines: [
            LyricLine(start: 0, text: "甲"),
            LyricLine(start: 0.05, text: "乙", words: [
                LyricWord(text: "乙", start: 0.05, duration: 1)
            ])
        ])
        view.setActive(true)
        view.apply(input)
        XCTAssertEqual(view.debugLine?.text, "乙", "a late first anchor must not show stale progress")
        XCTAssertGreaterThan(view.debugFill, 0, "the highlight follows the displayed time")
    }

    func testReactivationCatchesUpAcrossABoundaryWithHighlight() {
        let view = NativeLyricsRowView(frame: NSRect(x: 0, y: 0, width: 260, height: 17))
        defer { view.stop() }
        var input = snapshot(elapsed: 0, playing: true, width: 260, sampledAt: Date())
        input.timeline = LyricTimeline(lines: [
            LyricLine(start: 0, text: "甲"),
            LyricLine(start: 0.05, text: "乙", words: [
                LyricWord(text: "乙", start: 0.05, duration: 1)
            ])
        ])
        view.setActive(true)
        view.apply(input)
        view.setActive(false)
        spin(0.2)
        view.setActive(true)
        XCTAssertEqual(view.debugLine?.text, "乙")
        XCTAssertGreaterThan(view.debugFill, 0, "recovery refreshes the highlight too")
    }

    func testHostCallbackReentrancyDoesNotRewindOrLoop() {
        let anchor = Date()
        var snap = snapshot(elapsed: 0.01, playing: true, width: 260, sampledAt: anchor)
        snap.timeline = LyricTimeline(lines: [wordLine(0, "甲"), wordLine(0.15, "乙")])
        let view = NativeLyricsRowView(frame: NSRect(x: 0, y: 0, width: 260, height: 17))
        defer { view.stop() }
        view.setActive(true)
        // Deterministic display clock: the re-entrant host update must see the
        // same instant as the frame that triggered it.
        view.debugNow = { anchor }
        view.apply(snap)
        var callbacks = 0
        view.onLineChange = { _ in
            callbacks += 1
            // The host's accessibility state triggers another updateNSView.
            view.apply(snap)
        }
        view.debugNow = { anchor.addingTimeInterval(0.16) }
        view.render(at: anchor.addingTimeInterval(0.16))
        XCTAssertEqual(view.debugLine?.text, "乙")
        XCTAssertEqual(callbacks, 1, "one notification, no switch feedback loop")
        XCTAssertEqual(view.lineSwitchAnimations, 1, "re-entrant apply must not switch again")
    }

    func testPausedProgressStaysPinnedWhileTimePasses() {
        let view = NativeLyricsRowView(frame: NSRect(x: 0, y: 0, width: 260, height: 17))
        defer { view.stop() }
        var input = snapshot(elapsed: 5, playing: false, width: 260, sampledAt: Date())
        input.timeline = LyricTimeline(lines: [
            LyricLine(start: 5, text: "暂停行", words: [
                LyricWord(text: "暂停", start: 5, duration: 2)
            ])
        ])
        view.setActive(true)
        view.apply(input)
        let line = view.debugLine
        let fill = view.debugFill
        spin(0.2)
        view.apply(input)
        XCTAssertEqual(view.debugLine, line)
        XCTAssertEqual(view.debugFill, fill, accuracy: 0.0001,
                       "a paused anchor keeps its progress instead of extrapolating")
    }

    func testRealSeekMovesInBothDirections() {
        let view = NativeLyricsRowView(frame: NSRect(x: 0, y: 0, width: 260, height: 17))
        defer { view.stop() }
        var input = snapshot(elapsed: 0, playing: true, width: 260, sampledAt: Date())
        input.timeline = LyricTimeline(lines: [wordLine(0, "甲"), wordLine(5, "乙"), wordLine(10, "丙")])
        view.setActive(true)
        view.apply(input)
        XCTAssertEqual(view.debugLine?.text, "甲")
        input.elapsed = 10
        input.sampledAt = Date()
        view.apply(input)
        XCTAssertEqual(view.debugLine?.text, "丙", "forward seek")
        input.elapsed = 5
        input.sampledAt = Date()
        view.apply(input)
        XCTAssertEqual(view.debugLine?.text, "乙", "backward seek")
    }

    // MARK: - Drawing / geometry invalidation

    func testAccentAndScaleUpdateDrawingWithoutRebuildingText() {
        let anchor = Date(timeIntervalSince1970: 1_000_000)
        var snap = snapshot(elapsed: 0, playing: false, width: 260, sampledAt: anchor)
        snap.timeline = LyricTimeline(lines: [LyricLine(start: 0, text: "当前行")])
        snap.accent = .systemRed
        let view = NativeLyricsRowView(frame: NSRect(x: 0, y: 0, width: 260, height: 17))
        defer { view.stop() }
        view.apply(snap)
        XCTAssertEqual(view.textBuilds, 1)
        XCTAssertTrue(view.debugAccentColor?.isEqual(NSColor.systemRed) == true)
        let width = view.debugTextWidth

        var blue = snap
        blue.accent = .systemBlue
        view.apply(blue)
        XCTAssertTrue(view.debugAccentColor?.isEqual(NSColor.systemBlue) == true)
        XCTAssertEqual(view.textBuilds, 1, "a colour change must not rebuild the text")
        XCTAssertEqual(view.debugTextWidth, width, accuracy: 0.001)

        view.debugSetBackingScale(1)
        XCTAssertEqual(view.debugContentsScale, 1, "a scale change must reach the layers")
        XCTAssertEqual(view.textBuilds, 1)
        view.debugSetBackingScale(2)
        XCTAssertEqual(view.debugContentsScale, 2)
    }

    func testKerningAndVerticalOffsetKeepTheirOwnInvalidation() {
        let anchor = Date(timeIntervalSince1970: 1_000_000)
        var snap = snapshot(elapsed: 0, playing: false, width: 260, sampledAt: anchor)
        snap.timeline = LyricTimeline(lines: [LyricLine(start: 0, text: "ABCDEFGHIJ")])
        snap.textKern = 0
        let view = NativeLyricsRowView(frame: NSRect(x: 0, y: 0, width: 260, height: 17))
        defer { view.stop() }
        view.apply(snap)
        let width = view.debugTextWidth
        let builds = view.textBuilds

        var kerned = snap
        kerned.textKern = 2
        view.apply(kerned)
        XCTAssertGreaterThan(view.debugTextWidth, width + 10)
        XCTAssertEqual(view.textBuilds, builds + 1, "kerning re-measures the text")
        XCTAssertNotEqual(view.debugTextWidth, width)

        var lifted = kerned
        lifted.verticalOffset = 0
        let buildsAfterKern = view.textBuilds
        let kernedY = view.debugTextFrameY
        view.apply(lifted)
        XCTAssertEqual(view.debugTextFrameY, kernedY + 2, accuracy: 0.001,
                       "vertical calibration is a layout change")
        XCTAssertEqual(view.textBuilds, buildsAfterKern, "layout must not rebuild text")
    }

    func testLineEndUpdateNeverRebuildsTextOrAnimates() {
        let anchor = Date(timeIntervalSince1970: 1_000_000)
        let current = LyricLine(start: 0, text: "当前行")
        var snap = snapshot(elapsed: 0, playing: false, width: 260, sampledAt: anchor)
        snap.timeline = LyricTimeline(lines: [current, LyricLine(start: 20, text: "旧后继")])
        let view = NativeLyricsRowView(frame: NSRect(x: 0, y: 0, width: 260, height: 17))
        defer { view.stop() }
        view.apply(snap)
        XCTAssertEqual(view.debugLineEnd, 20)
        let builds = view.textBuilds

        snap.timeline = LyricTimeline(lines: [current, LyricLine(start: 10, text: "新后继")])
        view.apply(snap)
        XCTAssertEqual(view.debugLineEnd, 10)
        XCTAssertEqual(view.textBuilds, builds, "the line did not change")
        XCTAssertEqual(view.lineSwitchAnimations, 0, "no switch replay for a boundary change")
    }

    // MARK: - Switch animation

    func testRapidSwitchesKeepOwnershipAndSettle() {
        let anchor = Date()
        var snap = snapshot(elapsed: 0.01, playing: true, width: 260, sampledAt: anchor)
        snap.timeline = LyricTimeline(lines: [wordLine(0, "甲"), wordLine(0.15, "乙"),
                                              wordLine(0.3, "丙")])
        let view = NativeLyricsRowView(frame: NSRect(x: 0, y: 0, width: 260, height: 17))
        defer { view.stop() }
        // No live clock here: this case injects future frame times, and the
        // clock's own wall-clock ticks would legitimately disagree with them.
        view.setActive(false)
        view.apply(snap)
        view.render(at: anchor.addingTimeInterval(0.16))
        XCTAssertEqual(view.debugLine?.text, "乙")
        view.render(at: anchor.addingTimeInterval(0.31))
        XCTAssertEqual(view.debugLine?.text, "丙")
        XCTAssertEqual(view.lineSwitchAnimations, 2)
        XCTAssertLessThanOrEqual(view.debugOutgoingLayers, 1, "an older outgoing layer is replaced")
        spin(0.4)
        XCTAssertEqual(view.debugOutgoingLayers, 0)
        XCTAssertEqual(view.debugLine?.text, "丙", "an old cleanup must not disturb the current line")
    }

    func testAnimationCompletionRedrawsAtTheCurrentTime() {
        let anchor = Date()
        var snap = snapshot(elapsed: 0.01, playing: true, width: 260, sampledAt: anchor)
        snap.timeline = LyricTimeline(lines: [
            LyricLine(start: 0, text: "甲乙丙", words: [
                LyricWord(text: "甲", start: 0, duration: 0.1),
                LyricWord(text: "乙", start: 0.1, duration: 0.1),
                LyricWord(text: "丙", start: 0.2, duration: 2)
            ]),
            wordLine(0.15, "切句")
        ])
        let view = NativeLyricsRowView(frame: NSRect(x: 0, y: 0, width: 260, height: 17))
        defer { view.stop() }
        view.setActive(true)
        view.apply(snap)
        view.render(at: anchor.addingTimeInterval(0.16))   // crosses into 切句
        XCTAssertEqual(view.debugLine?.text, "切句")
        let fillAtSwitch = view.debugFill
        let renderAtSwitch = view.debugLastRenderDate
        spin(0.4)
        XCTAssertGreaterThan(view.debugLastRenderDate, renderAtSwitch,
                             "the cleanup redraws at the current time")
        XCTAssertGreaterThan(view.debugFill, fillAtSwitch,
                             "the highlight must not rewind to the switch moment")
    }

    // MARK: - Pixel evidence (opt-in; source of the report's numbers)

    private func model(elapsed: Double, lines: [LyricLine]) -> (AppModel, String) {
        let suite = "com.wangqing.valora.native-lyrics-row.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(["nowPlayingEnabled": true, "showLyrics": true],
                     forKey: "referenceSettingsUI")
        defaults.set(true, forKey: "enableNowPlaying")
        let settings = RevivalSettings(defaults: defaults)
        let model = AppModel(settings: settings)
        model.title = "Probe"
        model.duration = 240
        model.lyrics = LyricsDisplayState(status: .ready, timeline: LyricTimeline(lines: lines),
                                          identity: nil)
        // A solid artwork gives the shipped row (and the snapshot) the same
        // non-grey accent, so the fill edge is measurable in pixels.
        let artwork = NSImage(size: NSSize(width: 64, height: 64))
        artwork.lockFocus()
        NSColor.systemRed.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 64, height: 64)).fill()
        artwork.unlockFocus()
        model.artwork = artwork
        model.playing = false
        model.playbackRate = 1
        model.setElapsed(elapsed, sampledAt: Date())
        return (model, suite)
    }

    private func bitmap(of view: NSView, scale: CGFloat = 2) -> NSBitmapImageRep? {
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        view.layer?.displayIfNeeded()
        let w = Int((view.bounds.width * scale).rounded())
        let h = Int((view.bounds.height * scale).rounded())
        guard w > 1, h > 1,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                         isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = view.bounds.size
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep
    }

    private func pixels(_ rep: NSBitmapImageRep) -> [UInt8]? {
        guard let cg = rep.cgImage else { return nil }
        let w = cg.width, h = cg.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        return data
    }

    private func inkBounds(_ data: [UInt8], width: Int, height: Int) -> CGRect? {
        var minX = width, maxX = -1, minY = height, maxY = -1
        for y in 0..<height { for x in 0..<width {
            if data[(y * width + x) * 4 + 3] > 20 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        } }
        guard maxX >= 0 else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    /// Right-most x where the pixel is accent-dominant (the coloured fill).
    private func fillBoundary(_ data: [UInt8], width: Int, height: Int) -> Int? {
        var result: Int?
        for y in 0..<height { for x in 0..<width {
            let i = (y * width + x) * 4
            let r = Int(data[i]), g = Int(data[i + 1]), b = Int(data[i + 2])
            if data[i + 3] > 20, r > g + 40, r > b + 40 { result = max(result ?? -1, x) }
        } }
        return result
    }

    /// Integer horizontal shift that best aligns the two captures, and its
    /// residual difference. A large gain means a real x-phase offset rather
    /// than anti-aliasing.
    private func bestShift(_ a: [UInt8], _ b: [UInt8], width: Int, height: Int) -> (dx: Int, differing: Int) {
        func score(_ dx: Int) -> Int {
            var differing = 0
            for y in 0..<height {
                for x in 0..<width {
                    let sx = x + dx
                    guard sx >= 0, sx < width else { continue }
                    let i = (y * width + x) * 4, j = (y * width + sx) * 4
                    let delta = abs(Int(a[i]) - Int(b[j])) + abs(Int(a[i + 1]) - Int(b[j + 1]))
                        + abs(Int(a[i + 2]) - Int(b[j + 2]))
                    if delta > 12 { differing += 1 }
                }
            }
            return differing
        }
        var best = (dx: 0, differing: score(0))
        for dx in -8...8 where dx != 0 {
            let value = score(dx)
            if value < best.differing { best = (dx, value) }
        }
        return best
    }

    private func diff(_ a: [UInt8], _ b: [UInt8]) -> (differing: Int, mean: Double) {
        var differing = 0
        var total = 0
        for index in stride(from: 0, to: a.count, by: 4) {
            let delta = abs(Int(a[index]) - Int(b[index]))
                + abs(Int(a[index + 1]) - Int(b[index + 1]))
                + abs(Int(a[index + 2]) - Int(b[index + 2]))
            if delta > 12 { differing += 1 }
            total += delta
        }
        return (differing, Double(total) / Double(a.count / 4) / 3.0)
    }

    private struct PixelCase {
        let name: String
        let lines: [LyricLine]
        let elapsed: Double
    }

    private func pixelCases() -> [PixelCase] {
        let long = LyricLine(start: 0, text: "这是一句没有逐字时间的长歌词，用于确认整行滚动仍然使用真实的行边界，并且不会在换行时跳到错误的位置")
        let words = LyricLine(start: 0, text: "逐字高亮示例", words: [
            LyricWord(text: "逐字", start: 0, duration: 0.6),
            LyricWord(text: "高亮", start: 0.6, duration: 0.6),
            LyricWord(text: "示例", start: 1.2, duration: 0.8)
        ])
        return [
            PixelCase(name: "zh-short", lines: [LyricLine(start: 0, text: "前奏")], elapsed: 0.5),
            PixelCase(name: "en-short", lines: [LyricLine(start: 0, text: "Hello world")], elapsed: 0.5),
            PixelCase(name: "emoji", lines: [LyricLine(start: 0, text: "你好 🎵 世界")], elapsed: 0.5),
            PixelCase(name: "zh-word-fill", lines: [words], elapsed: 0.9),
            PixelCase(name: "zh-long-scroll", lines: [long], elapsed: 0.4),
        ]
    }

    func testPrototypePixelsAgainstTheShippedRow() throws {
        guard ProcessInfo.processInfo.environment["VALORA_ROW_PIXEL_PROBE"] == "1" else {
            throw XCTSkip("set VALORA_ROW_PIXEL_PROBE=1 to run the pixel comparison")
        }
        let width: CGFloat = 220
        let fixed = Date(timeIntervalSince1970: 1_000_000)
        let only = ProcessInfo.processInfo.environment["VALORA_ROW_PIXEL_CASE"]
        let scaleFilter = ProcessInfo.processInfo.environment["VALORA_ROW_PIXEL_SCALE"].flatMap(Double.init)
        let outputDirectory = URL(fileURLWithPath: "/private/tmp/valora-row-r2", isDirectory: true)
        try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        var captured = 0
        for testCase in pixelCases() where only == nil || only == testCase.name {
            for scale in [CGFloat(1), CGFloat(2)] where scaleFilter == nil || Double(scale) == scaleFilter {
                let (model, suite) = model(elapsed: testCase.elapsed, lines: testCase.lines)
                defer { UserDefaults().removePersistentDomain(forName: suite) }
                let host = NSHostingView(rootView: CompactLyricsView(
                    model: model, width: width, rowHeight: 17, showsNote: false, horizontalInset: 0))
                host.frame = NSRect(x: 0, y: 0, width: width, height: 17)
                let window = NSWindow(contentRect: host.frame, styleMask: .borderless,
                                      backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
                window.contentView = host
                window.orderFrontRegardless()
                RunLoop.main.run(until: Date().addingTimeInterval(0.12))

                var snap = snapshot(elapsed: testCase.elapsed, width: width, sampledAt: fixed)
                snap.timeline = LyricTimeline(lines: testCase.lines)
                // Match the shipped row's accent (no artwork in this fixture).
                snap.accent = model.lyricsAccentColor
                let native = NativeLyricsRowView(frame: NSRect(x: 0, y: 0, width: width, height: 17))
                native.apply(snap)
                native.render(at: fixed)
                let nativeWindow = NSWindow(contentRect: native.frame, styleMask: .borderless,
                                            backing: .buffered, defer: false)
                nativeWindow.isReleasedWhenClosed = false
                nativeWindow.setFrameOrigin(NSPoint(x: -20000, y: -20000))
                nativeWindow.contentView = native
                nativeWindow.orderFrontRegardless()
                RunLoop.main.run(until: Date().addingTimeInterval(0.05))

                guard let a = bitmap(of: host, scale: scale), let b = bitmap(of: native, scale: scale),
                      let pa = pixels(a), let pb = pixels(b), pa.count == pb.count else {
                    XCTFail("pixel capture failed for \(testCase.name) at scale \(scale)")
                    native.stop(); nativeWindow.close(); window.close()
                    continue
                }
                let d = diff(pa, pb)
                let w = a.pixelsWide, h = a.pixelsHigh
                let shift = bestShift(pa, pb, width: w, height: h)
                let shippedFill = fillBoundary(pa, width: w, height: h)
                let nativeFill = fillBoundary(pb, width: w, height: h)
                let stem = "\(testCase.name)-x\(Int(scale))"
                if let data = a.representation(using: .png, properties: [:]) {
                    try? data.write(to: outputDirectory.appendingPathComponent("shipped-\(stem).png"))
                }
                if let data = b.representation(using: .png, properties: [:]) {
                    try? data.write(to: outputDirectory.appendingPathComponent("native-\(stem).png"))
                }
                captured += 1
                print(String(format: "ROWDIFF %@ scale=%.0f differing=%d/%d (%.1f%%) mean=%.2f bestShift=%d/%d fill=%@/%@ ink=%@/%@",
                             testCase.name, Double(scale), d.differing, w * h,
                             Double(d.differing) / Double(w * h) * 100, d.mean,
                             shift.dx, shift.differing,
                             String(describing: shippedFill), String(describing: nativeFill),
                             String(describing: inkBounds(pa, width: w, height: h)),
                             String(describing: inkBounds(pb, width: w, height: h))))
                native.stop()
                nativeWindow.close()
                window.close()
            }
        }
        XCTAssertGreaterThan(captured, 0, "the probe must capture at least one case")
    }
}
