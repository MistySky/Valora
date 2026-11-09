#if VALORA_DEVELOPMENT || VALORA_LYRICS_EXPERIMENT
import AppKit
import QuartzCore
import SwiftUI
import ReferenceCore

/// Text rendering backend for the prototype row. The default keeps the
/// original CATextLayer path so the two can be compared side by side.
enum NativeLyricsTextBackend: String, Equatable {
    case coreText
    case swiftUI
}

/// Immutable input for one lyric row frame. The renderer draws only from this
/// value: it never observes `AppModel`, never queries the player and never
/// changes lyric state.
struct NativeLyricsRowSnapshot {
    var identity: LyricsTrackIdentity?
    var timeline: LyricTimeline?
    var elapsed: Double
    var sampledAt: Date
    var rate: Double
    var playing: Bool
    var duration: Double
    var width: CGFloat
    var rowHeight: CGFloat = 17
    var accent: NSColor = .white
    var textKern: CGFloat = 0
    var verticalOffset: CGFloat = -2
    var reduceMotion: Bool = false
    var textBackend: NativeLyricsTextBackend = .coreText
    /// When false the host owns the switch presentation (viewport moves) and
    /// the renderer only reports the outgoing static line.
    var switchAnimation: Bool = true
}

/// Frozen outgoing line (images + geometry) for the viewport transition.
struct NativeLyricsStaticLine {
    var lineKey: String
    var base: CGImage
    var accent: CGImage
    var pointSize: CGSize
    var maskWidth: CGFloat
    /// The frozen horizontal viewport width (the old line's clip width).
    var viewportWidth: CGFloat
    var positionX: CGFloat
    var positionY: CGFloat
    var imageScale: CGFloat
}

/// The shipped compact lyric text style, rendered once into a static image.
/// No extra kerning, stroke, weight change or shadow is added.
private struct StaticLyricText: View {
    let text: String
    let color: Color
    /// When set, the text is laid out inside exactly this row height, matching
    /// the production row container instead of inventing a baseline.
    var rowHeight: CGFloat? = nil
    var body: some View {
        let content = Text(text)
            .font(.system(size: 12, weight: .semibold))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(color)
        if let rowHeight {
            content.frame(height: rowHeight)
        } else {
            content
        }
    }
}

/// Native prototype of the visible lyric row. Not wired into production.
@MainActor
final class NativeLyricsRowView: NSView {
    private let clipLayer = CALayer()
    private let lineContainer = CALayer()
    private let baseLayer = CATextLayer()
    private let accentLayer = CATextLayer()
    private let baseImageLayer = CALayer()
    private let accentImageLayer = CALayer()
    private let maskLayer = CALayer()
    private lazy var textHost = NSHostingView(rootView: StaticLyricText(text: "", color: .gray))
    private var textHostWindow: NSWindow?
    private var textHostContainer: NSView?

    private var snapshot: NativeLyricsRowSnapshot?
    private var line: LyricLine?
    private var metrics: LyricsLineMetrics?
    private var lineEnd: TimeInterval = 0
    private var textSize: CGSize = .zero

    private var preparedText: String?
    private var preparedKern: CGFloat?
    private var preparedAccent: NSColor?
    private var preparedScale: CGFloat = 0
    private var preparedBackend: NativeLyricsTextBackend?
    private var imagePointSize: CGSize = .zero
    private var imagePixelSize: CGSize = .zero
    private var imageScale: CGFloat = 2
    private var preparedBaseImage: CGImage?
    private var preparedAccentImage: CGImage?
    private var laidOutWidth: CGFloat = -1
    private var laidOutHeight: CGFloat = -1
    private var laidOutOffset: CGFloat = .nan
    private var appliedFill: CGFloat = 0
    private var appliedOffset: CGFloat = 0
    private var appliedOriginX: CGFloat = -1
    private var appliedYOffset: CGFloat = 0
    private var contentOriginX: CGFloat = 0
    private var lastRenderDate = Date(timeIntervalSince1970: 0)
    private var injectedScale: CGFloat?
    var debugNow: (() -> Date)?
    var debugOffsetOverride: CGFloat?
    /// Geometry probe: vertical offset applied to the content container, used
    /// to observe the renderer's internal viewport clip statically.
    var debugContainerYOffset: CGFloat = 0
    /// Geometry probe: opacity applied to the content container.
    var debugContentOpacity: Double = 1

    private var active = false
    private var stopped = false
    private var boundaryWake: Timer?
    private var boundaryDeadlineUptime: TimeInterval?
    private var lastContinuous: Bool?
    var onLineChange: ((LyricLine?) -> Void)?
    var onRenderFailure: (() -> Void)?
    var onContentWidthChange: ((CGFloat) -> Void)?
    var onSwitchOutgoing: ((NativeLyricsStaticLine?) -> Void)?

