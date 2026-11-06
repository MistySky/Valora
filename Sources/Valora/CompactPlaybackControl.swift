import AppKit
import SwiftUI
import QuartzCore
import CoreImage
import ReferenceCore

/// Compact-only evidence: 10020534c, 1002061c8, 1001fde28.
/// Both modes share the native renderer; each uses its recovered dimensions.
struct CompactPlaybackControl: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: RevivalSettings
    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    private var side: CGFloat {
        model.notchGeometry.hasPhysicalNotch || model.settings.forceSimulatedNotch ? 20 : 17
    }
    var body: some View {
        Button {
            model.media.command(2)
        } label: {
            ZStack {
                CompactWaveform(image:model.artwork, color:model.artworkColors.first ?? .gray.withAlphaComponent(0.8),
                    playing:model.playing, reducedMotion:reducedMotion, identity:(model.mediaRevisionIdentity.isEmpty ? model.mediaBundleIdentifier + "\u{1f}" + model.title + "\u{1f}" + model.artist : model.mediaRevisionIdentity))
                    .opacity(hovered ? 0 : 1)
                Image(systemName:model.playing ? "pause.fill" : "play.fill")
                    .foregroundStyle(.white).opacity(hovered ? 1 : 0)
            }.frame(width:side,height:side)
                .frame(maxWidth:.infinity,maxHeight:.infinity).contentShape(Rectangle())
        }.buttonStyle(.plain)
            .onHover { hovered = $0 }
            .onDisappear { hovered = false }
            .disabled(!model.previewMode && !model.mediaCanControl)
            .accessibilityLabel(model.playing ? "暂停" : "播放")
            .accessibilityIdentifier("compact.playPause")
            .help(model.playing ? "暂停播放" : "继续播放")
    }
}

struct CompactWaveform: NSViewRepresentable {
    let image: NSImage?
    let color: NSColor
    let playing: Bool
    let reducedMotion: Bool
    let identity: String
    var profile:WaveformProfile = .compact
    var suspended=false
    func makeNSView(context:Context) -> CompactWaveformView { CompactWaveformView() }
    func updateNSView(_ view:CompactWaveformView,context:Context) {
        view.configure(image:image,color:color,playing:playing,reducedMotion:reducedMotion,identity:identity,profile:profile,suspended:suspended)
    }
    static func dismantleNSView(_ view:CompactWaveformView,coordinator:()) { view.stop() }
}

struct PlayerWaveform:View {
    @ObservedObject var model:AppModel
    @ObservedObject var settings:RevivalSettings
    let active:Bool
    let translucent:Bool
    /// Lock-card ink palette; only consulted when `translucent` is set.
    var palette:LockCardPalette? = nil
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    var body:some View {
        CompactWaveform(image:translucent ? nil : model.artwork,
            color:translucent ? (NSColor(palette?.waveform ?? Color.gray.opacity(0.65))) : (model.artworkColors.first ?? .gray.withAlphaComponent(0.8)),
            playing:model.playing,reducedMotion:reducedMotion,
            identity:(model.mediaRevisionIdentity.isEmpty ? model.mediaBundleIdentifier+"\u{1f}"+model.title+"\u{1f}"+model.artist : model.mediaRevisionIdentity),
            profile:.expanded,suspended:!active)
            .accessibilityLabel(model.playing ? "正在播放" : "播放已暂停")
    }
}

