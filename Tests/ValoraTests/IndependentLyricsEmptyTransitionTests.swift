#if VALORA_LYRICS_EXPERIMENT
import AppKit
import SwiftUI
import XCTest
import ReferenceCore
@testable import Valora

@MainActor
final class IndependentLyricsEmptyTransitionTests: XCTestCase {
    func testEmptyLineStillAdvancesToNextLyricWithoutAnotherHostSample() {
        let suite = "com.wangqing.valora.empty-transition.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(settings: RevivalSettings(defaults: defaults))
        model.title = "test"
        model.duration = 20
        model.lyrics = LyricsDisplayState(status: .ready, timeline: LyricTimeline(lines: [
            LyricLine(start: 0, text: ""), LyricLine(start: 0.6, text: "下一句")
        ]), identity: nil)
        model.playing = true
        model.playbackRate = 1
        model.setElapsed(0, sampledAt: Date())
        let host = LyricsRowExperimentHost()
        let view = NSHostingView(rootView: ExperimentalDesktopLyricsView(
            model: model, width: 200, host: host))
        view.frame = NSRect(x: 0, y: 0, width: 200, height: 32)
        let window = NSWindow(contentRect: view.frame, styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
        window.contentView = view
        window.orderFrontRegardless()
        defer { window.contentView = nil; window.close() }

        RunLoop.main.run(until: Date().addingTimeInterval(1.0))
        XCTAssertEqual(model.elapsed, 0, "fixture sends no second host sample")
        XCTAssertEqual(host.displayedLine?.text, "下一句",
                       "a blank lyric must not stop the renderer that wakes the next line")
    }
}
#endif
