import AppKit
import Combine
import Foundation
import NativeBridge
import ReferenceCore
import SwiftUI

@MainActor
protocol LockSoundPlaying: AnyObject {
    func playLock()
    func playUnlock()
    func stop()
}

@MainActor
final class AppKitLockSound: LockSoundPlaying {
    private var current: NSSound?
    func playLock() { play(named: "lock") }
    func playUnlock() { play(named: "unlock") }
    func stop() { current?.stop(); current = nil }
    private func play(named name: String) {
        stop()
        guard let url = Bundle.main.url(forResource: name, withExtension: "caf", subdirectory: "Sounds"),
              let sound = NSSound(contentsOf: url, byReference: true) else { return }
        current = sound
        sound.play()
    }
}

@MainActor
protocol LockPresentationSpace: AnyObject {
    func attachWindowNumber(_ number: Int) -> Bool
    func detachWindowNumber(_ number: Int)
    func windowSpaceIDs(_ number: Int) -> [NSNumber]?
    func migrateWindowNumberToOwnedSpace(_ number: Int) -> Bool
    /// Move the window into the owned Space only. The default keeps the previous
    /// add-only meaning for injected fakes; production forwards to the native
    /// exclusive migration that reports the real captured memberships.
    func migrateWindowNumberExclusively(_ number: Int) -> [String: Any]
    var spaceID: UInt64 { get }
    func diagnostic() -> [AnyHashable: Any]
}
extension LockPresentationSpace {
    func migrateWindowNumberExclusively(_ number: Int) -> [String: Any] {
        ["ok": migrateWindowNumberToOwnedSpace(number), "reason": "default-migration"]
    }
}
extension ARLockPresentationSpace: LockPresentationSpace {
    func migrateWindowNumberToOwnedSpace(_ number: Int) -> Bool {
        ARLockSpaceMigrateWindow(self, number)
    }
    func migrateWindowNumberExclusively(_ number: Int) -> [String: Any] {
        ARLockSpaceMigrateWindowExclusive(self, number)
    }
    var spaceID: UInt64 { ARLockSpaceOwnedID(self) }
}

/// Selected lock-screen music/device experience. All native-facing resources
/// (windows, notifications, Space, sound and scheduler) are injected seams so
/// isolated tests never create a real panel, register a system observer, create
/// a Space, play a sound or wait ten minutes.
@MainActor
final class LockMusicCoordinator: ObservableObject {
    /// Host window height: the card's tallest state plus transition room. The
    /// window keeps this size in every state so its top edge cannot move.
    static let canvasHeight: CGFloat = CGFloat(LockCardLayout.canvasHeight)

    unowned let model: AppModel
    private let windowFactory: any LockPresentationWindowFactory
    private let overlayWindowFactory: any LockPresentationWindowFactory
    private let overlayFrameProvider: (@MainActor () -> CGRect?)?
    private let displayProvider: @MainActor () -> [DisplayDescriptor]
    private var targetDisplay: DisplayDescriptor?
    private let spaceFactory: () -> (any LockPresentationSpace)?
    private let eventSource: any LockSystemEventSource
    private let scheduler: any LockScheduling
    private let collapsePresentation: (@escaping () -> Void) -> Void
    private let geometryAnimator: any LockGeometryAnimating
    private let clock: () -> TimeInterval
    private let notchWindowProvider: @MainActor () -> (any LockNotchWindow)?
    private let notchWindowUpdates: AnyPublisher<Int?, Never>
    private let sound: any LockSoundPlaying
    private let usePresentationSpace: Bool
    private let sessionLocked: () -> Bool

    private(set) var panel: (any LockPresentationWindow)!
    private(set) var informationPanel: (any LockPresentationWindow)!
    /// Published explicitly: LockInformationView reads this property and must
    /// repaint when nil→device, battery/model changes or device→nil happens.
    @Published private(set) var informationAirPods: AudioDevice?
    @Published private(set) var visible = false
    @Published private(set) var appeared = false
    @Published var showsVolume = false
    /// Owns the temporary activation taken while the card is on screen. The
    /// previous policy (and the previous frontmost app) are restored conservatively
    /// on release; see `LockActivationOwner`.
    private let activationOwner = LockActivationOwner(registry: .shared)
    private var glassActivated = false

    private var state = LockMusicState()
    private var lockSpace: (any LockPresentationSpace)?
    private var overlayWindow: (any LockPresentationWindow)?
    private var overlayFailureReason: String?
    private var overlayFailureAttempt: UInt64?
    private var overlayFailureFrameKey: String?
    private var lockAttemptGeneration: UInt64 = 0
    private var sleeping = false
    private var lastLocked: Bool?
    private var lastInformationIdentity: String?
    private var mountedNotchNumber: Int?
    private var deadlineTask: (any LockScheduledTask)?
    private var hideTask: (any LockScheduledTask)?
    private var appearanceTask: (any LockScheduledTask)?
    private var unlockTask: (any LockScheduledTask)?
    private var neutralTask: (any LockScheduledTask)?
    private var overlayCheckTask: (any LockScheduledTask)?
    private var notchCheckTask: (any LockScheduledTask)?
    private var subscriptions = Set<AnyCancellable>()
    private var started = false
    private var sessionEpoch: UInt64 = 0

