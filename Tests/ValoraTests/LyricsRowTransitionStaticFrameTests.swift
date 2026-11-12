#if VALORA_LYRICS_EXPERIMENT
import AppKit
import SwiftUI
import XCTest
import ReferenceCore
@testable import Valora

/// Static reference frame for the line-switch geometry. It copies the current
/// `CompactLyricsView` line-node structure (same Text style, 17pt inner row,
/// short/long layout and clipping, note + 5pt spacing, rowHeight outer frame
/// and `.clipped()`), with the whole lyric subview offset/opacity injected to
/// simulate one instant of the production transition. It never animates and
/// does not change production code.
struct ProductionLineFixture: View {
    let text: String
    let elapsed: TimeInterval
    let duration: Double
    let accent: NSColor
    let identity: LyricsTrackIdentity?
    let width: CGFloat
    var rowHeight: CGFloat = 32
    var showsNote: Bool = true
    var horizontalInset: CGFloat = 18
    var offsetY: CGFloat = 0
    var opacity: Double = 1

    private var line: LyricLine {
        LyricLine(start: 0, text: text)
    }
    private var metrics: LyricsLineMetrics { LyricsLineMetrics(line: line) }
    private var available: CGFloat { max(1, width - (showsNote ? 22 : 0)) }
    private var isLong: Bool { metrics.totalWidth > available }
    private var current: (index: Int, fraction: Double)? {
        metrics.currentWord(at: elapsed, line: line)
    }
    private var fill: CGFloat {
        guard let current else { return 0 }
        return LyricsLineLayout.fillWidth(
            prefixWidth: metrics.prefixes[current.index],
            currentWordWidth: metrics.wordWidths[current.index],
            fraction: current.fraction,
            totalWidth: metrics.totalWidth)
    }
    private var readingOffset: CGFloat {
        if isLong, let current, current.index < metrics.prefixes.count {
            return LyricsLineLayout.followingOffset(
                prefixWidth: metrics.prefixes[current.index],
                currentWordWidth: metrics.wordWidths[current.index],
                fraction: current.fraction, totalWidth: metrics.totalWidth,
                availableWidth: available)
        }
        return 0
    }

    private var base: some View {
        ZStack(alignment: .leading) {
            Text(text).foregroundStyle(.gray)
            Text(text)
                .foregroundStyle(Color(nsColor: accent))
                .mask(alignment: .leading) { Rectangle().frame(width: fill) }
        }
        .font(.system(size: 12, weight: .semibold))
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }

    var body: some View {
        HStack(spacing: 5) {
            if showsNote {
                Image(systemName: "music.note")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(nsColor: accent))
            }
            Group {
                if isLong {
                    base.offset(x: -readingOffset)
                        .frame(width: available, height: 17, alignment: .leading)
                        .clipped()
                } else {
                    base.frame(height: 17)
                }
            }
            .offset(y: offsetY)
            .opacity(opacity)
        }
        .foregroundStyle(.gray)
        .frame(width: max(1, width), height: rowHeight,
               alignment: isLong ? .leading : .center)
        .padding(.horizontal, horizontalInset)
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("compact.lyrics")
    }
}

@MainActor
final class LyricsRowTransitionStaticFrameTests: XCTestCase {
    private let scale: CGFloat = 2

