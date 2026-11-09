import AppKit
import XCTest
import ReferenceCore
@testable import Valora

@MainActor
final class IndependentNativeLyricsRowTests: XCTestCase {
    private let anchor = Date(timeIntervalSince1970: 1_000_000)

    private func snapshot(_ lines: [LyricLine]) -> NativeLyricsRowSnapshot {
        NativeLyricsRowSnapshot(identity: nil, timeline: LyricTimeline(lines: lines),
                                elapsed: 0, sampledAt: anchor, rate: 1,
                                playing: true, duration: 100, width: 260)
    }

    func testContinuousFramesAdvanceLineWithoutNewHostSnapshot() {
        let first = LyricLine(start: 0, text: "第一句", words: [
            LyricWord(text: "第一句", start: 0, duration: 1)
        ])
        let second = LyricLine(start: 1, text: "第二句")
        let view = NativeLyricsRowView(frame: NSRect(x: 0, y: 0, width: 260, height: 17))
        defer { view.stop() }
        // Deterministic display clock matching the synthetic anchor.
        view.debugNow = { self.anchor }
        view.apply(snapshot([first, second]))
        XCTAssertTrue(view.debugNeedsContinuousFrames)
        // clockTick and render share update(at:). No host update occurs at
        // this boundary: the renderer must extrapolate AND select the line.
        view.render(at: anchor.addingTimeInterval(1.1))
        XCTAssertEqual(view.debugLine, second, "continuous playback must switch at the lyric boundary")
        XCTAssertFalse(view.debugNeedsContinuousFrames, "the new short LRC line should stop continuous frames")
    }

    func testReplacementTimelineRefreshesUnchangedCurrentLineEnd() {
        let current = LyricLine(start: 0, text: "当前行")
        let view = NativeLyricsRowView(frame: .zero)
        defer { view.stop() }
        view.debugNow = { self.anchor }
        view.apply(snapshot([current, LyricLine(start: 20, text: "旧后继")]))
        XCTAssertEqual(view.debugLineEnd, 20)
        view.apply(snapshot([current, LyricLine(start: 10, text: "新后继")]))
        XCTAssertEqual(view.debugLineEnd, 10, "same current line does not imply the same successor")
    }

    func testDurationUpdateRefreshesLastLineFallback() {
        let view = NativeLyricsRowView(frame: .zero)
        defer { view.stop() }
        view.debugNow = { self.anchor }
        var input = snapshot([LyricLine(start: 0, text: "末行")])
        view.apply(input)
        XCTAssertEqual(view.debugLineEnd, 100)
        input.duration = 120
        view.apply(input)
        XCTAssertEqual(view.debugLineEnd, 120)
    }

    func testKerningChangeRebuildsTextWithUnchangedLine() {
        let view = NativeLyricsRowView(frame: .zero)
        defer { view.stop() }
        view.debugNow = { self.anchor }
        var input = snapshot([LyricLine(start: 0, text: "ABCDEFGHIJ")])
        input.textKern = 0
        view.apply(input)
        let before = view.debugTextWidth
        input.textKern = 2
        view.apply(input)
        XCTAssertGreaterThan(view.debugTextWidth, before + 10,
                             "changed drawing attributes must invalidate the attributed text")
    }

    func testStaticBoundaryWakeReschedulesWhenTimelineChanges() throws {
        let view = NativeLyricsRowView(frame: .zero)
        defer { view.stop() }
        let current = LyricLine(start: 0, text: "当前")
        var input = snapshot([current, LyricLine(start: 20, text: "后继")])
        input.sampledAt = Date()
        view.setActive(true)
        view.apply(input)
        XCTAssertGreaterThan(try XCTUnwrap(view.debugBoundaryDelay), 19)
        input.timeline = LyricTimeline(lines: [current, LyricLine(start: 1, text: "提前")])
        view.apply(input)
        XCTAssertEqual(view.debugLineEnd, 1)
        XCTAssertLessThan(try XCTUnwrap(view.debugBoundaryDelay), 1.1,
                          "updating lineEnd must also replace the stale boundary timer")
    }

