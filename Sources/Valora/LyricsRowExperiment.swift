import AppKit
import ReferenceCore
import SwiftUI

/// Outer transition strategy is typed so lock and desktop cannot silently
/// share a policy through a string role.
enum LyricsTransitionStrategy: Equatable, Sendable {
    /// build26-aligned SwiftUI outer layout/animation (desktop).
    case build26SwiftUI
    /// build49 timer/old-width outer strategy (lock fallback).
    case legacyTimer
}

/// Which desktop lyric row implementation this build contains.
enum LyricsRowBackend: Equatable {
    case production
    case experiment

    static var experimentCompiled: Bool {
        #if VALORA_LYRICS_EXPERIMENT
        return true
        #else
        return false
        #endif
    }

    static var active: LyricsRowBackend {
        experimentCompiled ? .experiment : .production
    }
}

/// Identity-scoped fallback latch (plain value kept for review/tests).
struct LyricsRowFallbackState: Equatable {
    private(set) var failed = false
    private(set) var identity = ""

    mutating func updateIdentity(_ newIdentity: String) {
        guard newIdentity != identity else { return }
        identity = newIdentity
        failed = false
    }

    mutating func reportFailure() {
        failed = true
    }

    mutating func reset() {
        failed = false
    }
}

/// Desktop lyric row used by `NotchView` at the floating / inline / expanded
/// call sites. The lock screen keeps calling `CompactLyricsView` directly.
struct DesktopLyricsRow: View {
    @ObservedObject var model: AppModel
    let width: CGFloat
    var rowHeight: CGFloat = 32
    var showsNote: Bool = true
    var horizontalInset: CGFloat = 18
    var centersNoteWhenEmpty: Bool = false
    var auditRole: String = "active"
    /// Independent presentation condition. Lock-screen callers must not use
    /// the desktop notch visibility flag.
    var active: Bool? = nil

    var body: some View {
        #if VALORA_LYRICS_EXPERIMENT
        ExperimentalDesktopLyricsView(model: model, width: width, rowHeight: rowHeight,
                                      showsNote: showsNote, horizontalInset: horizontalInset,
                                      centersNoteWhenEmpty: centersNoteWhenEmpty,
                                      auditRole: auditRole,
                                      active: active ?? model.notchSurfaceOnScreen)
        #else
        CompactLyricsView(model: model, width: width, rowHeight: rowHeight,
                          showsNote: showsNote, horizontalInset: horizontalInset,
                          centersNoteWhenEmpty: centersNoteWhenEmpty, auditRole: auditRole)
        #endif
    }
}

#if VALORA_LYRICS_EXPERIMENT
/// Debug seam used only by the isolated hosting tests.
@MainActor
enum LyricsRowExperimentDebug {
    static var failHostRender = false
}

@MainActor
final class LyricsRowExperimentHost: ObservableObject {
    @Published private(set) var failed = false
    @Published private(set) var displayedLine: LyricLine?
    @Published private(set) var contentWidth: CGFloat?
    @Published private(set) var outgoing: NativeLyricsStaticLine?
    /// Desktop keyed-child presentation identity. The SwiftUI row uses this
    /// as `.id`; a real line change increments it exactly once.
    @Published private(set) var presentationID: UInt64 = 0
    @Published private(set) var presentationLineKey = ""
    /// Viewport transition state, updated by a short 0.2s driver (one at a
    /// time). Offsets/opacities are the production ±26pt/0..1 values.
    @Published private(set) var incomingOffset: CGFloat = 0
    @Published private(set) var incomingOpacity: Double = 1
    @Published private(set) var outgoingOffset: CGFloat = 0
    @Published private(set) var outgoingOpacity: Double = 1
    private var transitionTimer: Timer?
    private var transitionGeneration: UInt64 = 0
    private weak var currentNativeView: NativeLyricsRowView?
    /// Desktop keyed children share this owner-held preparation host.
    let textPreparer = NativeLyricsTextPreparer()
    private var transitionProgress: Double = 1
    /// Fixed duration of the viewport transition.
    private static let transitionDuration: Double = 0.2
    /// Monotonic start time of the live transition (seconds).
    private var transitionStartedAt: Double = 0
    /// Typed production transition policy. The desktop view explicitly sets
    /// `.build26SwiftUI`; the default keeps direct/legacy harness users on the
    /// established timer path.
    var transitionStrategy: LyricsTransitionStrategy = .legacyTimer
    /// Tests drive the transition deterministically instead of wall time.
    var debugManualTransition = false
    /// Legacy timer seam only for isolated transition-clock tests. Production
    /// never enables this; the app uses one SwiftUI animation transaction.
    var debugUsesTimer = false
    /// Test seam: injectable monotonic clock in seconds. Production reads
    /// `systemUptime` (same monotonic source the renderer's boundary wake
    /// already uses, unaffected by wall-clock changes); behavior tests
    /// substitute a manually advanced fake clock.
    var debugMonotonicClock: (() -> Double)?
    /// Debug geometry seam: moves the whole 17pt viewport (not the text inside
    /// it) to validate the switch geometry statically.
    @Published var debugViewportOffsetY: CGFloat = 0
    private(set) var identity = ""
    private(set) var generation: UInt64 = 0
    /// Non-published owner lease. NSViewRepresentable make/update must never
    /// mutate @Published state; the outer view owns activation/invalidation.
    private(set) var isActiveOwner = false

