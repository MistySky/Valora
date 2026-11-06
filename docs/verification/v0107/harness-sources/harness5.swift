import AppKit
import QuartzCore

func caFilter(_ name: String) -> AnyObject? {
    guard let cls = NSClassFromString("CAFilter") as? NSObject.Type else { return nil }
    let meta: AnyObject = cls
    let sel = NSSelectorFromString("filterWithName:")
    guard meta.responds(to: sel) else { return nil }
    return meta.perform(sel, with: name)?.takeUnretainedValue() as AnyObject?
}

func configure(_ f: AnyObject, source: String) {
    let values: [String: Any] = [
        "inputSourceSublayerName": source,
        "inputBlurRadius": 20.0,
        "inputFaceOpacity": 0.35,
        "inputInnerRefractionAmount": 0.25,
        "inputInnerRefractionHeight": 14.0,
        "inputOuterRefractionAmount": -0.25,
        "inputOuterRefractionHeight": 14.0,
        "inputRefractionDistance0": 0.0,
        "inputRefractionDistance1": 18.0,
        "inputRefractionOpacity": 1.0,
        "inputBleedAmount": 0.0,
        "inputShadowAmount": 0.0,
        "inputRingShadowOpacity": 0.0
    ]
    for (k, v) in values { f.setValue(v, forKey: k) }
}

final class CheckerView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill(); bounds.fill()
        NSColor.black.setFill()
        let s: CGFloat = 16
        for row in 0..<Int(bounds.height / s) {
            for col in 0..<Int(bounds.width / s) where (row + col) % 2 == 0 {
                NSRect(x: CGFloat(col) * s, y: CGFloat(row) * s, width: s, height: s).fill()
            }
        }
    }
}

final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class Harness: NSObject, NSApplicationDelegate {
    var bg: NSWindow!; var panel: KeyPanel!; var other: NSWindow!
    func applicationDidFinishLaunching(_ n: Notification) {
        let frame = NSRect(x: 120, y: 300, width: 1200, height: 360)
        bg = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        bg.isOpaque = true; bg.backgroundColor = .white; bg.level = .normal
        bg.collectionBehavior = [.canJoinAllSpaces, .stationary]; bg.isReleasedWhenClosed = false
        bg.contentView = CheckerView(frame: NSRect(origin: .zero, size: frame.size))
        bg.orderFrontRegardless()

        panel = KeyPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]; panel.isReleasedWhenClosed = false
        let content = NSView(frame: NSRect(origin: .zero, size: frame.size))
        content.wantsLayer = true; content.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = content
        panel.orderFrontRegardless()

        let backdropType = NSClassFromString("CABackdropLayer") as? CALayer.Type

        // A: backdrop root named src + filtered child referencing src
        if let backdropType {
            let host = NSView(frame: NSRect(x: 40, y: 70, width: 220, height: 220)); host.wantsLayer = true
            let root = backdropType.init(); root.frame = host.bounds; root.name = "srcA"; root.cornerRadius = 28; root.masksToBounds = true
            let filtered = CALayer(); filtered.frame = root.bounds; filtered.cornerRadius = 28; filtered.masksToBounds = true
            if let f = caFilter("glassBackground") { configure(f, source: "srcA"); filtered.filters = [f] }
            root.addSublayer(filtered)
            host.layer?.addSublayer(root); content.addSubview(host)
        }

        // B: sibling backdrop named srcB + filtered sibling
        if let backdropType {
            let host = NSView(frame: NSRect(x: 300, y: 70, width: 220, height: 220)); host.wantsLayer = true
            let root = CALayer(); root.frame = host.bounds
            let source = backdropType.init(); source.frame = root.bounds; source.name = "srcB"
            let filtered = CALayer(); filtered.frame = root.bounds; filtered.cornerRadius = 28; filtered.masksToBounds = true
            if let f = caFilter("glassBackground") { configure(f, source: "srcB"); filtered.filters = [f] }
            root.addSublayer(source); root.addSublayer(filtered)
            host.layer?.addSublayer(root); content.addSubview(host)
        }

        // C: filtered layer on top of a backdrop sibling inside a mask
        if let backdropType {
            let host = NSView(frame: NSRect(x: 560, y: 70, width: 220, height: 220)); host.wantsLayer = true
            let root = CALayer(); root.frame = host.bounds; root.cornerRadius = 28; root.masksToBounds = true
            let source = backdropType.init(); source.frame = root.bounds; source.name = "srcC"
            let filtered = CALayer(); filtered.frame = root.bounds
            if let f = caFilter("glassBackground") { configure(f, source: "srcC"); filtered.filters = [f] }
            root.addSublayer(source); root.addSublayer(filtered)
            host.layer?.addSublayer(root); content.addSubview(host)
        }

        // Control NSGlassEffectView dark
        let g = NSGlassEffectView(frame: NSRect(x: 820, y: 70, width: 220, height: 220))
        g.style = .regular; g.appearance = NSAppearance(named: .darkAqua); g.cornerRadius = 28
        var c: UInt32 = 0
        if let ivars = class_copyIvarList(NSGlassEffectView.self, &c) {
            defer { free(ivars) }
            if (0..<Int(c)).contains(where: { ivar_getName(ivars[$0]).map { String(cString: $0) == "_variant" } ?? false }) { g.setValue(5, forKey: "variant") }
        }
        content.addSubview(g)

        other = NSWindow(contentRect: NSRect(x: 40, y: 40, width: 300, height: 140), styleMask: [.titled], backing: .buffered, defer: false)
        other.isReleasedWhenClosed = false; other.orderFrontRegardless()
        other.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { NSApp.terminate(nil) }
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let d = Harness(); app.delegate = d; app.setActivationPolicy(.accessory); app.run()
}
