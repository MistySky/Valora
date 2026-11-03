import AppKit
import SwiftUI

/// Corner radius from the decompiled macOS 26+ branch (`100186a7c` passes 30).
enum LockGlassCorner {
    static let radius: CGFloat = 30
}

/// Lock card glass.
///
/// The mature revival's `NSVisualEffectView` recipe is the only one that has
/// actually produced a see-through glass on the lock screen in practice — the
/// macOS 26 `NSGlassEffectView` path renders as a milky fill above the login
/// shield, while `behindWindow` blur still samples there. Its default look was
/// judged a little too dark, so the effect view is pinned to the light Aqua
/// appearance (the decompiled lock branch also uses a light background) and the
/// card keeps the revival's 0.5pt / 15% hairline.
///
/// Container shape follows the decompiled factory: an outer `NSView` owns the
/// continuous corner clip, the effect view is constrained to its four edges.
struct LockFrostedBackground: NSViewRepresentable {
    var cornerRadius: CGFloat

    func makeNSView(context: Context) -> LockFrostedContainerView {
        let view = LockFrostedContainerView()
        view.cornerRadius = cornerRadius
        return view
    }

    func updateNSView(_ view: LockFrostedContainerView, context: Context) {
        view.cornerRadius = cornerRadius
    }

    /// No intrinsic size: report the proposal back so the background can never
    /// stretch the 345pt card.
    func sizeThatFits(_ proposal: ProposedViewSize,
                      nsView: LockFrostedContainerView,
                      context: Context) -> CGSize? {
        guard let width = proposal.width, let height = proposal.height else { return nil }
        return CGSize(width: width, height: height)
    }
}

final class LockFrostedContainerView: NSView {
    private let effect = NSVisualEffectView()

    var cornerRadius: CGFloat = 30 {
        didSet { layer?.cornerRadius = cornerRadius }
    }

    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true

        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.isEmphasized = true
        // The revival pinned .darkAqua, which read too dark. The system runs a
        // light appearance and the decompiled lock branch uses a light
        // background too, so pin Aqua explicitly instead of inheriting.
        effect.appearance = NSAppearance(named: .aqua)
        effect.translatesAutoresizingMaskIntoConstraints = false
        addSubview(effect)
        NSLayoutConstraint.activate([
            effect.leadingAnchor.constraint(equalTo: leadingAnchor),
            effect.trailingAnchor.constraint(equalTo: trailingAnchor),
            effect.topAnchor.constraint(equalTo: topAnchor),
            effect.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Decoration only; the player above owns every interaction.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
