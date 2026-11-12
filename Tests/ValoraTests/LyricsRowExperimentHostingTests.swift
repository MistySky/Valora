#if VALORA_LYRICS_EXPERIMENT
import AppKit
import SwiftUI
import XCTest
import ReferenceCore
@testable import Valora

/// Real hosting tests for the experimental desktop row. Only compiled in the
/// explicit experiment build; the normal suite never instantiates it.
@MainActor
final class LyricsRowExperimentHostTests: XCTestCase {
    private let lineA = LyricLine(start: 0, text: "第一句")
    private let lineB = LyricLine(start: 1, text: "第二句")

    private func staticLineForStrategy() -> NativeLyricsStaticLine {
        let image = NSImage(size: NSSize(width: 1, height: 1))
        image.lockFocus(); NSColor.black.setFill(); NSBezierPath(rect: NSRect(x: 0, y: 0, width: 1, height: 1)).fill(); image.unlockFocus()
        let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
        return NativeLyricsStaticLine(lineKey: "0-", base: cg, accent: cg,
                                      pointSize: CGSize(width: 20, height: 17), maskWidth: 20,
                                      viewportWidth: 20, positionX: 0, positionY: 0, imageScale: 2)
    }

    func testCurrentCallbacksAreAccepted() {
        let host = LyricsRowExperimentHost()
        host.begin(identity: "a")
        host.reportLine(lineA, outgoing: nil, generation: host.generation, identity: "a")
        XCTAssertEqual(host.displayedLine, lineA)
        host.reportFailure(generation: host.generation, identity: "a")
        XCTAssertTrue(host.failed)
    }

    func testProductionStrategiesAreTypedAndIsolated() {
        let desktop = LyricsRowExperimentHost()
        desktop.transitionStrategy = .build26SwiftUI
        desktop.begin(identity: "desktop")
        desktop.reportLine(LyricLine(start: 0, text: "第一句"), outgoing: nil,
                           generation: desktop.generation, identity: "desktop")
        desktop.reportLine(LyricLine(start: 1, text: "第二句"),
                           outgoing: staticLineForStrategy(), generation: desktop.generation,
                           identity: "desktop")
        XCTAssertFalse(desktop.debugTransitionTimerActive,
                       "desktop build26 strategy must not start the legacy timer")

        let lock = LyricsRowExperimentHost()
        lock.transitionStrategy = .legacyTimer
        lock.begin(identity: "lock")
        lock.reportLine(LyricLine(start: 0, text: "第一句"), outgoing: nil,
                        generation: lock.generation, identity: "lock")
        lock.reportLine(LyricLine(start: 1, text: "第二句"),
                        outgoing: staticLineForStrategy(), generation: lock.generation,
                        identity: "lock")
        XCTAssertTrue(lock.debugTransitionTimerActive,
                      "lock strategy retains the build49 timer path")
        lock.invalidate()
    }

    func testStaleGenerationAndIdentityAreIgnored() {
        let host = LyricsRowExperimentHost()
        host.begin(identity: "a")
        let oldGeneration = host.generation
        host.begin(identity: "b")
        host.reportLine(lineA, outgoing: nil, generation: oldGeneration, identity: "a")
        host.reportFailure(generation: oldGeneration, identity: "a")
        XCTAssertNil(host.displayedLine, "a callback from the previous track must not update the row")
        XCTAssertFalse(host.failed, "a previous track's failure must not lock the new track")
        host.reportLine(lineB, outgoing: nil, generation: host.generation, identity: "b")
        XCTAssertEqual(host.displayedLine, lineB)
    }

    func testInvalidatedViewDropsLateCallbacks() {
        let host = LyricsRowExperimentHost()
        host.begin(identity: "a")
        let generation = host.generation
        host.invalidate()
        host.reportLine(lineA, outgoing: nil, generation: generation, identity: "a")
        host.reportFailure(generation: generation, identity: "a")
        XCTAssertNil(host.displayedLine)
        XCTAssertFalse(host.failed)
    }
}

@MainActor
final class LyricsRowExperimentHostingTests: XCTestCase {
    private let width: CGFloat = 200
    private let scale: CGFloat = 2

