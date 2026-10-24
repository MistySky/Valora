import Combine
import Foundation
import ReferenceCore

/// Owns the lyrics request lifecycle. Network work lives in `LyricsProviding`;
/// this controller only compares metadata identities, cancels stale work and
/// publishes UI state. No timer or elapsed-tick search exists.
@MainActor
final class LyricsController {
    unowned let model: AppModel
    private let provider: any LyricsProviding
    private let budget: TimeInterval
    private var task: Task<Void, Never>?
    private var taskRunning = false
    private var generation: UInt64 = 0
    private var currentIdentity: LyricsTrackIdentity?
    private var started = false
    private var subscriptions = Set<AnyCancellable>()

    init(model: AppModel, provider: any LyricsProviding,
         budget: TimeInterval = 3) {
        self.model = model
        self.provider = provider
        self.budget = max(0, budget)
    }

    func start() {
        guard !started else { return }
        started = true
        Publishers.MergeMany(
            model.$title.map { _ in () }.eraseToAnyPublisher(),
            model.$artist.map { _ in () }.eraseToAnyPublisher(),
            model.$album.map { _ in () }.eraseToAnyPublisher(),
            model.$duration.map { _ in () }.eraseToAnyPublisher(),
            model.$mediaIdle.map { _ in () }.eraseToAnyPublisher(),
            model.$frontmostBundleIdentifier.map { _ in () }.eraseToAnyPublisher(),
            model.$mediaBundleIdentifier.map { _ in () }.eraseToAnyPublisher()
        ).sink { [weak self] _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.update() }
            }
        }.store(in: &subscriptions)
        model.settings.$musicPreferences.removeDuplicates().sink { [weak self] _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.update() }
            }
        }.store(in: &subscriptions)
        model.settings.$nowPlayingEnabled.removeDuplicates().sink { [weak self] _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.update() }
            }
        }.store(in: &subscriptions)
        model.settings.$showNotch.removeDuplicates().sink { [weak self] _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.visibilityChanged() }
            }
        }.store(in: &subscriptions)
        model.$screenHidden.removeDuplicates().sink { [weak self] _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.visibilityChanged() }
            }
        }.store(in: &subscriptions)
        update()
    }

    /// Called synchronously after the media controller has written a complete
    /// metadata snapshot, so old lyrics do not survive a track change frame.
    func mediaMetadataChanged() { update() }

    /// Isolated QA seam: reports whether this controller still owns a running
    /// request. It does not expose or retain the task itself.
    var verificationTaskIsActive: Bool { taskRunning }

    private func visibilityChanged() {
        if model.screenHidden || !model.settings.showNotch {
            cancelCurrentTask()
            generation &+= 1
            if model.lyrics.status == .loading {
                model.lyrics = LyricsDisplayState(status: .unavailable, identity: currentIdentity)
            }
            return
        }
        update()
    }

    func cancel() {
        cancelCurrentTask()
        generation &+= 1
        currentIdentity = nil
        model.lyrics = LyricsDisplayState()
    }

    private func update() {
        // A hidden notch must never start a new request just because metadata
        // changed while it was hidden. Retain a valid loaded timeline; a
        // canceled in-flight load becomes unavailable and waits for a later
        // explicit identity/state change.
        if model.screenHidden || !model.settings.showNotch {
            if task != nil {
                cancelCurrentTask()
                generation &+= 1
                if model.lyrics.status == .loading {
                    model.lyrics = LyricsDisplayState(status: .unavailable, identity: currentIdentity)
                }
            }
            return
        }
        let enabled = model.settings.nowPlayingEnabled && model.settings.musicPreferences.showLyrics
        let identity: LyricsTrackIdentity? = enabled && model.hasTrack
            && model.showsMusicActivity
            ? LyricsTrackIdentity(title: model.title, artist: model.artist,
                                  album: model.album, duration: model.duration)
            : nil

        guard identity != currentIdentity else { return }
        cancelCurrentTask()
        generation &+= 1
        currentIdentity = identity
        guard let identity else {
            model.lyrics = LyricsDisplayState()
            return
        }

        let request = LyricsRequest(identity: identity, title: model.title,
                                    artist: model.artist, album: model.album,
                                    duration: model.duration)
        let token = generation
        model.lyrics = LyricsDisplayState(status: .loading, identity: identity)
        taskRunning = true
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.generation == token { self.taskRunning = false }
            }
            do {
                let providerTask = Task { try await self.provider.lyrics(for: request) }
                let timeoutTask = Task { () throws -> LyricsFetchResult in
                    try await Task.sleep(nanoseconds: UInt64(max(0, self.budget) * 1_000_000_000))
                    throw LyricsFetchError.timedOut
                }
                let race = LyricsDeadlineRace(provider: providerTask, timeout: timeoutTask)
                let result = try await withTaskCancellationHandler {
                    try await withCheckedThrowingContinuation { continuation in
                        race.attach(continuation)
                    }
                } onCancel: {
                    race.cancel()
                }
                guard !Task.isCancelled, self.generation == token,
                      self.currentIdentity == identity,
                      self.model.settings.musicPreferences.showLyrics,
                      self.model.settings.showNotch,
                      !self.model.screenHidden,
                      self.model.showsMusicActivity else { return }
                switch result {
                case .timed(let timeline), .wordTimed(let timeline):
                    self.model.lyrics = LyricsDisplayState(status: .ready, timeline: timeline,
                                                           identity: identity)
                case .noLyrics:
                    self.model.lyrics = LyricsDisplayState(status: .noLyrics, identity: identity)
                case .instrumental:
                    self.model.lyrics = LyricsDisplayState(status: .instrumental, identity: identity)
                case .unsynchronized:
                    self.model.lyrics = LyricsDisplayState(status: .unsynchronized, identity: identity)
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, self.generation == token,
                      self.currentIdentity == identity,
                      self.model.settings.musicPreferences.showLyrics else { return }
                self.model.lyrics = LyricsDisplayState(status: .unavailable, identity: identity)
            }
        }
    }

    private func cancelCurrentTask() {
        task?.cancel()
        task = nil
        taskRunning = false
    }

    isolated deinit {
        task?.cancel()
    }
}