    private var switchGeneration: UInt64 = 0
    private var outgoingLayer: CALayer?
    private var outgoingGeneration: UInt64 = 0

    private(set) var imageRenderFailed = false
    private(set) var imageRenderFailures = 0
    private(set) var imageRenderCalls = 0
    var debugFailImageRender: Set<Int> = []
    private var retryImagesOnNextSync = false

    var debugLine: LyricLine? { line }
    var debugFill: CGFloat { appliedFill }
    var debugOffset: CGFloat { appliedOffset }
    var debugLineEnd: TimeInterval { lineEnd }
    var debugTextWidth: CGFloat { textSize.width }
    var debugAccentColor: NSColor? { preparedAccent }
    var debugContentsScale: CGFloat { baseLayer.contentsScale }
    var debugTextFrameY: CGFloat { baseLayer.frame.minY }
    var debugLineKey: String { lastLineKey }
    var debugOutgoingLayers: Int { clipLayer.sublayers?.filter { $0 !== lineContainer }.count ?? 0 }
    var debugHasBoundaryWake: Bool { boundaryWake != nil }
    var debugBoundaryDelay: TimeInterval? {
        boundaryDeadlineUptime.map { max(0, $0 - ProcessInfo.processInfo.systemUptime) }
    }
    var debugIsClockRunning: Bool { NativeLyricsRowClock.shared.isRegistered(self) }
    var debugNeedsContinuousFrames: Bool { needsContinuousFrames }
    var debugLastRenderDate: Date { lastRenderDate }
    var debugBackend: NativeLyricsTextBackend { snapshot?.textBackend ?? .coreText }
    var debugUsesImageContents: Bool { !baseImageLayer.isHidden && baseImageLayer.contents != nil }
    var debugImagePointSize: CGSize { imagePointSize }
    var debugImagePixelSize: CGSize { imagePixelSize }
    var debugImageByteEstimate: Int {
        Int(imagePixelSize.width * imagePixelSize.height * 4)
            * (accentImageLayer.contents == nil ? 1 : 2)
    }
    var debugOutgoingHasImage: Bool {
        clipLayer.sublayers?.contains { layer in
            layer !== lineContainer && layer.sublayers?.contains { $0.contents != nil } == true
        } ?? false
    }
    var debugHostingViewInWindow: Bool { textHost.window != nil }
    var debugImageRenderFailed: Bool { imageRenderFailed }
    var debugContainerPosition: CGPoint { lineContainer.position }
    var debugImageLayerPosition: CGPoint { baseImageLayer.position }
    var debugHasActiveSwitchAnimation: Bool {
        (lineContainer.animationKeys()?.isEmpty == false) || (outgoingLayer != nil)
    }
    var debugHasOutgoing: Bool { outgoingLayer != nil }

