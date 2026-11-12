import AppKit
import SwiftUI
import XCTest
import ReferenceCore
@testable import Valora

@MainActor
final class NotchFixedContourTests: XCTestCase {
    private func makeModel(showLyrics: Bool = true, inline: Bool = false,
                           eligible: Bool = false) -> (AppModel, RevivalSettings, UserDefaults) {
        let suite = "com.wangqing.valora.fixed-contour.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defaults.set(["showLyrics": showLyrics, "inlineLyrics": inline],
                     forKey: "referenceSettingsUI")
        let settings = RevivalSettings(defaults: defaults)
        settings.nowPlayingEnabled = true
        let model = AppModel(settings: settings)
        model.title = "Fixture"
        model.artist = "Artist"
        model.playing = true
        model.duration = 200
        model.notchGeometry = LockDisplayPolicy.geometry(
            for: DisplayDescriptor(id: "external", name: "External",
                                   frame: CGRect(x: -1920, y: 0, width: 1920, height: 1080),
                                   safeAreaTop: 0, auxiliaryLeftWidth: nil,
                                   auxiliaryRightWidth: nil, menuBarHeight: 24),
            simulated: true)
        model.inlineLyricsDisplayEligible = eligible
        return (model, settings, defaults)
    }

    private func timeline(_ texts: [String]) -> LyricTimeline {
        LyricTimeline(lines: texts.enumerated().map { LyricLine(start: Double($0.offset), text: $0.element) })
    }

    private func pathBounds(_ model: AppModel) -> CGRect {
        NotchShape(topRadius: model.contour.topRadius,
                   bottomRadius: model.contour.bottomRadius,
                   style: model.contour.style)
            .path(in: CGRect(origin: .zero, size: model.visibleSize)).boundingRect
    }

    func testCompactSlotStaysReservedAcrossLoadingReadyAndLineContent() {
        let (model, settings, _) = makeModel()
        settings.forceSimulatedNotch = true
        let baseline = model.visibleSize
        let baselinePath = pathBounds(model)
        XCTAssertTrue(model.reservesCompactLyricsSlot)
        XCTAssertFalse(model.showsCompactLyrics)
        XCTAssertEqual(baseline.height, model.notchGeometry.compact.height + 32, accuracy: 0.001)

        model.lyrics = LyricsDisplayState(status: .loading, identity: nil)
        XCTAssertTrue(model.reservesCompactLyricsSlot)
        XCTAssertFalse(model.showsCompactLyrics)
        XCTAssertEqual(model.visibleSize, baseline)
        XCTAssertEqual(pathBounds(model), baselinePath)

        model.lyrics = LyricsDisplayState(status: .ready, timeline: timeline(["短句"]), identity: nil)
        XCTAssertTrue(model.showsCompactLyrics)
        XCTAssertEqual(model.visibleSize, baseline)
        XCTAssertEqual(pathBounds(model), baselinePath)

        model.lyrics = LyricsDisplayState(status: .ready,
                                         timeline: timeline([String(repeating: "长歌词", count: 20)]),
                                         identity: nil)
        XCTAssertEqual(model.visibleSize, baseline)
        XCTAssertEqual(pathBounds(model), baselinePath)

        model.lyrics = LyricsDisplayState(status: .ready, timeline: timeline([""]), identity: nil)
        XCTAssertEqual(model.visibleSize, baseline)
        XCTAssertEqual(pathBounds(model), baselinePath)

        model.lyrics = LyricsDisplayState(status: .unavailable, identity: nil)
        XCTAssertTrue(model.reservesCompactLyricsSlot)
        XCTAssertFalse(model.showsCompactLyrics)
        XCTAssertEqual(model.visibleSize, baseline)
        XCTAssertEqual(pathBounds(model), baselinePath)
    }

    func testInlineSlotStaysReservedAndUsesOneGeometrySource() {
        let (model, settings, defaults) = makeModel(inline: true, eligible: true)
        settings.forceSimulatedNotch = true
        let baseline = model.visibleSize
        let baselinePath = pathBounds(model)
        XCTAssertTrue(model.reservesInlineLyricsSlot)
        XCTAssertEqual(model.inlineLyricsWidthAddition, 16)
        XCTAssertEqual(baseline.height, model.notchGeometry.compact.height, accuracy: 0.001)
        defaults.set(["showLyrics": false, "inlineLyrics": true], forKey: "referenceSettingsUI")
        settings.reloadPreferences()
        let withoutSlot = model.visibleSize
        XCTAssertEqual(baseline.width, withoutSlot.width + 16, accuracy: 0.001)
        defaults.set(["showLyrics": true, "inlineLyrics": true], forKey: "referenceSettingsUI")
        settings.reloadPreferences()
        XCTAssertEqual(model.visibleSize, baseline)

        model.lyrics = LyricsDisplayState(status: .loading, identity: nil)
        XCTAssertEqual(model.visibleSize, baseline)
        XCTAssertEqual(model.inlineLyricsWidthAddition, 16)
        XCTAssertEqual(pathBounds(model), baselinePath)

        model.lyrics = LyricsDisplayState(status: .ready, timeline: timeline(["内嵌"]), identity: nil)
        XCTAssertTrue(model.showsInlineLyrics)
        XCTAssertEqual(model.visibleSize, baseline)
        XCTAssertEqual(pathBounds(model), baselinePath)

        model.lyrics = LyricsDisplayState(status: .unavailable, identity: nil)
        XCTAssertFalse(model.showsInlineLyrics)
        XCTAssertTrue(model.reservesInlineLyricsSlot)
        XCTAssertEqual(model.visibleSize, baseline)
    }

    func testExplicitSettingsAndSurfaceChangesStillChangeGeometry() {
        let (model, settings, defaults) = makeModel()
        settings.forceSimulatedNotch = true
        let withSlot = model.visibleSize
        defaults.set(["showLyrics": false], forKey: "referenceSettingsUI")
        settings.reloadPreferences()
        XCTAssertFalse(model.reservesCompactLyricsSlot)
        XCTAssertEqual(model.visibleSize.height, model.notchGeometry.compact.height, accuracy: 0.001)
        XCTAssertLessThan(model.visibleSize.height, withSlot.height)

        defaults.set(["showLyrics": true], forKey: "referenceSettingsUI")
        settings.reloadPreferences()
        model.screenHidden = true
        XCTAssertFalse(model.reservesCompactLyricsSlot)
        model.screenHidden = false
        XCTAssertTrue(model.reservesCompactLyricsSlot)
        model.playing = false
        model.mediaIdle = MediaIdleState()
        // A paused state with a fresh visible media activity still reserves the
        // layout slot until the existing idle policy hides the surface.
        XCTAssertTrue(model.reservesCompactLyricsSlot)
    }

    func testHostedNotchBlackContourDoesNotMoveWithLyricsContent() throws {
        let (model, settings, _) = makeModel()
        settings.forceSimulatedNotch = true
        let host = NSHostingView(rootView: NotchView(model: model, settings: settings))
        host.frame = NSRect(x: 0, y: 0, width: 624, height: 320)
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
        window.orderFrontRegardless()
        defer { window.close() }

        func blackBounds() -> CGRect? {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            host.layoutSubtreeIfNeeded()
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
            host.cacheDisplay(in: host.bounds, to: rep)
            guard let data = rep.bitmapData, let cg = rep.cgImage else { return nil }
            let w = cg.width, h = cg.height
            var minX = w, maxX = -1, minY = h, maxY = -1
            for y in 0..<h {
                for x in 0..<w {
                    let i = (y * w + x) * 4
                    if data[i] < 12 && data[i+1] < 12 && data[i+2] < 12 && data[i+3] > 180 {
                        minX = min(minX, x); maxX = max(maxX, x)
                        minY = min(minY, y); maxY = max(maxY, y)
                    }
                }
            }
            guard maxX >= 0 else { return nil }
            return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
        }

        model.lyrics = LyricsDisplayState(status: .ready, timeline: timeline(["短句"]), identity: nil)
        let readyShort = try XCTUnwrap(blackBounds())
        model.lyrics = LyricsDisplayState(status: .ready,
                                         timeline: timeline([String(repeating: "长歌词", count: 20)]),
                                         identity: nil)
        let readyLong = try XCTUnwrap(blackBounds())
        model.lyrics = LyricsDisplayState(status: .ready, timeline: timeline([""]), identity: nil)
        let readyEmpty = try XCTUnwrap(blackBounds())
        model.lyrics = LyricsDisplayState(status: .loading, identity: nil)
        let loading = try XCTUnwrap(blackBounds())

        print("CONTOUR_HOST readyShort=\(readyShort) readyLong=\(readyLong) readyEmpty=\(readyEmpty) loading=\(loading) visible=\(model.visibleSize)")
        XCTAssertEqual(readyShort, readyLong, "external contour must not follow line length")
        XCTAssertEqual(readyShort, readyEmpty, "external contour must not follow an empty line")
        XCTAssertEqual(readyShort, loading, "external contour must stay fixed while lyrics load")
    }
}