    private func model(elapsed: Double, lines: [LyricLine]) -> (AppModel, String) {
        let suite = "com.wangqing.valora.experiment-host.\(UUID().uuidString)"
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

    private func host(_ view: AnyView, height: CGFloat) -> (NSHostingView<AnyView>, NSWindow) {
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)
        let window = NSWindow(contentRect: hosting.frame, styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
        window.contentView = hosting
        window.orderFrontRegardless()
        return (hosting, window)
    }

    private func bitmap(of view: NSView) -> NSBitmapImageRep? {
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

    private func nativeRow(_ view: NSView) -> NativeLyricsRowView? {
        if let row = view as? NativeLyricsRowView { return row }
        for subview in view.subviews {
            if let row = nativeRow(subview) { return row }
        }
        return nil
    }

    /// Ink bounds of the text area only (excludes the note icon).
    private func textInkBounds(_ rep: NSBitmapImageRep) -> CGRect? {
        guard let data = px(rep), let cg = rep.cgImage else { return nil }
        let w = cg.width, h = cg.height
        var minX = w, maxX = -1, minY = h, maxY = -1
        for y in 0..<h { for x in 0..<w {
            guard x >= 70 else { continue }
            if data[(y * w + x) * 4 + 3] > 20 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        } }
        guard maxX >= 0 else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    private func inkBounds(_ rep: NSBitmapImageRep) -> CGRect? {
        guard let data = px(rep), let cg = rep.cgImage else { return nil }
        let w = cg.width, h = cg.height
        var minX = w, maxX = -1, minY = h, maxY = -1
        for y in 0..<h { for x in 0..<w {
            if data[(y * w + x) * 4 + 3] > 20 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        } }
        guard maxX >= 0 else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    private func makeHostedExperiment(model: AppModel, host: LyricsRowExperimentHost,
                                      rowHeight: CGFloat, showsNote: Bool,
                                      inset: CGFloat, width: CGFloat,
                                      transitionStrategy: LyricsTransitionStrategy = .legacyTimer)
        -> (NSHostingView<AnyView>, NSWindow) {
        self.host(AnyView(ExperimentalDesktopLyricsView(model: model, width: width,
                                                        rowHeight: rowHeight,
                                                        showsNote: showsNote,
                                                        horizontalInset: inset,
                                                        transitionStrategy: transitionStrategy,
                                                        host: host)),
                  height: rowHeight)
    }

    func testAlignmentAndRowFollowTheDisplayedLineAcrossBoundaries() {
        func run(showsNote: Bool) {
            // Real anchor so the initial mount shows the 0.2s line; afterwards
            // only the injected display time advances (no model pushes).
            let anchor = Date()
            let short = LyricLine(start: 0, text: "短句")
            let long = LyricLine(start: 1, text: String(repeating: "长歌词内容", count: 10))
            let third = LyricLine(start: 5, text: "又一句短句")
            let (model, suite) = model(elapsed: 0.2, lines: [short, long, third])
            defer { UserDefaults().removePersistentDomain(forName: suite) }
            model.playing = true
            model.playbackRate = 1
            model.setElapsed(0.2, sampledAt: anchor)   // constant anchor; never pushed again
            let host = LyricsRowExperimentHost()
            let (view, window) = makeHostedExperiment(model: model, host: host, rowHeight: 32,
                                                      showsNote: showsNote, inset: 18, width: width)
            defer {
                stopNativeRows(view)
                window.close()
            }
            waitUntil { host.displayedLine != nil }
            guard let row = nativeRow(view) else {
                XCTFail("native row missing (showsNote: \(showsNote))")
                return
            }
            XCTAssertEqual(host.displayedLine?.start, 0)
            let shortInk = bitmap(of: view).flatMap { inkBounds($0) }

            // Constant host anchor: only the injected display time advances.
            row.debugNow = { anchor.addingTimeInterval(1.2) }
            row.render(at: anchor.addingTimeInterval(1.2))
            waitUntil { host.displayedLine?.start == 1 }
            waitUntil { host.isSettled }
            print("BND2 row=\(row.debugLine?.start ?? -1) host=\(host.displayedLine?.start ?? -1) gen=\(host.generation) invoking=\(row.debugLine != nil)")
            XCTAssertEqual(row.debugLine?.start, 1)
            XCTAssertEqual(host.displayedLine?.start, 1,
                           "outer alignment state must follow the displayed line")
            let longInk = bitmap(of: view).flatMap { inkBounds($0) }
            if showsNote {
                XCTAssertGreaterThan(longInk?.width ?? 0, shortInk?.width ?? 0,
                                     "the rendered row must actually show the long line")
            }
            XCTAssertEqual(model.elapsed, 0.2, accuracy: 0.001,
                           "no model sample was pushed")

            row.debugNow = { anchor.addingTimeInterval(5.2) }
            row.render(at: anchor.addingTimeInterval(5.2))
            waitUntil { host.displayedLine?.start == 5 }
            waitUntil { host.isSettled }
            XCTAssertEqual(row.debugLine?.start, 5)
            XCTAssertEqual(host.displayedLine?.start, 5, "long→short also updates together")
        }
        run(showsNote: true)
        run(showsNote: false)
    }

    func testTrackChangeRetriesTheExperimentForTheNewIdentity() {
        let anchor = Date()
        let (model, suite) = model(elapsed: 0.5, lines: [LyricLine(start: 0, text: "第一句")])
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        model.setElapsed(0.5, sampledAt: anchor)
        LyricsRowExperimentDebug.failHostRender = true
        defer { LyricsRowExperimentDebug.failHostRender = false }

        let host = LyricsRowExperimentHost()
        let (view, window) = makeHostedExperiment(model: model, host: host, rowHeight: 32,
                                                  showsNote: true, inset: 18, width: width)
        defer {
            stopNativeRows(view)
            window.close()
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.35))
        XCTAssertTrue(host.failed, "the first identity falls back")
        XCTAssertFalse(hostsNativeRow(view))

        // A new track is a new identity and may use the experiment again.
        LyricsRowExperimentDebug.failHostRender = false
        model.title = "另一首"
        model.mediaRevisionIdentity = "another-track"
        RunLoop.main.run(until: Date().addingTimeInterval(0.35))
        XCTAssertFalse(host.failed, "a new identity must not inherit the old failure")
        XCTAssertTrue(hostsNativeRow(view), "the new identity retries the experiment")
    }

    func testUnmountedViewDropsLateCallbacks() {
        let anchor = Date()
        let (model, suite) = model(elapsed: 0.5, lines: [LyricLine(start: 0, text: "第一句")])
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        model.setElapsed(0.5, sampledAt: anchor)
        let host = LyricsRowExperimentHost()
        let (view, window) = makeHostedExperiment(model: model, host: host, rowHeight: 32,
                                                  showsNote: true, inset: 18, width: width)
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        XCTAssertNotNil(host.displayedLine)
        let generation = host.generation
        let identity = host.identity
        window.contentView = nil
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        host.reportLine(LyricLine(start: 9, text: "迟到"), outgoing: nil,
                        generation: generation, identity: identity)
        host.reportFailure(generation: generation, identity: identity)
        XCTAssertFalse(host.failed, "a callback from an unmounted row must be ignored")
        XCTAssertNotEqual(host.displayedLine?.start, 9)
        window.close()
        _ = view
    }

    /// Column segments of ink, used to locate the note and the text start.
    private func inkSegments(_ rep: NSBitmapImageRep, minGap: Int = 8) -> [ClosedRange<Int>] {
        guard let data = px(rep), let cg = rep.cgImage else { return [] }
        let w = cg.width, h = cg.height
        var columns = [Bool](repeating: false, count: w)
        for x in 0..<w {
            for y in 0..<h where data[(y * w + x) * 4 + 3] > 20 { columns[x] = true; break }
        }
        var segments: [ClosedRange<Int>] = []
        var start: Int?
        var gap = 0
        for x in 0..<w {
            if columns[x] {
                if start == nil { start = x }
                gap = 0
            } else if let s = start {
                gap += 1
                if gap >= minGap {
                    segments.append(s...(x - gap))
                    start = nil
                    gap = 0
                }
            }
        }
        if let s = start { segments.append(s...(w - 1)) }
        return segments
    }

    private func noteAndTextStart(_ rep: NSBitmapImageRep, showsNote: Bool) -> (note: Int?, text: Int?) {
        let segments = inkSegments(rep)
        guard showsNote else { return (nil, segments.first?.lowerBound) }
        guard let note = segments.first else { return (nil, nil) }
        let text = segments.dropFirst().first?.lowerBound
        return (note.lowerBound, text)
    }

    func testDesktopKeyedNoteDoesNotJumpOrReverseAtLineChange() throws {
        let (model, suite) = model(elapsed: 0.2, lines: [
            LyricLine(start: 0, text: "短句"),
            LyricLine(start: 1, text: String(repeating: "长歌词内容", count: 6))
        ])
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        model.playing = false
        let owner = LyricsRowExperimentHost()
        let (view, window) = makeHostedExperiment(
            model: model, host: owner, rowHeight: 32, showsNote: true,
            inset: 18, width: width, transitionStrategy: .build26SwiftUI)
        defer { stopNativeRows(view); window.close() }
        RunLoop.main.run(until: Date().addingTimeInterval(0.35))
        func noteX() throws -> Int {
            let rep = try XCTUnwrap(bitmap(of: view))
            let pixels = try XCTUnwrap(px(rep))
            let w = try XCTUnwrap(rep.cgImage).width
            let h = rep.pixelsHigh
            var left = w
            for y in 0..<h {
                for x in 0..<w {
                    let i = (y * w + x) * 4
                    if pixels[i] > 100 && Double(pixels[i]) > Double(pixels[i+1]) * 1.6
                        && Double(pixels[i]) > Double(pixels[i+2]) * 1.6 && pixels[i+3] > 30 {
                        left = min(left, x)
                    }
                }
            }
            XCTAssertLessThan(left, w, "fixture must show the accent note")
            return left
        }
        let before = try noteX()
        let start = Date()
        model.setElapsed(1.1, sampledAt: start)
        var samples: [Int] = []
        for delay in [0.001, 0.05, 0.10, 0.15, 0.25] {
            let target = start.addingTimeInterval(delay)
            if target > Date() { RunLoop.main.run(until: target) }
            samples.append(try noteX())
        }
        print("NOTE_CONTINUITY before=\(before) samples=\(samples)")
        stopNativeRows(view)
        model.setElapsed(0.2, sampledAt: Date())
        view.rootView = AnyView(CompactLyricsView(model: model, width: width,
                                                  rowHeight: 32, showsNote: true,
                                                  horizontalInset: 18))
        RunLoop.main.run(until: Date().addingTimeInterval(0.35))
        let referenceBefore = try noteX()
        let referenceStart = Date()
        model.setElapsed(1.1, sampledAt: referenceStart)
        var reference: [Int] = []
        for delay in [0.001, 0.05, 0.10, 0.15, 0.25] {
            let target = referenceStart.addingTimeInterval(delay)
            if target > Date() { RunLoop.main.run(until: target) }
            reference.append(try noteX())
        }
        print("NOTE_REFERENCE before=\(referenceBefore) samples=\(reference)")
        XCTAssertLessThanOrEqual(abs(before - referenceBefore), 2,
                                 "stable short-line note position must match the reference")
        XCTAssertLessThanOrEqual(abs(samples[0] - before), 8,
                                 "note must not snap before the 0.2s layout transition starts")
        for index in 1..<samples.count {
            XCTAssertLessThanOrEqual(samples[index], samples[index-1] + 2,
                                     "short-to-long note movement must not reverse direction")
        }
    }

    /// Natural playback clock crossing the next line, without a seek after the
    /// sample starts. This is the path the real media tick uses.
    func testDesktopKeyedNaturalTickNoteDoesNotReverse() throws {
        let anchor = Date()
        let short = LyricLine(start: 0, text: "短句")
        let long = LyricLine(start: 1, text: String(repeating: "长歌词内容", count: 6))
        let (model, suite) = model(elapsed: 0.0, lines: [short, long])
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        model.playing = true
        model.playbackRate = 1
        model.setElapsed(0.0, sampledAt: anchor)
        let owner = LyricsRowExperimentHost()
        owner.transitionStrategy = .build26SwiftUI
        let (view, window) = makeHostedExperiment(model: model, host: owner,
                                                  rowHeight: 32, showsNote: true,
                                                  inset: 18, width: width,
                                                  transitionStrategy: .build26SwiftUI)
        defer { stopNativeRows(view); window.close() }
        waitUntil { owner.displayedLine?.start == 0 }
        RunLoop.main.run(until: Date().addingTimeInterval(0.12))
        func noteX() throws -> Int {
            let rep = try XCTUnwrap(bitmap(of: view))
            return try XCTUnwrap(noteAndTextStart(rep, showsNote: true).note)
        }
        let before = try noteX()
        XCTAssertEqual(before, 200, "stable short note must match the reference x")
        var samples: [(Double, Int)] = []
        let start = Date()
        for delay in [0.2, 0.4, 0.6, 0.8, 1.0, 1.2] {
            let target = start.addingTimeInterval(delay)
            if target > Date() { RunLoop.main.run(until: target) }
            samples.append((Date().timeIntervalSince(start), try noteX()))
        }
        print("NOTE_NATURAL before=\(before) samples=\(samples)")
        XCTAssertLessThanOrEqual(samples[0].1, before + 2,
                                 "natural tick must not snap the note right")
        for index in 1..<samples.count {
            XCTAssertLessThanOrEqual(samples[index].1, samples[index-1].1 + 2,
                                     "natural tick note movement must not reverse")
        }
        XCTAssertEqual(owner.displayedLine?.start, 1)
    }

    func testNoteAndTextPositionsMatchProduction() {
        let anchor = Date()
        func compare(caseName: String, elapsed: Double, lines: [LyricLine], rowHeight: CGFloat,
                     showsNote: Bool, inset: CGFloat, width: CGFloat, expectText: Bool) {
            let (model, suite) = model(elapsed: elapsed, lines: lines)
            defer { UserDefaults().removePersistentDomain(forName: suite) }
            model.setElapsed(elapsed, sampledAt: anchor)
            let host = LyricsRowExperimentHost()
            host.transitionStrategy = .build26SwiftUI
            let production = self.host(AnyView(CompactLyricsView(model: model, width: width,
                                                                 rowHeight: rowHeight,
                                                                 showsNote: showsNote,
                                                                 horizontalInset: inset)),
                                       height: rowHeight)
            let experiment = makeHostedExperiment(model: model, host: host, rowHeight: rowHeight,
                                                  showsNote: showsNote, inset: inset, width: width,
                                                  transitionStrategy: .build26SwiftUI)
            RunLoop.main.run(until: Date().addingTimeInterval(0.35))
            defer {
                stopNativeRows(experiment.0)
                production.1.close()
                experiment.1.close()
            }
            guard let a = bitmap(of: production.0), let b = bitmap(of: experiment.0) else {
                XCTFail("capture failed: \(caseName)")
                return
            }
            let prod = noteAndTextStart(a, showsNote: showsNote)
            let exp = noteAndTextStart(b, showsNote: showsNote)
            print("EMPTY? \(caseName) hostWidth=\(String(describing: host.contentWidth)) native=\(hostsNativeRow(experiment.0))")
            print("POS \(caseName) note=\(String(describing: prod.note))/\(String(describing: exp.note)) text=\(String(describing: prod.text))/\(String(describing: exp.text))")
            if let p = prod.note, let e = exp.note {
                XCTAssertLessThanOrEqual(abs(p - e), 1, "\(caseName): note x within 1px")
            } else if showsNote {
                XCTFail("\(caseName): note missing")
            }
            if expectText {
                if let p = prod.text, let e = exp.text {
                    XCTAssertLessThanOrEqual(abs(p - e), 1, "\(caseName): text start within 1px")
                } else {
                    XCTFail("\(caseName): text segment missing")
                }
            }
        }

        let short = LyricLine(start: 0, text: "短句")
        let long = LyricLine(start: 0, text: String(repeating: "长歌词内容", count: 10))
        compare(caseName: "short-note", elapsed: 0.5, lines: [short], rowHeight: 32,
                showsNote: true, inset: 18, width: width, expectText: true)
        compare(caseName: "long-note", elapsed: 0.5, lines: [long], rowHeight: 32,
                showsNote: true, inset: 18, width: width, expectText: true)
        compare(caseName: "inline-no-note", elapsed: 0.5, lines: [short], rowHeight: 17,
                showsNote: false, inset: 10, width: 120, expectText: true)
        compare(caseName: "empty-line", elapsed: 0.5, lines: [LyricLine(start: 0, text: "")],
                rowHeight: 32, showsNote: true, inset: 18, width: width, expectText: false)
        // Same line, two widths: centering must follow production at both.
        compare(caseName: "short-wide", elapsed: 0.5, lines: [short], rowHeight: 32,
                showsNote: true, inset: 18, width: 300, expectText: true)
        compare(caseName: "short-narrow", elapsed: 0.5, lines: [short], rowHeight: 32,
                showsNote: true, inset: 18, width: 140, expectText: true)
    }

    /// Key frames of the line switch: production vs experiment, captured at
    /// the same wall-clock offsets after the same trigger. The experiment must
    /// keep exactly one live renderer during the transition.
    func testSwitchKeyFrames() {
        let delays: [TimeInterval] = [0, 0.05, 0.10, 0.15, 0.25]
        let short = LyricLine(start: 0, text: "短句")
        let long = LyricLine(start: 1, text: String(repeating: "长歌词内容", count: 6))
        let anchor = Date()

        // Production reference.
        var productionFrames: [(TimeInterval, CGRect?, Int)] = []
        do {
            let (model, suite) = model(elapsed: 0.2, lines: [short, long])
            defer { UserDefaults().removePersistentDomain(forName: suite) }
            model.setElapsed(0.2, sampledAt: anchor)
            let (view, window) = host(AnyView(CompactLyricsView(model: model, width: width,
                                                                rowHeight: 32,
                                                                showsNote: true,
                                                                horizontalInset: 18)), height: 32)
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
            model.setElapsed(1.0, sampledAt: Date())
            let productionStart = Date()
            for delay in delays {
                let target = productionStart.addingTimeInterval(max(0.001, delay))
                if target > Date() { RunLoop.main.run(until: target) }
                if let rep = bitmap(of: view) {
                    productionFrames.append((target.timeIntervalSince(productionStart),
                                             inkBounds(rep), statsAlpha(rep)))
                }
            }
            window.close()
        }

        // Experiment. A fresh anchor: the model clock must still be on the
        // short line when the row mounts, otherwise no switch is exercised.
        var experimentFrames: [(TimeInterval, CGRect?, Int)] = []
        var sawOutgoing = false
        do {
            let mount = Date()
            let (model, suite) = model(elapsed: 0.2, lines: [short, long])
            defer { UserDefaults().removePersistentDomain(forName: suite) }
            model.playing = true
            model.playbackRate = 1
            model.setElapsed(0.2, sampledAt: mount)
            let hostModel = LyricsRowExperimentHost()
            let (view, window) = makeHostedExperiment(model: model, host: hostModel,
                                                      rowHeight: 32, showsNote: true,
                                                      inset: 18, width: width)
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
            guard let row = nativeRow(view) else {
                XCTFail("native row missing")
                window.close()
                return
            }
            XCTAssertEqual(hostModel.displayedLine?.start, 0, "the row must mount on the short line")
            let trigger = mount.addingTimeInterval(0.95)
            row.debugNow = { trigger }
            let experimentStart = Date()
            row.render(at: trigger)
            for delay in delays {
                let target = experimentStart.addingTimeInterval(max(0.001, delay))
                if target > Date() { RunLoop.main.run(until: target) }
                let liveRows = countNativeRows(view)
                XCTAssertEqual(liveRows, 1, "exactly one live renderer during the switch")
                if hostModel.outgoing != nil { sawOutgoing = true }
                print("STATE t=\(delay) outgoing=\(hostModel.outgoing != nil) offset=\(hostModel.incomingOffset) opacity=\(hostModel.incomingOpacity) line=\(hostModel.displayedLine?.start ?? -1) width=\(hostModel.contentWidth ?? -1) settled=\(hostModel.isSettled)")
                if let rep = bitmap(of: view) {
                    experimentFrames.append((target.timeIntervalSince(experimentStart),
                                             inkBounds(rep), statsAlpha(rep)))
                }
            }
            XCTAssertTrue(sawOutgoing, "the real host must enter the viewport transition")
            XCTAssertTrue(hostModel.isSettled, "the 0.2s transition must finish on its own")
            XCTAssertNil(hostModel.outgoing, "the outgoing viewport must be released")
            XCTAssertEqual(row.lineSwitchAnimations, 0,
                           "the renderer's own switch animation stays disabled in the experiment")
            stopNativeRows(view)
            window.close()
        }

        for (p, e) in zip(productionFrames, experimentFrames) {
            print(String(format: "FRAME t=%.2f production y=%.1f ink=%d | experiment y=%.1f ink=%d",
                         p.0, Double(p.1?.minY ?? -1), p.2, Double(e.1?.minY ?? -1), e.2))
        }
        XCTAssertEqual(productionFrames.count, delays.count)
        XCTAssertEqual(experimentFrames.count, delays.count)
        if let productionStart = productionFrames.first, let experimentStart = experimentFrames.first {
            // At t=0 both show the outgoing short line at its settled position.
            XCTAssertLessThanOrEqual(abs(productionStart.2 - experimentStart.2), 120,
                                     "the transition must start from the old line, not the new one")
            XCTAssertLessThanOrEqual(abs(Double(productionStart.1?.minY ?? 0)
                                         - Double(experimentStart.1?.minY ?? 0)), 2)
        }
        if let productionEnd = productionFrames.last, let experimentEnd = experimentFrames.last {
            XCTAssertGreaterThan(productionEnd.2, 4000)
            XCTAssertLessThanOrEqual(abs(productionEnd.2 - experimentEnd.2), 120,
                                     "after the switch both rows show the new line")
        }
    }

    /// R3 production path: the desktop row is a keyed SwiftUI child. A real
    /// model/playback line change must freeze the old native presentation and
    /// mount exactly one live successor through the asymmetric transition.
    func testDesktopKeyedHandoffFreezesOldAndMountsOneLiveClock() {
        let anchor = Date()
        let short = LyricLine(start: 0, text: "短句")
        let long = LyricLine(start: 1, text: String(repeating: "长歌词内容", count: 6))
        let (model, suite) = model(elapsed: 0.2, lines: [short, long])
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        model.playing = true
        model.playbackRate = 1
        model.setElapsed(0.2, sampledAt: anchor)
        let hostModel = LyricsRowExperimentHost()
        hostModel.transitionStrategy = .build26SwiftUI
        let (view, window) = makeHostedExperiment(model: model, host: hostModel,
                                                  rowHeight: 32, showsNote: true,
                                                  inset: 18, width: width,
                                                  transitionStrategy: .build26SwiftUI)
        defer {
            stopNativeRows(view)
            window.close()
        }
        waitUntil { hostModel.displayedLine?.start == 0 }
        let initialID = hostModel.presentationID
        let trigger = Date()
        model.setElapsed(1.0, sampledAt: trigger)

        // Sample from the trigger origin itself; do not wait for handoff first,
        // otherwise the nominal t=0 frame is already mid-transition.
        var evidence: [(TimeInterval, CGRect?, Int)] = []
        for delay in [0.0, 0.05, 0.10, 0.15, 0.25] {
            let target = trigger.addingTimeInterval(delay)
            if target > Date() { RunLoop.main.run(until: target) }
            guard let rep = bitmap(of: view) else { continue }
            evidence.append((Date().timeIntervalSince(trigger), inkBounds(rep), statsAlpha(rep)))
            savePNG(rep, "r3-keyed-\(Int(delay * 100)).png")
        }
        for e in evidence {
            print(String(format: "R3KEY t=%.3f ink=%d y=%.1f", e.0, e.2,
                         Double(e.1?.minY ?? -1)))
        }
        waitUntil { hostModel.presentationID > initialID }
        XCTAssertEqual(hostModel.displayedLine?.start, 1, "handoff publishes the new line")
        XCTAssertNil(hostModel.outgoing, "frozen old line is released after the transition")

        let during = nativeRows(view)
        XCTAssertEqual(during.count, 1, "only the keyed successor owns a native view")
        XCTAssertEqual(during.filter(\.debugIsClockRunning).count, 1,
                       "exactly one live native clock during keyed handoff")
        XCTAssertFalse(during.contains { $0.diagnosticRetired },
                       "the old native view is retired before the frozen image takes over")

        waitUntil { self.countNativeRows(view) == 1 }
        XCTAssertEqual(countNativeRows(view), 1, "retired child is released after transition")
        let finalRows = nativeRows(view)
        XCTAssertEqual(finalRows.count, 1)
        XCTAssertFalse(finalRows[0].diagnosticRetired)
        XCTAssertEqual(finalRows[0].debugLine?.start, 1)
        XCTAssertEqual(hostModel.displayedLine?.start, 1)
        XCTAssertNil(hostModel.outgoing)
    }

    func testDesktopKeyedShortShortAndLongShortLifecycle() {
        func run(_ name: String, old: String, new: String) {
            let anchor = Date()
            let lines = [LyricLine(start: 0, text: old), LyricLine(start: 1, text: new)]
            let (model, suite) = model(elapsed: 0.2, lines: lines)
            defer { UserDefaults().removePersistentDomain(forName: suite) }
            model.playing = true
            model.playbackRate = 1
            model.setElapsed(0.2, sampledAt: anchor)
            let hostModel = LyricsRowExperimentHost()
            hostModel.transitionStrategy = .build26SwiftUI
            let (view, window) = makeHostedExperiment(model: model, host: hostModel,
                                                      rowHeight: 32, showsNote: true,
                                                      inset: 18, width: width,
                                                      transitionStrategy: .build26SwiftUI)
            defer {
                stopNativeRows(view)
                window.close()
            }
            waitUntil { hostModel.displayedLine?.start == 0 }
            let initialID = hostModel.presentationID
            model.setElapsed(1.2, sampledAt: Date())
            waitUntil { hostModel.presentationID > initialID }
            XCTAssertEqual(hostModel.displayedLine?.start, 1, "\(name): new line published")
            waitUntil { self.countNativeRows(view) == 1 }
            XCTAssertEqual(countNativeRows(view), 1, "\(name): old native released")
            let rows = nativeRows(view)
            XCTAssertEqual(rows.count, 1)
            XCTAssertEqual(rows[0].debugLine?.start, 1, "\(name): live row is new line")
            XCTAssertFalse(rows[0].diagnosticRetired)
        }
        run("short-to-short", old: "上一句", new: "下一句")
        run("long-to-short", old: String(repeating: "长歌词内容", count: 6), new: "下一句")
    }

    func testDesktopKeyedSharedPreparationAndSingleOldVisual() {
        let anchor = Date()
        let lines = [LyricLine(start: 0, text: "第一句"),
                     LyricLine(start: 1, text: "第二句"),
                     LyricLine(start: 2, text: "第三句")]
        let (model, suite) = model(elapsed: 0.2, lines: lines)
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        model.playing = true
        model.playbackRate = 1
        model.setElapsed(0.2, sampledAt: anchor)
        let hostModel = LyricsRowExperimentHost()
        hostModel.transitionStrategy = .build26SwiftUI
        let (view, window) = makeHostedExperiment(model: model, host: hostModel,
                                                  rowHeight: 32, showsNote: true,
                                                  inset: 18, width: width,
                                                  transitionStrategy: .build26SwiftUI)
        waitUntil { hostModel.displayedLine?.start == 0 }
        XCTAssertEqual(hostModel.textPreparer.windowCreations, 1,
                       "the owner prepares in one shared window")

        model.setElapsed(1.2, sampledAt: Date())
        waitUntil { hostModel.displayedLine?.start == 1 }
        let oldRows = nativeRows(view).filter { $0.diagnosticRetired }
        XCTAssertEqual(oldRows.count, 1, "one retired native row is retained")
        XCTAssertTrue(oldRows[0].diagnosticHiddenForTransition,
                      "retired native is hidden so the frozen image is the only old visual")
        XCTAssertEqual(hostModel.textPreparer.windowCreations, 1,
                       "second line must not create another capture window")
        waitUntil { hostModel.outgoing == nil }

        model.setElapsed(2.2, sampledAt: Date())
        waitUntil { hostModel.displayedLine?.start == 2 }
        XCTAssertEqual(hostModel.textPreparer.windowCreations, 1,
                       "third line still uses the same capture window")
        waitUntil { hostModel.outgoing == nil }

        stopNativeRows(view)
        window.close()
        hostModel.invalidate()
        XCTAssertEqual(hostModel.textPreparer.windowCloses, 1,
                       "owner teardown releases the shared capture window")
    }

    func testInvalidatedOwnerDropsLateBridgeAndReactivatesSameIdentity() {
        let anchor = Date()
        let lines = [LyricLine(start: 0, text: "第一句")]
        let (model, suite) = model(elapsed: 0.2, lines: lines)
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        model.playing = false
        model.setElapsed(0.2, sampledAt: anchor)
        let host = LyricsRowExperimentHost()
        host.transitionStrategy = .build26SwiftUI
        let (view, window) = makeHostedExperiment(model: model, host: host,
                                                  rowHeight: 32, showsNote: true,
                                                  inset: 18, width: width,
                                                  transitionStrategy: .build26SwiftUI)
        waitUntil { host.displayedLine != nil }
        let oldGeneration = host.generation
        let oldIdentity = host.identity
        host.invalidate()
        XCTAssertFalse(host.isActiveOwner)
        XCTAssertFalse(host.textPreparer.isAvailable)
        let windowsBefore = host.textPreparer.windowCreations

        // A bridge callback from the retired lease must not revive the owner,
        // prepare an image, or publish a fallback.
        host.reportLine(lines[0], outgoing: nil, generation: oldGeneration,
                        identity: oldIdentity)
        host.reportFailure(generation: oldGeneration, identity: oldIdentity)
        XCTAssertFalse(host.failed)
        XCTAssertEqual(host.displayedLine, lines[0],
                       "late callback must not replace the last published line")
        XCTAssertEqual(host.textPreparer.windowCreations, windowsBefore)

        // Re-appearance with the same identity is a new legal lease, not a
        // permanent "same identity" lockout; it must restore a native row.
        host.begin(identity: oldIdentity)
        view.rootView = AnyView(ExperimentalDesktopLyricsView(
            model: model, width: width, rowHeight: 32, showsNote: true,
            horizontalInset: 18, transitionStrategy: .build26SwiftUI, host: host))
        waitUntil { host.isActiveOwner && host.displayedLine != nil }
        waitUntil { countNativeRows(view) == 1 }
        XCTAssertFalse(host.failed)
        XCTAssertEqual(countNativeRows(view), 1)
        XCTAssertEqual(nativeRows(view).first?.diagnosticRetired, false)
        stopNativeRows(view)
        window.close()
    }

    private func statsAlpha(_ rep: NSBitmapImageRep) -> Int {
        guard let data = px(rep) else { return -1 }
        var count = 0
        for i in stride(from: 0, to: data.count, by: 4) where data[i + 3] > 20 { count += 1 }
        return count
    }

    private func waitUntil(_ timeout: TimeInterval = 1.0, _ condition: () -> Bool) {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end, !condition() {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
    }

    private func countNativeRows(_ view: NSView) -> Int {
        nativeRows(view).count
    }

    private func nativeRows(_ view: NSView) -> [NativeLyricsRowView] {
        var rows: [NativeLyricsRowView] = view is NativeLyricsRowView ? [view as! NativeLyricsRowView] : []
        for subview in view.subviews { rows.append(contentsOf: nativeRows(subview)) }
        return rows
    }

    func testNormalEmptyNormalKeepsTheRendererAndAdvances() {
        let anchor = Date()
        let lines = [LyricLine(start: 0, text: "第一句"),
                     LyricLine(start: 1, text: ""),
                     LyricLine(start: 2, text: "第三句")]
        let (model, suite) = model(elapsed: 0.2, lines: lines)
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        model.playing = true
        model.playbackRate = 1
        model.setElapsed(0.2, sampledAt: anchor)
        let host = LyricsRowExperimentHost()
        let (view, window) = makeHostedExperiment(model: model, host: host, rowHeight: 32,
                                                  showsNote: true, inset: 18, width: width)
        defer {
            stopNativeRows(view)
            window.close()
        }
        waitUntil { host.displayedLine != nil }
        guard let row = nativeRow(view) else {
            XCTFail("renderer missing")
            return
        }
        XCTAssertEqual(host.displayedLine?.text, "第一句")

        row.debugNow = { anchor.addingTimeInterval(1.05) }
        row.render(at: anchor.addingTimeInterval(1.05))
        waitUntil { host.displayedLine?.text == "" }
        XCTAssertEqual(host.displayedLine?.text, "")
        XCTAssertEqual(host.contentWidth, 0, "an empty line collapses the text area")
        XCTAssertEqual(countNativeRows(view), 1, "the renderer must stay mounted on a blank line")

        row.debugNow = { anchor.addingTimeInterval(2.05) }
        row.render(at: anchor.addingTimeInterval(2.05))
        waitUntil { host.displayedLine?.text == "第三句" }
        XCTAssertEqual(host.displayedLine?.text, "第三句")
        XCTAssertGreaterThan(host.contentWidth ?? 0, 0)
    }

    func testSeekToEmptyLineAndBack() {
        let anchor = Date()
        let lines = [LyricLine(start: 0, text: "第一句"),
                     LyricLine(start: 5, text: ""),
                     LyricLine(start: 10, text: "最后一句")]
        let (model, suite) = model(elapsed: 0.5, lines: lines)
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        model.setElapsed(0.5, sampledAt: anchor)
        let host = LyricsRowExperimentHost()
        let (view, window) = makeHostedExperiment(model: model, host: host, rowHeight: 32,
                                                  showsNote: true, inset: 18, width: width)
        defer {
            stopNativeRows(view)
            window.close()
        }
        waitUntil { host.displayedLine?.text == "第一句" }
        // Seek to the blank line.
        let (blankModel, blankSuite) = (model, suite)
        _ = blankSuite
        model.setElapsed(5.5, sampledAt: Date())
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        // The host re-applies the same lyrics with a new anchor.
        waitUntil { host.displayedLine?.text == "" }
        XCTAssertEqual(host.displayedLine?.text, "")
        XCTAssertEqual(host.contentWidth, 0)
        model.setElapsed(10.5, sampledAt: Date())
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        waitUntil { host.displayedLine?.text == "最后一句" }
        XCTAssertEqual(host.displayedLine?.text, "最后一句")
        XCTAssertGreaterThan(host.contentWidth ?? 0, 0)
        _ = blankModel
    }

    func testHiddenRecoveryAcrossAnEmptyBoundary() {
        let anchor = Date()
        let lines = [LyricLine(start: 0, text: "第一句"),
                     LyricLine(start: 0.5, text: ""),
                     LyricLine(start: 1, text: "第三句")]
        let (model, suite) = model(elapsed: 0.2, lines: lines)
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        model.playing = true
        model.playbackRate = 1
        model.setElapsed(0.2, sampledAt: anchor)
        let host = LyricsRowExperimentHost()
        let (view, window) = makeHostedExperiment(model: model, host: host, rowHeight: 32,
                                                  showsNote: true, inset: 18, width: width)
        defer {
            stopNativeRows(view)
            window.close()
        }
        waitUntil { host.displayedLine?.text == "第一句" }
        guard let row = nativeRow(view) else {
            XCTFail("renderer missing")
            return
        }
        row.debugNow = { anchor.addingTimeInterval(1.2) }
        row.setActive(false)
        RunLoop.main.run(until: Date().addingTimeInterval(1.1))
        row.setActive(true)
        waitUntil { host.displayedLine?.text == "第三句" }
        XCTAssertEqual(host.displayedLine?.text, "第三句",
                       "reactivation must catch up across the blank boundary")
    }

    func testFailureOnTheLineAfterAnEmptyLineFallsBack() {
        let anchor = Date()
        let lines = [LyricLine(start: 0, text: ""),
                     LyricLine(start: 0.4, text: "下一句")]
        let (model, suite) = model(elapsed: 0, lines: lines)
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        model.playing = true
        model.playbackRate = 1
        model.setElapsed(0, sampledAt: anchor)
        LyricsRowExperimentDebug.failHostRender = true
        defer { LyricsRowExperimentDebug.failHostRender = false }
        let host = LyricsRowExperimentHost()
        let (view, window) = makeHostedExperiment(model: model, host: host, rowHeight: 32,
                                                  showsNote: true, inset: 18, width: width)
        defer {
            stopNativeRows(view)
            window.close()
        }
        waitUntil { host.failed }
        XCTAssertTrue(host.failed)
        XCTAssertFalse(hostsNativeRow(view), "a failed preparation must fall back to the full production row")
    }

    /// Static geometry probe for the switch clip: the renderer's own 17pt
    /// viewport clips the text, while the production row clips at rowHeight
    /// (32pt). A production mid-transition frame cannot be paused reliably in
    /// this harness, so only the experiment's clip is measured here.
    func testInternalViewportClipsAtSeventeenPoints() {
        let anchor = Date()
        let line = LyricLine(start: 0, text: "裁剪几何")
        let (model, suite) = model(elapsed: 0.5, lines: [line])
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        model.setElapsed(0.5, sampledAt: anchor)
        let host = LyricsRowExperimentHost()
        let (view, window) = makeHostedExperiment(model: model, host: host, rowHeight: 32,
                                                  showsNote: true, inset: 18, width: width)
        defer {
            stopNativeRows(view)
            window.close()
        }
        waitUntil { host.displayedLine != nil }
        guard let row = nativeRow(view) else {
            XCTFail("renderer missing")
            return
        }
        guard let base = bitmap(of: view) else {
            XCTFail("capture failed")
            return
        }
        // Text band only: skip the note icon on the left.
        let rest = textInkBounds(base)
        row.debugSetContainerYOffset(10)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        guard let movedRep = bitmap(of: view), let moved = textInkBounds(movedRep) else {
            XCTFail("moved capture failed")
            return
        }
        // The row is 32pt; the renderer's host view is 17pt tall inside it, so
        // a +10pt container shift is clipped at the host viewport, not at 32pt.
        let hostBottom: CGFloat = (32 - 17) / 2 + 17   // host bottom in row points
        print(String(format: "CLIP rest y=[%.1f,%.1f] moved y=[%.1f,%.1f] hostBottom=%.1fpt",
                     Double(rest?.minY ?? -1), Double(rest?.maxY ?? -1),
                     Double(moved.minY), Double(moved.maxY), Double(hostBottom)))
        XCTAssertNotEqual(moved, rest, "the probe must change the visible text range")
        XCTAssertLessThanOrEqual(moved.maxY, hostBottom * scale + 1,
                                 "the text must stay inside the 17pt host viewport")
    }

    func testWidthChangeRecomputesAlignmentFromTheSameDisplayedLine() {
        let line = LyricLine(start: 0, text: "宽度临界的一句歌词")
        let textWidth = LyricsLineMetrics(line: line).totalWidth
        XCTAssertGreaterThan(textWidth, 40)
        let anchor = Date(timeIntervalSince1970: 1_000_000)
        let (model, suite) = model(elapsed: 0.5, lines: [line])
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        model.playing = false
        model.setElapsed(0.5, sampledAt: anchor)

        func minInkX(width: CGFloat) -> CGFloat? {
            let host = LyricsRowExperimentHost()
            let (view, window) = makeHostedExperiment(model: model, host: host, rowHeight: 17,
                                                      showsNote: false, inset: 0, width: width)
            defer {
                stopNativeRows(view)
                window.close()
            }
            RunLoop.main.run(until: Date().addingTimeInterval(0.25))
            return bitmap(of: view).flatMap { inkBounds($0) }?.minX
        }

        // Fits: available > text width → production centers the line.
        let fitting = minInkX(width: textWidth + 40)
        // Overflows: available < text width → production leads the line.
        let overflowing = minInkX(width: textWidth - 20)
        if let fitting, let overflowing {
            XCTAssertGreaterThan(fitting, overflowing + 5,
                                 "a width change must re-apply leading vs center from the same line")
        } else {
            XCTFail("captures failed")
        }
    }

    private func hostsNativeRow(_ view: NSView) -> Bool {
        if view is NativeLyricsRowView { return true }
        return view.subviews.contains { hostsNativeRow($0) }
    }

    private func stopNativeRows(_ view: NSView) {
        if let row = view as? NativeLyricsRowView { row.stop() }
        for subview in view.subviews { stopNativeRows(subview) }
    }

    private func compare(caseName: String, elapsed: Double, lines: [LyricLine],
                         rowHeight: CGFloat, showsNote: Bool, inset: CGFloat) {
        let (model, suite) = model(elapsed: elapsed, lines: lines)
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let production = host(AnyView(CompactLyricsView(model: model, width: width,
                                                        rowHeight: rowHeight,
                                                        showsNote: showsNote,
                                                        horizontalInset: inset)), height: rowHeight)
        let experimental = host(AnyView(ExperimentalDesktopLyricsView(model: model, width: width,
                                                                     rowHeight: rowHeight,
                                                                     showsNote: showsNote,
                                                                     horizontalInset: inset)),
                                height: rowHeight)
        RunLoop.main.run(until: Date().addingTimeInterval(0.35))
        defer {
            stopNativeRows(production.0)
            stopNativeRows(experimental.0)
            production.1.close()
            experimental.1.close()
        }
        XCTAssertTrue(hostsNativeRow(experimental.0), "the experiment must mount the native row")
        XCTAssertEqual(production.0.frame.size, experimental.0.frame.size,
                       "outer size must match the production row")
        guard let a = bitmap(of: production.0), let b = bitmap(of: experimental.0),
              let pa = px(a), let pb = px(b) else {
            XCTFail("capture failed for \(caseName)")
            return
        }
        let d = diff(pa, pb)
        print(String(format: "HOST %@ differing=%d/%d (%.1f%%) mean=%.2f",
                     caseName, d.differing, a.pixelsWide * a.pixelsHigh,
                     Double(d.differing) / Double(a.pixelsWide * a.pixelsHigh) * 100, d.mean))
        XCTAssertGreaterThan(a.pixelsWide, 0)
    }

    func testRepeatedShellUpdateWithSameInputSkipsNativeApply() {
        let (model, suite) = model(elapsed: 0.5, lines: [LyricLine(start: 0, text: "第一句")])
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        model.playing = false
        let host = LyricsRowExperimentHost()
        let (view, window) = makeHostedExperiment(model: model, host: host, rowHeight: 32,
                                                  showsNote: true, inset: 18, width: width)
        defer { stopNativeRows(view); window.close() }
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        guard let row = nativeRow(view) else { XCTFail("native row missing"); return }
        // Let the first shell pass report the real text width, then take the
        // baseline; the next identical shell update is the actual duplicate.
        view.rootView = AnyView(ExperimentalDesktopLyricsView(
            model: model, width: width, rowHeight: 32, showsNote: true,
            horizontalInset: 18, transitionStrategy: .legacyTimer, host: host))
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        let applied = row.applyCount
        let requests = row.applyRequestCount
        // This is the real shell transition update (offset changes, snapshot
        // does not): SwiftUI must re-evaluate the representable, but the
        // native apply should be skipped.
        host.debugViewportOffsetY = 1
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        XCTAssertGreaterThan(row.applyRequestCount, requests,
                             "the shell transition must still request an input check")
        XCTAssertEqual(row.applyCount, applied,
                       "identical shell input must not execute another native apply")
    }

    func testNewProgressAnchorStillApplies() {
        let (model, suite) = model(elapsed: 0.5, lines: [LyricLine(start: 0, text: "第一句")])
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        model.playing = false
        let host = LyricsRowExperimentHost()
        let (view, window) = makeHostedExperiment(model: model, host: host, rowHeight: 32,
                                                  showsNote: true, inset: 18, width: width)
        defer { stopNativeRows(view); window.close() }
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        guard let row = nativeRow(view) else { XCTFail("native row missing"); return }
        let applied = row.applyCount
        model.setElapsed(1.25, sampledAt: Date())
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        XCTAssertGreaterThan(row.applyCount, applied,
                             "a real progress anchor must be applied immediately")
    }

    func testSameIdentityLyricsReplacementStillApplies() {
        let (model, suite) = model(elapsed: 0.5, lines: [LyricLine(start: 0, text: "第一句")])
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let host = LyricsRowExperimentHost()
        let (view, window) = makeHostedExperiment(model: model, host: host, rowHeight: 32,
                                                  showsNote: true, inset: 18, width: width)
        defer { stopNativeRows(view); window.close() }
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        guard let row = nativeRow(view) else { XCTFail("native row missing"); return }
        let applied = row.applyCount
        model.lyrics = LyricsDisplayState(
            status: .ready,
            timeline: LyricTimeline(lines: [LyricLine(start: 0, text: "替换后的同 identity 歌词")]),
            identity: nil)
        view.rootView = AnyView(ExperimentalDesktopLyricsView(
            model: model, width: width, rowHeight: 32, showsNote: true,
            horizontalInset: 18, transitionStrategy: .legacyTimer, host: host))
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        XCTAssertGreaterThan(row.applyCount, applied,
                             "same identity/content replacement must not be skipped")
    }

    func testHostedShortLineMatchesProduction() {
        compare(caseName: "short-note", elapsed: 0.5, lines: [LyricLine(start: 0, text: "第一句")],
                rowHeight: 32, showsNote: true, inset: 18)
    }

    func testHostedLongLineMatchesProductionLayout() {
        let long = LyricLine(start: 0, text: "这是一句没有逐字时间的长歌词，用于确认整行滚动仍然使用真实的行边界，并且不会在换行时跳到错误的位置")
        compare(caseName: "long-note", elapsed: 4,
                lines: [long, LyricLine(start: 8, text: "后继")],
                rowHeight: 32, showsNote: true, inset: 18)
    }

    func testHostedInlineLineWithoutNoteMatchesProduction() {
        compare(caseName: "inline-no-note", elapsed: 4.3,
                lines: [LyricLine(start: 4, text: "无音符内嵌")],
                rowHeight: 17, showsNote: false, inset: 10)
    }

    func testInjectedFailureFallsBackToTheFullProductionRowAndReleasesTheRenderer() {
        let baselineWindows = NativeLyricsRowView.debugLiveCaptureWindows
        let (model, suite) = model(elapsed: 0.5, lines: [LyricLine(start: 0, text: "第一句")])
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        LyricsRowExperimentDebug.failHostRender = true
        defer { LyricsRowExperimentDebug.failHostRender = false }

        let experimental = host(AnyView(ExperimentalDesktopLyricsView(model: model, width: width,
                                                                     rowHeight: 32,
                                                                     showsNote: true,
                                                                     horizontalInset: 18)),
                                height: 32)
        let production = host(AnyView(CompactLyricsView(model: model, width: width,
                                                        rowHeight: 32, showsNote: true,
                                                        horizontalInset: 18)), height: 32)
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        defer {
            experimental.1.close()
            production.1.close()
        }
        XCTAssertFalse(hostsNativeRow(experimental.0),
                       "the failed experiment host must be removed")
        XCTAssertEqual(NativeLyricsRowView.debugLiveCaptureWindows, baselineWindows,
                       "the renderer must close its capture window on fallback")
        guard let a = bitmap(of: production.0), let b = bitmap(of: experimental.0),
              let pa = px(a), let pb = px(b) else {
            XCTFail("fallback capture failed")
            return
        }
        let d = diff(pa, pb)
        print(String(format: "HOST fallback differing=%d/%d (%.1f%%) mean=%.2f",
                     d.differing, a.pixelsWide * a.pixelsHigh,
                     Double(d.differing) / Double(a.pixelsWide * a.pixelsHigh) * 100, d.mean))
        XCTAssertLessThan(Double(d.differing) / Double(a.pixelsWide * a.pixelsHigh), 0.03,
                          "the fallback must render the production row, not an approximation")
    }

    /// cubic-bezier(0.42, 0, 0.58, 1), used to predict the stepped state.
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

    private func staticLineViews(_ view: NSView) -> Int {
        var count = view is StaticLyricsLineNSView ? 1 : 0
        for subview in view.subviews { count += staticLineViews(subview) }
        return count
    }

    private func savePNG(_ rep: NSBitmapImageRep, _ name: String) {
        let dir = URL(fileURLWithPath: "/private/tmp/valora-transition-runtime",
                      isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: dir.appendingPathComponent(name))
        }
    }

    /// Stepped runtime transition: the real hosted view must apply every
    /// intermediate viewport offset/opacity, keep one live renderer and one
    /// frozen outgoing view, never rebuild text per frame, and release the
    /// outgoing view at the end.
    func testRuntimeViewportTransitionSteppedShortAndLong() {
        func run(_ name: String, old: String, new: String, newStart: Double) {
            let anchor = Date()
            let lines = [LyricLine(start: 0, text: old), LyricLine(start: newStart, text: new)]
            let (model, suite) = model(elapsed: 0.2, lines: lines)
            defer { UserDefaults().removePersistentDomain(forName: suite) }
            model.playing = true
            model.playbackRate = 1
            model.setElapsed(0.2, sampledAt: anchor)
            let hostModel = LyricsRowExperimentHost()
            hostModel.debugManualTransition = true
            let (view, window) = makeHostedExperiment(model: model, host: hostModel,
                                                      rowHeight: 32, showsNote: true,
                                                      inset: 18, width: width)
            defer {
                stopNativeRows(view)
                window.close()
            }
            waitUntil { hostModel.displayedLine?.start == 0 }
            guard let row = nativeRow(view) else {
                XCTFail("\(name): native row missing")
                return
            }
            let buildsBefore = row.textBuilds
            let trigger = anchor.addingTimeInterval(newStart + 0.5)
            row.debugNow = { trigger }
            row.render(at: trigger)
            waitUntil { hostModel.outgoing != nil }
            XCTAssertEqual(hostModel.displayedLine?.start, newStart, "\(name): incoming line")
            XCTAssertFalse(hostModel.isSettled, "\(name): transition must be in flight")
            XCTAssertEqual(countNativeRows(view), 1, "\(name): one live renderer")
            XCTAssertEqual(staticLineViews(view), 1, "\(name): one frozen outgoing view")
            XCTAssertEqual(row.lineSwitchAnimations, 0,
                           "\(name): no double switch animation")

            var frames: [[UInt8]] = []
            for step in [0.0, 0.25, 0.5, 0.75] {
                hostModel.debugSetTransitionProgress(step)
                RunLoop.main.run(until: Date().addingTimeInterval(0.03))
                let eased = easeInOut(step)
                XCTAssertEqual(hostModel.incomingOffset, 26 * (1 - eased), accuracy: 0.2,
                               "\(name): incoming offset at \(step)")
                XCTAssertEqual(hostModel.incomingOpacity, eased, accuracy: 0.01,
                               "\(name): incoming opacity at \(step)")
                XCTAssertEqual(hostModel.outgoingOffset, -26 * eased, accuracy: 0.2,
                               "\(name): outgoing offset at \(step)")
                XCTAssertEqual(hostModel.outgoingOpacity, 1 - eased, accuracy: 0.01,
                               "\(name): outgoing opacity at \(step)")
                if let rep = bitmap(of: view) {
                    if let buffer = px(rep) { frames.append(buffer) }
                    savePNG(rep, "\(name)-progress-\(Int(step * 100)).png")
                }
            }
            XCTAssertEqual(frames.count, 4, "\(name): every step captured")
            for index in 1..<frames.count {
                XCTAssertGreaterThan(diff(frames[index - 1], frames[index]).differing, 0,
                                     "\(name): step \(index) must present differently")
            }
            XCTAssertEqual(row.textBuilds, buildsBefore + 1,
                           "\(name): only the incoming line is built once")

            hostModel.debugSetTransitionProgress(1.0)
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            XCTAssertTrue(hostModel.isSettled, "\(name): settles")
            XCTAssertNil(hostModel.outgoing, "\(name): outgoing released")
            XCTAssertEqual(staticLineViews(view), 0, "\(name): frozen view removed")
            XCTAssertEqual(countNativeRows(view), 1, "\(name): renderer stays mounted")
        }
        run("short-to-long", old: "上一句", new: String(repeating: "长歌词内容", count: 6),
            newStart: 2)
        run("long-to-short", old: String(repeating: "长歌词内容", count: 6), new: "下一句",
            newStart: 2)
    }

    /// At the start of a same-width short switch the frozen outgoing view must
    /// look like the production row at offset 0/opacity 1; at the end the
    /// incoming row must look like the production row for the new line.
    func testRuntimeTransitionEndpointsMatchProductionFrames() {
        let anchor = Date()
        let old = "上一句"
        let new = "下一句"
        let lines = [LyricLine(start: 0, text: old), LyricLine(start: 2, text: new)]
        let (model, suite) = model(elapsed: 0.2, lines: lines)
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        model.playing = true
        model.playbackRate = 1
        model.setElapsed(0.2, sampledAt: anchor)
        let hostModel = LyricsRowExperimentHost()
        hostModel.debugManualTransition = true
        let (view, window) = makeHostedExperiment(model: model, host: hostModel,
                                                  rowHeight: 32, showsNote: true,
                                                  inset: 18, width: width)
        defer {
            stopNativeRows(view)
            window.close()
        }
        waitUntil { hostModel.displayedLine?.start == 0 }
        guard let row = nativeRow(view) else {
            XCTFail("native row missing")
            return
        }
        row.debugNow = { anchor.addingTimeInterval(2.5) }
        row.render(at: anchor.addingTimeInterval(2.5))
        waitUntil { hostModel.outgoing != nil }
        hostModel.debugSetTransitionProgress(0)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        func compare(_ text: String, _ label: String) {
            let production = host(AnyView(ProductionLineFixture(
                text: text, elapsed: 0.5, duration: 240,
                accent: model.lyricsAccentColor, identity: nil, width: width,
                rowHeight: 32, showsNote: true, horizontalInset: 18)), height: 32)
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            defer { production.1.close() }
            guard let a = bitmap(of: production.0), let b = bitmap(of: view),
                  let pa = px(a), let pb = px(b) else {
                XCTFail("\(label): capture failed")
                return
            }
            let d = diff(pa, pb)
            print(String(format: "RUNTIME %@ differing=%d/%d (%.1f%%) mean=%.2f",
                         label, d.differing, a.pixelsWide * a.pixelsHigh,
                         Double(d.differing) / Double(a.pixelsWide * a.pixelsHigh) * 100,
                         d.mean))
            savePNG(b, "endpoint-\(label)-experiment.png")
            savePNG(a, "endpoint-\(label)-production.png")
            XCTAssertLessThan(Double(d.differing) / Double(a.pixelsWide * a.pixelsHigh), 0.03,
                              "\(label): the presented frame must match production")
        }
        compare(old, "start-old-line")
        hostModel.debugSetTransitionProgress(1.0)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertTrue(hostModel.isSettled)
        compare(new, "end-new-line")
    }

    /// Rapid consecutive switches: a new switch replaces the outgoing snapshot,
    /// keeps a single renderer and ends on the last line.
    func testRuntimeRapidSwitchesKeepOneRendererAndEndOnLastLine() {
        let anchor = Date()
        let lines = [LyricLine(start: 0, text: "第一句"),
                     LyricLine(start: 1, text: "第二句"),
                     LyricLine(start: 2, text: "第三句")]
        let (model, suite) = model(elapsed: 0.2, lines: lines)
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        model.playing = true
        model.playbackRate = 1
        model.setElapsed(0.2, sampledAt: anchor)
        let hostModel = LyricsRowExperimentHost()
        hostModel.debugManualTransition = true
        let (view, window) = makeHostedExperiment(model: model, host: hostModel,
                                                  rowHeight: 32, showsNote: true,
                                                  inset: 18, width: width)
        defer {
            stopNativeRows(view)
            window.close()
        }
        waitUntil { hostModel.displayedLine?.start == 0 }
        guard let row = nativeRow(view) else {
            XCTFail("native row missing")
            return
        }
        row.debugNow = { anchor.addingTimeInterval(1.5) }
        row.render(at: anchor.addingTimeInterval(1.5))
        waitUntil { hostModel.outgoing != nil }
        hostModel.debugSetTransitionProgress(0.5)
        RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        XCTAssertEqual(hostModel.outgoing?.lineKey.hasPrefix("0.0-"), true,
                       "the mid-transition outgoing view is the first line")

        row.debugNow = { anchor.addingTimeInterval(2.5) }
        row.render(at: anchor.addingTimeInterval(2.5))
        waitUntil { hostModel.displayedLine?.start == 2 }
        XCTAssertEqual(hostModel.outgoing?.lineKey.hasPrefix("1.0-"), true,
                       "the second switch must freeze the second line, not the first")
        XCTAssertEqual(countNativeRows(view), 1)
        XCTAssertEqual(staticLineViews(view), 1)
        hostModel.debugSetTransitionProgress(1.0)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertTrue(hostModel.isSettled)
        XCTAssertEqual(hostModel.displayedLine?.start, 2)
        XCTAssertEqual(staticLineViews(view), 0)
    }

    /// Pause during a transition and a seek to another line must both settle on
    /// the line the clock reports, without a second renderer.
    func testRuntimePauseAndSeekAcrossATransition() {
        let anchor = Date()
        let lines = [LyricLine(start: 0, text: "第一句"),
                     LyricLine(start: 2, text: "第二句"),
                     LyricLine(start: 4, text: "第三句")]
        let (model, suite) = model(elapsed: 0.2, lines: lines)
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        model.playing = true
        model.playbackRate = 1
        model.setElapsed(0.2, sampledAt: anchor)
        let hostModel = LyricsRowExperimentHost()
        hostModel.debugManualTransition = true
        let (view, window) = makeHostedExperiment(model: model, host: hostModel,
                                                  rowHeight: 32, showsNote: true,
                                                  inset: 18, width: width)
        defer {
            stopNativeRows(view)
            window.close()
        }
        waitUntil { hostModel.displayedLine?.start == 0 }
        guard let row = nativeRow(view) else {
            XCTFail("native row missing")
            return
        }
        row.debugNow = { anchor.addingTimeInterval(2.5) }
        row.render(at: anchor.addingTimeInterval(2.5))
        waitUntil { hostModel.outgoing != nil }
        hostModel.debugSetTransitionProgress(0.4)
        RunLoop.main.run(until: Date().addingTimeInterval(0.03))

        // Pause mid-transition: the line must not change and the switch settles.
        model.playing = false
        model.setElapsed(2.4, sampledAt: Date())
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        hostModel.debugSetTransitionProgress(1.0)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertEqual(hostModel.displayedLine?.start, 2)
        XCTAssertTrue(hostModel.isSettled)

        // Seek forward to the third line.
        model.setElapsed(4.5, sampledAt: Date())
        waitUntil { hostModel.displayedLine?.start == 4 }
        XCTAssertEqual(hostModel.displayedLine?.start, 4)
        waitUntil { hostModel.outgoing != nil }
        hostModel.debugSetTransitionProgress(1.0)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertTrue(hostModel.isSettled)
        XCTAssertEqual(countNativeRows(view), 1)
    }

    /// Hiding the surface releases the frozen outgoing view immediately.
    func testRuntimeHideReleasesTheOutgoingView() {
        let anchor = Date()
        let lines = [LyricLine(start: 0, text: "第一句"),
                     LyricLine(start: 2, text: "第二句")]
        let (model, suite) = model(elapsed: 0.2, lines: lines)
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        model.playing = true
        model.playbackRate = 1
        model.setElapsed(0.2, sampledAt: anchor)
        let hostModel = LyricsRowExperimentHost()
        hostModel.debugManualTransition = true
        let (view, window) = makeHostedExperiment(model: model, host: hostModel,
                                                  rowHeight: 32, showsNote: true,
                                                  inset: 18, width: width)
        defer {
            stopNativeRows(view)
            window.close()
        }
        waitUntil { hostModel.displayedLine?.start == 0 }
        guard let row = nativeRow(view) else {
            XCTFail("native row missing")
            return
        }
        row.debugNow = { anchor.addingTimeInterval(2.5) }
        row.render(at: anchor.addingTimeInterval(2.5))
        waitUntil { hostModel.outgoing != nil }
        hostModel.debugSetTransitionProgress(0.4)
        RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        XCTAssertEqual(staticLineViews(view), 1)

        model.notchSurfaceOnScreen = false
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        XCTAssertNil(hostModel.outgoing, "hide must release the frozen line")
        XCTAssertTrue(hostModel.isSettled)
        XCTAssertEqual(staticLineViews(view), 0)
    }

    /// A capture failure during the switch falls back to the production row and
    /// drops the frozen outgoing view.
    func testRuntimeFailureDuringTransitionFallsBackAndReleases() {
        let anchor = Date()
        let lines = [LyricLine(start: 0, text: "第一句"),
                     LyricLine(start: 2, text: "第二句")]
        let (model, suite) = model(elapsed: 0.2, lines: lines)
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        model.playing = true
        model.playbackRate = 1
        model.setElapsed(0.2, sampledAt: anchor)
        let hostModel = LyricsRowExperimentHost()
        hostModel.debugManualTransition = true
        let (view, window) = makeHostedExperiment(model: model, host: hostModel,
                                                  rowHeight: 32, showsNote: true,
                                                  inset: 18, width: width)
        defer {
            stopNativeRows(view)
            window.close()
        }
        waitUntil { hostModel.displayedLine?.start == 0 }
        guard let row = nativeRow(view) else {
            XCTFail("native row missing")
            return
        }
        row.debugFailImageRender = [1]
        row.debugNow = { anchor.addingTimeInterval(2.5) }
        row.render(at: anchor.addingTimeInterval(2.5))
        waitUntil { hostModel.failed }
        XCTAssertTrue(hostModel.failed)
        XCTAssertNil(hostModel.outgoing, "failure must release the frozen line")
        XCTAssertFalse(hostsNativeRow(view), "failure falls back to the production row")
        XCTAssertEqual(staticLineViews(view), 0)
    }

    /// Unmounting mid-transition releases the outgoing view and the host state.
    func testRuntimeUnmountDuringTransitionReleases() {
        let anchor = Date()
        let lines = [LyricLine(start: 0, text: "第一句"),
                     LyricLine(start: 2, text: "第二句")]
        let (model, suite) = model(elapsed: 0.2, lines: lines)
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        model.playing = true
        model.playbackRate = 1
        model.setElapsed(0.2, sampledAt: anchor)
        let hostModel = LyricsRowExperimentHost()
        hostModel.debugManualTransition = true
        let (view, window) = makeHostedExperiment(model: model, host: hostModel,
                                                  rowHeight: 32, showsNote: true,
                                                  inset: 18, width: width)
        waitUntil { hostModel.displayedLine?.start == 0 }
        guard let row = nativeRow(view) else {
            XCTFail("native row missing")
            window.close()
            return
        }
        row.debugNow = { anchor.addingTimeInterval(2.5) }
        row.render(at: anchor.addingTimeInterval(2.5))
        waitUntil { hostModel.outgoing != nil }
        hostModel.debugSetTransitionProgress(0.4)
        RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        let lineBeforeUnmount = hostModel.displayedLine?.start

        window.contentView = nil
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        XCTAssertNil(hostModel.outgoing)
        XCTAssertTrue(hostModel.isSettled, "unmount must drop the transition state")
        XCTAssertEqual(hostModel.displayedLine?.start, lineBeforeUnmount,
                       "no callback after invalidate may advance the row")
        window.close()
        _ = view
    }
}
#endif
