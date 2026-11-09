import AppKit
import Foundation
import SwiftUI
import XCTest
import ReferenceCore
@testable import Valora

/// Isolated verification for the SwiftUI static-text-image backend. The shipped
/// `CompactLyricsView` is untouched; these tests only compare the two prototype
/// text backends and reuse the R4 scheduling/lifecycle tests' expectations.
@MainActor
final class SwiftUITextFidelityTests: XCTestCase {
    private func timeline() -> LyricTimeline {
        LyricTimeline(lines: [
            LyricLine(start: 0, text: "前奏"),
            LyricLine(start: 4, text: "逐字高亮示例", words: [
                LyricWord(text: "逐字", start: 4, duration: 0.6),
                LyricWord(text: "高亮", start: 4.6, duration: 0.6),
                LyricWord(text: "示例", start: 5.2, duration: 0.8)
            ]),
            LyricLine(start: 8, text: "这是一句没有逐字时间的长歌词，用于确认整行滚动仍然使用真实的行边界"),
            LyricLine(start: 30, text: "末句")
        ])
    }

    private func snapshot(elapsed: Double, playing: Bool = false, rate: Double = 1,
                          width: CGFloat = 260, sampledAt: Date,
                          backend: NativeLyricsTextBackend) -> NativeLyricsRowSnapshot {
        NativeLyricsRowSnapshot(identity: nil, timeline: timeline(), elapsed: elapsed,
                                sampledAt: sampledAt, rate: rate, playing: playing,
                                duration: 240, width: width, rowHeight: 17,
                                accent: .systemRed, textBackend: backend)
    }

    private func view(_ backend: NativeLyricsTextBackend, width: CGFloat = 260)
        -> NativeLyricsRowView {
        let view = NativeLyricsRowView(frame: NSRect(x: 0, y: 0, width: width, height: 17))
        view.debugSetBackingScale(2)
        return view
    }

    func testSwiftUIBackendPreparesStaticImages() {
        let fixed = Date(timeIntervalSince1970: 1_000_000)
        let row = view(.swiftUI)
        defer { row.stop() }
        row.debugNow = { fixed }
        row.apply(snapshot(elapsed: 4.3, width: 260, sampledAt: fixed, backend: .swiftUI))
        XCTAssertTrue(row.debugUsesImageContents)
        XCTAssertGreaterThan(row.debugImagePointSize.width, 10)
        XCTAssertGreaterThan(row.debugImagePointSize.height, 8)
        XCTAssertEqual(row.debugImagePixelSize.width,
                       ceil(row.debugImagePointSize.width * 2), accuracy: 0.5)
        XCTAssertEqual(row.debugImagePixelSize.height,
                       ceil(row.debugImagePointSize.height * 2), accuracy: 0.5)
        XCTAssertEqual(row.imageBuilds, 2, "one base and one accent image")
        XCTAssertEqual(row.textBuilds, 1)
        XCTAssertGreaterThan(row.debugImageByteEstimate, 0)
    }

    func testThirtyFramesInsideOneLinePrepareNothing() {
        let anchor = Date()
        var input = snapshot(elapsed: 4, playing: true, width: 260, sampledAt: anchor,
                             backend: .swiftUI)
        input.timeline = timeline()
        let row = view(.swiftUI)
        defer { row.stop() }
        row.setActive(true)
        row.apply(input)
        let textBuilds = row.textBuilds
        let imageBuilds = row.imageBuilds
        let hostingLayouts = row.hostingLayouts
        let rootUpdates = row.rootViewUpdates
        for step in 1...30 {
            row.render(at: anchor.addingTimeInterval(Double(step) / 30.0))
        }
        XCTAssertEqual(row.textBuilds, textBuilds)
        XCTAssertEqual(row.imageBuilds, imageBuilds, "no bitmap generation per frame")
        XCTAssertEqual(row.hostingLayouts, hostingLayouts, "no hosting layout per frame")
        XCTAssertEqual(row.rootViewUpdates, rootUpdates, "no rootView update per frame")
        XCTAssertGreaterThan(row.maskUpdates, 5)
    }

    func testLineChangePreparesOnePairAndOutgoingSharesIt() {
        let anchor = Date()
        var input = snapshot(elapsed: 4, playing: true, width: 260, sampledAt: anchor,
                             backend: .swiftUI)
        input.timeline = timeline()
        let row = view(.swiftUI)
        defer { row.stop() }
        row.setActive(true)
        row.apply(input)
        let images = row.imageBuilds
        let builds = row.textBuilds
        row.render(at: anchor.addingTimeInterval(0.2) + 8.0 - 4.0)  // past the next boundary

        XCTAssertEqual(row.textBuilds, builds + 1, "one preparation per line change")
        XCTAssertEqual(row.imageBuilds, images + 2, "one base+accent pair per line change")
        XCTAssertEqual(row.debugOutgoingLayers, 1)
        XCTAssertTrue(row.debugOutgoingHasImage, "the departing line keeps the prepared image")
    }

