import AppKit
import XCTest
@testable import Valora

@MainActor
final class IndependentWaveformReturnTests: XCTestCase {
    func testVisiblePlayingWaveformResumesWithoutAnotherConfigure() {
        let waveform = CompactWaveformView(frame: NSRect(x: 0, y: 0, width: 20, height: 20))
        let window = NSWindow(contentRect: waveform.frame, styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
        window.contentView = waveform
        defer { waveform.stop(); window.close() }

        waveform.configure(image: nil, color: .blue, playing: true,
                           reducedMotion: false, identity: "unchanged-track")
        XCTAssertFalse(waveform.isTicking)
        // Production may configure while its panel is still ordered out.
        // Returning the panel must not need a click or unrelated model update.
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))
        let resumedWithoutConfigure = waveform.isTicking

        // This is the extra refresh a user click currently supplies.
        waveform.configure(image: nil, color: .blue, playing: true,
                           reducedMotion: false, identity: "unchanged-track")
        XCTAssertTrue(waveform.isTicking, "an unrelated configure repairs the stopped clock")
        XCTAssertTrue(resumedWithoutConfigure,
                      "visible playing waveform must resume without a user click")
    }
}
