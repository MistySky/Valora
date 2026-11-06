import SwiftUI
import AppKit
import ReferenceCore

@MainActor
final class ArtworkTransitionController: ObservableObject {
    // Preserve a rendered placeholder as a transition origin after an artwork
    // gap. The previous cover is still released and never displayed as the
    // new song's artwork; late artwork can now animate instead of looking like
    // the first image mounted by this view.
    private static let placeholderIdentity = "valora-artwork-placeholder"
    @Published private(set) var state = ArtworkTransitionState()
    @Published private(set) var image: NSImage?
    @Published private(set) var progress = 0.0
    @Published private(set) var effectProgress = 0.0
    private var frames: [String:NSImage] = [:]
    private var task: Task<Void,Never>?
    func update(image next: NSImage?, identity: String, animated: Bool) {
        if let next, !identity.isEmpty { frames[identity] = next }
        var candidate = state
        let missing = next == nil || identity.isEmpty
        let nextIdentity = missing
            ? (animated && state.current != nil ? Self.placeholderIdentity : nil)
            : identity
        candidate.set(nextIdentity, animated: animated && !missing)
        guard candidate != state else { return }
        let changedGeneration = candidate.generation != state.generation
        state = candidate
        if changedGeneration {
            task?.cancel(); task = nil
            if state.phase == .idle {
                withoutAnimation { image = state.current.flatMap { frames[$0] }; progress = 0; effectProgress = 0 }
            } else { runTransition() }
        }
        pruneFrames()
    }
    private func withoutAnimation(_ body: () -> Void) {
        var transaction = Transaction(); transaction.disablesAnimations = true
        withTransaction(transaction,body)
    }
    private func pruneFrames() {
        let ids = Set([state.current,state.target,state.queued].compactMap { $0 })
        frames = frames.filter { ids.contains($0.key) }
    }
    private func runTransition() {
        let token = state.generation
        withoutAnimation { progress = 0; effectProgress = 0 }
        withAnimation(.easeIn(duration:ArtworkFlipMetrics.outgoingDuration)) { progress = 1; effectProgress = 1 }
        task = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds:150_000_000) } catch { return }
            guard let self, !Task.isCancelled, self.state.generation == token else { return }
            self.withoutAnimation {
                self.state.finishOutgoing(token)
                self.image = self.state.current.flatMap { self.frames[$0] }
                self.progress = 0; self.effectProgress = 0
            }
            // Allow the incoming frame's compressed pose to reach SwiftUI first.
            do { try await Task.sleep(nanoseconds:16_000_000) } catch { return }
            guard !Task.isCancelled, self.state.generation == token else { return }
            withAnimation(.spring(duration:ArtworkFlipMetrics.incomingDuration,bounce:ArtworkFlipMetrics.incomingBounce)) { self.progress = 1 }
            withAnimation(.easeOut(duration:ArtworkFlipMetrics.effectDuration).delay(ArtworkFlipMetrics.effectDelay)) { self.effectProgress = 1 }
            do { try await Task.sleep(nanoseconds:650_000_000) } catch { return }
            guard !Task.isCancelled, self.state.generation == token else { return }
            self.withoutAnimation { self.state.finishIncoming(token) }
            if self.state.phase == .outgoing { self.runTransition() }
            else { self.withoutAnimation { self.progress = 0; self.effectProgress = 0 } }
            self.pruneFrames()
        }
    }
    func stop() { task?.cancel(); task = nil; frames.removeAll(); state = ArtworkTransitionState(); image = nil }
    deinit { task?.cancel() }
}

struct TransitioningArtwork: View {
    let image: NSImage?
    let identity: String
    let size: CGFloat
    var cornerRadius: CGFloat? = nil
    let enabled: Bool
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    @StateObject private var transition = ArtworkTransitionController()
    private var incoming: Bool { transition.state.phase == .incoming }
    private var moving: Bool { transition.state.phase != .idle }
    var body: some View {
        Artwork(image:transition.image,size:size,cornerRadius:cornerRadius)
            .brightness(moving && incoming ? (1-transition.effectProgress)*0.225:0)
            .blur(radius:moving ? (incoming ? (1-transition.effectProgress)*4.5:transition.effectProgress*2.5):0)
            .clipShape(RoundedRectangle(cornerRadius:cornerRadius ?? size*0.14,style:.continuous))
            .scaleEffect(x:moving ? ArtworkFlipMetrics.scale(progress:transition.progress,incoming:incoming):1,y:1)
            .onAppear { synchronize() }
            .onChange(of:identity) { _,_ in synchronize() }
            .onChange(of:enabled) { _,_ in synchronize() }
            .onChange(of:reducedMotion) { _,_ in synchronize() }
            .onDisappear { transition.stop() }
    }
    private func synchronize() { transition.update(image:image,identity:identity,animated:enabled && !reducedMotion) }
}
