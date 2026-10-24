import AppKit
import SwiftUI
import ReferenceCore

/// All expansion entry points share one generation and cancellable task group.
/// Blur/luminance lifecycle is retained here; the original backdrop renderer is
/// still pending and is not approximated with a generic material.
@MainActor
final class PresentationController {
    unowned let model: AppModel
    private var idleTask: Task<Void, Never>?
    private var idleDeadline: Date?
    private var peekTask: Task<Void, Never>?
    private var tasks: [Task<Void, Never>] = []
    private var collapseCompletions: [() -> Void] = []
    init(_ model: AppModel) { self.model = model }

    func trackChanged(identity: String?) {
        let eligible = model.settings.nowPlayingEnabled && model.settings.quickPeekEnabled && model.settings.peekWhenSongChanges
            && !model.sourceActivityHidden && !model.expanded && !model.screenHidden
            && (model.notchGeometry.hasPhysicalNotch || model.settings.forceSimulatedNotch || model.allowsMultiDisplayDynamic)
        var state = model.songPeek
        let reveal = state.observe(identity: identity, eligible: eligible)
        // With lyrics enabled the peek and lyric share one row. Swap without
        // SwiftUI's implicit transition so the two texts cannot overlap.
        if model.settings.musicPreferences.showLyrics {
            model.songPeek = state
        } else {
            withAnimation(peekAnimation) { model.songPeek = state }
        }
        guard reveal else { return }
        peekTask?.cancel()
        let token = state.generation, delay = model.settings.peekDuration
        peekTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) } catch { return }
            guard let self, !Task.isCancelled else { return }
            if self.model.settings.musicPreferences.showLyrics {
                self.model.songPeek.expire(generation: token)
            } else {
                withAnimation(self.peekAnimation) { self.model.songPeek.expire(generation: token) }
            }
        }
    }

    /// 1.7.9: 100383384 → 100392c34 (idleDuration) → 100392da0.
    /// Changing the input invalidates the old task before starting another one.
    func mediaStateChanged() {
        let identity = model.hasTrack ? [model.mediaBundleIdentifier,model.title,model.artist,model.album].joined(separator:"\u{0}") : nil
        let input = MediaIdleState.Input(identity:identity,playing:model.playing,
            enabled:model.settings.nowPlayingEnabled,pointerInside:model.isPointerInside,
            outputNotification:false,duration:model.settings.musicPreferences.idleDuration)
        var state = model.mediaIdle
        guard state.update(input) else {
            // A screen/geometry reset may have canceled the task without
            // changing the shared media input. Re-arm only when no deadline is
            // running; identical metadata polls never move an active deadline.
            if state.pending, idleTask == nil {
                scheduleIdle(after: remainingIdleDuration(fallback: input.duration),
                             token: state.generation)
            }
            return
        }
        idleTask?.cancel(); idleTask = nil; idleDeadline = nil
        withAnimation(idleAnimation) { model.mediaIdle = state }
        guard state.pending else { return }
        scheduleIdle(after: input.duration, token: state.generation)
    }

    private func remainingIdleDuration(fallback: Double) -> Double {
        guard let idleDeadline else { return max(0, fallback) }
        return max(0, idleDeadline.timeIntervalSinceNow)
    }

    private func scheduleIdle(after duration: Double, token: UInt64) {
        idleTask?.cancel()
        idleDeadline = Date().addingTimeInterval(max(0, duration))
        idleTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds:UInt64(max(0, duration) * 1_000_000_000)) } catch { return }
            guard let self, !Task.isCancelled else { return }
            // Reconcile again: an application event can precede its queued sink.
            self.mediaStateChanged()
            var current = self.model.mediaIdle
            guard current.expire(generation: token) else { return }
            self.idleDeadline = nil
            self.cancelPeek()
            withAnimation(self.idleAnimation) { self.model.mediaIdle = current }
        }
    }

    private var idleAnimation: Animation {
        reducedMotion ? .easeOut(duration:0.12) : .spring(duration:0.35,bounce:-0.2)
    }

    func musicVisibilityChanged() {
        mediaStateChanged()
        if model.sourceActivityHidden || !model.settings.nowPlayingEnabled {
            cancelPeek()
        } else if !model.settings.quickPeekEnabled || !model.settings.peekWhenSongChanges {
            cancelPeek()
        }
    }

    private var peekAnimation: Animation {
        reducedMotion ? .easeOut(duration: 0.12) : .spring(duration: 0.45, bounce: 0.1)
    }

    func cancelPeek(reset: Bool = false) {
        peekTask?.cancel(); peekTask = nil
        if model.settings.musicPreferences.showLyrics {
            if reset { model.songPeek.reset() } else { model.songPeek.cancel() }
        } else {
            withAnimation(peekAnimation) {
                if reset { model.songPeek.reset() } else { model.songPeek.cancel() }
            }
        }
    }

    func pointerEntered(_ inside: Bool) {
        guard model.isPointerInside != inside else { return }
        let animation: Animation = reducedMotion ? .easeOut(duration:0.12)
            : .spring(duration:NotchHoverMetrics.duration,bounce:NotchHoverMetrics.bounce(entering:inside))
        withAnimation(animation) { model.isPointerInside = inside }
        mediaStateChanged()
    }

    func expand() {
        cancelPeek()
        guard model.canExpandActivity else { return }
        setExpanded(true)
    }

    func collapse(completion: (() -> Void)? = nil) {
        model.pinned = false
        if !model.expanded { model.showsOutputVolume = false }
        if let completion {
            if model.presentation.phase == .collapsed { completion(); return }
            collapseCompletions.append(completion)
        }
        setExpanded(false)
    }

    /// Reset the active screen's interaction when it is removed/hidden or the
    /// display selection changes. Cancels scheduled callbacks for the old panel.
    func resetForScreenChange() {
        // Display/geometry changes cancel presentation callbacks, but must not
        // permanently strand the shared paused-media grace period. Preserve the
        // remaining deadline across the reset; a later identical metadata poll
        // sees the re-armed task and does not postpone it.
        let remaining = remainingIdleDuration(fallback: model.mediaIdle.input?.duration ?? 0)
        idleTask?.cancel(); idleTask = nil; idleDeadline = nil
        peekTask?.cancel(); peekTask = nil
        tasks.forEach { $0.cancel() }; tasks.removeAll()
        collapseCompletions.removeAll()
        model.pinned = false
        model.showsOutputVolume = false
        model.presentation = NotchTransitionState()
        model.songPeek.reset()
        model.isPointerInside = false
        if model.mediaIdle.pending {
            scheduleIdle(after: remaining, token: model.mediaIdle.generation)
        } else if model.mediaIdle.input?.pointerInside == true {
            // The old screen's pointer ownership is gone. Re-evaluate the real
            // media input so a hovered-paused activity starts its normal grace
            // period instead of staying visible with pending=false forever.
            mediaStateChanged()
        }
    }

    private var reducedMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    private func schedule(after seconds: Double, _ action: @escaping @MainActor (PresentationController) -> Void) {
        tasks.append(Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }
            catch { return }
            guard !Task.isCancelled, let self else { return }
            action(self)
        })
    }

    private func withoutAnimation(_ action: () -> Void) {
        var transaction = Transaction(); transaction.disablesAnimations = true
        withTransaction(transaction, action)
    }

    private func setExpanded(_ target: Bool) {
        guard target != model.expanded else { return }
        tasks.forEach { $0.cancel() }; tasks.removeAll()
        if target { collapseCompletions.removeAll() }
        let animation: Animation = reducedMotion ? .easeOut(duration: 0.12) : target
            ? .spring(duration: ExpansionTiming.duration, bounce: ExpansionTiming.bounce(hasNotification: false))
            : .spring(response: ExpansionTiming.collapseResponse(secondFlag: false), dampingFraction: 1)
        if target {
            withAnimation(animation) { _ = model.presentation.begin(expanding: true) }
            let token = model.presentation.generation
            schedule(after: reducedMotion ? 0 : ExpansionTiming.cornerDelay) { owner in
                withAnimation(animation) { owner.model.presentation.revealCorners(generation: token) }
            }
            withAnimation(.spring(response: ExpansionTiming.duration, dampingFraction: 1)) {
                model.presentation.setBlur(true, generation: token)
            }
            schedule(after: reducedMotion ? 0 : ExpansionTiming.backdropLumaDelay) { owner in
                owner.withoutAnimation { owner.model.presentation.setBackdrop(true, generation: token) }
            }
            schedule(after: reducedMotion ? 0.12 : ExpansionTiming.completionDelay) { owner in
                owner.withoutAnimation { owner.model.presentation.complete(generation: token) }
            }
        } else {
            // SwiftUI's logical completion determines cleanup, not a guessed timer.
            let token = model.presentation.generation &+ 1
            withAnimation(animation, completionCriteria: .logicallyComplete) {
                // 1.7.9 0x10022cd00 calls hasOutput(false) when collapse begins.
                // Reset now, not in completion: a rapid reopen must not inherit it.
                model.showsOutputVolume = false
                model.presentation.begin(expanding: false)
                model.presentation.setBlur(false, generation: token)
            } completion: { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.model.presentation.generation == token else { return }
                    self.withoutAnimation { self.model.presentation.complete(generation: token) }
                    let callbacks = self.collapseCompletions
                    self.collapseCompletions.removeAll()
                    callbacks.forEach { $0() }
                }
            }
            schedule(after: reducedMotion ? 0.12 : ExpansionTiming.collapseResponse(secondFlag: false)) { owner in
                owner.withoutAnimation { owner.model.presentation.setBackdrop(false, generation: token) }
            }
        }
    }

    deinit { idleTask?.cancel(); peekTask?.cancel(); tasks.forEach { $0.cancel() } }
}