    /// Called from the outer view initializer, before SwiftUI observes the
    /// host. This only reserves identity/generation; no @Published state and
    /// no bridge callback can be produced yet.
    func prepareInitial(identity newIdentity: String) {
        guard !isActiveOwner, identity.isEmpty else { return }
        identity = newIdentity
        generation = 1
        isActiveOwner = true
        textPreparer.isAvailable = true
    }

    /// Safe re-activation/reset point. Only outer onAppear/onChange (or a
    /// direct unit-test harness) may call this; wire/make/update never do.
    func begin(identity newIdentity: String) {
        guard newIdentity != identity || !isActiveOwner else { return }
        identity = newIdentity
        generation &+= 1
        isActiveOwner = true
        failed = false
        textPreparer.isAvailable = true
        displayedLine = nil
        contentWidth = nil
        currentNativeView = nil
        presentationLineKey = ""
        presentationID &+= 1
        stopTransition()
    }

    func invalidate() {
        isActiveOwner = false
        generation &+= 1
        currentNativeView?.stop()
        currentNativeView = nil
        textPreparer.isAvailable = false
        textPreparer.close()
        stopTransition()
    }

    /// Called by the freshly mounted keyed child. The weak reference is the
    /// only native presentation the owner may freeze at handoff.
    func registerNativeView(_ view: NativeLyricsRowView) {
        guard isActiveOwner, transitionStrategy == .build26SwiftUI else { return }
        currentNativeView = view
    }

    func unregisterNativeView(_ view: NativeLyricsRowView) {
        guard currentNativeView === view else { return }
        currentNativeView = nil
    }

    /// Desktop keyed handoff: runs before the old native view rewrites its
    /// layers. Freeze it, then publish a new presentation ID so SwiftUI removes
    /// the old child with its removal transition and inserts the new child.
    /// Returns false for the legacy timer strategy or a repeated same line.
    func handoffToNextLine(from view: NativeLyricsRowView,
                           nextLine: LyricLine?,
                           outgoing: NativeLyricsStaticLine?) -> Bool {
        guard isActiveOwner, transitionStrategy == .build26SwiftUI,
              currentNativeView === view else { return false }
        let nextKey = nextLine.map { "\($0.start)-\($0.text)" } ?? ""
        guard nextKey != presentationLineKey else { return false }
        view.retireForTransition()
        currentNativeView = nil
        // The handoff is called from the native view update. Do not publish
        // @Published presentation state synchronously here; freeze first, then
        // publish on the next main-queue turn. No fixed delay is introduced.
        let lease = generation
        let frozen = outgoing
        DispatchQueue.main.async { [weak self, weak view] in
            guard let self, self.isActiveOwner, self.generation == lease else { return }
            view?.isHidden = true
            self.presentationLineKey = nextKey
            self.displayedLine = nextLine
            self.presentationID &+= 1
            guard let frozen else { return }
            let token = self.presentationID
            self.outgoing = frozen
            DispatchQueue.main.async { [weak self] in
                guard let self, self.presentationID == token else { return }
                withAnimation(.easeInOut(duration: 0.2)) { self.outgoing = nil }
            }
        }
        return true
    }

