import AppKit
import Combine
import ReferenceCore

/// Narrow test seam for the real SystemMediaSource. Production always injects
/// the bundled source; tests can observe start/stop and simulate stream errors.
@MainActor
protocol SystemMediaProviding: AnyObject {
    var onSnapshot: (@MainActor (SystemMediaSnapshot?) -> Void)? { get set }
    var onError: (@MainActor (String) -> Void)? { get set }
    func start()
    func stop()
    func perform(_ arguments: [String], expected: SystemMediaSnapshot, requireSameTrack: Bool,
                 completion: @escaping @MainActor (Bool) -> Void)
}

extension SystemMediaSource: SystemMediaProviding {}

/// One-shot timer seam so the 0.25s playback anchor can be observed without a
/// real run loop in tests.
@MainActor
protocol MediaTickToken: AnyObject {
    var isRunning: Bool { get }
    func cancel()
}

@MainActor
protocol MediaTickScheduling: AnyObject {
    func schedule(_ action: @escaping @MainActor () -> Void) -> any MediaTickToken
}

@MainActor
final class TimerMediaTickScheduler: MediaTickScheduling {
    static let interval: TimeInterval = 0.25

    private final class Token: MediaTickToken {
        private let timer: Timer
        init(_ timer: Timer) { self.timer = timer }
        var isRunning: Bool { timer.isValid }
        func cancel() { timer.invalidate() }
    }

    func schedule(_ action: @escaping @MainActor () -> Void) -> any MediaTickToken {
        let timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { _ in
            MainActor.assumeIsolated { action() }
        }
        return Token(timer)
    }
}

/// System-only media pipeline. The archived player-specific AppleScript / QQ
/// branches are intentionally not migrated: this round has one source, the
/// current macOS Now Playing session, read through the bundled adapter.
@MainActor
final class MediaController {
    unowned let model: AppModel
    private var tickToken: (any MediaTickToken)?
    private let system: any SystemMediaProviding
    private var systemSnapshot: SystemMediaSnapshot?
    private var timeline = SystemMediaTimeline()
    private var systemStarted = false
    private var isActive = false
    private var retryNotBefore: TimeInterval = 0
    private let retryInterval: TimeInterval
    private let tickScheduler: any MediaTickScheduling
    private var subscriptions = Set<AnyCancellable>()
    private var tick = 0
    private var commandGeneration: UInt64 = 0
    /// Optimistic seek anchor. The thumb must stay where the user dropped it;
    /// the adapter's pre-seek position arriving right after must not rewind it
    /// while the seek round-trip is still in flight.
    private struct PendingSeek {
        var target: Double
        var startedAt: Date
        var deadline: TimeInterval
        var identity: String
    }
    private var pendingSeek: PendingSeek?
    private var seekGeneration: UInt64 = 0
    private let seekConfirmationWindow: TimeInterval
    /// A confirmed seek lands within this distance of the requested position.
    static let seekConfirmationTolerance: Double = 1.5

    init(_ model: AppModel,
         system: any SystemMediaProviding = SystemMediaSource(),
         retryInterval: TimeInterval = 1.0,
         tickScheduler: any MediaTickScheduling = TimerMediaTickScheduler(),
         seekConfirmationWindow: TimeInterval = 1.5) {
        self.model = model
        self.system = system
        self.retryInterval = max(0, retryInterval)
        self.tickScheduler = tickScheduler
        self.seekConfirmationWindow = max(0.1, seekConfirmationWindow)
    }