    func testBackendSwitchRebuildsOnceAndFramesAreFree() {
        let fixed = Date(timeIntervalSince1970: 1_000_000)
        let row = view(.swiftUI)
        defer { row.stop() }
        row.debugNow = { fixed }
        var input = snapshot(elapsed: 4.3, width: 260, sampledAt: fixed, backend: .coreText)
        row.apply(input)
        XCTAssertEqual(row.textBuilds, 1)
        XCTAssertFalse(row.debugUsesImageContents)

        input.textBackend = .swiftUI
        row.apply(input)
        XCTAssertEqual(row.textBuilds, 2, "switching backends prepares once")
        XCTAssertTrue(row.debugUsesImageContents)
        let builds = row.textBuilds
        row.render(at: fixed)
        XCTAssertEqual(row.textBuilds, builds, "no rebuild on a later frame")

        input.textBackend = .coreText
        row.apply(input)
        XCTAssertEqual(row.textBuilds, builds + 1)
        XCTAssertFalse(row.debugUsesImageContents)
    }

    // MARK: - R4 behaviour preserved with the image backend

    func testContinuousSwitchWithImageBackend() {
        let anchor = Date()
        var input = snapshot(elapsed: 1.5, playing: true, width: 260, sampledAt: anchor,
                             backend: .swiftUI)
        input.timeline = LyricTimeline(lines: [
            LyricLine(start: 0, text: "甲", words: [LyricWord(text: "甲", start: 0, duration: 1)]),
            LyricLine(start: 2, text: "乙")
        ])
        let row = view(.swiftUI)
        defer { row.stop() }
        row.setActive(true)
        row.apply(input)
        XCTAssertEqual(row.debugLine?.text, "甲")
        row.render(at: anchor.addingTimeInterval(2.2))
        XCTAssertEqual(row.debugLine?.text, "乙")
        XCTAssertFalse(row.debugNeedsContinuousFrames)
    }

    func testPausedSeekWithImageBackend() {
        let fixed = Date(timeIntervalSince1970: 1_000_000)
        let row = view(.swiftUI)
        defer { row.stop() }
        row.debugNow = { fixed }
        var input = snapshot(elapsed: 4.3, width: 260, sampledAt: fixed, backend: .swiftUI)
        row.apply(input)
        XCTAssertEqual(row.debugLine?.start, 4)
        input.elapsed = 30
        row.apply(input)
        XCTAssertEqual(row.debugLine?.start, 30)
        input.elapsed = 4.6
        row.apply(input)
        XCTAssertEqual(row.debugLine?.start, 4)
    }

    func testHostRedrawOfSameAnchorDoesNotRewindWithImageBackend() {
        let anchor = Date()
        var input = snapshot(elapsed: 0, playing: true, width: 260, sampledAt: anchor,
                             backend: .swiftUI)
        input.timeline = LyricTimeline(lines: [
            LyricLine(start: 0, text: "甲"),
            LyricLine(start: 0.05, text: "乙")
        ])
        let row = view(.swiftUI)
        defer { row.stop() }
        row.setActive(true)
        row.apply(input)
        spin(0.15)
        XCTAssertEqual(row.debugLine?.text, "乙")
        row.setActive(true)
        row.apply(input)
        XCTAssertEqual(row.debugLine?.text, "乙", "host redraw must not rewind")
    }

    func testHiddenRecoveryAndOldAnchorWithImageBackend() {
        let row = view(.swiftUI)
        defer { row.stop() }
        var input = snapshot(elapsed: 0, playing: true, width: 260, sampledAt: Date(),
                             backend: .swiftUI)
        input.timeline = LyricTimeline(lines: [
            LyricLine(start: 0, text: "甲"),
            LyricLine(start: 0.05, text: "乙")
        ])
        row.setActive(true)
        row.apply(input)
        row.setActive(false)
        spin(0.2)
        row.setActive(true)
        XCTAssertEqual(row.debugLine?.text, "乙", "recovery catches up across the boundary")

        // 61s-old valid anchor: the line at 61s must show, not the anchor line.
        var old = snapshot(elapsed: 0, playing: true, width: 260,
                           sampledAt: Date().addingTimeInterval(-61), backend: .swiftUI)
        old.timeline = LyricTimeline(lines: [
            LyricLine(start: 0, text: "甲"),
            LyricLine(start: 60, text: "乙")
        ])
        row.apply(old)
        XCTAssertEqual(row.debugLine?.text, "乙", "anchor age must not reset valid progress")
    }

    func testStopReleasesClockAndImageCache() {
        let fixed = Date(timeIntervalSince1970: 1_000_000)
        let row = view(.swiftUI)
        row.debugNow = { fixed }
        var input = snapshot(elapsed: 4, playing: true, width: 260, sampledAt: fixed,
                             backend: .swiftUI)
        input.timeline = timeline()
        row.setActive(true)
        row.apply(input)
        XCTAssertTrue(row.debugIsClockRunning)
        XCTAssertGreaterThan(row.imageBuilds, 0)
        row.stop()
        XCTAssertFalse(row.debugIsClockRunning)
        XCTAssertEqual(row.debugOutgoingLayers, 0)
        XCTAssertFalse(row.debugUsesImageContents, "stopping releases the image cache")
        XCTAssertEqual(row.debugImagePointSize, .zero)
        // A later host update can prepare again.
        row.setActive(true)
        row.apply(input)
        XCTAssertTrue(row.debugUsesImageContents)
        row.stop()
    }

