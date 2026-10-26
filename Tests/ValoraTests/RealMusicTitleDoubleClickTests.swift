import AppKit
import SwiftUI
import XCTest
@testable import Valora
@MainActor
final class RealMusicTitleDoubleClickTests: XCTestCase {
    func testHostedMusicTitleReceivesDoubleClick() throws {
        let suite = "com.wangqing.valora.title-hit.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = RevivalSettings(defaults: defaults)
        settings.nowPlayingEnabled = true
        let model = AppModel(settings: settings)
        model.title = "Long enough title to receive hit"
        model.artist = "Artist"
        model.mediaBundleIdentifier = "com.test.player"
        var activations = 0
        model.openMediaSourceAction = { _ in activations += 1 }
        let view = MusicPlayerContent(model: model, settings: settings, width: 330,
            compensatesForNotch: false, active: true,
            showsVolume: .constant(false))
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 360, height: 180)
        let window = NotchPanel(contentRect: host.frame,
                                styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFrontRegardless()
        XCTAssertFalse(window.canBecomeKey, "the production panel must remain non-activating")
        host.layoutSubtreeIfNeeded()
        func find(_ root: NSView) -> [MarqueeLabelView] {
            (root as? MarqueeLabelView).map { [$0] } ?? root.subviews.flatMap(find)
        }
        let labels = find(host)
        XCTAssertFalse(labels.isEmpty)
        guard let label = labels.first else { return }
        let point = NSPoint(x: label.bounds.midX, y: label.bounds.midY)
        XCTAssertTrue(label.hitTest(point) === label, "title text must be hit-testable")
        func event(_ count: Int) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown,
                location: window.convertPoint(toScreen: label.convert(point, to: nil)),
                modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                context: nil, eventNumber: 0, clickCount: count, pressure: 1))
        }
        window.sendEvent(try event(1))
        XCTAssertEqual(activations, 0, "single click must not activate")
        window.sendEvent(try event(2))
        XCTAssertEqual(activations, 1, "double click must reach native title")
        window.close()
    }
}