    func start() {
        guard !isActive else { return }      // repeated start must not stack timers
        isActive = true
        commandGeneration &+= 1
        system.onSnapshot = { [weak self] snapshot in self?.applySystem(snapshot) }
        system.onError = { [weak self] error in
            guard let self else { return }
            // The source has already dropped its Process. Allow the existing
            // periodic refresh to reconnect, but rate-limit failed attempts.
            self.systemStarted = false
            self.retryNotBefore = ProcessInfo.processInfo.systemUptime + self.retryInterval
            self.clearMedia(error: error)
        }
        model.settings.$nowPlayingEnabled.removeDuplicates().dropFirst().receive(on: RunLoop.main).sink { [weak self] enabled in
            MainActor.assumeIsolated { self?.applyNowPlayingEnabled(enabled) }
        }.store(in: &subscriptions)
        // Expanding the player or revealing the lock card must show a fresh
        // anchor immediately instead of waiting for the next collapsed 1Hz
        // sample; the same holds when the surface goes away (the anchor is
        // republished so the low-frequency cadence starts from a known value).
        Publishers.Merge(
            model.$presentation.map(\.retainsExpandedContent).removeDuplicates().eraseToAnyPublisher(),
            model.$lockMusicCardVisible.removeDuplicates().eraseToAnyPublisher()
        ).sink { [weak self] _ in
            MainActor.assumeIsolated { self?.publishProgressNow() }
        }.store(in: &subscriptions)
        applyNowPlayingEnabled(model.settings.nowPlayingEnabled)
    }

    /// The playback anchor only exists while the module is enabled: turning the
    /// music switch off cancels the tick immediately, turning it back on restores
    /// exactly one.
    private func applyNowPlayingEnabled(_ enabled: Bool) {
        guard isActive else { return }
        if enabled {
            startTickIfNeeded()
            refresh()
        } else {
            stopTick()
            invalidate()
            clearMedia()
        }
    }

