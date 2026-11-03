import Combine
import Foundation
import ReferenceCore
import SwiftUI

/// Process-local desktop preview of the lock-notch animation. It mutates only
/// AppModel.preview state and uses the existing PresentationController geometry
/// completion; it never creates a Space/window, plays a sound, changes the real
/// session, or shows the lock-screen music/device cards.
@MainActor
final class LockPreviewController {
    unowned let model: AppModel
    private let scheduler: any LockScheduling
    private let geometryAnimator: any LockGeometryAnimating
    private let collapsePresentation: (@escaping () -> Void) -> Void
    private var subscriptions = Set<AnyCancellable>()
    private var active = false
    private var generation: UInt64 = 0
    private var unlockTask: (any LockScheduledTask)?
    private var restoringTask: (any LockScheduledTask)?
    private var started = false

    init(_ model: AppModel,
         scheduler: any LockScheduling = LockAsyncScheduler(),
         geometryAnimator: any LockGeometryAnimating = LockSwiftUIGeometryAnimator(),
         collapsePresentation: ((@escaping () -> Void) -> Void)? = nil) {
        self.model = model
        self.scheduler = scheduler
        self.geometryAnimator = geometryAnimator
        self.collapsePresentation = collapsePresentation ?? { completion in
            model.presenter.collapse(completion: completion)
        }
    }

    func start() {
        guard !started else { return }
        started = true
        model.$previewLockScreenEnabled.removeDuplicates().dropFirst().sink { [weak self] enabled in
            Task { @MainActor [weak self] in self?.request(enabled) }
        }.store(in: &subscriptions)
        model.$isSessionLocked.removeDuplicates().sink { [weak self] locked in
            guard locked else { return }
            Task { @MainActor [weak self] in self?.cancelForRealLock() }
        }.store(in: &subscriptions)
        model.settings.$lockPreferences.map(\.enabled).removeDuplicates().sink { [weak self] enabled in
            guard !enabled else { return }
            Task { @MainActor [weak self] in self?.cancelForMasterOff() }
        }.store(in: &subscriptions)
    }

    func stop() {
        guard started else { return }
        started = false
        subscriptions.removeAll()
        cancel()
    }

    private func isCurrent(_ token: UInt64) -> Bool {
        started && active && token == generation
    }

    private func request(_ enabled: Bool) {
        guard enabled else {
            beginUnlock()
            return
        }
        guard started, !model.isSessionLocked, model.settings.lockPreferences.enabled else {
            model.previewLockScreenEnabled = false
            return
        }
        beginLock()
    }

    private func beginLock() {
        if active {
            let phase = model.previewLockIndicator.phase
            if phase == .unlocking || phase == .restoring {
                cancelScheduled()
                var indicator = model.previewLockIndicator
                indicator.forceLocked()
                model.previewLockIndicator = indicator
            }
            return
        }
        generation &+= 1
        let token = generation
        active = true
        model.previewLockPresentationActive = true
        var indicator = LockIndicatorState()
        _ = indicator.beginLocking()
        model.previewLockIndicator = indicator
        // Keep the normal compact music during this bounded collapse, exactly
        // as the real lock sequence does.
        collapsePresentation { [weak self] in
            guard let self, self.isCurrent(token) else { return }
            self.beginNeutralizing(token: token)
        }
    }

    private func beginNeutralizing(token: UInt64) {
        guard isCurrent(token) else { return }
        var indicator = model.previewLockIndicator
        guard indicator.phase == .locking else { return }
        _ = indicator.beginNeutralizing()
        let neutralToken = indicator.generation
        geometryAnimator.animate({ [weak self] in
            guard let self, self.isCurrent(token) else { return }
            self.model.previewLockIndicator = indicator
        }, completion: { [weak self] in
            guard let self, self.isCurrent(token) else { return }
            var locked = self.model.previewLockIndicator
            guard locked.completeLocking(token: neutralToken) else { return }
            withAnimation(self.activityAnimation) {
                self.model.previewLockIndicator = locked
            }
        })
    }

    private func beginUnlock() {
        guard active else {
            model.previewLockPresentationActive = false
            return
        }
        let token = generation
        switch model.previewLockIndicator.phase {
        case .locking, .neutralizing:
            cancelScheduled()
            active = false
            model.previewLockPresentationActive = false
            var hidden = model.previewLockIndicator
            hidden.forceHidden()
            model.previewLockIndicator = hidden
        case .locked:
            cancelScheduled()
            var indicator = model.previewLockIndicator
            let unlockToken = indicator.beginUnlocking()
            model.previewLockIndicator = indicator
            unlockTask = scheduler.schedule(after: 0.8) { [weak self] in
                guard let self, self.isCurrent(token) else { return }
                var restoring = self.model.previewLockIndicator
                guard restoring.finishUnlockToRestoring(token: unlockToken) else { return }
                let restoreToken = restoring.generation
                self.geometryAnimator.animate({ [weak self] in
                    guard let self, self.isCurrent(token) else { return }
                    self.model.previewLockIndicator = restoring
                }, completion: { [weak self] in
                    guard let self, self.isCurrent(token) else { return }
                    var hidden = self.model.previewLockIndicator
                    guard hidden.finishRestoring(token: restoreToken) else { return }
                    // Only after the neutral geometry animation completes may
                    // the normal music activity expand. Use the existing
                    // compact-activity animation, not an immediate content swap.
                    withAnimation(self.activityAnimation) {
                        self.active = false
                        self.model.previewLockIndicator = hidden
                        self.model.previewLockPresentationActive = false
                    }
                })
            }
        case .unlocking:
            // Already showing the open glyph; let the current completion finish.
            break
        case .restoring:
            break
        case .hidden:
            active = false
            model.previewLockPresentationActive = false
        }
    }

    private func cancelForRealLock() {
        cancel()
        model.previewLockScreenEnabled = false
    }

    private func cancelForMasterOff() {
        cancel()
        model.previewLockScreenEnabled = false
    }

    private func cancelScheduled() {
        unlockTask?.cancel(); unlockTask = nil
        restoringTask?.cancel(); restoringTask = nil
    }

    private func cancel() {
        cancelScheduled()
        generation &+= 1
        active = false
        model.previewLockScreenEnabled = false
        model.previewLockPresentationActive = false
        var indicator = model.previewLockIndicator
        indicator.forceHidden()
        model.previewLockIndicator = indicator
        // Do not touch model.isSessionLocked or the real lock indicator.
    }

    private var activityAnimation: Animation {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            ? .easeOut(duration: 0.12)
            : .spring(duration: 0.35, bounce: -0.2)
    }

    isolated deinit {
        unlockTask?.cancel(); restoringTask?.cancel()
    }
}
