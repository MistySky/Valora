import AppKit
import SwiftUI
import ReferenceCore

/// The lock card's glass background: `NSGlassEffectView` with the reference's
/// private variant, in the dark appearance the user accepted.
///
/// The player/volume/lyrics are deliberately **not** hosted inside this view.
/// An NSHostingView root is vertically centred when its contents are shorter
/// than the glass, and during the spring resize the glass and the SwiftUI
/// content can briefly disagree in height. That made the fixed player block
/// drift even while the outer glass top looked stationary. Keeping the content
/// in the SwiftUI layout and using the glass only as a background removes that
/// second layout owner; the glass always receives the final content size.
///
/// Known limitation (documented in
/// docs/research/liquid-glass-inactive-window-2026-11-04.md): Liquid Glass only
/// renders its refractive material on a key window, so once the login window
/// takes focus the lock card falls back to the flat, inactive material. The
/// reference has the same constraint; forcing a vibrancy material active
/// (`NSVisualEffectView.state = .active`) keeps a stable look but is not the
/// accepted glass, so the glass is used and the degradation is accepted.
struct LockGlassSurface: NSViewRepresentable {
    var cornerRadius: CGFloat

    func makeNSView(context: Context) -> LockGlassHostView {
        let glass = LockGlassHostView()
        glass.cornerRadius = cornerRadius
        glass.apply()
        // The material is the view itself. An empty content view keeps the
        // AppKit glass API complete without introducing a second SwiftUI
        // layout owner that could centre or resize the player.
        let empty = NSView()
        empty.autoresizingMask = [.width, .height]
        glass.contentView = empty
        return glass
    }

    func updateNSView(_ glass: LockGlassHostView, context: Context) {
        glass.cornerRadius = cornerRadius
        glass.apply()
    }

    /// Used from `.background`, where SwiftUI proposes the exact card size.
    /// Filling that proposal makes the visible glass edge follow the real
    /// content on every animation frame instead of keeping a stale height.
    func sizeThatFits(_ proposal: ProposedViewSize,
                      nsView: LockGlassHostView,
                      context: Context) -> CGSize? {
        guard let width = proposal.width, let height = proposal.height else { return nil }
        return CGSize(width: width, height: height)
    }
}

/// `NSGlassEffectView` plus the reference's private variant, applied only when
/// the running system still exposes it. It is a background surface only; all
/// controls live in the SwiftUI layer above it.
final class LockGlassHostView: NSGlassEffectView {
    /// `100187f28.c:1033–1036`: 2 for a nearly white wallpaper, 5 otherwise.
    private static let variant = 5

    private static let supportsVariant: Bool = {
        var count: UInt32 = 0
        guard let ivars = class_copyIvarList(NSGlassEffectView.self, &count) else { return false }
        defer { free(ivars) }
        return (0..<Int(count)).contains { index in
            guard let name = ivar_getName(ivars[index]) else { return false }
            return String(cString: name) == "_variant"
        }
    }()

    func apply() {
        self.style = .regular
        // Dark appearance: the accepted reading of the reference's lock card
        // (neutral grey glass with white ink over a pale wallpaper). The light
        // appearance renders as a flat white pane and was rejected.
        appearance = NSAppearance(named: .darkAqua)
        guard Self.supportsVariant else { return }
        setValue(Self.variant, forKey: "variant")
    }

    /// The material view owns the frame; keep its empty content view filled
    /// without letting it influence the size or layout of the SwiftUI card.
    override func layout() {
        super.layout()
        if let contentView, contentView.frame != bounds {
            contentView.frame = bounds
        }
    }

    /// Decorative only. The SwiftUI controls above must receive every click;
    /// without this the representable can become an AppKit hit-test target.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