    /// Prepares the outgoing line and initial state before publishing the new
    /// displayed line, so the first frame cannot expose the new line at its
    /// settled position. The actual 0.2s curve is one SwiftUI transaction in
    /// production; timer stepping exists only behind the debug seams.
    private func prepareTransition(_ outgoing: NativeLyricsStaticLine?) -> UInt64? {
        stopTransition()
        guard let outgoing else { return nil }
        transitionGeneration &+= 1
        let token = transitionGeneration
        self.outgoing = outgoing
        transitionProgress = 0
        incomingOffset = 26
        incomingOpacity = 0
        outgoingOffset = 0
        outgoingOpacity = 1
        return token
    }

    private func beginTransition(token: UInt64) {
        if debugManualTransition {
            transitionStartedAt = currentMonotonicSeconds()
            return
        }
        if transitionStrategy == .legacyTimer || debugUsesTimer {
            transitionStartedAt = currentMonotonicSeconds()
            let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, token == self.transitionGeneration else { return }
                    self.stepTransitionByElapsedClock()
                }
            }
            timer.tolerance = 0.002
            transitionTimer = timer
            RunLoop.main.add(timer, forMode: .common)
            return
        }
        // Let the prepared offset/opacity render once, then hand the whole
        // 0.2s curve to SwiftUI. No per-frame timer or published tick.
        // One short main-queue defer lets the prepared 26pt/0-opacity state
        // reach a render. It is a single handoff, not a repeating driver.
        DispatchQueue.main.async { [weak self] in
            guard let self, token == self.transitionGeneration,
                  self.outgoing != nil else { return }
            withAnimation(.easeInOut(duration: Self.transitionDuration),
                          completionCriteria: .logicallyComplete) {
                self.incomingOffset = 0
                self.incomingOpacity = 1
                self.outgoingOffset = -26
                self.outgoingOpacity = 0
            } completion: { [weak self] in
                guard let self, token == self.transitionGeneration else { return }
                self.stopTransition()
            }
        }
    }

    /// Reads the monotonic clock in seconds. `systemUptime` stays monotonic
    /// across wall-clock changes and already drives the renderer's boundary
    /// wake; the debug seam substitutes a manually advanced test clock.
    private func currentMonotonicSeconds() -> Double {
        debugMonotonicClock?() ?? ProcessInfo.processInfo.systemUptime
    }

    /// One driver tick: the progress is the fraction of the fixed 0.2s window
    /// that has actually elapsed, clamped to 1. A late, merged or coalesced
    /// callback therefore jumps straight to the end point and releases the old
    /// line instead of stretching the animation; no fixed per-frame share is
    /// accumulated. Curve, ±26pt and both-sided opacity are unchanged.
    private func stepTransitionByElapsedClock() {
        guard transitionTimer != nil else { return }
        let elapsed = currentMonotonicSeconds() - transitionStartedAt
        let progress = min(1, max(0, elapsed / Self.transitionDuration))
        transitionProgress = progress
        applyTransition(progress: progress)
        if progress >= 1 { stopTransition() }
    }

    /// Debug seam for behavior tests: performs exactly one driver tick with
    /// the current (possibly injected) clock, so tests can present uneven or
    /// dropped callbacks without depending on timer punctuality. A no-op once
    /// the live timer is gone (stale ticks must not restart anything).
    func debugFireTransitionTick() {
        stepTransitionByElapsedClock()
    }

    /// Debug observability: the 60Hz driver lives exactly during a real
    /// transition and is invalidated when the transition ends for any reason.
    var debugTransitionTimerActive: Bool { transitionTimer != nil }

    private func applyTransition(progress: Double) {
        let eased = Self.easeInOut(min(1, max(0, progress)))
        incomingOffset = 26 * (1 - eased)
        incomingOpacity = eased
        outgoingOffset = -26 * eased
        outgoingOpacity = 1 - eased
    }

    /// Deterministic stepping for the isolated harness.
    func debugSetTransitionProgress(_ progress: Double) {
        transitionProgress = min(1, max(0, progress))
        applyTransition(progress: transitionProgress)
        if transitionProgress >= 1 { stopTransition() }
    }

    private func stopTransition() {
        transitionTimer?.invalidate()
        transitionTimer = nil
        outgoing = nil
        incomingOffset = 0
        incomingOpacity = 1
        outgoingOffset = 0
        outgoingOpacity = 1
        transitionProgress = 1
    }

    /// cubic-bezier(0.42, 0, 0.58, 1), the easeInOut curve.
    private static func easeInOut(_ x: Double) -> Double {
        guard x > 0, x < 1 else { return x }
        func curve(_ t: Double, _ p1: Double, _ p2: Double) -> Double {
            let mt = 1 - t
            return 3 * mt * mt * t * p1 + 3 * mt * t * t * p2 + t * t * t
        }
        var low = 0.0, high = 1.0
        for _ in 0..<24 {
            let mid = (low + high) / 2
            if curve(mid, 0.42, 0.42) < x { low = mid } else { high = mid }
        }
        return curve((low + high) / 2, 0, 1)
    }

    func reportLine(_ line: LyricLine?, outgoing: NativeLyricsStaticLine?,
                    generation: UInt64, identity: String) {
        // The capture-failure callback may arrive before the matching line
        // callback; a failed row must not restart a transition.
        guard isActiveOwner, generation == self.generation, identity == self.identity,
              !failed else { return }
        if transitionStrategy == .build26SwiftUI {
            // The keyed owner published this line before the new child mounted.
            // This callback is only the initial native render confirmation.
            if displayedLine != line { displayedLine = line }
            return
        }
        let firstLine = displayedLine == nil
        if firstLine {
            displayedLine = line
            stopTransition()
        } else {
            // Prepare offsets/outgoing first; publishing the new line after
            // that prevents a one-frame settled flash of the incoming line.
            let token = prepareTransition(outgoing)
            displayedLine = line
            if let token { beginTransition(token: token) }
        }
    }

    func reportContentWidth(_ width: CGFloat, generation: UInt64, identity: String) {
        guard isActiveOwner, generation == self.generation, identity == self.identity else { return }
        guard width.isFinite, width >= 0 else { return }
        if contentWidth != width { contentWidth = width }
    }

    func reportFailure(generation: UInt64, identity: String) {
        guard isActiveOwner, generation == self.generation, identity == self.identity else { return }
        failed = true
        textPreparer.isAvailable = false
        currentNativeView?.stop()
        textPreparer.close()
        stopTransition()
    }

    /// The surface went away: release the frozen outgoing line immediately.
    func endPresentation() {
        stopTransition()
    }

    /// True once the viewport transition has fully settled.
    var isSettled: Bool {
        outgoing == nil && incomingOffset == 0 && incomingOpacity == 1
    }

    func retry() { failed = false }
}