    private func startTickIfNeeded() {
        guard isActive, tickToken == nil else { return }
        tickToken = tickScheduler.schedule { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.model.previewMode else { return }
                if self.systemSnapshot != nil {
                    // Paused playback cannot advance the timeline (`rate` is
                    // stored in the snapshot), so re-publishing an identical
                    // value four times a second only invalidates every view
                    // that observes the model.
                    if !self.model.playing {
                        self.publishProgressIfChanged()
                    } else if self.progressSurfaceVisible || self.tick % 4 == 0 {
                        // The 4Hz sample is only rendered while a progress bar
                        // is on screen (expanded player or lock card). The
                        // collapsed notch shows no progress and its lyrics
                        // interpolate locally from this anchor, so a 1Hz anchor
                        // is enough there. Expanding the player publishes
                        // immediately through the subscription below.
                        self.publishProgressNow()
                    }
                }
                self.tick += 1
                if self.tick % 4 == 0 { self.refresh() }
            }
        }
    }

    /// Anything that actually draws `MediaProgressView`: the expanded player
    /// (still mounted while expanding/collapsing) or the lock music card. The
    /// compact strip has no elapsed-dependent content.
    private var progressSurfaceVisible: Bool {
        model.presentation.retainsExpandedContent || model.lockMusicCardVisible
    }

    private func publishProgressNow() {
        guard systemSnapshot != nil, !model.previewMode else { return }
        let now = Date()
        expirePendingSeekIfNeeded(at: now)
        model.setElapsed(currentPosition(at: now), sampledAt: now)
    }

    private func publishProgressIfChanged() {
        guard systemSnapshot != nil, !model.previewMode else { return }
        let now = Date()
        expirePendingSeekIfNeeded(at: now)
        let position = currentPosition(at: now)
        if position != model.elapsed {
            model.setElapsed(position, sampledAt: now)
        }
    }

    /// Position shown to the user: the optimistic seek target while a seek is
    /// in flight, otherwise the source timeline.
    private func currentPosition(at date: Date) -> Double {
        if let pending = pendingSeek {
            let rate = model.playing ? model.playbackRate : 0
            let delta = max(0, date.timeIntervalSince(pending.startedAt))
            return MediaProgressState.clamp(pending.target + delta * rate, duration: model.duration)
        }
        return timeline.position(at: date.timeIntervalSince1970)
    }

    private func expirePendingSeekIfNeeded(at date: Date) {
        guard let pending = pendingSeek,
              ProcessInfo.processInfo.systemUptime >= pending.deadline else { return }
        // No confirmation inside the window: treat the source as authoritative
        // again instead of leaving the thumb on an unconfirmed position.
        pendingSeek = nil
        seekGeneration &+= 1
        republishAuthoritativePosition(at: date)
    }

    private func republishAuthoritativePosition(at date: Date) {
        guard let snapshot = systemSnapshot else { return }
        timeline.update(snapshot, at: date.timeIntervalSince1970)
        model.setElapsed(timeline.position(at: date.timeIntervalSince1970), sampledAt: date)
    }

    private func stopTick() {
        tickToken?.cancel()
        tickToken = nil
    }

    func stop() {
        guard isActive else { return }   // repeated stop must not touch another cycle
        isActive = false
        commandGeneration &+= 1
        stopTick()
        invalidate()
        // A restarted controller registers a fresh preference subscription; the
        // old one must be cancelled here or every cycle would process the same
        // change again (one disable → two source stops, growing per restart).
        subscriptions.removeAll()
        system.onSnapshot = nil
        system.onError = nil
    }

    func invalidate() {
        commandGeneration &+= 1
        seekGeneration &+= 1
        pendingSeek = nil
        model.presenter.cancelPeek(reset: true)
        system.stop()
        systemStarted = false
        retryNotBefore = 0
        systemSnapshot = nil
        previousSystemArtwork = nil
    }

    func refresh() {
        guard isActive, !model.previewMode, model.settings.nowPlayingEnabled else { return }
        // "System" always means the real macOS Now Playing session. There is no
        // player-selection branch in this candidate.
        guard !systemStarted else { return }
        guard ProcessInfo.processInfo.systemUptime >= retryNotBefore else { return }
        systemStarted = true
        system.start()
    }

    private func clearMedia(error: String? = nil) {
        commandGeneration &+= 1
        seekGeneration &+= 1
        pendingSeek = nil
        model.presenter.cancelPeek(reset: true)
        systemSnapshot = nil
        timeline = SystemMediaTimeline()
        model.title = "暂无播放"; model.artist = ""; model.album = ""; model.artwork = nil
        model.duration = 0; model.setElapsed(0, sampledAt: Date()); model.playing = false; model.playbackRate = 1
        model.source = "系统"; model.mediaBundleIdentifier = ""
        model.mediaCanSeek = false; model.mediaCanSkip = false; model.mediaCanControl = false
        model.mediaRevisionIdentity = ""
        model.mediaError = error
        previousSystemArtwork = nil
        model.lyricsController?.mediaMetadataChanged()
        model.presenter.mediaStateChanged()
    }

    private func applySystem(_ snapshot: SystemMediaSnapshot?) {
        guard !model.previewMode, systemStarted else { return }
        guard let snapshot else { clearMedia(); return }
        let old = systemSnapshot
        let changed = snapshot.identity != old?.identity
        let authoritativeStateChanged = changed || snapshot.playing != old?.playing
            || snapshot.rate != old?.rate || snapshot.duration != old?.duration
        if authoritativeStateChanged {
            // Any new source-authoritative state invalidates a previous
            // pending command completion, even on the same track.
            commandGeneration &+= 1
        }
        let now = Date()
        expirePendingSeekIfNeeded(at: now)
        // A snapshot that still carries the pre-seek position must not rewind
        // the thumb; only the confirmed position (or a new track) replaces it.
        var stalePreSeekSnapshot = false
        if let pending = pendingSeek {
            let sameTrack = snapshot.identity == pending.identity
            let confirmed = sameTrack
                && abs(snapshot.elapsed - pending.target) <= Self.seekConfirmationTolerance
            if sameTrack && !confirmed {
                stalePreSeekSnapshot = true
            } else {
                pendingSeek = nil
            }
        }
        if !stalePreSeekSnapshot {
            timeline.update(snapshot, at: now.timeIntervalSince1970)
        }
        systemSnapshot = snapshot
        if changed && snapshot.artwork == nil { model.artwork = nil }
        if let data = snapshot.artwork, changed || model.artwork == nil || data != previousSystemArtwork {
            model.artwork = ArtworkImage.prepare(data)
        }
        previousSystemArtwork = snapshot.artwork
        // A full source event often only updates the playback anchor. Avoid
        // republishing unchanged metadata to every view/window coordinator.
        // Compare the live model (not the previous snapshot), so authoritative
        // state still corrects optimistic play/pause feedback immediately.
        if model.title != snapshot.title { model.title = snapshot.title }
        if model.artist != snapshot.artist { model.artist = snapshot.artist }
        if model.album != snapshot.album { model.album = snapshot.album }
        if model.playing != snapshot.playing { model.playing = snapshot.playing }
        if model.playbackRate != snapshot.rate { model.playbackRate = snapshot.rate }
        if model.duration != snapshot.duration { model.duration = snapshot.duration }
        if !stalePreSeekSnapshot {
            model.setElapsed(timeline.position(at: now.timeIntervalSince1970), sampledAt: now)
        }
        if model.source != "系统" { model.source = "系统" }
        if model.mediaBundleIdentifier != snapshot.bundleIdentifier { model.mediaBundleIdentifier = snapshot.bundleIdentifier }
        if model.mediaRevisionIdentity != snapshot.revisionIdentity { model.mediaRevisionIdentity = snapshot.revisionIdentity }
        if model.mediaCanSeek != (snapshot.duration > 0) { model.mediaCanSeek = snapshot.duration > 0 }
        if model.mediaCanSkip != !snapshot.prohibitsSkip { model.mediaCanSkip = !snapshot.prohibitsSkip }
        if !model.mediaCanControl { model.mediaCanControl = true }
        if model.mediaError != nil { model.mediaError = nil }
        model.lyricsController?.mediaMetadataChanged()
        updateSongPeek()
    }

    private var previousSystemArtwork: Data?

    private func updateSongPeek() {
        model.presenter.mediaStateChanged()
        let identity = model.hasTrack ? [model.source, model.mediaBundleIdentifier, model.title, model.artist, model.album].joined(separator: "\u{0}") : nil
        if let handler = model.trackChangedHandler {
            handler(identity)
        } else {
            model.presenter.trackChanged(identity: identity)
        }
    }

    func command(_ command: Int) {
        if model.previewMode {
            if command == 2 { model.playing.toggle() }
            return
        }
        guard model.hasTrack, model.mediaCanControl, [2,4,5].contains(command),
              command == 2 || model.mediaCanSkip else { return }
        guard let snapshot = systemSnapshot else { return }
        commandGeneration &+= 1
        let generation = commandGeneration
        let previousPlaying = model.playing
        // Give the button immediate, reversible feedback; the real system
        // command still runs on the bounded command queue and a failure
        // restores the actual state.
        if command == 2 { model.playing.toggle() }
        system.perform(["send", String(command)], expected: snapshot, requireSameTrack: false) { [weak self] ok in
            guard let self, generation == self.commandGeneration else { return }
            if !ok {
                if command == 2 { self.model.playing = previousPlaying }
                self.model.mediaError = "播放来源已改变或未接受控制，请重试。"
            }
        }
    }

    func seek(_ seconds: Double) {
        guard seconds.isFinite, model.previewMode || model.mediaCanSeek else { return }
        let target = MediaProgressState.clamp(seconds, duration: model.duration)
        if model.previewMode { model.elapsed = target; return }
        guard let micros = Self.seekMicros(target) else { return }
        guard let snapshot = systemSnapshot else { return }
        let now = Date()
        seekGeneration &+= 1
        let generation = seekGeneration
        // The dragged position is shown immediately, like the volume path's
        // local target; the source confirmation (or failure/timeout) is what
        // may move it afterwards.
        pendingSeek = PendingSeek(target: target, startedAt: now,
                                  deadline: ProcessInfo.processInfo.systemUptime + seekConfirmationWindow,
                                  identity: snapshot.identity)
        model.setElapsed(target, sampledAt: now)
        model.mediaError = nil
        system.perform(["seek", String(micros)], expected: snapshot, requireSameTrack: true) { [weak self] ok in
            guard let self, generation == self.seekGeneration else { return }
            guard !ok else { return }
            self.pendingSeek = nil
            self.republishAuthoritativePosition(at: Date())
            self.model.mediaError = "当前歌曲已改变或未接受进度调整，请重试。"
        }
    }

    /// Convert clamped seconds to the adapter's microsecond parameter without
    /// trapping on finite-but-unrepresentable input. Truncation matches the
    /// archived `Int64(target * 1_000_000)` for all values that fit.
    static func seekMicros(_ seconds: Double) -> Int64? {
        guard seconds.isFinite, seconds >= 0 else { return nil }
        let scaled = seconds * 1_000_000
        guard scaled.isFinite, scaled >= 0,
              scaled < 9_223_372_036_854_775_808.0 else { return nil }
        return Int64(scaled)
    }
}