    private(set) var frameTicks = 0
    private(set) var maskUpdates = 0
    private(set) var textBuilds = 0
    private(set) var layoutPasses = 0
    private(set) var lineSwitchAnimations = 0
    private(set) var lastLineKey = ""
    private(set) var imageBuilds = 0
    private(set) var hostingLayouts = 0
    private(set) var rootViewUpdates = 0
    private(set) var captureWindowCreations = 0
    private(set) var captureWindowCloses = 0
    static private(set) var liveCaptureWindows = 0
    static var debugLiveCaptureWindows: Int { liveCaptureWindows }

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.isGeometryFlipped = true
        clipLayer.isGeometryFlipped = true
        clipLayer.masksToBounds = true
        lineContainer.isGeometryFlipped = true
        layer?.addSublayer(clipLayer)
        clipLayer.addSublayer(lineContainer)
        lineContainer.addSublayer(baseLayer)
        lineContainer.addSublayer(accentLayer)
        baseLayer.foregroundColor = NSColor.gray.cgColor
        lineContainer.anchorPoint = .zero
        lineContainer.position = .zero
        maskLayer.anchorPoint = .zero
        maskLayer.position = .zero
        accentLayer.mask = maskLayer
        maskLayer.backgroundColor = NSColor.white.cgColor
        baseLayer.contentsScale = 2
        accentLayer.contentsScale = 2
        baseImageLayer.isHidden = true
        accentImageLayer.isHidden = true
        for layer in [baseImageLayer, accentImageLayer] {
            layer.anchorPoint = .zero
            layer.position = .zero
            layer.contentsGravity = .resize
            lineContainer.addSublayer(layer)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func setActive(_ value: Bool) {
        let wasActive = active
        active = value
        stopped = !value
        guard value else { shutDownClocks(); return }
        if !wasActive { update(at: currentDisplayTime()) }
        synchronizeClock(force: !wasActive)
    }

    func apply(_ snapshot: NativeLyricsRowSnapshot) {
        let previous = self.snapshot
        self.snapshot = snapshot
        stopped = false
        if previous?.identity != snapshot.identity {
            switchGeneration &+= 1
        }
        retryImagesOnNextSync = true
        update(at: displayTime(for: snapshot))
        retryImagesOnNextSync = false
    }

    func render(at date: Date) { update(at: date) }

    /// Geometry probe: move the content container and redraw immediately.
    func debugSetContainerYOffset(_ value: CGFloat) {
        debugContainerYOffset = value
        render(at: lastRenderDate)
    }

    /// Isolated harness: pretend the surface moved to another backing scale.
    func debugSetBackingScale(_ scale: CGFloat) {
        injectedScale = scale
        guard let snapshot else { return }
        synchronizeDrawing(snapshot)
    }

    private func currentDisplayTime() -> Date { debugNow?() ?? Date() }

    private func displayTime(for snapshot: NativeLyricsRowSnapshot) -> Date {
        _ = snapshot
        return currentDisplayTime()
    }

    private func update(at date: Date) {
        lastRenderDate = date
        guard let snapshot else { return }
        frameTicks += 1
        let elapsed = LyricsPlaybackClock(anchorElapsed: snapshot.elapsed,
                                          anchorDate: snapshot.sampledAt,
                                          rate: snapshot.rate,
                                          playing: snapshot.playing).elapsed(at: date)
        let nextLine = snapshot.timeline?.line(at: elapsed)
        if nextLine != line {
            switchLine(to: nextLine, snapshot: snapshot)
        }
        synchronizeDrawing(snapshot)
        refreshLineEnd(snapshot)
        draw(at: elapsed)
        synchronizeClock()
    }

    private func switchLine(to nextLine: LyricLine?, snapshot: NativeLyricsRowSnapshot) {
        let outgoingStatic = snapshot.switchAnimation ? nil : frozenImageLine()
        let outgoing: CALayer? = snapshot.switchAnimation && (line != nil && nextLine != nil)
            ? snapshotOfLine() : nil
        line = nextLine
        metrics = nextLine.map { LyricsLineMetrics(line: $0) }
        lastLineKey = nextLine.map { "\($0.start)-\($0.text)" } ?? ""
        buildTextLayers(snapshot: snapshot)
        refreshLineEnd(snapshot)
        if let outgoing {
            animateSwitch(outgoing: outgoing, snapshot: snapshot)
        }
        if !snapshot.switchAnimation {
            onSwitchOutgoing?(outgoingStatic)
        }
        onLineChange?(nextLine)
    }

    private func refreshLineEnd(_ snapshot: NativeLyricsRowSnapshot) {
        guard let line else { lineEnd = 0; return }
        let next = LyricsLineFrameCache.nextStart(in: snapshot.timeline?.lines ?? [],
                                                  after: line.start)
        lineEnd = next ?? max(line.start + 8,
                              snapshot.duration > line.start ? snapshot.duration : line.start + 8)
    }

    private func draw(at elapsed: TimeInterval) {
        guard let snapshot, let line, let metrics else { return }
        let current = metrics.currentWord(at: elapsed, line: line)
        let fill = LyricsLineLayout.fillWidth(
            prefixWidth: current.map { metrics.prefixes[safe: $0.index] ?? 0 } ?? 0,
            currentWordWidth: current.map { metrics.wordWidths[safe: $0.index] ?? 0 } ?? 0,
            fraction: current?.fraction ?? 0,
            totalWidth: metrics.totalWidth)
        let fillContainer = metrics.totalWidth > snapshot.width
        let offset: CGFloat
        if fillContainer, let current, current.index < metrics.prefixes.count {
            offset = LyricsLineLayout.followingOffset(
                prefixWidth: metrics.prefixes[current.index],
                currentWordWidth: metrics.wordWidths[current.index],
                fraction: current.fraction, totalWidth: metrics.totalWidth,
                availableWidth: snapshot.width)
        } else if fillContainer, line.words.isEmpty, lineEnd > line.start {
            let raw = min(1, max(0, (elapsed - line.start) / (lineEnd - line.start)))
            let hold = 0.15
            let progress = max(0, min(1, (raw - hold) / (1 - hold)))
            offset = LyricsLineLayout.lineOnlyOffset(progress: progress,
                                                     totalWidth: metrics.totalWidth,
                                                     availableWidth: snapshot.width)
        } else {
            offset = 0
        }
        let renderOffset = debugOffsetOverride ?? offset
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if fill != appliedFill {
            maskLayer.bounds = CGRect(x: 0, y: 0, width: max(0, fill), height: textSize.height)
            appliedFill = fill
            maskUpdates += 1
        }
        if lineContainer.opacity != Float(debugContentOpacity) {
            lineContainer.opacity = Float(debugContentOpacity)
        }
        if renderOffset != appliedOffset || contentOriginX != appliedOriginX
            || debugContainerYOffset != appliedYOffset {
            lineContainer.position = CGPoint(x: contentOriginX - renderOffset,
                                             y: debugContainerYOffset)
            appliedOffset = renderOffset
            appliedOriginX = contentOriginX
            appliedYOffset = debugContainerYOffset
        }
        CATransaction.commit()
    }

    // MARK: - Invalidation

    private func synchronizeDrawing(_ snapshot: NativeLyricsRowSnapshot) {
        if imageRenderFailed, retryImagesOnNextSync {
            buildTextLayers(snapshot: snapshot)
            return
        }
        let scale = injectedScale ?? window?.backingScaleFactor ?? 2
        let text = line?.text ?? ""
        let backend = snapshot.textBackend
        let accentChanged = !(snapshot.accent.isEqual(preparedAccent))
        let textChanged = backend == .swiftUI
            ? text != preparedText
            : (text != preparedText || snapshot.textKern != preparedKern)
        let backendChanged = preparedBackend != backend
        let scaleChanged = scale != preparedScale
        if backendChanged || textChanged {
            buildTextLayers(snapshot: snapshot)
        } else if accentChanged {
            if backend == .swiftUI {
                buildTextLayers(snapshot: snapshot)
            } else {
                accentLayer.string = attributed(for: text, color: snapshot.accent,
                                                kern: snapshot.textKern)
                preparedAccent = snapshot.accent
            }
        } else if scaleChanged {
            if backend == .swiftUI {
                buildTextLayers(snapshot: snapshot)
            } else {
                preparedScale = scale
                baseLayer.contentsScale = scale
                accentLayer.contentsScale = scale
                maskLayer.contentsScale = scale
            }
        }
        if snapshot.width != laidOutWidth || snapshot.rowHeight != laidOutHeight
            || snapshot.verticalOffset != laidOutOffset || backendChanged {
            layoutLine(snapshot)
        }
    }

    private func buildTextLayers(snapshot: NativeLyricsRowSnapshot) {
        let text = line?.text ?? ""
        if text.isEmpty {
            clearTextVisuals()
            preparedText = text
            preparedKern = snapshot.textKern
            preparedAccent = snapshot.accent
            preparedBackend = snapshot.textBackend
            onContentWidthChange?(0)
            textBuilds += 1
            layoutLine(snapshot)
            return
        }
        switch snapshot.textBackend {
        case .coreText: buildCoreTextLayers(snapshot)
        case .swiftUI: buildTextImages(snapshot)
        }
        preparedBackend = snapshot.textBackend
        textBuilds += 1
        layoutLine(snapshot)
    }

    private func clearTextVisuals() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        baseLayer.string = nil
        accentLayer.string = nil
        baseLayer.isHidden = true
        accentLayer.isHidden = true
        baseImageLayer.contents = nil
        accentImageLayer.contents = nil
        baseImageLayer.isHidden = true
        accentImageLayer.isHidden = true
        preparedBaseImage = nil
        preparedAccentImage = nil
        maskLayer.bounds = .zero
        lineContainer.removeAllAnimations()
        lineContainer.position = .zero
        textSize = .zero
        imagePointSize = .zero
        imagePixelSize = .zero
        appliedFill = 0
        appliedOffset = 0
        appliedOriginX = -1
        CATransaction.commit()
    }

