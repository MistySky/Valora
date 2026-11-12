import AppKit
import SwiftUI
import XCTest
import ReferenceCore
@testable import Valora

@MainActor
final class IndependentLyricsContourTests: XCTestCase {
    func testTrackLoadingAndLineClockPreserveFullPathAcrossDisplayModes() {
        for physical in [false, true] {
            for inline in [false, true] {
                let suite = "valora.independent.contour.\(UUID().uuidString)"
                let defaults = UserDefaults(suiteName: suite)!
                defer { defaults.removePersistentDomain(forName: suite) }
                defaults.set(["showLyrics": true, "inlineLyrics": inline], forKey: "referenceSettingsUI")
                let settings = RevivalSettings(defaults: defaults)
                let model = AppModel(settings: settings)
                model.title = "Track A"
                model.playing = true
                model.duration = 200
                model.inlineLyricsDisplayEligible = true
                model.notchGeometry = LockDisplayPolicy.geometry(for: DisplayDescriptor(
                    id: "fixture", name: "Fixture",
                    frame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
                    safeAreaTop: physical ? 32 : 0,
                    auxiliaryLeftWidth: physical ? 771.5 : nil,
                    auxiliaryRightWidth: physical ? 771.5 : nil,
                    menuBarHeight: 32, isBuiltIn: physical))
                let timeline = LyricTimeline(lines: [
                    LyricLine(start: 0, text: "短"),
                    LyricLine(start: 2, text: "下一句"),
                    LyricLine(start: 4, text: String(repeating: "长歌词", count: 30)),
                    LyricLine(start: 6, text: "短"),
                    LyricLine(start: 8, text: "")
                ])
                model.lyrics = LyricsDisplayState(status: .ready, timeline: timeline)
                let size = model.visibleSize
                let scale = model.hoverScale
                func path() -> Path {
                    let c = model.contour
                    return NotchShape(topRadius: c.topRadius, bottomRadius: c.bottomRadius, style: c.style)
                        .path(in: CGRect(origin: .zero, size: model.visibleSize))
                }
                let initialPath = path()
                func check() {
                    XCTAssertEqual(model.visibleSize, size)
                    XCTAssertEqual(model.hoverScale, scale)
                    XCTAssertEqual(path(), initialPath, "full outline must stay fixed, not only its bounding box")
                }
                for time in [0.5, 2.5, 4.5, 6.5, 8.5] {
                    model.elapsed = time
                    check()
                }
                model.title = "Track B"
                model.lyrics = LyricsDisplayState(status: .loading)
                XCTAssertNil(model.currentLyricLine)
                XCTAssertFalse(model.showsCompactLyrics)
                XCTAssertFalse(model.showsInlineLyrics)
                check()
                model.lyrics = LyricsDisplayState(status: .unavailable)
                check()
                model.lyrics = LyricsDisplayState(status: .ready, timeline: timeline)
                check()
                XCTAssertEqual(model.showsInlineLyrics, inline && !physical)
                XCTAssertEqual(model.showsCompactLyrics, !inline || physical)
                settings.nowPlayingEnabled = false
                XCTAssertFalse(model.reservesCompactLyricsSlot)
                XCTAssertFalse(model.reservesInlineLyricsSlot)
                XCTAssertEqual(model.visibleSize.height, model.notchGeometry.compact.height)
            }
        }
    }
}