/// Experiment host: identical outer row chrome with the native renderer only
/// replacing the text content. On failure the whole row is replaced by the
/// shipped `CompactLyricsView` with exactly the production parameters.
struct ExperimentalDesktopLyricsView: View {
    @ObservedObject var model: AppModel
    let width: CGFloat
    var rowHeight: CGFloat = 32
    var showsNote: Bool = true
    var horizontalInset: CGFloat = 18
    var centersNoteWhenEmpty: Bool = false
    var auditRole: String = "active"
    /// Explicit presentation condition. When nil, preserve the desktop
    /// row's existing `notchSurfaceOnScreen` behavior for callers/tests.
    var active: Bool? = nil
    /// Desktop uses build26 SwiftUI layout; lock uses the legacy timer path.
    var transitionStrategy: LyricsTransitionStrategy = .build26SwiftUI
    private var isActive: Bool { active ?? model.notchSurfaceOnScreen }

    @StateObject private var host: LyricsRowExperimentHost
    @ObservedObject private var playback: PlaybackProgress
    @State private var metricsCache = LyricMetricsCache()

    init(model: AppModel, width: CGFloat, rowHeight: CGFloat = 32,
         showsNote: Bool = true, horizontalInset: CGFloat = 18,
         centersNoteWhenEmpty: Bool = false, auditRole: String = "active",
         active: Bool? = nil, transitionStrategy: LyricsTransitionStrategy = .build26SwiftUI,
         host: LyricsRowExperimentHost? = nil,
         playback: PlaybackProgress? = nil) {
        self.model = model
        self.width = width
        self.rowHeight = rowHeight
        self.showsNote = showsNote
        self.horizontalInset = horizontalInset
        self.centersNoteWhenEmpty = centersNoteWhenEmpty
        self.auditRole = auditRole
        self.active = active
        self.transitionStrategy = transitionStrategy
        self._playback = ObservedObject(wrappedValue: playback ?? model.progress)
        let resolvedHost = host ?? LyricsRowExperimentHost()
        resolvedHost.transitionStrategy = transitionStrategy
        resolvedHost.prepareInitial(identity: resolvedHost.identity.isEmpty
            ? model.mediaRevisionIdentity + "\u{0}" + model.title + "\u{0}" + model.artist
            : resolvedHost.identity)
        _host = StateObject(wrappedValue: resolvedHost)
    }

