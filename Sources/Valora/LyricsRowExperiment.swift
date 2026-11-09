import AppKit
import ReferenceCore
import SwiftUI

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

    var body: some View {
        #if VALORA_LYRICS_EXPERIMENT
        ExperimentalDesktopLyricsView(model: model, width: width, rowHeight: rowHeight,
                                      showsNote: showsNote, horizontalInset: horizontalInset,
                                      centersNoteWhenEmpty: centersNoteWhenEmpty,
                                      auditRole: auditRole)
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
    /// Viewport transition state, updated by a short 0.2s driver (one at a
    /// time). Offsets/opacities are the production ±26pt/0..1 values.
    @Published private(set) var incomingOffset: CGFloat = 0
    @Published private(set) var incomingOpacity: Double = 1
    @Published private(set) var outgoingOffset: CGFloat = 0
    @Published private(set) var outgoingOpacity: Double = 1
    private var transitionTimer: Timer?
    private var transitionGeneration: UInt64 = 0
    private var transitionProgress: Double = 1
    /// Fixed duration of the viewport transition.
    private static let transitionDuration: Double = 0.2
    /// Monotonic start time of the live transition (seconds).
    private var transitionStartedAt: Double = 0
    /// Tests drive the transition deterministically instead of wall time.
    var debugManualTransition = false
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

    func begin(identity newIdentity: String) {
        guard newIdentity != identity else { return }
        identity = newIdentity
        generation &+= 1
        failed = false
        displayedLine = nil
        contentWidth = nil
        stopTransition()
    }

    func invalidate() {
        generation &+= 1
        stopTransition()
    }

    /// Drives the 0.2s viewport transition with the production easeInOut curve.
    private func startTransition(outgoing: NativeLyricsStaticLine?) {
        stopTransition()
        // No frozen outgoing line (empty line, first line, failed capture):
        // show the incoming line immediately, matching production.
        guard let outgoing else { return }
        transitionGeneration &+= 1
        let token = transitionGeneration
        self.outgoing = outgoing
        transitionProgress = 0
        applyTransition(progress: 0)
        guard !debugManualTransition else { return }
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
        guard generation == self.generation, identity == self.identity, !failed else { return }
        let firstLine = displayedLine == nil
        displayedLine = line
        if firstLine {
            stopTransition()
        } else {
            startTransition(outgoing: outgoing)
        }
    }

    func reportContentWidth(_ width: CGFloat, generation: UInt64, identity: String) {
        guard generation == self.generation, identity == self.identity else { return }
        guard width.isFinite, width >= 0 else { return }
        if contentWidth != width { contentWidth = width }
    }

    func reportFailure(generation: UInt64, identity: String) {
        guard generation == self.generation, identity == self.identity else { return }
        failed = true
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

    @StateObject private var host: LyricsRowExperimentHost
    @State private var metricsCache = LyricMetricsCache()

    init(model: AppModel, width: CGFloat, rowHeight: CGFloat = 32,
         showsNote: Bool = true, horizontalInset: CGFloat = 18,
         centersNoteWhenEmpty: Bool = false, auditRole: String = "active",
         host: LyricsRowExperimentHost? = nil) {
        self.model = model
        self.width = width
        self.rowHeight = rowHeight
        self.showsNote = showsNote
        self.horizontalInset = horizontalInset
        self.centersNoteWhenEmpty = centersNoteWhenEmpty
        self.auditRole = auditRole
        _host = StateObject(wrappedValue: host ?? LyricsRowExperimentHost())
    }

    private var availableWidth: CGFloat { max(1, width - (showsNote ? 22 : 0)) }
    private var identityKey: String {
        model.mediaRevisionIdentity + "\u{0}" + model.title + "\u{0}" + model.artist
    }
    /// Content width for the renderer/viewport. An empty line reports 0: the
    /// text area collapses so the note alone is centered, but the renderer
    /// stays mounted so its static-line boundary timer can wake the next lyric.
    private var resolvedWidth: CGFloat {
        guard let reported = host.contentWidth else { return availableWidth }
        return min(availableWidth, max(0, reported))
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
                                timeline: model.lyrics.timeline,
                                elapsed: model.elapsed,
                                sampledAt: model.elapsedSampleDate,
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
            } else {
                experimentRow
            }
        }
        .onAppear { host.begin(identity: identityKey) }
        .onChange(of: identityKey) { _, _ in host.begin(identity: identityKey) }
        .onChange(of: model.notchSurfaceOnScreen) { _, visible in
            if !visible { host.endPresentation() }
        }
        .onDisappear { host.invalidate() }
    }

    /// Union of the incoming and outgoing viewports so neither is clipped by
    /// the transition container; once the switch settles this equals the
    /// incoming width and the production geometry is unchanged.
    private var transitionWidth: CGFloat {
        max(resolvedWidth, host.outgoing?.viewportWidth ?? 0)
    }

    private var experimentRow: some View {
        HStack(spacing: 5) {
            if showsNote { noteIcon }
            if !model.lyrics.hasTimedLyrics {
                Color.clear.frame(width: availableWidth, height: 17)
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
                    NativeLyricsRowHost(snapshot: snapshot,
                                        active: model.notchSurfaceOnScreen,
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
                        // The whole 17pt viewport (with its horizontal clip
                        // and mask) moves; the outer rowHeight frame clips.
                        .frame(width: resolvedWidth, height: 17)
                        .offset(y: host.incomingOffset)
                        .opacity(host.incomingOpacity)
                }
                .frame(width: max(1, transitionWidth), height: 17, alignment: .topLeading)
                .offset(y: host.debugViewportOffsetY)
            }
        }
        .foregroundStyle(.gray)
        .frame(width: max(1, width), height: rowHeight,
               alignment: isLong ? .leading : .center)
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

private struct NativeLyricsRowHost: NSViewRepresentable {
    let snapshot: NativeLyricsRowSnapshot
    let active: Bool
    let host: LyricsRowExperimentHost
    let identity: String
    let failRender: Bool
    let onLineChange: (LyricLine?, NativeLyricsStaticLine?, UInt64, String) -> Void
    let onContentWidth: (CGFloat, UInt64, String) -> Void
    let onFailure: (UInt64, String) -> Void

    func makeNSView(context: Context) -> NativeLyricsRowView {
        let view = NativeLyricsRowView(frame: .zero)
        wire(view)
        view.setActive(active)
        view.apply(snapshot)
        return view
    }

    func updateNSView(_ view: NativeLyricsRowView, context: Context) {
        wire(view)
        view.setActive(active)
        view.apply(snapshot)
    }

    private func wire(_ view: NativeLyricsRowView) {
        // Establish the identity/generation synchronously before any renderer
        // callback can be produced; `.onAppear` may run after makeNSView.
        host.begin(identity: identity)
        let generation = host.generation
        let identity = host.identity
        let box = SwitchBox()
        view.onSwitchOutgoing = { box.outgoing = $0 }
        view.onLineChange = { line in
            let outgoing = box.outgoing
            box.outgoing = nil
            onLineChange(line, outgoing, generation, identity)
        }
        view.onContentWidthChange = { width in onContentWidth(width, generation, identity) }
        view.onRenderFailure = { onFailure(generation, identity) }
        view.debugFailImageRender = failRender ? [1] : []
    }

    static func dismantleNSView(_ view: NativeLyricsRowView, coordinator: ()) {
        view.stop()
    }
}
#endif
