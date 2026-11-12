#if VALORA_LYRICS_EXPERIMENT
import AppKit
import XCTest
@testable import Valora

@MainActor
final class LyricsDiagnosticsTests: XCTestCase {
    func testDisabledDiagnosticsHasNoTimerOrOutput() {
        let diagnostics = LyricsDiagnostics(directory: nil, startTimer: true)
        XCTAssertFalse(diagnostics.isEnabled)
        XCTAssertFalse(diagnostics.isTimerRunning)
        XCTAssertNil(diagnostics.outputURL)
        diagnostics.stop()
    }

    func testWeakRegistryFallbackAndBoundedJsonlSnapshot() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("valora-lyrics-diagnostics-\(UUID().uuidString)")
        let diagnostics = LyricsDiagnostics(directory: directory, startTimer: false)
        XCTAssertTrue(diagnostics.isEnabled)
        XCTAssertFalse(diagnostics.isTimerRunning, "test controls emission")
        let view = NativeLyricsRowView(frame: NSRect(x: 0, y: 0, width: 200, height: 17))
        diagnostics.register(view: view, role: "lock")
        diagnostics.setFallback(role: "lock", active: true)
        XCTAssertEqual(diagnostics.entryCount, 1)
        XCTAssertEqual(diagnostics.fallbackCount, 1)
        diagnostics.emitForTesting()
        let url = try XCTUnwrap(diagnostics.outputURL)
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.contains("\"role\":\"lock\""))
        XCTAssertTrue(text.contains("\"nativeLive\":1"))
        XCTAssertTrue(text.contains("\"fallbackCount\":1"))
        XCTAssertFalse(text.contains("\"lyricsText\""), "diagnostics must not log lyric text")
        diagnostics.stop()
        XCTAssertFalse(diagnostics.isTimerRunning)
    }

    func testRegistryDoesNotRetainNativeView() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("valora-lyrics-diagnostics-\(UUID().uuidString)")
        let diagnostics = LyricsDiagnostics(directory: directory, startTimer: false)
        weak var weakView: NativeLyricsRowView?
        autoreleasepool {
            let view = NativeLyricsRowView(frame: NSRect(x: 0, y: 0, width: 200, height: 17))
            weakView = view
            diagnostics.register(view: view, role: "desktop-active")
        }
        diagnostics.emitForTesting()
        XCTAssertNil(weakView, "weak registry must not retain the view")
        XCTAssertEqual(diagnostics.entryCount, 0)
        diagnostics.stop()
    }
}
#endif