    private var availableWidth: CGFloat { max(1, width - (showsNote ? 22 : 0)) }
    private var identityKey: String {
        model.mediaRevisionIdentity + "\u{0}" + model.title + "\u{0}" + model.artist
    }
    /// Content width for the renderer/viewport. Derive it synchronously from
    /// the line the host is displaying, using the same metrics as the
    /// production row. Using the asynchronous native `contentWidth` callback
    /// here made a long→short switch keep the old wide viewport until the
    /// renderer reported back, then contract later: the visible "shrinking"
    /// stutter. Empty lines still collapse to 0 so the note alone centers.
    private var resolvedWidth: CGFloat {
        guard let line = host.displayedLine else {
            return centersNoteWhenEmpty ? 0 : availableWidth
        }
        if line.text.isEmpty { return 0 }
        let content = metricsCache.metrics(for: line, identity: model.lyrics.identity).totalWidth
        return min(availableWidth, max(0, content))
    }
    /// Production rule: an overflowing line leads, a fitting line centers,
    /// derived from the line the renderer actually displays.
    private var isLong: Bool {
        guard let line = host.displayedLine else { return false }
        return metricsCache.metrics(for: line, identity: model.lyrics.identity).totalWidth
            > availableWidth
    }
    private var snapshot: NativeLyricsRowSnapshot {
        NativeLyricsRowSnapshot(identity: model.lyrics.identity,
                                contentRevision: model.lyricsRevision,
                                timeline: model.lyrics.timeline,
                                elapsed: playback.snapshot.elapsed,
                                sampledAt: playback.snapshot.sampledAt,
                                rate: model.playbackRate,
                                playing: model.playing,
                                duration: model.duration,
                                width: resolvedWidth,
                                rowHeight: 17,
                                accent: model.lyricsAccentColor,
                                textBackend: .swiftUI,
                                switchAnimation: false)
    }
    private var accessibilityText: String {
        if let text = host.displayedLine?.text, !text.isEmpty { return "歌词，\(text)" }
        return "歌词"
    }

    var body: some View {
        Group {
            if host.failed {
                CompactLyricsView(model: model, width: width, rowHeight: rowHeight,
                                  showsNote: showsNote, horizontalInset: horizontalInset,
                                  centersNoteWhenEmpty: centersNoteWhenEmpty,
                                  auditRole: auditRole)
            } else if transitionStrategy == .build26SwiftUI {
                keyedRow
            } else {
                experimentRow
            }
        }
        .onAppear {
            host.begin(identity: identityKey)
        }
        .onChange(of: identityKey) { _, _ in
            host.begin(identity: identityKey)
        }
        .onChange(of: isActive) { _, visible in
            if !visible { host.endPresentation() }
        }
        #if VALORA_LYRICS_EXPERIMENT
        .onAppear {
            LyricsDiagnostics.shared.setFallback(role: auditRole, active: host.failed)
        }
        .onChange(of: host.failed) { _, failed in
            LyricsDiagnostics.shared.setFallback(role: auditRole, active: failed)
            if failed { host.textPreparer.close() }
        }
        .onDisappear {
            LyricsDiagnostics.shared.setFallback(role: auditRole, active: false)
            host.invalidate()
        }
        #else
        .onDisappear { host.invalidate() }
        #endif
    }

    private var effectiveWidth: CGFloat { resolvedWidth }
    private var effectiveIsLong: Bool { isLong }

    private var activeLineKey: String {
        host.displayedLine.map { "\($0.start)-\($0.text)" } ?? ""
    }