    init(_ model: AppModel,
         notchWindowProvider: @escaping @MainActor () -> (any LockNotchWindow)? = { nil },
         notchWindowUpdates: AnyPublisher<Int?, Never> = Empty<Int?, Never>(completeImmediately: false).eraseToAnyPublisher(),
         windowFactory: any LockPresentationWindowFactory = LockAppKitWindowFactory(),
         overlayWindowFactory: any LockPresentationWindowFactory = LockNotchOverlayWindowFactory(),
         overlayFrameProvider: (@MainActor () -> CGRect?)? = nil,
         displayProvider: @escaping @MainActor () -> [DisplayDescriptor] = { LockDisplayPolicy.availableDisplays() },
         usePresentationSpace: Bool = true,
         spaceFactory: @escaping () -> (any LockPresentationSpace)? = {
             ARLockPresentationSpace.create()
         },
         eventSource: any LockSystemEventSource = LockAppKitEventSource(),
         scheduler: any LockScheduling = LockAsyncScheduler(),
         collapsePresentation: ((@escaping () -> Void) -> Void)? = nil,
         geometryAnimator: any LockGeometryAnimating = LockSwiftUIGeometryAnimator(),
         clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         sessionLocked: @escaping () -> Bool = {
             (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Bool ?? false
         },
         sound: any LockSoundPlaying = AppKitLockSound()) {
        self.model = model
        self.notchWindowProvider = notchWindowProvider
        self.notchWindowUpdates = notchWindowUpdates
        self.windowFactory = windowFactory
        self.overlayWindowFactory = overlayWindowFactory
        self.overlayFrameProvider = overlayFrameProvider
        self.displayProvider = displayProvider
        self.usePresentationSpace = usePresentationSpace
        self.spaceFactory = spaceFactory
        self.eventSource = eventSource
        self.scheduler = scheduler
        self.collapsePresentation = collapsePresentation ?? { completion in
            model.presenter.collapse(completion: completion)
        }
        self.geometryAnimator = geometryAnimator
        self.clock = clock
        self.sessionLocked = sessionLocked
        self.sound = sound
    }

    var enabled: Bool { started }
    private func isCurrent(_ epoch: UInt64) -> Bool { started && epoch == sessionEpoch }
    /// The compact lock activity must use the same horizontal expansion feel as
    /// the normal music activity. PresentationController's media idle/activity
    /// animation is spring(duration: 0.35, bounce: -0.2); the lock glyph itself
    /// keeps its own existing .45/.2 open/close animation.
    private var activityAnimation: Animation {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            ? .easeOut(duration: 0.12)
            : .spring(duration: 0.35, bounce: -0.2)
    }

    func setEnabled(_ enabled: Bool) {
        if enabled { startIfNeeded() } else { stop() }
    }

    private func startIfNeeded() {
        guard !started, model.settings.lockPreferences.enabled else { return }
        started = true
        sessionEpoch &+= 1
        let epoch = sessionEpoch
        state = LockMusicState()
        sleeping = false
        lockAttemptGeneration = 0
        overlayFailureAttempt = nil
        overlayFailureFrameKey = nil
        lastLocked = nil
        lastInformationIdentity = nil
        mountedNotchNumber = nil
        showsVolume = false
        createPanels()
        bindModel(epoch: epoch)
        wireEvents(epoch: epoch)
        eventSource.start()
        let locked = sessionLocked()
        lastLocked = locked
        if locked { lockAttemptGeneration &+= 1 }
        model.isSessionLocked = locked
        var indicator = model.lockIndicator
        if locked { indicator.forceLocked() } else { indicator.forceHidden() }
        model.lockIndicator = indicator
        place()
        refresh(epoch: epoch)
    }

    private func createPanels() {
        let level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        panel = windowFactory.makeWindow(size: CGSize(width: 385, height: Self.canvasHeight),
                                         level: level, ignoresMouseEvents: false)
        panel.setRootView(AnyView(LockMusicView(model: model, settings: model.settings, coordinator: self)))
        informationPanel = windowFactory.makeWindow(size: CGSize(width: 360, height: 94),
                                                    level: level, ignoresMouseEvents: true)
        informationPanel.setRootView(AnyView(LockInformationView(model: model, coordinator: self)))
        if usePresentationSpace { lockSpace = spaceFactory() }
        applySharingType()
    }

    private func bindModel(epoch: UInt64) {
        model.settings.$hideFromScreenCapture.removeDuplicates().sink { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isCurrent(epoch) else { return }
                self.applySharingType()
            }
        }.store(in: &subscriptions)
        Publishers.MergeMany(
            model.$playing.map { _ in () }.eraseToAnyPublisher(),
            model.$title.map { _ in () }.eraseToAnyPublisher(),
            model.$artist.map { _ in () }.eraseToAnyPublisher(),
            model.$album.map { _ in () }.eraseToAnyPublisher(),
            model.$devices.map { _ in () }.eraseToAnyPublisher(),
            model.$mediaBundleIdentifier.map { _ in () }.eraseToAnyPublisher(),
            model.settings.$nowPlayingEnabled.map { _ in () }.eraseToAnyPublisher(),
            model.settings.$bluetoothEnabled.map { _ in () }.eraseToAnyPublisher(),
            model.settings.$lockPreferences.map { _ in () }.eraseToAnyPublisher()
        ).sink { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh(epoch: epoch) }
        }.store(in: &subscriptions)
        notchWindowUpdates.sink { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh(epoch: epoch) }
        }.store(in: &subscriptions)
    }

    private func wireEvents(epoch: UInt64) {
        eventSource.onLocked = { [weak self] locked in
            self?.receiveLocked(locked, epoch: epoch)
        }
        eventSource.onSleep = { [weak self] in
            self?.receiveSleep(epoch: epoch)
        }
        eventSource.onWake = { [weak self] in
            self?.receiveWake(epoch: epoch)
        }
        eventSource.onScreensChanged = { [weak self] in
            self?.receiveScreensChanged(epoch: epoch)
        }
    }

    private func receiveLocked(_ value: Bool, epoch: UInt64) {
        guard isCurrent(epoch) else { return }
        NotchWindowDiagnostic.shared.recordSystemEvent(locked: value,
            phase: String(describing: model.lockIndicator.phase))
        let changed = lastLocked != value
        lastLocked = value
        if changed, value {
            lockAttemptGeneration &+= 1
            overlayFailureAttempt = nil
            overlayFailureFrameKey = nil
        }
        if changed {
            let preferences = model.settings.lockPreferences
            if value, preferences.soundOnLock { sound.playLock() }
            if !value, preferences.soundOnUnlock { sound.playUnlock() }
        }

        guard value else {
            beginUnlock(epoch: epoch)
            return
        }

        // A relock while the open glyph is still visible should return to the
        // settled badge directly; normal content has already been removed.
        if model.lockIndicator.phase == .unlocking || model.lockIndicator.phase == .restoring {
            unlockTask?.cancel(); unlockTask = nil
            neutralTask?.cancel(); neutralTask = nil
            var indicator = model.lockIndicator
            indicator.forceLocked()
            model.lockIndicator = indicator
            model.isSessionLocked = true
            refresh(epoch: epoch)
            return
        }

        // Lock: keep ordinary music on screen while the existing presentation
        // collapse shrinks it. The badge is committed only after that bounded
        // collapse completes. No expanded/peek height survives into the badge.
        var indicator = model.lockIndicator
        model.isSessionLocked = true
        if indicator.phase == .locked || indicator.phase == .locking
            || indicator.phase == .neutralizing { return }
        let token = indicator.beginLocking()
        model.lockIndicator = indicator
        model.presenter.cancelPeek()
        unlockTask?.cancel(); unlockTask = nil
        let complete: () -> Void = { [weak self] in
            guard let self, self.isCurrent(epoch) else { return }
            var current = self.model.lockIndicator
            guard current.phase == .locking, current.generation == token else { return }
            // The production collapsed-player completion can be synchronous
            // for compact music. Defer the neutral geometry to the next run
            // loop so the actual locking phase is observable and so the compact
            // side wings are retracted by a real stage rather than an enum jump.
            self.neutralTask?.cancel()
            self.neutralTask = self.scheduler.schedule(after: 0) { [weak self] in
                guard let self, self.isCurrent(epoch) else { return }
                var neutral = self.model.lockIndicator
                guard neutral.phase == .locking, neutral.generation == token else { return }
                guard neutral.beginNeutralizing() != 0 else { return }
                let neutralToken = neutral.generation
                self.neutralTask = nil
                self.geometryAnimator.animate({ [weak self] in
                    guard let self, self.isCurrent(epoch) else { return }
                    self.model.lockIndicator = neutral
                    self.refresh(epoch: epoch)
                }, completion: { [weak self] in
                    guard let self, self.isCurrent(epoch) else { return }
                    var locked = self.model.lockIndicator
                    guard locked.completeLocking(token: neutralToken) else { return }
                    withAnimation(self.activityAnimation) {
                        self.model.lockIndicator = locked
                        self.refresh(epoch: epoch)
                    }
                })
            }
        }
        // If already collapsed this runs synchronously; otherwise the existing
        // PresentationController completion (or the isolated test seam) owns
        // the collapse sequence.
        collapsePresentation(complete)
    }

    private func beginUnlock(epoch: UInt64) {
        guard isCurrent(epoch) else { return }
        switch model.lockIndicator.phase {
        case .locking:
            // Unlock arrived before the lock badge was committed. Cancel the
            // old collapse completion and its queued neutral transition via
            // generation/phase checks, then return to normal presentation.
            neutralTask?.cancel(); neutralTask = nil
            var indicator = model.lockIndicator
            indicator.forceHidden()
            model.lockIndicator = indicator
            model.isSessionLocked = false
            cancelHideAndAppearance()
            visible = false
            appeared = false
            showsVolume = false
            if let panel {
                panel.orderOut()
                lockSpace?.detachWindowNumber(panel.windowNumber)
            }
            deactivateGlassSurface()
            refresh(epoch: epoch)
        case .neutralizing:
            neutralTask?.cancel(); neutralTask = nil
            var indicator = model.lockIndicator
            indicator.forceHidden()
            model.lockIndicator = indicator
            model.isSessionLocked = false
            refresh(epoch: epoch)
        case .locked:
            var indicator = model.lockIndicator
            let token = indicator.beginUnlocking()
            model.lockIndicator = indicator
            // The login-only music card is a hard boundary: remove/detach it
            // immediately while the notch badge remains for the unlock glyph.
            cancelHideAndAppearance()
            visible = false
            appeared = false
            showsVolume = false
            if let panel {
                panel.orderOut()
                lockSpace?.detachWindowNumber(panel.windowNumber)
            }
            deactivateGlassSurface()
            refresh(epoch: epoch)
            unlockTask?.cancel()
            unlockTask = scheduler.schedule(after: 0.8) { [weak self] in
                guard let self, self.isCurrent(epoch) else { return }
                var current = self.model.lockIndicator
                guard current.finishUnlockToRestoring(token: token) else { return }
                // Keep the actual session locked and music blocked while the
                // badge retracts to the neutral base notch.
                self.unlockTask = nil
                self.neutralTask?.cancel()
                let restoreToken = current.generation
                self.geometryAnimator.animate({ [weak self] in
                    guard let self, self.isCurrent(epoch) else { return }
                    self.model.lockIndicator = current
                    self.refresh(epoch: epoch)
                }, completion: { [weak self] in
                    guard let self, self.isCurrent(epoch) else { return }
                    var restored = self.model.lockIndicator
                    guard restored.finishRestoring(token: restoreToken) else { return }
                    withAnimation(self.activityAnimation) {
                        self.model.lockIndicator = restored
                        self.model.isSessionLocked = false
                        self.refresh(epoch: epoch)
                    }
                })
            }
        case .unlocking:
            // Duplicate unlock notification: preserve the already-running
            // staged animation rather than restarting it.
            break
        case .restoring:
            // Keep the short restore completion; do not reintroduce a lock.
            break
        case .hidden:
            // An unlock during sleep may arrive while the badge is hidden.
            // Reconcile the actual session flag without replaying a lock edge.
            model.isSessionLocked = false
            refresh(epoch: epoch)
        }
    }

    private func receiveSleep(epoch: UInt64) {
        guard isCurrent(epoch) else { return }
        var indicator = model.lockIndicator
        indicator.forceHidden()
        model.lockIndicator = indicator
        sleeping = true
        unlockTask?.cancel(); unlockTask = nil
        neutralTask?.cancel(); neutralTask = nil
        releaseOverlay()
        refresh(epoch: epoch)
    }

    private func receiveWake(epoch: UInt64) {
        guard isCurrent(epoch) else { return }
        sleeping = false
        overlayFailureAttempt = nil
        overlayFailureFrameKey = nil
        // Wake is reconciliation, not a replay of the animated lock edge.
        model.isSessionLocked = lastLocked == true
        var indicator = model.lockIndicator
        if lastLocked == true { indicator.forceLocked() } else { indicator.forceHidden() }
        model.lockIndicator = indicator
        refresh(epoch: epoch)
    }

    private func receiveScreensChanged(epoch: UInt64) {
        guard isCurrent(epoch) else { return }
        overlayFailureAttempt = nil
        overlayFailureFrameKey = nil
        place()
        refresh(epoch: epoch)
    }

    /// Kept for narrow compatibility with existing callers/tests that inject a
    /// lock edge directly. Notification delivery always uses receiveLocked with
    /// its captured epoch instead.
    func setLocked(_ value: Bool) {
        receiveLocked(value, epoch: sessionEpoch)
    }

    func refresh() { refresh(epoch: sessionEpoch) }

    private func refresh(epoch: UInt64) {
        guard isCurrent(epoch) else { return }
        let preferences = model.settings.lockPreferences
        let now = clock()
        let previous = state.generation
        var musicPreferences = preferences
        musicPreferences.musicEnabled = model.settings.nowPlayingEnabled
        // The music card belongs to the settled locked stage only; during
        // locking/unlocking/restoring the normal or badge surface owns the
        // transition and must not be covered by a stale lock-only card.
        state.update(locked: model.isSessionLocked && model.lockIndicator.phase == .locked,
                     sleeping: sleeping,
                     hasTrack: model.hasTrack, playing: model.playing,
                     identity: model.mediaBundleIdentifier + "\u{0}" + model.title + "\u{0}" + model.artist + "\u{0}" + model.album,
                     preferences: musicPreferences, now: now)
        place()
        syncLockIndicator()
        refreshInformation()
        if previous != state.generation {
            deadlineTask?.cancel()
            deadlineTask = nil
            if let deadline = state.deadline {
                let token = state.generation
                deadlineTask = scheduler.schedule(after: max(0, deadline - now)) { [weak self] in
                    guard let self, self.isCurrent(epoch) else { return }
                    self.state.expire(token: token, now: self.clock())
                    self.applyVisibility(epoch: epoch)
                }
            }
        }
        applyVisibility(epoch: epoch)
    }

    private func syncLockIndicator() {
        // The phase is owned by receiveLocked/receiveSleep/receiveWake. The
        // real lock gets a dedicated top overlay; the ordinary desktop panel is
        // only a fallback when that overlay cannot be prepared.
        if model.lockOverlayReady {
            if model.lockIndicator.phase == .hidden && !model.isSessionLocked {
                releaseOverlay()
            } else {
                // The overlay owns the top surface. Never attach the ordinary
                // primary to the lock Space in parallel. Active-screen changes
                // arrive through notchWindowUpdates and only reposition the
                // already-prepared overlay; no timers or duplicate windows.
                repositionOverlay()
                recordOverlayState(reason: "phase:\(model.lockIndicator.phase)")
                detachNotchIfNeeded()
                return
            }
        }
        // Keep the ordinary primary visible during the bounded `.locking`
        // collapse; create the isolated overlay only once the compact/music
        // surface has reached the neutral/locked presentation boundary.
        if model.isSessionLocked, model.lockIndicator.phase != .hidden,
           model.lockIndicator.phase != .locking,
           ensureOverlay() {
            return
        }
        if !model.isSessionLocked || model.lockIndicator.phase == .hidden {
            releaseOverlay()
        }
        updateNotchMount(wanted: model.lockIndicator.phase != .hidden)
    }

    /// Dedicated fixed-top lock overlay. It is created only for a real lock and
    /// is only allowed to become the owner after the owned window is migrated to
    /// exactly the target Space and verified. Failure keeps the known primary
    /// fallback visible.
    private func ensureOverlay() -> Bool {
        guard model.isSessionLocked, started else { return false }
        if model.lockOverlayReady, overlayWindow != nil { return true }
        guard let lockSpace, let screenFrame = lockDisplayFrame else {
            overlayFailureReason = "missing-space-or-screen"
            return false
        }
        let frameKey = "\(screenFrame.origin.x),\(screenFrame.origin.y),\(screenFrame.width),\(screenFrame.height)"
        if overlayFailureAttempt == lockAttemptGeneration, overlayFailureFrameKey == frameKey {
            return false
        }
        let window = overlayWindowFactory.makeWindow(
            size: CGSize(width: 624, height: 320),
            level: NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1),
            ignoresMouseEvents: true)
        window.setRootView(AnyView(NotchView(model: model, settings: model.settings,
                                             compactOnly: false, allowsDynamic: false, lockSurface: true)))
        window.setFrameOrigin(NSPoint(x: screenFrame.midX - 312,
                                      y: screenFrame.maxY - 320))
        // A not-yet-ordered NSWindow has no Space membership for the conservative
        // migration precheck. Order it transparently so it joins the normal
        // desktop Space, migrate it, then reveal only after verification. It is
        // never visible alongside primary before `lockOverlayReady`.
        window.setAlphaValue(0)
        window.orderFrontRegardless()
        let number = window.windowNumber
        // A freshly ordered window has no Space membership yet, which is a legal
        // starting point rather than a failure. The exclusive migration adds the
        // owned Space and drops any user-session membership so the surface does
        // not ride the lock/unlock zoom of the ordinary desktop.
        let migration: [String: Any] = number > 0
            ? lockSpace.migrateWindowNumberExclusively(number)
            : ["ok": false, "reason": "no-window-number"]
        let verified = (migration["ok"] as? Bool) == true
        guard verified else {
            let reason = migration["reason"] as? String ?? "unknown"
            overlayFailureReason = reason
            overlayFailureAttempt = lockAttemptGeneration
            overlayFailureFrameKey = frameKey
            NotchWindowDiagnostic.shared.recordOverlay(
                reason: "failure:\(reason)",
                phase: String(describing: model.lockIndicator.phase),
                frame: window.frame, hostFrame: window.diagnosticHostFrame,
                visible: window.isVisible, sessionLocked: model.isSessionLocked,
                windowNumber: window.windowNumber,
                space: migration)
            window.orderOut()
            window.clearRootView()
            window.close()
            model.lockOverlayReady = false
            return false
        }
        window.setAlphaValue(1)
        overlayWindow = window
        overlayFailureReason = nil
        overlayFailureAttempt = nil
        overlayFailureFrameKey = nil
        model.lockOverlayReady = true
        window.orderFrontRegardless()
        detachNotchIfNeeded()
        scheduleOverlayCompositingCheck(windowNumber: window.windowNumber)
        NotchWindowDiagnostic.shared.recordOverlay(
            reason: "ready", phase: String(describing: model.lockIndicator.phase),
            frame: window.frame, hostFrame: window.diagnosticHostFrame,
            visible: window.isVisible, sessionLocked: model.isSessionLocked,
            windowNumber: window.windowNumber, space: diagnosticSpaceSnapshot(windowNumber: window.windowNumber))
        return true
    }

    private func repositionOverlay() {
        guard let overlayWindow, let frame = lockDisplayFrame else { return }
        overlayWindow.setFrameOrigin(NSPoint(x: frame.midX - 312,
                                             y: frame.maxY - 320))
        recordOverlayState(reason: "reposition")
    }

    /// The owned Space only helps if the surface is really composited. Check once
    /// per attempt and fall back to the known-visible user-session surface when
    /// the window is definitely not on screen; no timer, no retry loop.
    private func scheduleOverlayCompositingCheck(windowNumber: Int) {
        overlayCheckTask?.cancel()
        overlayCheckTask = nil
        guard windowNumber > 0 else { return }
        overlayCheckTask = scheduler.schedule(after: 0.25) { [weak self] in
            guard let self, self.started, self.model.lockOverlayReady,
                  self.overlayWindow?.windowNumber == windowNumber else { return }
            guard NotchWindowDiagnostic.isWindowComposited(windowNumber) == false else { return }
            self.overlayFailureReason = "not-composited"
            self.overlayFailureAttempt = self.lockAttemptGeneration
            self.releaseOverlay()
            self.updateNotchMount(wanted: self.model.lockIndicator.phase != .hidden)
        }
    }

    private func recordOverlayState(reason: String) {
        guard NotchWindowDiagnostic.shared.isEnabled, let overlayWindow else { return }
        NotchWindowDiagnostic.shared.recordOverlay(
            reason: reason, phase: String(describing: model.lockIndicator.phase),
            frame: overlayWindow.frame, hostFrame: overlayWindow.diagnosticHostFrame,
            visible: overlayWindow.isVisible, sessionLocked: model.isSessionLocked,
            windowNumber: overlayWindow.windowNumber,
            space: diagnosticSpaceSnapshot(windowNumber: overlayWindow.windowNumber))
    }

    private func releaseOverlay() {
        guard let overlayWindow else {
            model.lockOverlayReady = false
            return
        }
        lockSpace?.detachWindowNumber(overlayWindow.windowNumber)
        NotchWindowDiagnostic.shared.recordOverlay(
            reason: "release", phase: String(describing: model.lockIndicator.phase),
            frame: overlayWindow.frame, hostFrame: overlayWindow.diagnosticHostFrame,
            visible: overlayWindow.isVisible, sessionLocked: model.isSessionLocked,
            windowNumber: overlayWindow.windowNumber, space: diagnosticSpaceSnapshot(windowNumber: overlayWindow.windowNumber))
        overlayWindow.orderOut()
        overlayWindow.clearRootView()
        overlayWindow.close()
        self.overlayWindow = nil
        model.lockOverlayReady = false
    }

    private func updateNotchMount(wanted: Bool) {
        let number = notchWindowProvider()?.windowNumber
        let current = (number ?? 0) > 0 ? number : nil
        let before = diagnosticSpaceSnapshot(windowNumber: mountedNotchNumber ?? current)
        if let mounted = mountedNotchNumber, mounted != current || !wanted {
            lockSpace?.detachWindowNumber(mounted)
            mountedNotchNumber = nil
        }
        if wanted, let current, mountedNotchNumber != current {
            // Prefer the owned-Space-only mount so the panel keeps its physical
            // top edge through the lock/unlock zoom. The known-visible add-only
            // membership stays as the fallback when that is refused.
            let exclusive = usePresentationSpace
                && lockSpace?.migrateWindowNumberExclusively(current)["ok"] as? Bool == true
            if !usePresentationSpace || exclusive || lockSpace?.attachWindowNumber(current) == true {
                mountedNotchNumber = current
                model.lockNotchMounted = true
                if exclusive { scheduleNotchCompositingCheck(windowNumber: current) }
            } else {
                model.lockNotchMounted = false
            }
        } else {
            model.lockNotchMounted = wanted && mountedNotchNumber != nil
        }
        recordDiagnosticSpace(reason: "notch-mount", before: before,
                              windowNumber: current ?? mountedNotchNumber ?? 0)
    }

    private func detachNotchIfNeeded() {
        notchCheckTask?.cancel()
        notchCheckTask = nil
        let mountedBefore = mountedNotchNumber
        let before = diagnosticSpaceSnapshot(windowNumber: mountedBefore)
        if let mounted = mountedNotchNumber { lockSpace?.detachWindowNumber(mounted) }
        mountedNotchNumber = nil
        model.lockNotchMounted = false
        recordDiagnosticSpace(reason: "notch-detach", before: before,
                              windowNumber: mountedBefore ?? 0)
    }

    /// Same one-shot guard as the overlay: an owned-Space-only notch must prove
    /// it is composited, otherwise the add-only membership is restored so the
    /// lock never loses its top surface.
    private func scheduleNotchCompositingCheck(windowNumber: Int) {
        notchCheckTask?.cancel()
        notchCheckTask = nil
        guard windowNumber > 0 else { return }
        notchCheckTask = scheduler.schedule(after: 0.25) { [weak self] in
            guard let self, self.started, self.mountedNotchNumber == windowNumber else { return }
            guard NotchWindowDiagnostic.isWindowComposited(windowNumber) == false else { return }
            self.lockSpace?.detachWindowNumber(windowNumber)
            self.mountedNotchNumber = nil
            _ = self.lockSpace?.attachWindowNumber(windowNumber)
            self.mountedNotchNumber = windowNumber
            self.model.lockNotchMounted = true
            self.recordDiagnosticSpace(reason: "notch-fallback",
                                       before: ["reason": "not-composited"],
                                       windowNumber: windowNumber)
        }
    }

    private func diagnosticSpaceSnapshot(windowNumber: Int?) -> [String: Any] {
        guard NotchWindowDiagnostic.shared.isEnabled else { return [:] }
        guard let values = lockSpace?.diagnostic() else {
            return ["created": false, "windowSpaces": "unknown"]
        }
        var result: [String: Any] = ["query": "ok"]
        for (key, value) in values { result[String(describing: key)] = value }
        if let windowNumber, windowNumber > 0 {
            if let spaces = lockSpace?.windowSpaceIDs(windowNumber) {
                result["windowSpaces"] = spaces
            } else {
                result["windowSpaces"] = "unknown"
            }
        } else {
            result["windowSpaces"] = "unknown"
        }
        return result
    }

    private func recordDiagnosticSpace(reason: String, before: [String: Any], windowNumber: Int) {
        guard NotchWindowDiagnostic.shared.isEnabled else { return }
        let after = diagnosticSpaceSnapshot(windowNumber: windowNumber > 0 ? windowNumber : nil)
        guard String(describing: before) != String(describing: after) else { return }
        NotchWindowDiagnostic.shared.recordSpace(
            reason: reason,
            phase: String(describing: model.lockIndicator.phase),
            sessionLocked: model.isSessionLocked,
            windowNumber: windowNumber,
            before: before,
            after: after)
    }

    private func refreshInformation() {
        guard started else { return }
        let preferences = model.settings.lockPreferences
        let eligible = lockDisplayFrame != nil && model.isSessionLocked && model.lockIndicator.phase == .locked
            && preferences.enabled
        // The device module's own switch is the only source. When it is off the
        // cached device list is not consulted at all, so the lock card cannot
        // keep showing a stale AirPods entry.
        let next = (eligible && model.settings.bluetoothEnabled)
            ? model.displayDevices.first(where: { $0.isAirPods }) : nil
        if next != informationAirPods { informationAirPods = next }
        let wanted = eligible && !sleeping && next != nil
        let identity = next.map { $0.id + "\u{0}" + $0.name + "\u{0}" + $0.modelUID + "\u{0}" + ($0.battery.map(String.init) ?? "") }
        let changed = identity != lastInformationIdentity
        lastInformationIdentity = identity
        guard let informationPanel else { return }
        if wanted, !usePresentationSpace || lockSpace?.attachWindowNumber(informationPanel.windowNumber) == true {
            if changed || !informationPanel.isVisible { informationPanel.orderFrontRegardless() }
        } else {
            informationPanel.orderOut()
            lockSpace?.detachWindowNumber(informationPanel.windowNumber)
        }
    }

    private func applySharingType() {
        let type: NSWindow.SharingType = model.settings.hideFromScreenCapture ? .none : .readOnly
        panel?.setSharingType(type)
        informationPanel?.setSharingType(type)
    }

    private func place() {
        let target = LockDisplayPolicy.select(from: displayProvider())
        targetDisplay = target
        model.lockNotchGeometry = target.map {
            LockDisplayPolicy.geometry(for: $0, simulated: model.settings.forceSimulatedNotch)
        }
        guard let frame = lockDisplayFrame, panel != nil else {
            panel?.orderOut()
            informationPanel?.orderOut()
            releaseOverlay()
            return
        }
        informationPanel?.setFrameOrigin(NSPoint(x: frame.midX - 180,
                                                 y: frame.maxY - frame.height * 0.265 - 94))
        // Fixed top edge from the shared layout model: the host window keeps its
        // size, so the card's top and all existing content stay put while the
        // optional volume/lyrics blocks extend it downwards.
        //
        // The external/clamshell reserve must be decided here, from the real
        // selected target: an unknown target reserves too (safer than silently
        // using the built-in anchor on a screen we could not identify).
        let layout = LockCardLayout(screenMinY: frame.minY,
                                    screenHeight: frame.height,
                                    verticalOffset: model.settings.lockPreferences.offset,
                                    reserveFullExpansion: !(target?.isBuiltIn ?? false))
        panel.setFrameOrigin(NSPoint(x: frame.midX - 192.5,
                                     y: CGFloat(layout.panelOriginY)))
    }

    private var lockDisplayFrame: CGRect? {
        if let overlayFrameProvider { return overlayFrameProvider() }
        return targetDisplay?.frame
    }

    private func applyVisibility(epoch: UInt64) {
        guard isCurrent(epoch) else { return }
        let next = state.visible
        if model.lockMusicCardVisible != next { model.lockMusicCardVisible = next }
        guard next != visible else {
            if next, !panel.isVisible { present() }
            return
        }
        hideTask?.cancel()
        hideTask = nil
        if next {
            showsVolume = false
            appearanceTask?.cancel()
            appeared = false
            present()
            visible = true
            appearanceTask = scheduler.schedule(after: 0.032) { [weak self] in
                guard let self, self.isCurrent(epoch), self.state.visible, self.model.isSessionLocked else { return }
                self.appeared = true
            }
        } else {
            appearanceTask?.cancel()
            appearanceTask = nil
            appeared = false
            visible = false
            hideTask = scheduler.schedule(after: 0.85) { [weak self] in
                guard let self, self.isCurrent(epoch), !self.visible else { return }
                self.panel.orderOut()
                self.lockSpace?.detachWindowNumber(self.panel.windowNumber)
                self.showsVolume = false
                self.deactivateGlassSurface()
            }
        }
    }

    private func present() {
        guard state.visible, model.isSessionLocked, !sleeping, lockDisplayFrame != nil else { return }
        guard !usePresentationSpace || lockSpace?.attachWindowNumber(panel.windowNumber) == true else {
            panel.orderOut()
            return
        }
        panel.orderFrontRegardless()
        // In this implementation the material looked refractive only while the
        // surface was key; that is an observation of this app, not a proven
        // system rule, and the real lock remains to be verified on device. The
        // card therefore takes the regular activation policy while it is up and
        // gives it back through the shared activation lifetime when it leaves.
        activateGlassSurface()
    }

    private func activateGlassSurface() {
        guard usePresentationSpace, !glassActivated, NSApp != nil else { return }
        glassActivated = true
        activationOwner.acquire()
        panel?.makeKey()
    }

    private func deactivateGlassSurface() {
        guard glassActivated else { return }
        glassActivated = false
        activationOwner.release()
    }

    private func cancelHideAndAppearance() {
        hideTask?.cancel(); hideTask = nil
        appearanceTask?.cancel(); appearanceTask = nil
    }

    func stop() {
        guard started else { return }
        started = false
        overlayFailureAttempt = nil
        overlayFailureFrameKey = nil
        sessionEpoch &+= 1
        eventSource.onLocked = nil
        eventSource.onSleep = nil
        eventSource.onWake = nil
        eventSource.onScreensChanged = nil
        eventSource.stop()
        deadlineTask?.cancel(); deadlineTask = nil
        hideTask?.cancel(); hideTask = nil
        appearanceTask?.cancel(); appearanceTask = nil
        unlockTask?.cancel(); unlockTask = nil
        neutralTask?.cancel(); neutralTask = nil
        overlayCheckTask?.cancel(); overlayCheckTask = nil
        notchCheckTask?.cancel(); notchCheckTask = nil
        subscriptions.removeAll()
        state.hide()
        sleeping = false
        lastLocked = nil
        lastInformationIdentity = nil
        informationAirPods = nil
        sound.stop()
        informationPanel?.orderOut()
        if let informationPanel {
            lockSpace?.detachWindowNumber(informationPanel.windowNumber)
            informationPanel.clearRootView()
            informationPanel.close()
        }
        releaseOverlay()
        detachNotchIfNeeded()
        panel?.orderOut()
        deactivateGlassSurface()
        if let panel {
            lockSpace?.detachWindowNumber(panel.windowNumber)
            panel.clearRootView()
            panel.close()
        }
        lockSpace = nil
        visible = false
        appeared = false
        showsVolume = false
        model.lockMusicCardVisible = false
        model.isSessionLocked = false
        var indicator = model.lockIndicator
        indicator.forceHidden()
        model.lockIndicator = indicator
        informationPanel = nil
        panel = nil
    }

    isolated deinit {
        deadlineTask?.cancel(); hideTask?.cancel(); appearanceTask?.cancel()
        unlockTask?.cancel(); neutralTask?.cancel()
        overlayCheckTask?.cancel(); notchCheckTask?.cancel()
        eventSource.stop()
    }
}
