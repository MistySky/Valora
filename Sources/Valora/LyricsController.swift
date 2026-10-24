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
    private var task: Task<Void, Never>?
    private var generation: UInt64 = 0
    private var currentIdentity: LyricsTrackIdentity?
    private var started = false
    private var subscriptions = Set<AnyCancellable>()

    init(model: AppModel, provider: any LyricsProviding) {
        self.model = model
        self.provider = provider
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
            model.$screenHidden.map { _ in () }.eraseToAnyPublisher(),
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
                MainActor.assumeIsolated { self?.update() }
            }
        }.store(in: &subscriptions)
        update()
    }

    /// Called synchronously after the media controller has written a complete
    /// metadata snapshot, so old lyrics do not survive a track change frame.
    func mediaMetadataChanged() { update() }

    func cancel() {
        task?.cancel(); task = nil
        generation &+= 1
        currentIdentity = nil
        model.lyrics = LyricsDisplayState()
    }

    private func update() {
        let enabled = model.settings.nowPlayingEnabled && model.settings.musicPreferences.showLyrics
        let identity: LyricsTrackIdentity? = enabled && model.hasTrack
            && model.settings.showNotch && model.showsMusicActivity && !model.screenHidden
            ? LyricsTrackIdentity(title: model.title, artist: model.artist,
                                  album: model.album, duration: model.duration)
            : nil

        guard identity != currentIdentity else { return }
        task?.cancel(); task = nil
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
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let result = try await self.provider.lyrics(for: request)
                guard !Task.isCancelled, self.generation == token,
                      self.currentIdentity == identity,
                      self.model.settings.musicPreferences.showLyrics,
                      self.model.settings.showNotch,
                      !self.model.screenHidden,
                      self.model.showsMusicActivity else { return }
                switch result {
                case .timed(let timeline):
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

    isolated deinit {
        task?.cancel()
    }
}