    /// build26 mechanism: the line content is a keyed child. A real line
    /// change gets one asymmetric offset/opacity transition; the parent
    /// animates intrinsic width and alignment in the same transaction.
    private var keyedRow: some View {
        HStack(spacing: 5) {
            if showsNote { noteIcon }
            if !model.lyrics.hasTimedLyrics {
                if !centersNoteWhenEmpty {
                    Color.clear.frame(width: availableWidth, height: 17)
                }
            } else {
                ZStack(alignment: .topLeading) {
                    if let outgoing = host.outgoing {
                        FrozenLyricsImageView(line: outgoing)
                            .transition(.asymmetric(
                                insertion: .identity,
                                removal: .offset(y: -26).combined(with: .opacity)))
                            .allowsHitTesting(false)
                    }
                    nativeRow
                        .id(host.presentationID)
                        .transition(.asymmetric(
                            insertion: .offset(y: 26).combined(with: .opacity),
                            removal: .offset(y: -26).combined(with: .opacity)))
                        .frame(width: resolvedWidth, height: 17, alignment: .topLeading)
                        .clipped()
                }
                .frame(width: max(1, effectiveWidth), height: 17, alignment: .topLeading)
            }
        }
        .foregroundStyle(.gray)
        .frame(width: max(1, width), height: rowHeight,
               alignment: effectiveIsLong ? .leading : .center)
        .padding(.horizontal, horizontalInset)
        .clipped()
        .animation(.easeInOut(duration: 0.2), value: host.presentationID)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityIdentifier("compact.lyrics")
    }

    private var nativeRow: some View {
        NativeLyricsRowHost(snapshot: snapshot,
                            active: isActive,
                            diagnosticRole: auditRole,
                            host: host,
                            identity: identityKey,
                            failRender: LyricsRowExperimentDebug.failHostRender,
                            onLineChange: { line, outgoing, generation, identity in
                                DispatchQueue.main.async {
                                    host.reportLine(line, outgoing: outgoing,
                                                    generation: generation,
                                                    identity: identity)
                                }
                            },
                            onContentWidth: { width, generation, identity in
                                DispatchQueue.main.async {
                                    host.reportContentWidth(width,
                                                            generation: generation,
                                                            identity: identity)
                                }
                            },
                            onFailure: { generation, identity in
                                DispatchQueue.main.async {
                                    host.reportFailure(generation: generation,
                                                       identity: identity)
                                }
                            })
    }

    private var experimentRow: some View {
        HStack(spacing: 5) {
            if showsNote { noteIcon }
            if !model.lyrics.hasTimedLyrics {
                if !centersNoteWhenEmpty {
                    Color.clear.frame(width: availableWidth, height: 17)
                }
            } else {
                ZStack(alignment: .topLeading) {
                    if let outgoing = host.outgoing {
                        StaticLyricsLineView(staticLine: outgoing)
                            .frame(width: max(1, outgoing.viewportWidth), height: 17,
                                   alignment: .topLeading)
                            .offset(y: host.outgoingOffset)
                            .opacity(host.outgoingOpacity)
                            .allowsHitTesting(false)
                    }
                    nativeRow
                        // The whole 17pt viewport (with its horizontal clip
                        // and mask) moves; the outer rowHeight frame clips.
                        .frame(width: resolvedWidth, height: 17)
                        .offset(y: host.incomingOffset)
                        .opacity(host.incomingOpacity)
                }
                .frame(width: max(1, effectiveWidth), height: 17, alignment: .topLeading)
                .offset(y: host.debugViewportOffsetY)
            }
        }
        .foregroundStyle(.gray)
        .frame(width: max(1, width), height: rowHeight,
               alignment: effectiveIsLong ? .leading : .center)
        .padding(.horizontal, horizontalInset)
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityIdentifier("compact.lyrics")
    }

    private var noteIcon: some View {
        Image(systemName: "music.note")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color(nsColor: model.lyricsAccentColor))
    }
}

/// Holds the frozen outgoing line between the renderer's two synchronous
/// callbacks (`onSwitchOutgoing` then `onLineChange`).
private final class SwitchBox {
    var outgoing: NativeLyricsStaticLine?
}

/// Pure SwiftUI image of the retired native row. It has no renderer, clock or
/// capture window; only the keyed successor participates in the transition.
private struct FrozenLyricsImageView: View {
    let line: NativeLyricsStaticLine

    var body: some View {
        ZStack(alignment: .topLeading) {
            Image(decorative: line.base, scale: line.imageScale)
                .frame(width: line.pointSize.width, height: line.pointSize.height)
                .offset(x: line.positionX, y: line.positionY)
            Image(decorative: line.accent, scale: line.imageScale)
                .frame(width: line.pointSize.width, height: line.pointSize.height)
                .offset(x: line.positionX, y: line.positionY)
                .mask(alignment: .leading) {
                    Rectangle().frame(width: max(0, line.maskWidth))
                }
        }
        .frame(width: max(1, line.viewportWidth), height: 17, alignment: .topLeading)
        .clipped()
    }
}

