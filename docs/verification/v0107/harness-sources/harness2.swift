import AppKit
import SwiftUI
import QuartzCore

final class GradientView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSGradient(colors: [.systemPink, .systemTeal, .systemOrange, .systemBlue])?.draw(in: bounds, angle: 35)
        NSColor.white.withAlphaComponent(0.9).setFill()
        NSBezierPath(ovalIn: NSRect(x: 40, y: 60, width: 180, height: 180)).fill()
        NSColor.black.withAlphaComponent(0.8).setFill()
        NSBezierPath(rect: NSRect(x: 300, y: 40, width: 220, height: 120)).fill()
        NSColor.systemYellow.setFill()
        NSBezierPath(ovalIn: NSRect(x: 620, y: 120, width: 160, height: 160)).fill()
        // Sharp grid + labels so edge refraction/lensing is visible.
        NSColor.black.withAlphaComponent(0.55).setStroke()
        let grid = NSBezierPath()
        for x in stride(from: 0, through: bounds.width, by: 16) {
            grid.move(to: NSPoint(x: x, y: 0)); grid.line(to: NSPoint(x: x, y: bounds.height))
        }
        for y in stride(from: 0, through: bounds.height, by: 16) {
            grid.move(to: NSPoint(x: 0, y: y)); grid.line(to: NSPoint(x: bounds.width, y: y))
        }
        grid.lineWidth = 1
        grid.stroke()
        let text = "VALORA 0123456789" as NSString
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: 22), .foregroundColor: NSColor.black]
        for x in stride(from: 10, to: 900, by: 220) {
            text.draw(at: NSPoint(x: x, y: 150), withAttributes: attrs)
        }
    }
}

final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

struct GlassCard: View {
    var body: some View {
        Color.clear
            .frame(width: 210, height: 220)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28))
    }
}

struct ActiveGlassCard: View {
    var body: some View {
        Color.clear
            .frame(width: 210, height: 220)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28))
            .environment(\.appearsActive, true)
    }
}

@MainActor
final class Harness: NSObject, NSApplicationDelegate {
    var cardWindow: KeyPanel!
    var otherWindow: NSWindow!
    let makeKey: Bool
    init(makeKey: Bool) { self.makeKey = makeKey }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let frame = NSRect(x: 180, y: 360, width: 980, height: 340)
        cardWindow = KeyPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        cardWindow.isOpaque = true
        cardWindow.backgroundColor = .clear
        cardWindow.level = .floating
        cardWindow.collectionBehavior = [.canJoinAllSpaces, .stationary]
        cardWindow.isReleasedWhenClosed = false
        let content = GradientView(frame: NSRect(origin: .zero, size: frame.size))
        cardWindow.contentView = content
        cardWindow.orderFrontRegardless()

        let rects = [NSRect(x: 20, y: 60, width: 210, height: 220),
                     NSRect(x: 260, y: 60, width: 210, height: 220),
                     NSRect(x: 500, y: 60, width: 210, height: 220),
                     NSRect(x: 740, y: 60, width: 210, height: 220)]

        let plain = NSHostingView(rootView: GlassCard())
        plain.frame = rects[0]; plain.wantsLayer = true; plain.layer?.backgroundColor = .clear
        content.addSubview(plain)

        let active = NSHostingView(rootView: ActiveGlassCard())
        active.frame = rects[1]; active.wantsLayer = true; active.layer?.backgroundColor = .clear
        content.addSubview(active)

        let glass = NSGlassEffectView(frame: rects[2])
        glass.style = .regular
        glass.appearance = NSAppearance(named: .darkAqua)
        glass.cornerRadius = 28
        var count: UInt32 = 0
        if let ivars = class_copyIvarList(NSGlassEffectView.self, &count) {
            defer { free(ivars) }
            if (0..<Int(count)).contains(where: { ivar_getName(ivars[$0]).map { String(cString: $0) == "_variant" } ?? false }) {
                glass.setValue(5, forKey: "variant")
            }
        }
        content.addSubview(glass)

        let ve = NSVisualEffectView(frame: rects[3])
        ve.material = .underWindowBackground
        ve.blendingMode = .withinWindow
        ve.state = .active
        ve.wantsLayer = true
        ve.layer?.cornerRadius = 28
        ve.layer?.masksToBounds = true
        content.addSubview(ve)

        otherWindow = NSWindow(contentRect: NSRect(x: 60, y: 80, width: 320, height: 160),
                               styleMask: [.titled], backing: .buffered, defer: false)
        otherWindow.title = "control window"
        otherWindow.isReleasedWhenClosed = false
        otherWindow.orderFrontRegardless()

        if makeKey { cardWindow.makeKeyAndOrderFront(nil) } else { otherWindow.makeKeyAndOrderFront(nil) }
        NSApp.activate(ignoringOtherApps: true)
        if makeKey { cardWindow.makeKey() } else { otherWindow.makeKey() }

        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { NSApp.terminate(nil) }
    }
}

MainActor.assumeIsolated {
    let key = CommandLine.arguments.contains("key")
    let app = NSApplication.shared
    let delegate = Harness(makeKey: key)
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