/// Original NSWaveformView uses a masked artwork layer and native bounds
/// animations, not a SwiftUI per-frame sine wave (1003c5560 / 1003c5870).
/// Original artwork filters 1002d8f98: colorSaturate + gaussianBlur radius 6.
/// Public Core Image equivalents are rendered once per artwork/size change.
/// Core Image and the original private CA filters may differ at edge pixels.
@MainActor
final class CompactWaveformView: NSView {
    private static let seed = UInt64.random(in:UInt64.min...UInt64.max)
    private static let imageContext = CIContext(options:[.cacheIntermediates:false])
    private let texture = CALayer()
    private let whiteOverlay = CALayer()
    private let blackOverlay = CALayer()
    private let maskContainer = CALayer()
    private(set) var bars: [CALayer] = []
    private var registered = false
    private var lastTick: UInt64?
    private var playing = false
    private var reducedMotion = false
    private var suspended=false
    private var revision: UInt64 = 0
    private var previousImage: NSImage?
    private var profile:WaveformProfile = .compact
    private var textureSize = CGSize.zero
    private var positionedSize=CGSize.zero
    private var positionedProfile:WaveformProfile?
    private var positionedArtwork=false
    private(set) var textureRenderCount=0
    var hasArtworkTexture:Bool { texture.contents != nil }
    var isTicking: Bool { registered }
    override init(frame:NSRect) {
        super.init(frame:frame)
        wantsLayer = true
        layer?.addSublayer(texture)
        texture.contentsGravity = .resizeAspectFill
        texture.mask = maskContainer
        whiteOverlay.backgroundColor = NSColor.white.cgColor
        blackOverlay.backgroundColor = NSColor.black.cgColor
        whiteOverlay.opacity = 0
        blackOverlay.opacity = 0
        texture.addSublayer(whiteOverlay)
        texture.addSublayer(blackOverlay)
        rebuildBars()
    }
    private func rebuildBars() {
        for bar in bars { bar.removeFromSuperlayer() }
        bars=[]
        for _ in 0..<profile.count {
            let bar = CALayer()
            bar.backgroundColor = NSColor.white.cgColor
            bar.cornerRadius = profile.width / 2
            bar.cornerCurve = .continuous
            maskContainer.addSublayer(bar)
            bars.append(bar)
        }
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) has not been implemented") }
    func configure(image:NSImage?,color:NSColor,playing:Bool,reducedMotion:Bool,identity:String,profile:WaveformProfile = .compact,suspended:Bool=false) {
        let nextRevision = identity.utf8.reduce(UInt64(14695981039346656037)) { ($0 ^ UInt64($1)) &* 1099511628211 }
        let geometryChanged = self.profile != profile
        let revisionChanged = revision != nextRevision
        let changed = self.playing != playing || self.reducedMotion != reducedMotion || revisionChanged || geometryChanged || self.suspended != suspended
        self.suspended=suspended
        self.profile=profile
        if geometryChanged { rebuildBars(); textureSize = .zero; needsLayout=true }
        self.playing = playing; self.reducedMotion = reducedMotion; revision = nextRevision
        CATransaction.begin(); CATransaction.setDisableActions(true)
        texture.backgroundColor = color.cgColor
        if previousImage !== image {
            previousImage = image
            textureSize = .zero
            needsLayout=true
        }
        CATransaction.commit()
        if changed {
            if geometryChanged || revisionChanged { lastTick = nil }
            refresh(animated:!reducedMotion)
        }
        synchronizeTimer()
    }
    override func layout() {
        super.layout()
        let hasArtwork=previousImage != nil
        guard positionedSize != bounds.size || positionedProfile != profile || positionedArtwork != hasArtwork else {
            updateTexture()
            return
        }
        positionedSize=bounds.size;positionedProfile=profile;positionedArtwork=hasArtwork
        CATransaction.begin(); CATransaction.setDisableActions(true)
        // 1003c1b7c and 1003c2320: artwork occupies the bar envelope,
        // with horizontal (barWidth-spacing)/2 offset, not the whole view.
        let span = profile.span
        texture.frame = hasArtwork ? CGRect(x:(bounds.width-span)/2+(profile.width-profile.spacing)/2,
            y:(bounds.height-profile.height)/2,width:span,height:profile.height) : bounds
        maskContainer.frame = CGRect(x:-texture.frame.minX,y:-texture.frame.minY,width:bounds.width,height:bounds.height)
        let scale = window?.backingScaleFactor ?? 2
        for (i,bar) in bars.enumerated() {
            let x = (bounds.width-span)/2 + Double(i)*(profile.width+profile.spacing) + profile.width/2
            bar.position = CGPoint(x:(x*scale).rounded()/scale,y:(bounds.midY*scale).rounded()/scale)
        }
        CATransaction.commit()
        updateTexture()
        refresh(animated:false)
    }
    private func updateTexture() {
        guard textureSize != texture.bounds.size else { return }
        textureSize=texture.bounds.size
        guard let image=previousImage,textureSize.width>0,textureSize.height>0 else { texture.contents=nil; return }
        let scale=window?.backingScaleFactor ?? 2
        let w=max(1,Int((textureSize.width*scale).rounded())),h=max(1,Int((textureSize.height*scale).rounded()))
        guard let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:w,pixelsHigh:h,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0),
            let graphics=NSGraphicsContext(bitmapImageRep:bitmap) else { return }
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current=graphics
        let ratio=max(Double(w)/max(1,image.size.width),Double(h)/max(1,image.size.height))
        let size=NSSize(width:image.size.width*ratio,height:image.size.height*ratio)
        image.draw(in:NSRect(x:(Double(w)-size.width)/2,y:(Double(h)-size.height)/2,width:size.width,height:size.height),from:.zero,operation:.copy,fraction:1)
        NSGraphicsContext.restoreGraphicsState()
        guard let cg=bitmap.cgImage else { return }
        // 100102cac averages perceptual brightness over a 20px-wide raster;
        // 1002d7618 applies adaptive saturation, white and black overlays.
        let brightness=Self.artworkBrightness(image)
        let lighten=max(0,0.4-brightness),dim=max(0,brightness-0.5)
        let saturation=1.25+lighten*4
        textureRenderCount += 1
        CATransaction.begin(); CATransaction.setDisableActions(true)
        if texture.contents != nil {
            let fade=CATransition();fade.type = .fade;fade.duration=0.2
            texture.add(fade,forKey:"artwork")
        }
        if let filters = Self.artworkFilters(saturation:saturation) {
            // 1002d8f98: the original layer uses private CAFilters, not a
            // Core Image approximation: colorSaturate, gaussianBlur(6),
            // normalizeEdges. White/black overlays are separate layers.
            texture.filters = filters
            texture.contents = cg
            whiteOverlay.frame = texture.bounds
            blackOverlay.frame = texture.bounds
            whiteOverlay.opacity = Float(lighten)
            blackOverlay.opacity = Float(dim)
        } else {
            // Fallback for systems without the private CAFilter class.
            let input=CIImage(cgImage:cg)
            let gain=(1-lighten)*(1-dim),bias=lighten*(1-dim)
            let processed=input.applyingFilter("CIColorControls",parameters:[kCIInputSaturationKey:saturation])
                .clampedToExtent().applyingFilter("CIGaussianBlur",parameters:[kCIInputRadiusKey:6*scale]).cropped(to:input.extent)
                .applyingFilter("CIColorMatrix",parameters:["inputRVector":CIVector(x:gain,y:0,z:0,w:0),
                    "inputGVector":CIVector(x:0,y:gain,z:0,w:0),"inputBVector":CIVector(x:0,y:0,z:gain,w:0),
                    "inputBiasVector":CIVector(x:bias,y:bias,z:bias,w:0)])
            texture.filters = nil
            texture.contents=Self.imageContext.createCGImage(processed,from:input.extent)
            whiteOverlay.opacity = 0
            blackOverlay.opacity = 0
        }
        CATransaction.commit()
    }
    /// 1002d8f98: colorSaturate + gaussianBlur(radius 6) + normalizeEdges.
    /// CAFilter is private; resolve it at runtime and keep the CI fallback.
    private static func artworkFilters(saturation:Double) -> [Any]? {
        guard let cls = NSClassFromString("CAFilter") as? NSObject.Type else { return nil }
        func make(_ name:String,_ keys:[String:Any] = [:]) -> NSObject? {
            guard let object = cls.perform(NSSelectorFromString("filterWithName:"),with:name)?.takeUnretainedValue() as? NSObject else { return nil }
            for (key,value) in keys { object.setValue(value,forKey:key) }
            return object
        }
        let sat = make("colorSaturate",["inputSaturation":saturation])
        let blur = make("gaussianBlur",["inputRadius":6.0])
        let norm = make("normalizeEdges")
        guard let sat, let blur, let norm else { return nil }
        return [sat,blur,norm]
    }
    private static func artworkBrightness(_ image:NSImage)->Double {
        guard let cg=image.cgImage(forProposedRect:nil,context:nil,hints:nil),image.size.width>0,image.size.height>0 else { return 0.5 }
        let w=20,h=max(1,min(512,Int(image.size.height/image.size.width*20)))
        var pixels=[UInt8](repeating:0,count:w*h*4)
        let total:Double=pixels.withUnsafeMutableBytes { bytes in
            guard let context=CGContext(data:bytes.baseAddress,width:w,height:h,bitsPerComponent:8,bytesPerRow:w*4,
                space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else { return Double(w*h)*0.5 }
            context.interpolationQuality = .high
            context.draw(cg,in:CGRect(x:0,y:0,width:w,height:h))
            let p=bytes.bindMemory(to:UInt8.self)
            return stride(from:0,to:p.count,by:4).reduce(0.0) { sum,i in
                let r=Double(p[i])/255,g=Double(p[i+1])/255,b=Double(p[i+2])/255
                return sum+sqrt(0.2405*r*r+0.691*g*g+0.068*b*b)
            }
        }
        return total/Double(w*h)
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        synchronizeTimer()
    }
    func stop() {
        registered = false
        WaveformClock.shared.unregister(self)
    }
    private func synchronizeTimer() {
        guard window != nil,playing,!reducedMotion,!suspended else { stop(); return }
        registered = true
        WaveformClock.shared.register(self,duration:CompactWaveformMetrics.duration)
    }
    fileprivate func clockTick() {
        guard registered,playing,!reducedMotion,!suspended else { return }
        let tick = UInt64(max(0,(CACurrentMediaTime()-WaveformClock.epoch)/CompactWaveformMetrics.duration))
        guard tick != lastTick else { return }
        lastTick = tick
        refresh(animated:true)
    }
    private func refresh(animated:Bool) {
        let tick = UInt64(max(0,(CACurrentMediaTime()-WaveformClock.epoch)/CompactWaveformMetrics.duration))
        lastTick = tick
        for (i,bar) in bars.enumerated() {
            let height = playing ? CompactWaveformMetrics.amplitude(bar:i,tick:reducedMotion ? 0 : tick,seed:Self.seed,revision:revision,maximumHeight:Int(profile.height)) : 2
            let target = CGRect(x:0,y:0,width:profile.width,height:height)
            // 1003c5870: a normal playing tick animates from the previous
            // hash height; paused frames still read the presentation layer.
            let from: CGRect
            if playing {
                let previous = CompactWaveformMetrics.amplitude(bar:i,tick:tick > 0 ? tick-1 : 0,seed:Self.seed,revision:revision,maximumHeight:Int(profile.height))
                from = CGRect(x:0,y:0,width:profile.width,height:previous)
            } else {
                from = bar.presentation()?.bounds ?? bar.bounds
            }
            CATransaction.begin(); CATransaction.setDisableActions(true)
            bar.bounds = target
            CATransaction.commit()
            guard animated else { bar.removeAllAnimations(); continue }
            let animation: CABasicAnimation = playing ? CASpringAnimation(keyPath:"bounds") : CABasicAnimation(keyPath:"bounds")
            animation.fromValue = NSValue(rect:from); animation.toValue = NSValue(rect:target)
            animation.duration = playing ? CompactWaveformMetrics.duration : CompactWaveformMetrics.pauseDuration
            animation.preferredFrameRateRange=CAFrameRateRange(minimum:24,maximum:120,preferred:120)
            if !playing { animation.timingFunction = CAMediaTimingFunction(name:.easeOut) }
            bar.add(animation,forKey:"bounds")
        }
    }
}