    private func buildCoreTextLayers(_ snapshot: NativeLyricsRowSnapshot) {
        let text = line?.text ?? ""
        baseLayer.isHidden = false
        accentLayer.isHidden = false
        baseImageLayer.isHidden = true
        accentImageLayer.isHidden = true
        accentImageLayer.mask = nil
        accentLayer.mask = maskLayer
        baseLayer.string = attributed(for: text, color: .gray, kern: snapshot.textKern)
        accentLayer.string = attributed(for: text, color: snapshot.accent, kern: snapshot.textKern)
        for layer in [baseLayer, accentLayer] {
            layer.isWrapped = false
            layer.truncationMode = .none
            layer.alignmentMode = .left
        }
        let scale = injectedScale ?? window?.backingScaleFactor ?? 2
        preparedScale = scale
        baseLayer.contentsScale = scale
        accentLayer.contentsScale = scale
        maskLayer.contentsScale = scale
        textSize = (baseLayer.string as? NSAttributedString)?.size() ?? .zero
        onContentWidthChange?(textSize.width)
        imagePointSize = .zero
        imagePixelSize = .zero
        preparedText = text
        preparedKern = snapshot.textKern
        preparedAccent = snapshot.accent
    }

    private func buildTextImages(_ snapshot: NativeLyricsRowSnapshot) {
        let text = line?.text ?? ""
        let scale = injectedScale ?? window?.backingScaleFactor ?? 2
        prepareTextHostWindow()
        textHost.rootView = StaticLyricText(text: text, color: .gray)
        rootViewUpdates += 1
        textHost.frame = CGRect(x: 0, y: 0, width: 900, height: max(1, snapshot.rowHeight))
        textHost.layoutSubtreeIfNeeded()
        hostingLayouts += 1
        let measured = textHost.fittingSize
        let rowHeight = snapshot.rowHeight
        let imageSize = CGSize(width: measured.width, height: rowHeight)
        guard measured.width > 0, measured.height > 0 else {
            failTextImages(snapshot, reason: "empty measure")
            return
        }
        imageRenderCalls = 0
        guard let baseImage = renderTextImage(StaticLyricText(text: text, color: .gray,
                                                              rowHeight: rowHeight),
                                              size: imageSize, scale: scale),
              let accentImage = renderTextImage(StaticLyricText(text: text,
                                                                color: Color(nsColor: snapshot.accent),
                                                                rowHeight: rowHeight),
                                                size: imageSize, scale: scale) else {
            failTextImages(snapshot, reason: "image capture failed")
            return
        }
        baseLayer.isHidden = true
        accentLayer.isHidden = true
        baseImageLayer.isHidden = false
        accentImageLayer.isHidden = false
        accentLayer.mask = nil
        accentImageLayer.mask = maskLayer
        preparedBaseImage = baseImage
        preparedAccentImage = accentImage
        baseImageLayer.contents = baseImage
        baseImageLayer.contentsScale = scale
        baseImageLayer.bounds = CGRect(origin: .zero, size: imageSize)
        accentImageLayer.contents = accentImage
        accentImageLayer.contentsScale = scale
        accentImageLayer.bounds = CGRect(origin: .zero, size: imageSize)
        maskLayer.contentsScale = scale
        imageScale = scale
        textSize = CGSize(width: measured.width, height: rowHeight)
        onContentWidthChange?(measured.width)
        imagePointSize = imageSize
        imagePixelSize = CGSize(width: ceil(imageSize.width * scale),
                                height: ceil(imageSize.height * scale))
        preparedScale = scale
        preparedText = text
        preparedKern = snapshot.textKern
        preparedAccent = snapshot.accent
        imageRenderFailed = false
    }

