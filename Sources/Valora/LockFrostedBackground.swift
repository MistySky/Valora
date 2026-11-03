import AppKit
import SwiftUI

/// Recovered Alcove frosted branch: hudWindow material, behindWindow blending,
/// active state and emphasized, with a continuous rounded clip. The macOS 27
/// build keeps this existing path rather than inventing a liquid-glass branch.
struct LockFrostedBackground: NSViewRepresentable {
    var cornerRadius: CGFloat
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        configure(view)
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) { configure(view) }
    private func configure(_ view: NSVisualEffectView) {
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.isEmphasized = true
        // The decompiled 100131c1c fallback installs only material/blending/
        // state/emphasized. Forcing a dark Aqua appearance was a revival-only
        // addition and changed the sampled material; let the panel/host
        // appearance inherit as the source does.
        view.wantsLayer = true
        view.layer?.cornerRadius = cornerRadius
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
    }
}
