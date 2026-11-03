import AppKit
import Combine
import SwiftUI

/// Window-facing seam used by the lock coordinator. Production uses the
/// existing AppKit panel; isolated tests inject a fake and never construct an
/// NSWindow or NSHostingView.
@MainActor
protocol LockPresentationWindow: AnyObject {
    var windowNumber: Int { get }
    var isVisible: Bool { get }
    var frame: CGRect { get }
    var diagnosticHostFrame: CGRect { get }
    func setRootView(_ view: AnyView)
    func clearRootView()
    func setFrameOrigin(_ origin: CGPoint)
    func setSharingType(_ type: NSWindow.SharingType)
    func setAlphaValue(_ value: CGFloat)
    func orderFrontRegardless()
    func orderOut()
    func close()
}

extension LockPresentationWindow {
    var diagnosticHostFrame: CGRect { frame }
    func setAlphaValue(_ value: CGFloat) {}
}

@MainActor
protocol LockPresentationWindowFactory {
    func makeWindow(size: CGSize, level: NSWindow.Level, ignoresMouseEvents: Bool) -> any LockPresentationWindow
}

final class LockMusicPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class LockAppKitPresentationWindow: LockPresentationWindow {
    let panel: LockMusicPanel
    init(panel: LockMusicPanel) { self.panel = panel }
    var windowNumber: Int { panel.windowNumber }
    var isVisible: Bool { panel.isVisible }
    var frame: CGRect { panel.frame }
    var diagnosticHostFrame: CGRect { panel.contentView?.frame ?? .zero }
    func setRootView(_ view: AnyView) { panel.contentView = NSHostingView(rootView: view) }
    func clearRootView() { panel.contentView = nil }
    func setFrameOrigin(_ origin: CGPoint) { panel.setFrameOrigin(origin) }
    func setSharingType(_ type: NSWindow.SharingType) { panel.sharingType = type }
    func setAlphaValue(_ value: CGFloat) { panel.alphaValue = value }
    func orderFrontRegardless() { panel.orderFrontRegardless() }
    func orderOut() { panel.orderOut(nil) }
    func close() { panel.close() }
}

struct LockAppKitWindowFactory: LockPresentationWindowFactory {
    func makeWindow(size: CGSize, level: NSWindow.Level, ignoresMouseEvents: Bool) -> any LockPresentationWindow {
        let panel = LockMusicPanel(contentRect: NSRect(origin: .zero, size: size),
                                   styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                                   backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.canBecomeVisibleWithoutLogin = true
        panel.ignoresMouseEvents = ignoresMouseEvents
        panel.animationBehavior = .none
        panel.level = level
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        return LockAppKitPresentationWindow(panel: panel)
    }
}

/// The lock coordinator only needs the current active notch window number;
/// WindowCoordinator remains the owner of the panel.
@MainActor
protocol LockNotchWindow: AnyObject {
    var windowNumber: Int { get }
}
extension NSPanel: LockNotchWindow {}

/// System event seam. The AppKit source registers the real notification
/// centers; tests use the event source below without registering anything.
@MainActor
protocol LockSystemEventSource: AnyObject {
    var onLocked: (@MainActor @Sendable (Bool) -> Void)? { get set }
    var onSleep: (@MainActor @Sendable () -> Void)? { get set }
    var onWake: (@MainActor @Sendable () -> Void)? { get set }
    var onScreensChanged: (@MainActor @Sendable () -> Void)? { get set }
    func start()
    func stop()
}

@MainActor
final class LockAppKitEventSource: LockSystemEventSource {
    var onLocked: (@MainActor @Sendable (Bool) -> Void)?
    var onSleep: (@MainActor @Sendable () -> Void)?
    var onWake: (@MainActor @Sendable () -> Void)?
    var onScreensChanged: (@MainActor @Sendable () -> Void)?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var active = false
    private var generation: UInt64 = 0

    func start() {
        guard !active else { return }
        active = true
        generation &+= 1
        observe(DistributedNotificationCenter.default(), "com.apple.screenIsLocked") { [weak self] in
            self?.onLocked?(true)
        }
        observe(DistributedNotificationCenter.default(), "com.apple.screenIsUnlocked") { [weak self] in
            self?.onLocked?(false)
        }
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.willSleepNotification.rawValue) { [weak self] in
            self?.onSleep?()
        }
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.didWakeNotification.rawValue) { [weak self] in
            self?.onWake?()
        }
        observe(NotificationCenter.default, NSApplication.didChangeScreenParametersNotification.rawValue) { [weak self] in
            self?.onScreensChanged?()
        }
    }

    func stop() {
        active = false
        generation &+= 1
        for (center, token) in observers { center.removeObserver(token) }
        observers.removeAll()
    }

    private func observe(_ center: NotificationCenter, _ name: String, handler: @escaping @MainActor @Sendable () -> Void) {
        let generation = self.generation
        observers.append((center, center.addObserver(forName: Notification.Name(name), object: nil,
                                                     queue: .main) { [weak self] _ in
            // ObjC delivery is not a Swift actor guarantee. Hop explicitly and
            // reject a notification queued before a stop/start generation.
            Task { @MainActor [weak self] in
                guard let self, self.active, self.generation == generation else { return }
                handler()
            }
        }))
    }
}