    private func model(elapsed: Double, lines: [LyricLine]) -> (AppModel, String) {
        let suite = "com.wangqing.valora.static-frame.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
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

    private func host(_ view: AnyView, width: CGFloat, height: CGFloat)
        -> (NSHostingView<AnyView>, NSWindow) {
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

    private func textInkBounds(_ rep: NSBitmapImageRep, minX: Int = 70) -> CGRect? {
        guard let data = px(rep) else { return nil }
        let w = rep.pixelsWide, h = rep.pixelsHigh
        var minXv = w, maxX = -1, minY = h, maxY = -1
        for y in 0..<h { for x in minX..<w {
            if data[(y * w + x) * 4 + 3] > 20 {
                minXv = min(minXv, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        } }
        guard maxX >= 0 else { return nil }
        return CGRect(x: minXv, y: minY, width: maxX - minXv + 1, height: maxY - minY + 1)
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

    /// The fixture must match the real production row at offset 0/opacity 1.
    func testProductionFixtureMatchesProductionRow() {
        let (model, suite) = model(elapsed: 0.5, lines: [LyricLine(start: 0, text: "参考帧对照")])
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let production = host(AnyView(CompactLyricsView(model: model, width: 200,
                                                        rowHeight: 32, showsNote: true,
                                                        horizontalInset: 18)),
                              width: 236, height: 32)
        let fixture = host(AnyView(ProductionLineFixture(
            text: "参考帧对照", elapsed: 0.5, duration: 240,
            accent: model.lyricsAccentColor, identity: nil, width: 200,
            rowHeight: 32, showsNote: true, horizontalInset: 18)), width: 236, height: 32)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        defer {
            production.1.close()
            fixture.1.close()
        }
        guard let a = bitmap(of: production.0), let b = bitmap(of: fixture.0),
              let pa = px(a), let pb = px(b), pa.count == pb.count else {
            XCTFail("fixture capture failed")
            return
        }
        let d = diff(pa, pb)
        print(String(format: "FIXTURE differing=%d/%d (%.1f%%) mean=%.2f",
                     d.differing, a.pixelsWide * a.pixelsHigh,
                     Double(d.differing) / Double(a.pixelsWide * a.pixelsHigh) * 100, d.mean))
        XCTAssertLessThan(Double(d.differing) / Double(a.pixelsWide * a.pixelsHigh), 0.02,
                          "offset 0 fixture must match the production row")
    }

    /// Visible text range of the production fixture vs the current experiment
    /// content-clip implementation at the same injected offsets.
    func testVisibleRangeAtInjectedOffsets() {
        let cases = [("short", "参考帧对照"),
                     ("long", String(repeating: "长句裁剪内容", count: 8))]
        let offsets: [CGFloat] = [0, 5, -5, 10, -10]
        for (name, text) in cases {
            let (model, suite) = model(elapsed: 0.5, lines: [LyricLine(start: 0, text: text)])
            defer { UserDefaults().removePersistentDomain(forName: suite) }
            let hostModel = LyricsRowExperimentHost()
            let experiment = host(AnyView(ExperimentalDesktopLyricsView(model: model, width: 200,
                                                                        rowHeight: 32,
                                                                        showsNote: true,
                                                                        horizontalInset: 18,
                                                                        transitionStrategy: .legacyTimer,
                                                                        host: hostModel)),
                                  width: 236, height: 32)
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
            guard let row = nativeRow(experiment.0) else {
                XCTFail("renderer missing")
                experiment.1.close()
                continue
            }
            defer {
                row.stop()
                experiment.1.close()
            }
            for offset in offsets {
                let production = host(AnyView(ProductionLineFixture(
                    text: text, elapsed: 0.5, duration: 240,
                    accent: model.lyricsAccentColor, identity: nil, width: 200,
                    rowHeight: 32, showsNote: true, horizontalInset: 18,
                    offsetY: offset)), width: 236, height: 32)
                row.debugSetContainerYOffset(offset)
                RunLoop.main.run(until: Date().addingTimeInterval(0.05))
                let pRep = bitmap(of: production.0)
                let eRep = bitmap(of: experiment.0)
                production.1.close()
                guard let pRep, let eRep,
                      let pInk = textInkBounds(pRep), let eInk = textInkBounds(eRep) else {
                    XCTFail("capture failed \(name) \(offset)")
                    continue
                }
                print(String(format: "STATIC %@ offset=%+.0f production y=[%.1f,%.1f] experiment y=[%.1f,%.1f]",
                             name, Double(offset), Double(pInk.minY), Double(pInk.maxY),
                             Double(eInk.minY), Double(eInk.maxY)))
                let dir = URL(fileURLWithPath: "/private/tmp/valora-transition-static-frames",
                              isDirectory: true)
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                if let png = pRep.representation(using: .png, properties: [:]) {
                    try? png.write(to: dir.appendingPathComponent("\(name)-prod-\(Int(offset)).png"))
                }
                if let png = eRep.representation(using: .png, properties: [:]) {
                    try? png.write(to: dir.appendingPathComponent("\(name)-exp-\(Int(offset)).png"))
                }
            }
            row.debugSetContainerYOffset(0)
        }
    }

    /// Static geometry of the proposed fix: the whole 17pt viewport moves
    /// inside the rowHeight clip, so its visible text range should match the
    /// production fixture at the same offset.
    func testViewportMoveMatchesProductionGeometry() {
        let cases = [("short", "参考帧对照"),
                     ("long", String(repeating: "长句裁剪内容", count: 8))]
        let offsets: [CGFloat] = [5, -5, 10, -10]
        for (name, text) in cases {
            let (model, suite) = model(elapsed: 0.5, lines: [LyricLine(start: 0, text: text)])
            defer { UserDefaults().removePersistentDomain(forName: suite) }
            let hostModel = LyricsRowExperimentHost()
            let experiment = host(AnyView(ExperimentalDesktopLyricsView(model: model, width: 200,
                                                                        rowHeight: 32,
                                                                        showsNote: true,
                                                                        horizontalInset: 18,
                                                                        transitionStrategy: .legacyTimer,
                                                                        host: hostModel)),
                                  width: 236, height: 32)
            waitUntil(1.0) { hostModel.displayedLine != nil }
            defer { experiment.1.close() }
            for offset in offsets {
                let production = host(AnyView(ProductionLineFixture(
                    text: text, elapsed: 0.5, duration: 240,
                    accent: model.lyricsAccentColor, identity: nil, width: 200,
                    rowHeight: 32, showsNote: true, horizontalInset: 18,
                    offsetY: offset)), width: 236, height: 32)
                hostModel.debugViewportOffsetY = offset
                RunLoop.main.run(until: Date().addingTimeInterval(0.05))
                let pRep = bitmap(of: production.0)
                let eRep = bitmap(of: experiment.0)
                production.1.close()
                guard let pRep, let eRep,
                      let pInk = textInkBounds(pRep), let eInk = textInkBounds(eRep) else {
                    XCTFail("capture failed \(name) \(offset)")
                    continue
                }
                print(String(format: "VIEWPORT %@ offset=%+.0f production y=[%.1f,%.1f] experiment y=[%.1f,%.1f]",
                             name, Double(offset), Double(pInk.minY), Double(pInk.maxY),
                             Double(eInk.minY), Double(eInk.maxY)))
                XCTAssertLessThanOrEqual(abs(pInk.height - eInk.height), 3,
                                         "\(name) \(offset): visible height must match production")
            }
            hostModel.debugViewportOffsetY = 0
        }
    }

    private func waitUntil(_ timeout: TimeInterval, _ condition: () -> Bool) {
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
}
#endif