/// Frozen outgoing viewport: the same prepared images, mask and scroll
/// geometry, with no clock and no text/bitmap build.
private struct StaticLyricsLineView: NSViewRepresentable {
    let staticLine: NativeLyricsStaticLine

    func makeNSView(context: Context) -> StaticLyricsLineNSView {
        StaticLyricsLineNSView(staticLine: staticLine)
    }

    func updateNSView(_ view: StaticLyricsLineNSView, context: Context) {
        view.apply(staticLine)
    }
}

@MainActor
final class StaticLyricsLineNSView: NSView {
    private let container = CALayer()
    private let base = CALayer()
    private let accent = CALayer()
    private let mask = CALayer()
    private var applied: NativeLyricsStaticLine?

    init(staticLine: NativeLyricsStaticLine) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.isGeometryFlipped = true
        container.isGeometryFlipped = true
        container.anchorPoint = .zero
        layer?.addSublayer(container)
        for layer in [base, accent] {
            layer.anchorPoint = .zero
            layer.position = .zero
            layer.contentsGravity = .resize
            container.addSublayer(layer)
        }
        accent.mask = mask
        mask.anchorPoint = .zero
        mask.position = .zero
        mask.backgroundColor = NSColor.white.cgColor
        apply(staticLine)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func apply(_ staticLine: NativeLyricsStaticLine) {
        guard applied?.lineKey != staticLine.lineKey
            || applied?.pointSize != staticLine.pointSize
            || applied?.viewportWidth != staticLine.viewportWidth else { return }
        applied = staticLine
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        container.bounds = CGRect(origin: .zero, size: staticLine.pointSize)
        container.position = CGPoint(x: staticLine.positionX, y: staticLine.positionY)
        for (layer, image) in [(base, staticLine.base), (accent, staticLine.accent)] {
            layer.contents = image
            layer.contentsScale = staticLine.imageScale
            layer.bounds = CGRect(origin: .zero, size: staticLine.pointSize)
        }
        mask.bounds = CGRect(x: 0, y: 0, width: staticLine.maskWidth,
                             height: staticLine.pointSize.height)
        CATransaction.commit()
    }
}

/// Small, complete input key for the native adapter. The full timeline is
/// represented by `contentRevision`, maintained at the AppModel lyrics
/// assignment boundary; no per-frame deep sequence comparison is performed.
struct NativeLyricsAppliedKey: Equatable {
    let trackIdentity: LyricsTrackIdentity?
    let contentRevision: UInt64
    let elapsed: Double
    let sampledAt: Date
    let rate: Double
    let playing: Bool
    let duration: Double
    let width: CGFloat
    let rowHeight: CGFloat
    let verticalOffset: CGFloat
    let accent: NSColor
    let textKern: CGFloat
    let reduceMotion: Bool
    let textBackend: NativeLyricsTextBackend
    let switchAnimation: Bool
    let active: Bool
    let hostIdentity: String
    let hostGeneration: UInt64
    let failRender: Bool

    init(snapshot: NativeLyricsRowSnapshot, active: Bool,
         hostIdentity: String, hostGeneration: UInt64, failRender: Bool) {
        self.trackIdentity = snapshot.identity
        self.contentRevision = snapshot.contentRevision
        self.elapsed = snapshot.elapsed
        self.sampledAt = snapshot.sampledAt
        self.rate = snapshot.rate
        self.playing = snapshot.playing
        self.duration = snapshot.duration
        self.width = snapshot.width
        self.rowHeight = snapshot.rowHeight
        self.verticalOffset = snapshot.verticalOffset
        self.accent = snapshot.accent
        self.textKern = snapshot.textKern
        self.reduceMotion = snapshot.reduceMotion
        self.textBackend = snapshot.textBackend
        self.switchAnimation = snapshot.switchAnimation
        self.active = active
        self.hostIdentity = hostIdentity
        self.hostGeneration = hostGeneration
        self.failRender = failRender
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.trackIdentity == rhs.trackIdentity
            && lhs.contentRevision == rhs.contentRevision
            && lhs.elapsed == rhs.elapsed
            && lhs.sampledAt == rhs.sampledAt
            && lhs.rate == rhs.rate
            && lhs.playing == rhs.playing
            && lhs.duration == rhs.duration
            && lhs.width == rhs.width
            && lhs.rowHeight == rhs.rowHeight
            && lhs.verticalOffset == rhs.verticalOffset
            && lhs.accent.isEqual(rhs.accent)
            && lhs.textKern == rhs.textKern
            && lhs.reduceMotion == rhs.reduceMotion
            && lhs.textBackend == rhs.textBackend
            && lhs.switchAnimation == rhs.switchAnimation
            && lhs.active == rhs.active
            && lhs.hostIdentity == rhs.hostIdentity
            && lhs.hostGeneration == rhs.hostGeneration
            && lhs.failRender == rhs.failRender
    }
}

