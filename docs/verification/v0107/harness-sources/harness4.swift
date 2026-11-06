import AppKit
import SwiftUI

final class CheckerView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill(); bounds.fill()
        NSColor.black.setFill()
        let s: CGFloat = 16
        var row = 0
        var y: CGFloat = 0
        while y < bounds.height {
            var col = 0
            var x: CGFloat = 0
            while x < bounds.width {
                if (row + col) % 2 == 0 { NSRect(x: x, y: y, width: s, height: s).fill() }
                x += s; col += 1
            }
            y += s; row += 1
        }
    }
}

final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

struct Card: View {
    let glass: Glass
    let active: Bool
    var body: some View {
        Color.clear
            .frame(width: 200, height: 220)
            .glassEffect(glass, in: RoundedRectangle(cornerRadius: 28))
            .environment(\.appearsActive, active)
    }
}

@MainActor
final class Harness: NSObject, NSApplicationDelegate {
    var background: NSWindow!
    var cardWindow: KeyPanel!
    var otherWindow: NSWindow!
    let makeKey: Bool
    init(makeKey: Bool) { self.makeKey = makeKey }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let frame = NSRect(x: 120, y: 300, width: 1400, height: 360)
        background = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        background.isOpaque = true
        background.backgroundColor = .white
        background.level = .normal
        background.collectionBehavior = [.canJoinAllSpaces, .stationary]
        background.isReleasedWhenClosed = false
        background.contentView = CheckerView(frame: NSRect(origin: .zero, size: frame.size))
        background.orderFrontRegardless()

        cardWindow = KeyPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        cardWindow.isOpaque = false
        cardWindow.backgroundColor = .clear
        cardWindow.level = .floating
        cardWindow.collectionBehavior = [.canJoinAllSpaces, .stationary]
        cardWindow.isReleasedWhenClosed = false
        let transparent = NSView(frame: NSRect(origin: .zero, size: frame.size))
        transparent.wantsLayer = true
        transparent.layer?.backgroundColor = NSColor.clear.cgColor
        cardWindow.contentView = transparent
        cardWindow.orderFrontRegardless()

        let variants: [(String, AnyView)] = [
            ("regular", AnyView(Card(glass: .regular, active: false))),
            ("regular+active", AnyView(Card(glass: .regular, active: true))),
            ("clear", AnyView(Card(glass: .clear, active: false))),
            ("clear+active", AnyView(Card(glass: .clear, active: true))),
            ("clear+inactive", AnyView(Card(glass: .clear, active: false)))
        ]
        for (index, item) in variants.enumerated() {
            let host = NSHostingView(rootView: item.1)
            host.frame = NSRect(x: 20 + CGFloat(index) * 220, y: 70, width: 200, height: 220)
            host.wantsLayer = true
            host.layer?.backgroundColor = NSColor.clear.cgColor
            transparent.addSubview(host)
        }

        func glassView(_ style: NSGlassEffectView.Style, frame: NSRect) -> NSGlassEffectView {
            let v = NSGlassEffectView(frame: frame)
            v.style = style
            v.appearance = NSAppearance(named: .darkAqua)
            v.cornerRadius = 28
            var count: UInt32 = 0
            if let ivars = class_copyIvarList(NSGlassEffectView.self, &count) {
                defer { free(ivars) }
                if (0..<Int(count)).contains(where: { ivar_getName(ivars[$0]).map { String(cString: $0) == "_variant" } ?? false }) {
                    v.setValue(5, forKey: "variant")
                }
            }
            return v
        }
        transparent.addSubview(glassView(.regular, frame: NSRect(x: 1120, y: 70, width: 200, height: 220)))
        transparent.addSubview(glassView(.clear, frame: NSRect(x: 1330, y: 70, width: 50, height: 220)))

        otherWindow = NSWindow(contentRect: NSRect(x: 40, y: 40, width: 300, height: 140),
                               styleMask: [.titled], backing: .buffered, defer: false)
        otherWindow.title = "control"
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
