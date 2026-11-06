#if VALORA_DEVELOPMENT
import AppKit
import SwiftUI
import ReferenceCore

/// The desktop simulation of the lock music card. Two entry points use it:
/// `--lock-card-preview` for QA, and the Settings switch "模拟锁屏音乐" so the
/// card's material can be reviewed without locking the screen. It only shows
/// the *real* card on the desktop; nothing here changes the session, the lock
/// state or the player.
@MainActor
final class LockCardPreviewController {
    private let model: AppModel
    private var panel: NSPanel?
    private let activationOwner = LockActivationOwner(registry: .shared)


    init(_ model: AppModel) { self.model = model }

    /// Idempotent: the Settings switch and the launch flag cannot create a
    /// second panel.
    func setVisible(_ visible: Bool) {
        if visible { start() } else { stop() }
    }

    func start() {
        guard panel == nil, let screen = NSScreen.screens.first else { return }
        let size = CGSize(width: 385, height: LockMusicCoordinator.canvasHeight)
        let panel = LockCardPreviewPanel(contentRect: NSRect(origin: .zero, size: size),
                                         styleMask: [.borderless, .nonactivatingPanel],
                                         backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        // QA: make the preview clickable so the card's controls can be
        // exercised from the desktop without locking the screen.
        panel.ignoresMouseEvents = ProcessInfo.processInfo.environment["VALORA_LOCK_PREVIEW_CLICKABLE"] != "1"
        panel.animationBehavior = .none
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        let host = LockFirstMouseHostingView(rootView: LockCardPreviewRoot(
            model: model, settings: model.settings))
        host.sizingOptions = []
        panel.contentView = host
        panel.setContentSize(size)
        // Optional inspection position, so the card can be parked over a
        // colourful part of the wallpaper instead of a white window.
        let layout = LockCardLayout(screenMinY: screen.frame.minY,
                                    screenHeight: screen.frame.height)
        let defaultOrigin = NSPoint(x: screen.frame.midX - 192.5,
                                    y: CGFloat(layout.panelOriginY))
        let origin: NSPoint
        if let raw = ProcessInfo.processInfo.environment["VALORA_LOCK_PREVIEW_ORIGIN"],
           case let parts = raw.split(separator: ",").compactMap({ Double($0) }),
           parts.count == 2 {
            origin = NSPoint(x: parts[0], y: parts[1])
        } else {
            origin = defaultOrigin
        }
        panel.setFrameOrigin(origin)
        // The desktop simulation is deliberately a focused window: with the
        // current material, the refractive look appeared while the surface was
        // key (an observation, not a proven system rule). The preview takes the
        // regular policy through the shared activation lifetime and gives it
        // back on `stop()`; the real lock behaviour still needs on-device checks.
        activationOwner.acquire()
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
    }

    func stop() {
        if panel != nil { activationOwner.release() }
        panel?.orderOut(nil)
        panel?.contentView = nil
        panel?.close()
        panel = nil
    }
}

/// Borderless panels cannot become key by default; the simulation needs to be
/// key so the system renders the active glass material.
private final class LockCardPreviewPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private struct LockCardPreviewRoot: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: RevivalSettings
    @State private var showsVolume = false

    var body: some View {
        VStack(spacing: 0) {
            LockMusicCard(model: model, settings: settings,
                          active: true, showsVolume: $showsVolume)
        }
        .frame(width: 385, height: LockMusicCoordinator.canvasHeight, alignment: .top)
    }
}
#endif