private struct NativeLyricsRowHost: NSViewRepresentable {
    let snapshot: NativeLyricsRowSnapshot
    let active: Bool
    let diagnosticRole: String
    let host: LyricsRowExperimentHost
    let identity: String
    let failRender: Bool
    let onLineChange: (LyricLine?, NativeLyricsStaticLine?, UInt64, String) -> Void
    let onContentWidth: (CGFloat, UInt64, String) -> Void
    let onFailure: (UInt64, String) -> Void

    private func key(hostIdentity: String, hostGeneration: UInt64) -> NativeLyricsAppliedKey {
        NativeLyricsAppliedKey(snapshot: snapshot, active: active,
                               hostIdentity: hostIdentity,
                               hostGeneration: hostGeneration,
                               failRender: failRender)
    }

    func makeNSView(context: Context) -> NativeLyricsRowView {
        let view = NativeLyricsRowView(frame: .zero)
        #if VALORA_LYRICS_EXPERIMENT
        LyricsDiagnostics.shared.register(view: view, role: diagnosticRole)
        #endif
        guard host.isActiveOwner else { return view }
        wire(view)
        let input = key(hostIdentity: host.identity, hostGeneration: host.generation)
        view.noteApplyRequest()
        view.setActive(active)
        view.apply(snapshot)
        #if VALORA_LYRICS_EXPERIMENT
        view.lastAppliedInput = input
        #endif
        host.registerNativeView(view)
        return view
    }

    func updateNSView(_ view: NativeLyricsRowView, context: Context) {
        guard host.isActiveOwner else { view.stop(); return }
        guard !host.failed else { view.stop(); return }
        guard !view.diagnosticRetired else { return }
        #if VALORA_LYRICS_EXPERIMENT
        LyricsDiagnostics.shared.register(view: view, role: diagnosticRole)
        #endif
        wire(view)
        host.registerNativeView(view)
        let input = key(hostIdentity: host.identity, hostGeneration: host.generation)
        view.noteApplyRequest()
        #if VALORA_LYRICS_EXPERIMENT
        guard view.lastAppliedInput != input else {
            view.noteApplySkipped()
            return
        }
        #endif
        view.setActive(active)
        view.apply(snapshot)
        #if VALORA_LYRICS_EXPERIMENT
        view.lastAppliedInput = input
        #endif
    }

    private func wire(_ view: NativeLyricsRowView) {
        // Never publish @Published state from make/update; the owner identity
        // was reserved in the outer initializer and activation is owned by
        // onAppear/onChange.
        let generation = host.generation
        let identity = host.identity
        view.textPreparer = host.transitionStrategy == .build26SwiftUI ? host.textPreparer : nil
        let box = SwitchBox()
        view.onSwitchOutgoing = { box.outgoing = $0 }
        view.onLineChange = { line in
            let outgoing = box.outgoing
            box.outgoing = nil
            onLineChange(line, outgoing, generation, identity)
        }
        view.onLineChangeWillApply = { [weak view] nextLine, outgoing in
            guard let view else { return false }
            return host.handoffToNextLine(from: view, nextLine: nextLine, outgoing: outgoing)
        }
        view.onContentWidthChange = { width in onContentWidth(width, generation, identity) }
        view.onRenderFailure = { onFailure(generation, identity) }
        view.debugFailImageRender = failRender ? [1] : []
    }

    static func dismantleNSView(_ view: NativeLyricsRowView, coordinator: ()) {
        #if VALORA_LYRICS_EXPERIMENT
        LyricsDiagnostics.shared.unregister(view: view)
        #endif
        view.stop()
    }
}
#endif