/// Races provider completion against the deadline without a structured task
/// group. A task group waits for every child on scope exit, so a provider that
/// ignores cancellation would keep the controller's 3s deadline stuck. This
/// gate resumes the controller as soon as either side wins, cancels both
/// underlying tasks, and ignores late provider completion.
// @unchecked Sendable: every mutable field below is guarded by `lock`; this
// gate owns no UI/model state and never resumes its continuation twice.
private final class LyricsDeadlineRace: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false
    private var pendingResult: Result<LyricsFetchResult, Error>?
    private var continuation: CheckedContinuation<LyricsFetchResult, Error>?
    private let provider: Task<LyricsFetchResult, Error>
    private let timeout: Task<LyricsFetchResult, Error>
    private var providerWaiter: Task<Void, Never>?
    private var timeoutWaiter: Task<Void, Never>?
    private var started = false

    init(provider: Task<LyricsFetchResult, Error>, timeout: Task<LyricsFetchResult, Error>) {
        self.provider = provider
        self.timeout = timeout
    }

    func attach(_ continuation: CheckedContinuation<LyricsFetchResult, Error>) {
        lock.lock()
        if finished {
            let result = pendingResult
            pendingResult = nil
            lock.unlock()
            // cancel() may have won before the continuation existed. Preserve
            // that completion and resume exactly once here.
            continuation.resume(with: result ?? .failure(CancellationError()))
            return
        }
        self.continuation = continuation
        let shouldStart = !started
        started = true
        lock.unlock()
        if shouldStart { startWaiters() }
    }

    func cancel() {
        finish(.failure(CancellationError()))
    }

    private func startWaiters() {
        providerWaiter = Task { [weak self] in
            guard let self else { return }
            do { self.finish(.success(try await self.provider.value)) }
            catch { self.finish(.failure(error)) }
        }
        timeoutWaiter = Task { [weak self] in
            guard let self else { return }
            do { self.finish(.success(try await self.timeout.value)) }
            catch { self.finish(.failure(error)) }
        }
    }

    private func finish(_ result: Result<LyricsFetchResult, Error>) {
        let completion: CheckedContinuation<LyricsFetchResult, Error>?
        lock.lock()
        if finished {
            lock.unlock()
            return
        }
        finished = true
        completion = continuation
        continuation = nil
        if completion == nil { pendingResult = result }
        let shouldCancel = !result.isSuccess
        lock.unlock()
        if shouldCancel {
            provider.cancel()
            timeout.cancel()
        } else {
            timeout.cancel()
        }
        completion?.resume(with: result)
    }
}

private extension Result {
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}