    func testFirstImageFailureClearsOldVisualsAndRecordsFailure() {
        let fixed = Date(timeIntervalSince1970: 1_000_000)
        let row = view(.swiftUI)
        defer { row.stop() }
        row.debugNow = { fixed }
        var input = snapshot(elapsed: 0, width: 260, sampledAt: fixed, backend: .swiftUI)
        input.timeline = LyricTimeline(lines: [LyricLine(start: 0, text: "旧歌词")])
        row.apply(input)
        XCTAssertTrue(row.debugUsesImageContents)
        let failures = row.imageRenderFailures

        input.timeline = LyricTimeline(lines: [LyricLine(start: 0, text: "新歌词")])
        row.debugFailImageRender = [1]          // the base image fails
        row.apply(input)
        XCTAssertTrue(row.debugImageRenderFailed)
        XCTAssertEqual(row.imageRenderFailures, failures + 1)
        XCTAssertFalse(row.debugUsesImageContents, "the old bitmap must not stay visible")
        XCTAssertEqual(row.debugImagePointSize, .zero)
        XCTAssertFalse(row.debugIsClockRunning)
        row.debugFailImageRender = []
        row.stop()
    }

    func testSecondImageFailureIsAlsoAtomic() {
        let fixed = Date(timeIntervalSince1970: 1_000_000)
        let row = view(.swiftUI)
        defer { row.stop() }
        row.debugNow = { fixed }
        var input = snapshot(elapsed: 0, width: 260, sampledAt: fixed, backend: .swiftUI)
        input.timeline = LyricTimeline(lines: [LyricLine(start: 0, text: "歌词")])
        row.debugFailImageRender = [2]          // the accent image fails
        row.apply(input)
        XCTAssertTrue(row.debugImageRenderFailed)
        XCTAssertFalse(row.debugUsesImageContents)
        XCTAssertEqual(row.debugImagePointSize, .zero)
        row.debugFailImageRender = []
    }

    func testFailureRecoversOnTheNextHostUpdate() {
        let fixed = Date(timeIntervalSince1970: 1_000_000)
        let row = view(.swiftUI)
        defer { row.stop() }
        row.debugNow = { fixed }
        var input = snapshot(elapsed: 0, width: 260, sampledAt: fixed, backend: .swiftUI)
        input.timeline = LyricTimeline(lines: [LyricLine(start: 0, text: "歌词")])
        row.debugFailImageRender = [1]
        row.apply(input)
        XCTAssertTrue(row.debugImageRenderFailed)
        row.debugFailImageRender = []
        row.apply(input)                        // same text: a host update retries
        XCTAssertFalse(row.debugImageRenderFailed)
        XCTAssertTrue(row.debugUsesImageContents)
    }

    func testStopAfterFailureReleasesWindowAndKeepsNoPixels() {
        let fixed = Date(timeIntervalSince1970: 1_000_000)
        let row = view(.swiftUI)
        row.debugNow = { fixed }
        var input = snapshot(elapsed: 0, width: 260, sampledAt: fixed, backend: .swiftUI)
        input.timeline = LyricTimeline(lines: [LyricLine(start: 0, text: "歌词")])
        row.debugFailImageRender = [1]
        row.apply(input)
        XCTAssertTrue(row.debugImageRenderFailed)
        row.stop()
        XCTAssertEqual(row.captureWindowCloses, 1)
        XCTAssertFalse(row.debugHostingViewInWindow)
        XCTAssertFalse(row.debugUsesImageContents)
        XCTAssertEqual(row.debugOutgoingLayers, 0)
    }

    func testEmptyLineIsNotAFailure() {
        let fixed = Date(timeIntervalSince1970: 1_000_000)
        let row = view(.swiftUI)
        defer { row.stop() }
        row.debugNow = { fixed }
        var input = snapshot(elapsed: 0, width: 260, sampledAt: fixed, backend: .swiftUI)
        input.timeline = LyricTimeline(lines: [LyricLine(start: 0, text: "")])
        row.apply(input)
        XCTAssertFalse(row.debugImageRenderFailed)
        XCTAssertEqual(row.imageRenderFailures, 0)
        XCTAssertFalse(row.debugUsesImageContents)
    }

    func testEmptyTextLineClearsImagesWithoutANewCapture() {
        let fixed = Date(timeIntervalSince1970: 1_000_000)
        let row = view(.swiftUI)
        defer { row.stop() }
        row.debugNow = { fixed }
        var input = snapshot(elapsed: 0, width: 260, sampledAt: fixed, backend: .swiftUI)
        input.timeline = LyricTimeline(lines: [LyricLine(start: 0, text: "旧歌词")])
        row.apply(input)
        XCTAssertTrue(row.debugUsesImageContents)
        let images = row.imageBuilds
        let builds = row.textBuilds

        input.timeline = LyricTimeline(lines: [LyricLine(start: 0, text: "")])
        row.apply(input)
        XCTAssertNil(row.debugLine?.text.isEmpty == false ? row.debugLine : nil)
        XCTAssertFalse(row.debugUsesImageContents, "an empty line must not keep the old bitmap")
        XCTAssertEqual(row.debugImagePointSize, .zero)
        XCTAssertEqual(row.imageBuilds, images, "no capture for an empty line")
        XCTAssertEqual(row.textBuilds, builds + 1)
    }

