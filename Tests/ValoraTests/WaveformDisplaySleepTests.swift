import AppKit
import QuartzCore
import ReferenceCore
import XCTest
@testable import Valora

@MainActor
final class WaveformDisplaySleepTests: XCTestCase {
    // Exercise the mounted-view path without ordering a window onto the desktop.
    private final class VisibleWindow: NSWindow {
        override var isVisible: Bool { true }
    }

    func testTintAndArtworkUpdateIndependentlyOnRepeatedConfiguration() throws {
        let frame = NSRect(x: 0, y: 0, width: 20, height: 20)
        let waveform = CompactWaveformView(frame: frame)
        let texture = try XCTUnwrap(waveform.layer?.sublayers?.first)
        let light = try XCTUnwrap(NSAppearance(named: .aqua))
        let dark = try XCTUnwrap(NSAppearance(named: .darkAqua))
        let tint = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .red : .blue
        }
        let image = NSImage(size: frame.size, flipped: false) { rect in
            NSColor.cyan.setFill()
            NSBezierPath(rect: rect).fill()
            return true
        }
        func update(_ image: NSImage?) {
            waveform.configure(image: image, color: tint, playing: false, reducedMotion: false, identity: "fixture")
            waveform.layoutSubtreeIfNeeded()
        }

        light.performAsCurrentDrawingAppearance { update(nil) }
        XCTAssertEqual(texture.backgroundColor, NSColor.blue.cgColor)
        dark.performAsCurrentDrawingAppearance {
            update(nil)
            XCTAssertEqual(texture.backgroundColor, NSColor.red.cgColor)
            update(image)
            XCTAssertTrue(waveform.hasArtworkTexture)
            update(image)
            XCTAssertEqual(waveform.textureRenderCount, 1)
            update(nil)
            XCTAssertFalse(waveform.hasArtworkTexture)
        }
    }

    func testWakeRestoresTheCurrentSpringAndKeepsThePausedViewStatic() throws {
        let frame = NSRect(x: 0, y: 0, width: 20, height: 20)
        let window = VisibleWindow(contentRect: frame, styleMask: .borderless,
                                   backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        let waveform = CompactWaveformView(frame: frame)
        window.contentView = waveform
        defer {
            waveform.stop()
            CompactWaveformView.setDisplaysAsleep(false)
            window.close()
        }

        waveform.configure(image: nil, color: .blue, playing: true, reducedMotion: false, identity: "first")
        XCTAssertTrue(waveform.isTicking)
        CompactWaveformView.setDisplaysAsleep(true)
        XCTAssertFalse(waveform.isTicking)
        waveform.bars.forEach { $0.removeAllAnimations() }
        let sleepingBounds = waveform.bars.map(\.bounds)
        waveform.configure(image: nil, color: .blue, playing: true, reducedMotion: false, identity: "next")
        XCTAssertEqual(waveform.bars.map(\.bounds), sleepingBounds)
        XCTAssertTrue(waveform.bars.allSatisfy { $0.animation(forKey: "bounds") == nil })

        let wakeTime = CACurrentMediaTime()
        CompactWaveformView.setDisplaysAsleep(false)
        XCTAssertTrue(waveform.isTicking)
        let bar = try XCTUnwrap(waveform.bars.first)
        let spring = try XCTUnwrap(bar.animation(forKey: "bounds") as? CASpringAnimation)
        XCTAssertEqual(spring.duration, CompactWaveformMetrics.duration)
        XCTAssertEqual((spring.toValue as? NSValue)?.rectValue, bar.bounds)
        let boundary = bar.convertTime(spring.beginTime, to: nil)
        XCTAssertGreaterThanOrEqual(boundary, wakeTime - CompactWaveformMetrics.duration)
        XCTAssertLessThanOrEqual(boundary, CACurrentMediaTime())

        CompactWaveformView.setDisplaysAsleep(true)
        waveform.configure(image: nil, color: .blue, playing: false, reducedMotion: false, identity: "next")
        CompactWaveformView.setDisplaysAsleep(false)
        XCTAssertFalse(waveform.isTicking)
        XCTAssertTrue(waveform.bars.allSatisfy { $0.bounds.height == 2 && $0.animation(forKey: "bounds") == nil })
    }
}