    private func failTextImages(_ snapshot: NativeLyricsRowSnapshot, reason: String) {
        imageRenderFailed = true
        imageRenderFailures += 1
        clearTextVisuals()
        switchGeneration &+= 1
        outgoingLayer?.removeFromSuperlayer()
        outgoingLayer = nil
        preparedText = line?.text ?? ""
        preparedKern = snapshot.textKern
        preparedAccent = snapshot.accent
        preparedBackend = snapshot.textBackend
        retryImagesOnNextSync = false
        onRenderFailure?()
        NSLog("NativeLyricsRow: SwiftUI text image preparation failed (%@)", reason)
    }

    private func attributed(for text: String, color: NSColor, kern: CGFloat) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .kern: kern,
            .foregroundColor: color
        ])
    }

    private func prepareTextHostWindow() {
        guard textHostWindow == nil else { return }
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 1000, height: 40))
        container.addSubview(textHost)
        let window = NSWindow(contentRect: container.frame, styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
        window.contentView = container
        window.orderFrontRegardless()
        textHostWindow = window
        textHostContainer = container
        captureWindowCreations += 1
        Self.liveCaptureWindows += 1
    }

    private func releaseCaptureWindow() {
        guard let window = textHostWindow else { return }
        textHost.removeFromSuperview()
        window.contentView = nil
        window.close()
        textHostWindow = nil
        textHostContainer = nil
        captureWindowCloses += 1
        Self.liveCaptureWindows = max(0, Self.liveCaptureWindows - 1)
    }

    private func renderTextImage(_ view: StaticLyricText, size: CGSize,
                                 scale: CGFloat) -> CGImage? {
        imageRenderCalls += 1
        if debugFailImageRender.contains(imageRenderCalls) { return nil }
        prepareTextHostWindow()
        textHost.rootView = view
        rootViewUpdates += 1
        textHost.frame = CGRect(origin: .zero, size: size)
        textHost.layoutSubtreeIfNeeded()
        hostingLayouts += 1
        let w = Int(ceil(size.width * scale))
        let h = Int(ceil(size.height * scale))
        guard w > 0, h > 0,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                         isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = size
        textHost.cacheDisplay(in: CGRect(origin: .zero, size: size), to: rep)
        imageBuilds += 1
        return rep.cgImage
    }

    private func layoutLine(_ snapshot: NativeLyricsRowSnapshot) {
        let usesImages = snapshot.textBackend == .swiftUI
        let h = min(snapshot.rowHeight, max(textSize.height, 1))
        let y = usesImages ? 0 : (snapshot.rowHeight - h) / 2 + snapshot.verticalOffset
        contentOriginX = textSize.width > snapshot.width ? 0
            : max(0, (snapshot.width - textSize.width) / 2)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        clipLayer.frame = CGRect(x: 0, y: 0, width: max(1, snapshot.width), height: snapshot.rowHeight)
        lineContainer.frame = CGRect(x: 0, y: 0, width: max(1, textSize.width), height: max(1, h))
        lineContainer.position = CGPoint(x: contentOriginX - appliedOffset, y: 0)
        appliedOriginX = contentOriginX
        let frame = CGRect(x: 0, y: y, width: max(1, textSize.width), height: max(1, h))
        baseLayer.frame = frame
        accentLayer.frame = frame
        for layer in [baseImageLayer, accentImageLayer] {
            layer.bounds = CGRect(origin: .zero, size: textSize)
            layer.position = CGPoint(x: 0, y: y)
        }
        maskLayer.bounds = CGRect(x: 0, y: 0, width: max(0, appliedFill), height: max(1, h))
        CATransaction.commit()
        laidOutWidth = snapshot.width
        laidOutHeight = snapshot.rowHeight
        laidOutOffset = snapshot.verticalOffset
        layoutPasses += 1
    }

    override func layout() {
        super.layout()
        guard let snapshot else { return }
        layoutLine(snapshot)
        update(at: max(lastRenderDate, currentDisplayTime()))
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window?.backingScaleFactor != preparedScale else { return }
        if let snapshot {
            synchronizeDrawing(snapshot)
            layoutLine(snapshot)
            draw(at: LyricsPlaybackClock(anchorElapsed: snapshot.elapsed,
                                         anchorDate: snapshot.sampledAt,
                                         rate: snapshot.rate,
                                         playing: snapshot.playing).elapsed(at: currentDisplayTime()))
        }
    }

    // MARK: - Line switch animation

    private func snapshotOfLine() -> CALayer? {
        if snapshot?.textBackend == .swiftUI { return snapshotOfImageLine() }
        guard let base = baseLayer.string as? NSAttributedString,
              let accent = accentLayer.string as? NSAttributedString else { return nil }
        let container = CALayer()
        container.isGeometryFlipped = true
        container.anchorPoint = .zero
        container.bounds = CGRect(x: 0, y: 0, width: max(1, textSize.width),
                                  height: max(1, textSize.height))
        container.position = CGPoint(x: contentOriginX - appliedOffset, y: 0)
        let outBase = CATextLayer()
        let outAccent = CATextLayer()
        for (layer, string) in [(outBase, base), (outAccent, accent)] {
            layer.string = string
            layer.isWrapped = false
            layer.truncationMode = .none
            layer.alignmentMode = .left
            layer.contentsScale = baseLayer.contentsScale
            layer.frame = baseLayer.frame
            container.addSublayer(layer)
        }
        let mask = CALayer()
        mask.anchorPoint = .zero
        mask.position = .zero
        mask.backgroundColor = NSColor.white.cgColor
        mask.bounds = maskLayer.bounds
        outAccent.mask = mask
        return container
    }

    private func snapshotOfImageLine() -> CALayer? {
        guard let base = baseImageLayer.contents, let accent = accentImageLayer.contents else {
            return nil
        }
        let container = CALayer()
        container.isGeometryFlipped = true
        container.anchorPoint = .zero
        container.bounds = CGRect(origin: .zero, size: textSize)
        container.position = CGPoint(x: contentOriginX - appliedOffset, y: 0)
        let outBase = CALayer()
        let outAccent = CALayer()
        for (layer, contents) in [(outBase, base), (outAccent, accent)] {
            layer.anchorPoint = .zero
            layer.contents = contents
            layer.contentsScale = imageScale
            layer.contentsGravity = .resize
            layer.bounds = CGRect(origin: .zero, size: textSize)
            layer.position = baseImageLayer.position
            container.addSublayer(layer)
        }
        let mask = CALayer()
        mask.anchorPoint = .zero
        mask.position = .zero
        mask.backgroundColor = NSColor.white.cgColor
        mask.bounds = maskLayer.bounds
        outAccent.mask = mask
        return container
    }

    private func frozenImageLine() -> NativeLyricsStaticLine? {
        guard let base = preparedBaseImage, let accent = preparedAccentImage,
              !lastLineKey.isEmpty else { return nil }
        return NativeLyricsStaticLine(lineKey: lastLineKey, base: base, accent: accent,
                                      pointSize: textSize,
                                      maskWidth: maskLayer.bounds.width,
                                      viewportWidth: max(1, clipLayer.bounds.width),
                                      positionX: lineContainer.position.x,
                                      positionY: lineContainer.position.y,
                                      imageScale: imageScale)
    }

    private func animateSwitch(outgoing: CALayer, snapshot: NativeLyricsRowSnapshot) {
        switchGeneration &+= 1
        let generation = switchGeneration
        lineSwitchAnimations += 1
        outgoingLayer?.removeFromSuperlayer()
        outgoing.removeFromSuperlayer()
        clipLayer.addSublayer(outgoing)
        outgoingLayer = outgoing
        outgoingGeneration = generation
        let duration: CFTimeInterval = 0.2
        let timing = CAMediaTimingFunction(name: .easeInEaseOut)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        outgoing.opacity = 0
        outgoing.transform = CATransform3DMakeTranslation(0, -26, 0)
        lineContainer.opacity = 1
        lineContainer.transform = CATransform3DIdentity
        CATransaction.commit()
        let outMove = CABasicAnimation(keyPath: "transform.translation.y")
        outMove.fromValue = 0
        outMove.toValue = -26
        outMove.duration = duration
        outMove.timingFunction = timing
        let outFade = CABasicAnimation(keyPath: "opacity")
        outFade.fromValue = 1
        outFade.toValue = 0
        outFade.duration = duration
        outFade.timingFunction = timing
        let inMove = CABasicAnimation(keyPath: "transform.translation.y")
        inMove.fromValue = 26
        inMove.toValue = 0
        inMove.duration = duration
        inMove.timingFunction = timing
        let inFade = CABasicAnimation(keyPath: "opacity")
        inFade.fromValue = 0
        inFade.toValue = 1
        inFade.duration = duration
        inFade.timingFunction = timing
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        outgoing.add(outMove, forKey: "switchOutMove")
        outgoing.add(outFade, forKey: "switchOutFade")
        lineContainer.add(inMove, forKey: "switchInMove")
        lineContainer.add(inFade, forKey: "switchInFade")
        CATransaction.commit()
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.05) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, generation == self.switchGeneration,
                      self.outgoingGeneration == generation else { return }
                self.outgoingLayer?.removeFromSuperlayer()
                self.outgoingLayer = nil
                self.lineContainer.removeAnimation(forKey: "switchInMove")
                self.lineContainer.removeAnimation(forKey: "switchInFade")
                guard self.active, !self.stopped else { return }
                self.update(at: max(self.currentDisplayTime(), self.lastRenderDate))
            }
        }
        _ = snapshot
    }

    // MARK: - Clock

    private var needsContinuousFrames: Bool {
        guard let snapshot, let line, let metrics else { return false }
        guard snapshot.playing, snapshot.rate > 0 else { return false }
        if !line.words.isEmpty { return true }
        return metrics.totalWidth > snapshot.width
    }

    private func synchronizeClock(force: Bool = false) {
        if active && needsContinuousFrames {
            boundaryWake?.invalidate()
            boundaryWake = nil
            boundaryDeadlineUptime = nil
            lastContinuous = true
            NativeLyricsRowClock.shared.register(self)
            return
        }
        NativeLyricsRowClock.shared.unregister(self)
        lastContinuous = false
        guard active, let deadline = computedBoundaryDeadlineUptime() else {
            boundaryWake?.invalidate()
            boundaryWake = nil
            boundaryDeadlineUptime = nil
            return
        }
        if !force, let current = boundaryDeadlineUptime,
           abs(current - deadline) < 0.02, boundaryWake != nil {
            return
        }
        boundaryWake?.invalidate()
        boundaryDeadlineUptime = deadline
        let delay = max(0.02, deadline - ProcessInfo.processInfo.systemUptime)
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.boundaryFired() }
        }
        timer.tolerance = 0.01
        RunLoop.main.add(timer, forMode: .common)
        boundaryWake = timer
    }

    private func computedBoundaryDeadlineUptime() -> TimeInterval? {
        guard let snapshot, snapshot.playing, snapshot.rate > 0,
              let timeline = snapshot.timeline else { return nil }
        let now = currentDisplayTime()
        let elapsedNow = LyricsPlaybackClock(anchorElapsed: snapshot.elapsed,
                                              anchorDate: snapshot.sampledAt,
                                              rate: snapshot.rate,
                                              playing: true).elapsed(at: now)
        let boundary = line.map {
            LyricsLineFrameCache.nextStart(in: timeline.lines, after: $0.start)
        } ?? Self.nextStart(in: timeline.lines, atOrAfter: elapsedNow)
        guard let boundary, boundary > elapsedNow else { return nil }
        return ProcessInfo.processInfo.systemUptime + (boundary - elapsedNow) / snapshot.rate
    }

    private func shutDownClocks() {
        boundaryWake?.invalidate()
        boundaryWake = nil
        boundaryDeadlineUptime = nil
        lastContinuous = nil
        NativeLyricsRowClock.shared.unregister(self)
        switchGeneration &+= 1
        outgoingLayer?.removeFromSuperlayer()
        outgoingLayer = nil
        lineContainer.removeAllAnimations()
    }

    private func boundaryFired() {
        boundaryWake = nil
        boundaryDeadlineUptime = nil
        guard active, !stopped, snapshot != nil else { return }
        update(at: currentDisplayTime())
    }

    static func nextStart(in lines: [LyricLine], atOrAfter elapsed: TimeInterval) -> TimeInterval? {
        guard !lines.isEmpty else { return nil }
        var low = 0
        var high = lines.count
        while low < high {
            let mid = (low + high) / 2
            if lines[mid].start >= elapsed { high = mid } else { low = mid + 1 }
        }
        return low < lines.count ? lines[low].start : nil
    }

    func stop() {
        active = false
        stopped = true
        shutDownClocks()
        baseImageLayer.contents = nil
        accentImageLayer.contents = nil
        baseImageLayer.isHidden = true
        accentImageLayer.isHidden = true
        imagePointSize = .zero
        imagePixelSize = .zero
        preparedText = nil
        preparedKern = nil
        preparedBackend = nil
        releaseCaptureWindow()
    }

    isolated deinit {
        boundaryWake?.invalidate()
        NativeLyricsRowClock.shared.unregister(self)
        textHostWindow?.contentView = nil
        textHostWindow?.close()
    }

    fileprivate func clockTick() {
        guard active, !stopped, needsContinuousFrames else { return }
        update(at: currentDisplayTime())
    }
}