    func testStopThenResumeRecreatesExactlyOneCaptureWindow() {
        let fixed = Date(timeIntervalSince1970: 1_000_000)
        let row = view(.swiftUI)
        row.debugNow = { fixed }
        var input = snapshot(elapsed: 0, width: 260, sampledAt: fixed, backend: .swiftUI)
        input.timeline = LyricTimeline(lines: [LyricLine(start: 0, text: "歌词")])
        row.apply(input)
        XCTAssertEqual(row.captureWindowCreations, 1)
        XCTAssertTrue(row.debugHostingViewInWindow)

        row.stop()
        XCTAssertEqual(row.captureWindowCloses, 1)
        XCTAssertFalse(row.debugHostingViewInWindow, "stop releases the capture window")

        row.setActive(true)
        row.apply(input)
        XCTAssertEqual(row.captureWindowCreations, 2, "resuming creates one fresh window")
        XCTAssertTrue(row.debugHostingViewInWindow)
        row.stop()
        XCTAssertEqual(row.captureWindowCloses, 2)
    }

    func testLineChangesReuseOneCaptureWindow() {
        let fixed = Date(timeIntervalSince1970: 1_000_000)
        let row = view(.swiftUI)
        defer { row.stop() }
        row.debugNow = { fixed }
        var input = snapshot(elapsed: 0, width: 260, sampledAt: fixed, backend: .swiftUI)
        input.timeline = LyricTimeline(lines: [LyricLine(start: 0, text: "甲"),
                                              LyricLine(start: 5, text: "乙")])
        row.apply(input)
        input.elapsed = 5
        row.apply(input)
        XCTAssertEqual(row.debugLine?.text, "乙")
        XCTAssertEqual(row.captureWindowCreations, 1, "line changes reuse the capture window")
    }

