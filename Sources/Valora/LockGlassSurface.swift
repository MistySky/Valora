import AppKit
import NativeBridge
import SwiftUI

/// Decorative background only. The SwiftUI player owns layout and mouse input.
struct LockGlassSurface: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var intensity: Double
    var cornerRadius: CGFloat = LockGlassCorner.radius

    var body: some View {
        LockGlassMaterial(reduceTransparency: reduceTransparency, tintOpacity: intensity * 0.8,
                          radius: cornerRadius)
            .id(reduceTransparency)
    }
}

private struct LockGlassMaterial: NSViewRepresentable {
    let reduceTransparency: Bool
    let tintOpacity: CGFloat
    let radius: CGFloat

    func makeNSView(context: Context) -> NSView {
        if !reduceTransparency, let glass = ARCreateLockClearGlassView(.zero, radius) {
            return glass
        }

        let fallback = LockSystemGlassView()
        fallback.style = .regular
        fallback.appearance = NSAppearance(named: .darkAqua)
        fallback.cornerRadius = radius
        if fallback.responds(to: NSSelectorFromString("set_variant:")) {
            fallback.setValue(5, forKey: "_variant")
        }
        let content = NSView()
        content.wantsLayer = true
        content.layer?.cornerRadius = radius
        content.layer?.cornerCurve = .continuous
        content.layer?.backgroundColor = NSColor.black.cgColor
        content.alphaValue = tintOpacity
        content.autoresizingMask = [.width, .height]
        fallback.contentView = content
        return fallback
    }

    func updateNSView(_ view: NSView, context: Context) {
        if let fallback = view as? LockSystemGlassView {
            if fallback.contentView?.alphaValue != tintOpacity {
                fallback.contentView?.alphaValue = tintOpacity
            }
        } else {
            ARSetLockClearGlassTintOpacity(view, tintOpacity)
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSView, context: Context) -> CGSize? {
        guard let width = proposal.width, let height = proposal.height else { return nil }
        return CGSize(width: width, height: height)
    }
}

/// AppKit handles the user's transparency preference on the system material.
private final class LockSystemGlassView: NSGlassEffectView {
    override func layout() {
        super.layout()
        if let contentView, contentView.frame != bounds {
            contentView.frame = bounds
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
