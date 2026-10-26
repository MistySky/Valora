import AppKit
import SwiftUI
import XCTest
@testable import Valora

@MainActor
private final class ArtworkStageFixture: ObservableObject {
    @Published var image: NSImage?
    @Published var identity = ""
}

@MainActor
private struct ArtworkStageHarness: View {
    @ObservedObject var fixture: ArtworkStageFixture
    var body: some View {
        TransitioningArtwork(image: fixture.image, identity: fixture.identity,
                             size: 56, cornerRadius: 12, enabled: true)
            .frame(width: 56, height: 56)
    }
}

@MainActor
final class RealArtworkViewStageTests: XCTestCase {
    private func makeImage(_ color: NSColor) -> NSImage {
        let image = NSImage(size: NSSize(width: 56, height: 56))
        image.lockFocus()
        color.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 56, height: 56)).fill()
        image.unlockFocus()
        return image
    }

    private func hostedArtwork() -> (ArtworkStageFixture, NSHostingView<ArtworkStageHarness>, NSWindow) {
        let fixture = ArtworkStageFixture()
        let host = NSHostingView(rootView: ArtworkStageHarness(fixture: fixture))
        host.frame = NSRect(x: 0, y: 0, width: 56, height: 56)
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFrontRegardless()
        return (fixture, host, window)
    }

    private func nonIdentityArtworkScale(_ host: NSView) -> CGFloat? {
        func walk(_ layer: CALayer) -> CGFloat? {
            if layer.transform.m11 < 0.999 {
                return layer.transform.m11
            }
            for sublayer in layer.sublayers ?? [] {
                if let value = walk(sublayer) { return value }
            }
            return nil
        }
        guard let layer = host.layer else { return nil }
        return walk(layer)
    }

    func testActualHostingViewAnimatesArtworkFlipThenSettles() async {
        let (fixture, host, window) = hostedArtwork()
        fixture.image = makeImage(.red)
        fixture.identity = "first"
        try? await Task.sleep(nanoseconds: 220_000_000)
        fixture.image = makeImage(.blue)
        fixture.identity = "second"
        host.layoutSubtreeIfNeeded()
        // Inspect the real SwiftUI hosting layer, not just controller state.
        // Poll a short window because animation start can follow the state
        // update by a run-loop turn.
        var observedScales: [CGFloat] = []
        for _ in 0..<20 {
            try? await Task.sleep(nanoseconds: 20_000_000)
            host.layoutSubtreeIfNeeded()
            if let scale = nonIdentityArtworkScale(host) {
                observedScales.append(scale)
            }
        }
        XCTAssertFalse(observedScales.isEmpty,
                       "the real hosted artwork layer must have a horizontal animation transform")
        XCTAssertLessThan(observedScales.min() ?? 1, 0.2,
                          "the outgoing artwork must compress near a vertical line")
        XCTAssertGreaterThan(observedScales.last ?? 0, 0.5,
                             "the incoming artwork must expand again")
        try? await Task.sleep(nanoseconds: 800_000_000)
        XCTAssertNil(nonIdentityArtworkScale(host),
                     "the hosted artwork layer must settle after the transition")
        window.close()
    }

    func testActualHostedViewTransitionsWhenArtworkArrivesAfterMissingFrame() async {
        let (fixture, host, window) = hostedArtwork()
        fixture.image = makeImage(.red)
        fixture.identity = "first"
        try? await Task.sleep(nanoseconds: 220_000_000)
        fixture.image = nil
        fixture.identity = ""
        try? await Task.sleep(nanoseconds: 120_000_000)
        XCTAssertNil(nonIdentityArtworkScale(host), "the gap itself must not animate an old cover")
        fixture.image = makeImage(.blue)
        fixture.identity = "late-second"
        host.layoutSubtreeIfNeeded()
        var observedScales: [CGFloat] = []
        for _ in 0..<20 {
            try? await Task.sleep(nanoseconds: 20_000_000)
            host.layoutSubtreeIfNeeded()
            if let scale = nonIdentityArtworkScale(host) {
                observedScales.append(scale)
            }
        }
        XCTAssertFalse(observedScales.isEmpty,
                       "late artwork must animate in the actual hosted view")
        XCTAssertLessThan(observedScales.min() ?? 1, 0.2)
        try? await Task.sleep(nanoseconds: 700_000_000)
        XCTAssertNil(nonIdentityArtworkScale(host))
        window.close()
    }
}