    func testStaticBoundaryWakeReschedulesWhenPlaybackRateChanges() throws {
        let view = NativeLyricsRowView(frame: .zero)
        defer { view.stop() }
        var input = snapshot([LyricLine(start: 0, text: "当前"),
                              LyricLine(start: 20, text: "后继")])
        input.sampledAt = Date()
        view.setActive(true)
        view.apply(input)
        input.rate = 2
        view.apply(input)
        XCTAssertLessThan(try XCTUnwrap(view.debugBoundaryDelay), 10.1,
                          "double-speed playback must wake at the new deadline")
    }

    func testOutgoingLinePreservesHorizontalPositionAtSwitch() throws {
        let view = NativeLyricsRowView(frame: NSRect(x: 0, y: 0, width: 260, height: 17))
        defer { view.stop() }
        var input = snapshot([LyricLine(start: 0, text: "甲"), LyricLine(start: 1, text: "乙")])
        input.playing = false
        view.apply(input)
        let clip = try XCTUnwrap(view.layer?.sublayers?.first)
        let incoming = try XCTUnwrap(clip.sublayers?.first)
        let originalX = incoming.position.x
        XCTAssertGreaterThan(originalX, 50, "fixture is centered")
        input.elapsed = 1
        view.apply(input)
        let outgoing = try XCTUnwrap(clip.sublayers?.first(where: { $0 !== incoming }))
        XCTAssertEqual(outgoing.position.x, originalX, accuracy: 0.001,
                       "the departing lyric must not jump horizontally when switching")
    }

    func testRealBoundaryTimerAdvancesWithoutHostUpdate() {
        let view = NativeLyricsRowView(frame: .zero)
        defer { view.stop() }
        var input = snapshot([LyricLine(start: 0, text: "甲"), LyricLine(start: 0.05, text: "乙")])
        input.sampledAt = Date()
        view.setActive(true)
        view.apply(input)
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        XCTAssertEqual(view.debugLine?.text, "乙", "the real timer must select the second line")
    }

    func testReapplyingSameAnchorAfterAutonomousSwitchDoesNotRewind() {
        let view = NativeLyricsRowView(frame: .zero)
        defer { view.stop() }
        var input = snapshot([LyricLine(start: 0, text: "甲"), LyricLine(start: 0.05, text: "乙")])
        input.sampledAt = Date()
        view.setActive(true)
        view.apply(input)
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        XCTAssertEqual(view.debugLine?.text, "乙")
        // A SwiftUI state/accessibility update can resend the same playback
        // anchor. This is not a seek; time must continue from that anchor.
        view.setActive(true)
        view.apply(input)
        XCTAssertEqual(view.debugLine?.text, "乙", "host redraw must not rewind autonomous playback")
    }

    func testReactivatingStaticLineCatchesUpAcrossMissedBoundary() {
        let view = NativeLyricsRowView(frame: .zero)
        defer { view.stop() }
        var input = snapshot([LyricLine(start: 0, text: "甲"), LyricLine(start: 0.05, text: "乙")])
        input.sampledAt = Date()
        view.setActive(true)
        view.apply(input)
        view.setActive(false)
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        view.setActive(true)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertEqual(view.debugLine?.text, "乙", "visibility recovery must catch up to the current line")
    }

    func testValidPlaybackAnchorOlderThanOneMinuteStillInterpolates() {
        let view = NativeLyricsRowView(frame: .zero)
        defer { view.stop() }
        var input = snapshot([LyricLine(start: 0, text: "甲"),
                              LyricLine(start: 60, text: "乙")])
        input.sampledAt = Date().addingTimeInterval(-61)
        view.setActive(true)
        view.apply(input)
        XCTAssertEqual(view.debugLine?.text, "乙",
                       "anchor age must not silently reset valid playing progress")
    }
}
