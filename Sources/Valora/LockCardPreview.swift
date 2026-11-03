import AppKit
import SwiftUI

/// `--lock-card-preview` inspection path. Shows the *real* lock music card on
/// the desktop at the exact lock-screen position and size, so the glass, type
/// and player can be reviewed without locking the screen. It is a launch flag
/// only; nothing in settings or the menus exposes it, and it never changes the
/// session or the lock state.
@MainActor
final class LockCardPreviewController {
    private let model: AppModel
    private var panel: NSPanel?

    init(_ model: AppModel) { self.model = model }

    func start() {
        guard panel == nil, let screen = NSScreen.screens.first else { return }
        let size = CGSize(width: 385, height: LockMusicCoordinator.canvasHeight)
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.animationBehavior = .none
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: LockCardPreviewRoot(model: model, settings: model.settings))
        // Optional inspection position, so the card can be parked over a
        // colourful part of the wallpaper instead of a white window.
        let origin: NSPoint
        if let raw = ProcessInfo.processInfo.environment["VALORA_LOCK_PREVIEW_ORIGIN"] {
            let parts = raw.split(separator: ",").compactMap { Double($0) }
            origin = parts.count == 2 ? NSPoint(x: parts[0], y: parts[1])
                                      : NSPoint(x: screen.frame.midX - 192.5,
                                                y: screen.frame.minY + screen.frame.height * 0.21 - LockMusicCoordinator.animationMargin)
        } else {
            origin = NSPoint(x: screen.frame.midX - 192.5,
                             y: screen.frame.minY + screen.frame.height * 0.21 - LockMusicCoordinator.animationMargin)
        }
        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func stop() {
        panel?.orderOut(nil)
        panel?.contentView = nil
        panel?.close()
        panel = nil
    }
}

private struct LockCardPreviewRoot: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: RevivalSettings
    @State private var showsVolume = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            LockMusicCard(model: model, settings: settings,
                          active: true, showsVolume: $showsVolume)
        }
        .padding(.bottom, LockMusicCoordinator.animationMargin)
        .frame(width: 385, height: LockMusicCoordinator.canvasHeight, alignment: .bottom)
    }
}