    private func spin(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    // MARK: - Pixel fidelity (opt-in; the batch's only visual evidence)

    private struct PixelCase {
        let name: String
        let lines: [LyricLine]
        let elapsed: Double
        let expectScroll: Bool
    }

    private func pixelCases() -> [PixelCase] {
        let words = LyricLine(start: 0, text: "逐字高亮示例", words: [
            LyricWord(text: "逐字", start: 0, duration: 0.6),
            LyricWord(text: "高亮", start: 0.6, duration: 0.6),
            LyricWord(text: "示例", start: 1.2, duration: 0.8)
        ])
        let long = LyricLine(start: 0, text: "这是一句没有逐字时间的长歌词，用于确认整行滚动仍然使用真实的行边界，并且不会在换行时跳到错误的位置")
        return [
            PixelCase(name: "zh-short", lines: [LyricLine(start: 0, text: "前奏")],
                      elapsed: 0.5, expectScroll: false),
            PixelCase(name: "zh-word-half", lines: [words], elapsed: 0.9, expectScroll: false),
            // A real successor at 8s: at 4s the LRC line is mid-slide.
            PixelCase(name: "zh-long-scroll", lines: [long, LyricLine(start: 8, text: "后继")],
                      elapsed: 4, expectScroll: true),
        ]
    }

    private func productionModel(elapsed: Double, lines: [LyricLine]) -> (AppModel, String) {
        let suite = "com.wangqing.valora.swiftui-fidelity.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(["nowPlayingEnabled": true, "showLyrics": true],
                     forKey: "referenceSettingsUI")
        defaults.set(true, forKey: "enableNowPlaying")
        let model = AppModel(settings: RevivalSettings(defaults: defaults))
        model.title = "Probe"
        model.duration = 240
        model.lyrics = LyricsDisplayState(status: .ready, timeline: LyricTimeline(lines: lines),
                                          identity: nil)
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

    private func bitmap(of view: NSView, scale: CGFloat) -> NSBitmapImageRep? {
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

    private func px(_ rep: NSBitmapImageRep) -> [UInt8]? {
        guard let cg = rep.cgImage else { return nil }
        let w = cg.width, h = cg.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        return data
    }

    private struct InkStats {
        var count = 0
        var bbox = CGRect.zero
        var mean: (Double, Double, Double) = (0, 0, 0)
        var accentEdge: Int?
    }

    private func stats(_ data: [UInt8], width: Int, height: Int) -> InkStats {
        var result = InkStats()
        var minX = width, maxX = -1, minY = height, maxY = -1
        var r = 0, g = 0, b = 0
        for y in 0..<height { for x in 0..<width {
            let i = (y * width + x) * 4
            guard data[i + 3] > 20 else { continue }
            result.count += 1
            minX = min(minX, x); maxX = max(maxX, x)
            minY = min(minY, y); maxY = max(maxY, y)
            r += Int(data[i]); g += Int(data[i + 1]); b += Int(data[i + 2])
            if data[i] > data[i + 1] + 40 && data[i] > data[i + 2] + 40 {
                result.accentEdge = max(result.accentEdge ?? -1, x)
            }
        } }
        if result.count > 0 {
            result.bbox = CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
            result.mean = (Double(r) / Double(result.count),
                           Double(g) / Double(result.count),
                           Double(b) / Double(result.count))
        }
        return result
    }

    private func bestShift(_ a: [UInt8], _ b: [UInt8], width: Int,
                           height: Int) -> (dx: Int, differing: Int) {
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
        for i in stride(from: 0, to: a.count, by: 4) {
            let d = abs(Int(a[i]) - Int(b[i])) + abs(Int(a[i + 1]) - Int(b[i + 1]))
                + abs(Int(a[i + 2]) - Int(b[i + 2]))
            if d > 12 { differing += 1 }
            total += d
        }
        return (differing, Double(total) / Double(a.count / 4) / 3)
    }

    /// Phase experiment for the long scrolling line: raw fractional offset vs
    /// the same offset snapped to the real 2x pixel grid. Captures are compared
    /// as-is (no pre-shift/resample).
    func testLongScrollPhaseExperiment() throws {
        guard ProcessInfo.processInfo.environment["VALORA_ROW_SWIFTUI_FIDELITY"] == "1" else {
            throw XCTSkip("set VALORA_ROW_SWIFTUI_FIDELITY=1 to run the phase experiment")
        }
        let width: CGFloat = 220
        let scale: CGFloat = 2
        let directory = URL(fileURLWithPath: "/private/tmp/valora-row-swiftui-fidelity-r1",
                            isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let long = LyricLine(start: 0, text: "这是一句没有逐字时间的长歌词，用于确认整行滚动仍然使用真实的行边界，并且不会在换行时跳到错误的位置")
        let lines = [long, LyricLine(start: 8, text: "后继")]

        let host = NSHostingView(rootView: AnyView(EmptyView()))
        host.frame = NSRect(x: 0, y: 0, width: width, height: 17)
        let shippedWindow = NSWindow(contentRect: host.frame, styleMask: .borderless,
                                     backing: .buffered, defer: false)
        shippedWindow.isReleasedWhenClosed = false
        shippedWindow.setFrameOrigin(NSPoint(x: -20000, y: -20000))
        shippedWindow.contentView = host
        shippedWindow.orderFrontRegardless()

        let row = NativeLyricsRowView(frame: NSRect(x: 0, y: 0, width: width, height: 17))
        row.debugSetBackingScale(scale)
        let nativeWindow = NSWindow(contentRect: row.frame, styleMask: .borderless,
                                    backing: .buffered, defer: false)
        nativeWindow.isReleasedWhenClosed = false
        nativeWindow.setFrameOrigin(NSPoint(x: -20000, y: -20000))
        nativeWindow.contentView = row
        nativeWindow.orderFrontRegardless()
        defer {
            row.stop()
            nativeWindow.close()
            shippedWindow.close()
        }

        let fixed = Date(timeIntervalSince1970: 1_000_000)
        // 1.5s is just past the hold, 4.0s and 6.5s are non-integer landings.
        for elapsed in [1.5, 4.0, 6.5] {
            let (model, suite) = productionModel(elapsed: elapsed, lines: lines)
            defer { UserDefaults().removePersistentDomain(forName: suite) }
            host.rootView = AnyView(CompactLyricsView(model: model, width: width, rowHeight: 17,
                                                      showsNote: false, horizontalInset: 0))
            RunLoop.main.run(until: Date().addingTimeInterval(0.12))
            guard let shippedRep = bitmap(of: host, scale: scale),
                  let shippedPx = px(shippedRep) else {
                XCTFail("production capture failed at \(elapsed)")
                continue
            }
            let w = shippedRep.pixelsWide, h = shippedRep.pixelsHigh
            guard stats(shippedPx, width: w, height: h).count > 0 else {
                XCTFail("production capture is blank at \(elapsed)")
                continue
            }
            if let png = shippedRep.representation(using: .png, properties: [:]) {
                do { try png.write(to: directory.appendingPathComponent("shipped-\(elapsed).png")) }
                catch { XCTFail("PNG write failed: \(error)") }
            }

            var snap = snapshot(elapsed: elapsed, width: width, sampledAt: fixed, backend: .swiftUI)
            snap.timeline = LyricTimeline(lines: lines)
            snap.accent = model.lyricsAccentColor
            row.debugNow = { fixed }
            row.apply(snap)
            row.render(at: fixed)
            let rawOffset = row.debugOffset
            XCTAssertGreaterThan(rawOffset, 0, "the compared moment must be mid-slide")
            let snapped = (rawOffset * scale).rounded() / scale
            for (name, offset) in [("raw", rawOffset), ("snapped", snapped)] {
                row.debugOffsetOverride = offset
                row.render(at: fixed)
                RunLoop.main.run(until: Date().addingTimeInterval(0.02))
                guard let rep = bitmap(of: row, scale: scale), let data = px(rep),
                      data.count == shippedPx.count else {
                    XCTFail("capture failed at \(elapsed)/\(name)")
                    continue
                }
                let d = diff(shippedPx, data)
                if let png = rep.representation(using: .png, properties: [:]) {
                    do {
                        try png.write(to: directory.appendingPathComponent("native-\(elapsed)-\(name).png"))
                    } catch { XCTFail("PNG write failed: \(error)") }
                }
                print("STATE phase t=\(elapsed) \(name) line=\(row.debugLine?.text.prefix(6) ?? "nil") end=\(row.debugLineEnd) pos=\(row.debugImageLayerPosition) scale=\(row.debugContentsScale) img=\(row.debugImagePointSize) outgoing=\(row.debugOutgoingLayers) switches=\(row.lineSwitchAnimations)")
                print(String(format: "PHASE t=%.1f %@ offset=%.4f (%.2fpx) differing=%d (%.1f%%) mean=%.3f",
                             elapsed, name, offset, offset * scale, d.differing,
                             Double(d.differing) / Double(w * h) * 100, d.mean))
            }
            row.debugOffsetOverride = nil
        }
    }

    /// Unified reference harness: identical scale, colour, size, anchor,
    /// timeline and settled state for the production row and the new backend.
    func testLongLineUnifiedReferenceHarness() throws {
        guard ProcessInfo.processInfo.environment["VALORA_ROW_SWIFTUI_FIDELITY"] == "1" else {
            throw XCTSkip("set VALORA_ROW_SWIFTUI_FIDELITY=1 to run the reference harness")
        }
        let width: CGFloat = 220
        let scale: CGFloat = 2
        let directory = URL(fileURLWithPath: "/private/tmp/valora-row-swiftui-fidelity-r2",
                            isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let long = LyricLine(start: 0, text: "这是一句没有逐字时间的长歌词，用于确认整行滚动仍然使用真实的行边界，并且不会在换行时跳到错误的位置")
        let lines = [long, LyricLine(start: 8, text: "后继")]

        let host = NSHostingView(rootView: AnyView(EmptyView()))
        host.frame = NSRect(x: 0, y: 0, width: width, height: 17)
        let shippedWindow = NSWindow(contentRect: host.frame, styleMask: .borderless,
                                     backing: .buffered, defer: false)
        shippedWindow.isReleasedWhenClosed = false
        shippedWindow.setFrameOrigin(NSPoint(x: -20000, y: -20000))
        shippedWindow.contentView = host
        shippedWindow.orderFrontRegardless()

        let row = NativeLyricsRowView(frame: NSRect(x: 0, y: 0, width: width, height: 17))
        row.debugSetBackingScale(scale)
        let nativeWindow = NSWindow(contentRect: row.frame, styleMask: .borderless,
                                    backing: .buffered, defer: false)
        nativeWindow.isReleasedWhenClosed = false
        nativeWindow.setFrameOrigin(NSPoint(x: -20000, y: -20000))
        nativeWindow.contentView = row
        nativeWindow.orderFrontRegardless()
        defer {
            row.stop()
            nativeWindow.close()
            shippedWindow.close()
        }

        let fixed = Date(timeIntervalSince1970: 1_000_000)
        for elapsed in [1.5, 4.0, 6.5] {
            let (model, suite) = productionModel(elapsed: elapsed, lines: lines)
            defer { UserDefaults().removePersistentDomain(forName: suite) }
            host.rootView = AnyView(CompactLyricsView(model: model, width: width, rowHeight: 17,
                                                      showsNote: false, horizontalInset: 0))
            RunLoop.main.run(until: Date().addingTimeInterval(0.25))
            guard let shippedRep = bitmap(of: host, scale: scale),
                  let shippedPx = px(shippedRep) else {
                XCTFail("production capture failed at \(elapsed)")
                continue
            }
            let w = shippedRep.pixelsWide, h = shippedRep.pixelsHigh
            let shippedStats = stats(shippedPx, width: w, height: h)
            XCTAssertGreaterThan(shippedStats.count, 0, "production capture is blank")

            var snap = snapshot(elapsed: elapsed, width: width, sampledAt: fixed, backend: .swiftUI)
            snap.timeline = LyricTimeline(lines: lines)
            snap.accent = model.lyricsAccentColor
            row.debugNow = { fixed }
            row.apply(snap)
            row.render(at: fixed)
            // Settle: no line-switch animation may be in flight for the
            // comparison (that was the source of the previous harness skew).
            RunLoop.main.run(until: Date().addingTimeInterval(0.35))
            XCTAssertFalse(row.debugHasActiveSwitchAnimation)
            XCTAssertEqual(row.debugOutgoingLayers, 0)
            row.render(at: fixed)

            guard let nativeRep = bitmap(of: row, scale: scale), let nativePx = px(nativeRep),
                  nativePx.count == shippedPx.count else {
                XCTFail("native capture failed at \(elapsed)")
                continue
            }
            let nativeStats = stats(nativePx, width: nativeRep.pixelsWide, height: nativeRep.pixelsHigh)
            XCTAssertGreaterThan(nativeStats.count, 0, "native capture is blank")
            let d = diff(shippedPx, nativePx)
            let shift = bestShift(shippedPx, nativePx, width: w, height: h)
            if let shippedPNG = shippedRep.representation(using: .png, properties: [:]) {
                do { try shippedPNG.write(to: directory.appendingPathComponent("shipped-\(elapsed).png")) }
                catch { XCTFail("PNG write failed: \(error)") }
            }
            if let nativePNG = nativeRep.representation(using: .png, properties: [:]) {
                do { try nativePNG.write(to: directory.appendingPathComponent("native-\(elapsed).png")) }
                catch { XCTFail("PNG write failed: \(error)") }
            }
            print(String(format: "REF t=%.1f line=%@ end=%.1f offset=%.4f container=(%.4f,%.1f) scale=%.1f bitmap=%dx%d outgoing=%d anim=%d differing=%d (%.1f%%) mean=%.3f bestShift=%d/%d ink=%d/%d bbox=%@/%@",
                         elapsed, row.debugLine?.text.prefix(4).description ?? "nil",
                         row.debugLineEnd, row.debugOffset,
                         row.debugContainerPosition.x, row.debugContainerPosition.y,
                         row.debugContentsScale, nativeRep.pixelsWide, nativeRep.pixelsHigh,
                         row.debugOutgoingLayers, row.debugHasActiveSwitchAnimation ? 1 : 0,
                         d.differing, Double(d.differing) / Double(w * h) * 100, d.mean,
                         shift.dx, shift.differing, nativeStats.count, shippedStats.count,
                         String(describing: nativeStats.bbox), String(describing: shippedStats.bbox)))
        }
    }

    func testEmojiRowMatchesProduction() throws {
        guard ProcessInfo.processInfo.environment["VALORA_ROW_SWIFTUI_FIDELITY"] == "1" else {
            throw XCTSkip("set VALORA_ROW_SWIFTUI_FIDELITY=1 to run the emoji comparison")
        }
        let width: CGFloat = 220
        let scale: CGFloat = 2
        let directory = URL(fileURLWithPath: "/private/tmp/valora-row-swiftui-fidelity-r2",
                            isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let lines = [LyricLine(start: 0, text: "你好 🎵 世界")]
        let (model, suite) = productionModel(elapsed: 0.5, lines: lines)
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let host = NSHostingView(rootView: CompactLyricsView(model: model, width: width,
                                                             rowHeight: 17, showsNote: false,
                                                             horizontalInset: 0))
        host.frame = NSRect(x: 0, y: 0, width: width, height: 17)
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
        window.contentView = host
        window.orderFrontRegardless()
        defer { window.close() }
        RunLoop.main.run(until: Date().addingTimeInterval(0.25))
        guard let shippedRep = bitmap(of: host, scale: scale), let shippedPx = px(shippedRep) else {
            XCTFail("production emoji capture failed")
            return
        }
        let row = NativeLyricsRowView(frame: NSRect(x: 0, y: 0, width: width, height: 17))
        row.debugSetBackingScale(scale)
        defer { row.stop() }
        let fixed = Date(timeIntervalSince1970: 1_000_000)
        var snap = snapshot(elapsed: 0.5, width: width, sampledAt: fixed, backend: .swiftUI)
        snap.timeline = LyricTimeline(lines: lines)
        snap.accent = model.lyricsAccentColor
        row.debugNow = { fixed }
        row.apply(snap)
        row.render(at: fixed)
        guard let nativeRep = bitmap(of: row, scale: scale), let nativePx = px(nativeRep) else {
            XCTFail("native emoji capture failed")
            return
        }
        let d = diff(shippedPx, nativePx)
        let shift = bestShift(shippedPx, nativePx, width: shippedRep.pixelsWide,
                              height: shippedRep.pixelsHigh)
        for (name, rep) in [("shipped", shippedRep), ("native", nativeRep)] {
            if let png = rep.representation(using: .png, properties: [:]) {
                do { try png.write(to: directory.appendingPathComponent("emoji-\(name).png")) }
                catch { XCTFail("PNG write failed: \(error)") }
            }
        }
        print(String(format: "EMOJI differing=%d (%.1f%%) mean=%.3f bestShift=%d/%d",
                     d.differing, Double(d.differing) / Double(shippedRep.pixelsWide * shippedRep.pixelsHigh) * 100,
                     d.mean, shift.dx, shift.differing))
        XCTAssertGreaterThan(stats(shippedPx, width: shippedRep.pixelsWide,
                                   height: shippedRep.pixelsHigh).count, 0)
        XCTAssertGreaterThan(stats(nativePx, width: nativeRep.pixelsWide,
                                   height: nativeRep.pixelsHigh).count, 0)
    }

    /// Line-switch key frames: records whether the switch animation is actually
    /// running in this offscreen harness and saves frames instead of only
    /// counting animations.
    func testLineSwitchKeyFrames() throws {
        guard ProcessInfo.processInfo.environment["VALORA_ROW_SWIFTUI_FIDELITY"] == "1" else {
            throw XCTSkip("set VALORA_ROW_SWIFTUI_FIDELITY=1 to run the switch frames")
        }
        let width: CGFloat = 220
        let scale: CGFloat = 2
        let directory = URL(fileURLWithPath: "/private/tmp/valora-row-swiftui-fidelity-r2",
                            isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let lines = [LyricLine(start: 0, text: "第一句"),
                     LyricLine(start: 1, text: "第二句，较长的一些内容")]
        let fixed = Date(timeIntervalSince1970: 1_000_000)
        let row = NativeLyricsRowView(frame: NSRect(x: 0, y: 0, width: width, height: 17))
        row.debugSetBackingScale(scale)
        defer { row.stop() }
        row.debugNow = { fixed }
        var snap = snapshot(elapsed: 0.5, width: width, sampledAt: fixed, backend: .swiftUI)
        snap.timeline = LyricTimeline(lines: lines)
        row.apply(snap)
        row.render(at: fixed)
        snap.elapsed = 1.05
        row.apply(snap)          // starts the 0.2s switch
        for (name, delay) in [("050ms", 0.05), ("150ms", 0.15)] {
            RunLoop.main.run(until: Date().addingTimeInterval(delay))
            let anim = row.debugHasActiveSwitchAnimation
            if let rep = bitmap(of: row, scale: scale), let data = px(rep) {
                let s = stats(data, width: rep.pixelsWide, height: rep.pixelsHigh)
                if let png = rep.representation(using: .png, properties: [:]) {
                    do { try png.write(to: directory.appendingPathComponent("switch-\(name).png")) }
                    catch { XCTFail("PNG write failed: \(error)") }
                }
                print("SWITCH \(name) anim=\(anim ? 1 : 0) outgoing=\(row.debugOutgoingLayers) ink=\(s.count) bbox=\(s.bbox)")
            } else {
                XCTFail("switch capture failed at \(name)")
            }
        }
    }

    func testSwiftUITextImageFidelityAgainstProduction() throws {
        guard ProcessInfo.processInfo.environment["VALORA_ROW_SWIFTUI_FIDELITY"] == "1" else {
            throw XCTSkip("set VALORA_ROW_SWIFTUI_FIDELITY=1 to run the visual comparison")
        }
        let width: CGFloat = 220
        let scale: CGFloat = 2
        let directory = URL(fileURLWithPath: "/private/tmp/valora-row-swiftui-fidelity",
                            isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        // One reusable offscreen window per side; never recreated per case.
        let host = NSHostingView(rootView: AnyView(EmptyView()))
        host.frame = NSRect(x: 0, y: 0, width: width, height: 17)
        let shippedWindow = NSWindow(contentRect: host.frame, styleMask: .borderless,
                                     backing: .buffered, defer: false)
        shippedWindow.isReleasedWhenClosed = false
        shippedWindow.setFrameOrigin(NSPoint(x: -20000, y: -20000))
        shippedWindow.contentView = host
        shippedWindow.orderFrontRegardless()

        let row = NativeLyricsRowView(frame: NSRect(x: 0, y: 0, width: width, height: 17))
        row.debugSetBackingScale(scale)
        let nativeWindow = NSWindow(contentRect: row.frame, styleMask: .borderless,
                                    backing: .buffered, defer: false)
        nativeWindow.isReleasedWhenClosed = false
        nativeWindow.setFrameOrigin(NSPoint(x: -20000, y: -20000))
        nativeWindow.contentView = row
        nativeWindow.orderFrontRegardless()
        defer {
            row.stop()
            nativeWindow.close()
            shippedWindow.close()
        }

        let fixed = Date(timeIntervalSince1970: 1_000_000)
        var captured = 0
        for testCase in pixelCases() {
            let (model, suite) = productionModel(elapsed: testCase.elapsed, lines: testCase.lines)
            defer { UserDefaults().removePersistentDomain(forName: suite) }
            host.rootView = AnyView(CompactLyricsView(model: model, width: width, rowHeight: 17,
                                                      showsNote: false, horizontalInset: 0))
            RunLoop.main.run(until: Date().addingTimeInterval(0.15))
            guard let shippedRep = bitmap(of: host, scale: scale),
                  let shippedPx = px(shippedRep) else {
                XCTFail("production capture failed for \(testCase.name)")
                continue
            }
            let w = shippedRep.pixelsWide, h = shippedRep.pixelsHigh
            let shipped = stats(shippedPx, width: w, height: h)
            guard shipped.count > 0 else {
                XCTFail("production capture is blank for \(testCase.name)")
                continue
            }

            var snap = snapshot(elapsed: testCase.elapsed, width: width, sampledAt: fixed,
                                backend: .coreText)
            snap.timeline = LyricTimeline(lines: testCase.lines)
            snap.accent = model.lyricsAccentColor
            row.debugNow = { fixed }

            var results: [(String, [UInt8], InkStats)] = []
            for backend in [NativeLyricsTextBackend.coreText, .swiftUI] {
                snap.textBackend = backend
                row.apply(snap)
                row.render(at: fixed)
                RunLoop.main.run(until: Date().addingTimeInterval(0.02))
                guard let rep = bitmap(of: row, scale: scale), let data = px(rep),
                      data.count == shippedPx.count else {
                    XCTFail("capture failed for \(testCase.name)/\(backend.rawValue)")
                    continue
                }
                let ink = stats(data, width: rep.pixelsWide, height: rep.pixelsHigh)
                guard ink.count > 0 else {
                    XCTFail("blank capture for \(testCase.name)/\(backend.rawValue)")
                    continue
                }
                if testCase.name == "zh-long-scroll" {
                    print("STATE fid \(backend.rawValue) line=\(row.debugLine?.text.prefix(6) ?? "nil") start=\(row.debugLine?.start ?? -1) end=\(row.debugLineEnd) offset=\(row.debugOffset) pos=\(row.debugImageLayerPosition) scale=\(row.debugContentsScale) img=\(row.debugImagePointSize) outgoing=\(row.debugOutgoingLayers) switches=\(row.lineSwitchAnimations)")
                }
                let name = "\(testCase.name)-\(backend.rawValue)"
                guard let png = rep.representation(using: .png, properties: [:]) else {
                    XCTFail("PNG encode failed for \(name)")
                    continue
                }
                do {
                    try png.write(to: directory.appendingPathComponent("native-\(name).png"))
                } catch {
                    XCTFail("PNG write failed for \(name): \(error)")
                    continue
                }
                results.append((backend.rawValue, data, ink))
                captured += 1
                let d = diff(shippedPx, data)
                print(String(format: "FIDELITY %@ %@ differing=%d/%d (%.1f%%) mean=%.2f ink=%d/%d bbox=%@/%@ accentEdge=%@/%@",
                             testCase.name, backend.rawValue, d.differing, w * h,
                             Double(d.differing) / Double(w * h) * 100, d.mean,
                             ink.count, shipped.count,
                             String(describing: ink.bbox), String(describing: shipped.bbox),
                             String(describing: ink.accentEdge),
                             String(describing: shipped.accentEdge)))
            }
            if let png = shippedRep.representation(using: .png, properties: [:]) {
                do {
                    try png.write(to: directory.appendingPathComponent("shipped-\(testCase.name).png"))
                } catch {
                    XCTFail("PNG write failed for shipped \(testCase.name): \(error)")
                }
            }
            if testCase.expectScroll {
                XCTAssertGreaterThan(row.debugOffset, 0,
                                     "the long line must be mid-slide at the compared time")
            }
        }
        XCTAssertGreaterThanOrEqual(captured, 6, "all three cases must capture both backends")
    }
}