/// One shared 30Hz clock for every prototype row.
@MainActor
final class NativeLyricsRowClock {
    static let shared = NativeLyricsRowClock()
    static let interval: TimeInterval = 1.0 / 30.0
    private var entries: [ObjectIdentifier: WeakView] = [:]
    private var timer: Timer?

    private struct WeakView { weak var view: NativeLyricsRowView? }

    func register(_ view: NativeLyricsRowView) {
        entries[ObjectIdentifier(view)] = WeakView(view: view)
        startIfNeeded()
    }

    func unregister(_ view: NativeLyricsRowView) {
        entries.removeValue(forKey: ObjectIdentifier(view))
        if entries.isEmpty { stop() }
    }

    func isRegistered(_ view: NativeLyricsRowView) -> Bool {
        entries[ObjectIdentifier(view)]?.view === view
    }

    private func startIfNeeded() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: Self.interval, repeats: true) { _ in
            MainActor.assumeIsolated { NativeLyricsRowClock.shared.fire() }
        }
        timer.tolerance = 0.002
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func fire() {
        entries = entries.filter { $0.value.view != nil }
        let views = entries.compactMap(\.value.view)
        guard !views.isEmpty else { stop(); return }
        for view in views { view.clockTick() }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

#if VALORA_DEVELOPMENT
/// Debug-only SwiftUI wrapper so the prototype can be mounted in isolation.
struct NativeLyricsRowPreview: View {
    let snapshot: NativeLyricsRowSnapshot
    var active: Bool = true
    @State private var currentLine: LyricLine?
    var body: some View {
        NativeLyricsRowRepresentable(snapshot: snapshot, active: active, line: $currentLine)
            .frame(width: max(1, snapshot.width), height: snapshot.rowHeight)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(currentLine?.text
                                ?? snapshot.timeline?.line(at: snapshot.elapsed)?.text
                                ?? "歌词")
            .accessibilityIdentifier("compact.lyrics.native-preview")
    }
}

private struct NativeLyricsRowRepresentable: NSViewRepresentable {
    let snapshot: NativeLyricsRowSnapshot
    let active: Bool
    @Binding var line: LyricLine?
    func makeNSView(context: Context) -> NativeLyricsRowView {
        let view = NativeLyricsRowView(frame: .zero)
        view.onLineChange = { newLine in
            DispatchQueue.main.async { line = newLine }
        }
        view.setActive(active)
        view.apply(snapshot)
        return view
    }
    func updateNSView(_ view: NativeLyricsRowView, context: Context) {
        view.onLineChange = { newLine in
            DispatchQueue.main.async { line = newLine }
        }
        view.setActive(active)
        view.apply(snapshot)
    }
    static func dismantleNSView(_ view: NativeLyricsRowView, coordinator: ()) {
        view.stop()
    }
}
#endif
#endif
