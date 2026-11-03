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

/// System-only media pipeline. The archived player-specific AppleScript / QQ
/// branches are intentionally not migrated: this round has one source, the
/// current macOS Now Playing session, read through the bundled adapter.
@MainActor
final class MediaController {
    unowned let model: AppModel
    private var timer: Timer?
    private let system: any SystemMediaProviding
    private var systemSnapshot: SystemMediaSnapshot?
    private var timeline = SystemMediaTimeline()
    private var systemStarted = false
    private var isActive = false
    private var retryNotBefore: TimeInterval = 0
    private let retryInterval: TimeInterval
    private var subscriptions = Set<AnyCancellable>()
    private var tick = 0
    private var commandGeneration: UInt64 = 0

    init(_ model: AppModel,
         system: any SystemMediaProviding = SystemMediaSource(),
         retryInterval: TimeInterval = 1.0) {
        self.model = model
        self.system = system
        self.retryInterval = max(0, retryInterval)
    }

    func start() {
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
        model.settings.$nowPlayingEnabled.removeDuplicates().dropFirst().receive(on: RunLoop.main).sink { [weak self] _ in
            self?.invalidate(); self?.clearMedia(); self?.refresh()
        }.store(in: &subscriptions)
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.model.previewMode else { return }
                if self.systemSnapshot != nil {
                    let now = Date()
                    self.model.setElapsed(self.timeline.position(at: now.timeIntervalSince1970),
                                          sampledAt: now)
                }
                self.tick += 1
                if self.tick % 4 == 0 { self.refresh() }
            }
        }
    }

    func stop() {
        isActive = false
        commandGeneration &+= 1
        timer?.invalidate(); timer = nil
        invalidate()
    }

    func invalidate() {
        commandGeneration &+= 1
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
        timeline.update(snapshot, at: Date().timeIntervalSince1970)
        systemSnapshot = snapshot
        if changed && snapshot.artwork == nil { model.artwork = nil }
        if let data = snapshot.artwork, changed || model.artwork == nil || data != previousSystemArtwork {
            model.artwork = NSImage(data: data)
        }
        previousSystemArtwork = snapshot.artwork
        model.title = snapshot.title; model.artist = snapshot.artist; model.album = snapshot.album
        model.playing = snapshot.playing; model.playbackRate = snapshot.rate
        model.duration = snapshot.duration
        let now = Date()
        model.setElapsed(timeline.position(at: now.timeIntervalSince1970), sampledAt: now)
        model.source = "系统"; model.mediaBundleIdentifier = snapshot.bundleIdentifier
        model.mediaRevisionIdentity = snapshot.revisionIdentity
        model.mediaCanSeek = snapshot.duration > 0
        model.mediaCanSkip = !snapshot.prohibitsSkip
        model.mediaCanControl = true
        model.mediaError = nil
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
        system.perform(["seek", String(micros)], expected: snapshot, requireSameTrack: true) { [weak self] ok in
            if !ok { self?.model.mediaError = "当前歌曲已改变或未接受进度调整，请重试。" }
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