@MainActor
protocol LockScheduledTask: AnyObject {
    func cancel()
}

@MainActor
protocol LockScheduling {
    func schedule(after seconds: TimeInterval,
                  _ action: @escaping @MainActor @Sendable () -> Void) -> any LockScheduledTask
}

@MainActor
private final class LockAsyncScheduledTask: LockScheduledTask {
    private var task: Task<Void, Never>?
    init(_ task: Task<Void, Never>) { self.task = task }
    func cancel() { task?.cancel(); task = nil }
}

@MainActor
final class LockAsyncScheduler: LockScheduling {
    func schedule(after seconds: TimeInterval,
                  _ action: @escaping @MainActor @Sendable () -> Void) -> any LockScheduledTask {
        let task = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
            } catch { return }
            guard !Task.isCancelled else { return }
            action()
        }
        return LockAsyncScheduledTask(task)
    }
}

/// Commits a geometry/content stage and reports when its SwiftUI animation has
/// logically completed. Tests inject a manual completion; production uses the
/// same logical-completion contract as PresentationController.
@MainActor
protocol LockGeometryAnimating {
    func animate(_ changes: @escaping @MainActor () -> Void,
                 completion: @escaping @MainActor () -> Void)
}

@MainActor
final class LockSwiftUIGeometryAnimator: LockGeometryAnimating {
    func animate(_ changes: @escaping @MainActor () -> Void,
                 completion: @escaping @MainActor () -> Void) {
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let animation: Animation = reduceMotion
            ? .easeOut(duration: 0.12)
            : .spring(duration: 0.45, bounce: 0.2)
        withAnimation(animation, completionCriteria: .logicallyComplete) {
            changes()
        } completion: {
            MainActor.assumeIsolated { completion() }
        }
    }
}

/// Dedicated hosting for the real lock notch overlay. This mirrors the mature
/// normal notch's zero-safe-area host and explicit frame, avoiding the generic
/// music-card NSHostingView from introducing a safe-area inset.
final class LockNotchOverlayHostingView: NSHostingView<AnyView> {
    override var safeAreaInsets: NSEdgeInsets { NSEdgeInsetsZero }
}

@MainActor
final class LockNotchOverlayWindow: LockPresentationWindow {
    let panel: NotchPanel
    init(panel: NotchPanel) { self.panel = panel }
    var windowNumber: Int { panel.windowNumber }
    var isVisible: Bool { panel.isVisible }
    var frame: CGRect { panel.frame }
    var diagnosticHostFrame: CGRect { panel.contentView?.frame ?? .zero }
    func setRootView(_ view: AnyView) {
        let host = LockNotchOverlayHostingView(rootView: view)
        host.sizingOptions = []
        panel.contentView = host
    }
    func clearRootView() { panel.contentView = nil }
    func setFrameOrigin(_ origin: CGPoint) { panel.setFrameOrigin(origin) }
    func setSharingType(_ type: NSWindow.SharingType) { panel.sharingType = type }
    func setAlphaValue(_ value: CGFloat) { panel.alphaValue = value }
    func orderFrontRegardless() { panel.orderFrontRegardless() }
    func orderOut() { panel.orderOut(nil) }
    func close() { panel.close() }
}

struct LockNotchOverlayWindowFactory: LockPresentationWindowFactory {
    func makeWindow(size: CGSize, level: NSWindow.Level,
                    ignoresMouseEvents: Bool) -> any LockPresentationWindow {
        let panel = NotchPanel(contentRect: NSRect(origin: .zero, size: size),
                               styleMask: [.borderless, .nonactivatingPanel],
                               backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.canBecomeVisibleWithoutLogin = true
        panel.ignoresMouseEvents = ignoresMouseEvents
        panel.acceptsMouseMovedEvents = false
        panel.animationBehavior = .none
        panel.level = level
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        return LockNotchOverlayWindow(panel: panel)
    }
}