/// 1003c64e0 / 1003c57c4: one global epoch and one-shot timer for every
/// mounted waveform, scheduled to the earliest next duration boundary.
/// Each view still computes its own tick from the shared epoch.
@MainActor
private final class WaveformClock {
    static let shared = WaveformClock()
    static let epoch = CACurrentMediaTime()
    private struct Entry { weak var view: CompactWaveformView?; var duration: Double }
    private var entries: [Entry] = []
    private var timer: Timer?
    func register(_ view: CompactWaveformView, duration: Double) {
        let interval = max(0.001,duration)
        if let index = entries.firstIndex(where:{ $0.view === view }) {
            if entries[index].duration == interval { return }
            entries[index].duration = interval
        } else {
            entries.removeAll { $0.view == nil }
            entries.append(Entry(view:view,duration:interval))
        }
        schedule()
    }
    func unregister(_ view: CompactWaveformView) {
        let oldCount = entries.count
        entries.removeAll { $0.view === view || $0.view == nil }
        if entries.count != oldCount { schedule() }
    }
    private func schedule() {
        timer?.invalidate(); timer = nil
        entries.removeAll { $0.view == nil }
        guard let duration = entries.map(\.duration).min() else { return }
        let now = CACurrentMediaTime()
        let phase = (now - Self.epoch).truncatingRemainder(dividingBy: duration)
        let delay = max(0.001, duration - phase)
        let next = Timer(timeInterval:delay,repeats:false) { [weak self] _ in
            MainActor.assumeIsolated { self?.fire() }
        }
        next.tolerance = min(0.01,delay*0.1)
        RunLoop.main.add(next,forMode:.common)
        timer = next
    }
    private func fire() {
        timer = nil
        let active = entries.compactMap(\.view)
        entries.removeAll { $0.view == nil }
        for view in active { view.clockTick() }
        schedule()
    }
}
