import AppKit
import QuartzCore
import SwiftUI
import ReferenceCore

/// Native, text-only part of the recovered marquee. Title badges and the
/// centered-layout alignment spring are not implemented by this component.
struct MarqueeLabel: NSViewRepresentable {
    var text: String
    var size: CGFloat
    var weight: NSFont.Weight
    var color: NSColor
    var longestTextWidth: CGFloat
    var active: Bool = true
    var paused: Bool = false
    var cycleStart: CFTimeInterval = 0
    var onDoubleClick: (() -> Void)? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    static func measure(_ text:String,size:CGFloat,weight:NSFont.Weight)->CGSize {
        (text as NSString).size(withAttributes:[.font:NSFont.systemFont(ofSize:size,weight:weight),.kern:0.05])
    }
    func makeNSView(context:Context)->MarqueeLabelView { MarqueeLabelView(frame:.zero) }
    func updateNSView(_ view:MarqueeLabelView,context:Context) {
        view.onDoubleClick = onDoubleClick
        view.configure(text:text,size:size,weight:weight,color:color,longestWidth:longestTextWidth,reduceMotion:reduceMotion,active:active,paused:paused,cycleStart:cycleStart)
    }
    func sizeThatFits(_ proposal:ProposedViewSize,nsView:MarqueeLabelView,context:Context)->CGSize? {
        let measured = Self.measure(text,size:size,weight:weight)
        return CGSize(width:proposal.width ?? measured.width+4.5,height:measured.height)
    }
    static func dismantleNSView(_ view:MarqueeLabelView,coordinator:()) {
        view.onDoubleClick = nil
        view.stop()
    }
}

@MainActor
final class MarqueeLabelView: NSView {
    var onDoubleClick: (() -> Void)?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { onDoubleClick != nil }
    override func mouseDown(with event: NSEvent) {
        guard let onDoubleClick else { super.mouseDown(with: event); return }
        if event.clickCount == 2 { onDoubleClick() }
    }
    private let content = CALayer()
    private let gradient = CAGradientLayer()
    private var text = ""
    private var size:CGFloat = 13.5
    private var weight:NSFont.Weight = .semibold
    private var textColor = NSColor.white
    private var longestWidth:CGFloat = 0
    private var reduceMotion = false
    private var active = true
    private var paused = false
    private var cycleStart: CFTimeInterval = 0
    private var lastOverflow = false
    private var needsRebuild = true
    private var lastScale:CGFloat = -1
    override var isFlipped:Bool { true }
    override var intrinsicContentSize:NSSize {
        let measured = MarqueeLabel.measure(text,size:size,weight:weight)
        return NSSize(width:measured.width+4.5,height:measured.height)
    }
    override init(frame:NSRect) {
        super.init(frame:frame)
        wantsLayer=true
        layer?.masksToBounds=true
        layer?.addSublayer(content)
        gradient.colors=[NSColor.clear.cgColor,NSColor.black.cgColor,NSColor.black.cgColor,NSColor.clear.cgColor]
        gradient.locations=[0,0.03,0.97,1]
        gradient.startPoint=CGPoint(x:0,y:0)
        gradient.endPoint=CGPoint(x:1,y:0)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not supported") }
    func configure(text:String,size:CGFloat,weight:NSFont.Weight,color:NSColor,longestWidth:CGFloat,reduceMotion:Bool,
                   active:Bool = true,paused:Bool = false,cycleStart:CFTimeInterval = 0) {
        let geometryChanged = self.text != text || self.size != size || self.weight != weight
            || self.longestWidth != longestWidth
        let timingChanged = self.reduceMotion != reduceMotion || self.active != active || self.cycleStart != cycleStart
        let pauseChanged = self.paused != paused
        let colorChanged = !textColor.isEqual(color)
        guard geometryChanged || timingChanged || colorChanged || pauseChanged else { return }
        self.text=text;self.size=size;self.weight=weight;self.textColor=color
        self.longestWidth=longestWidth;self.reduceMotion=reduceMotion
        self.active=active;self.paused=paused;self.cycleStart=cycleStart
        setAccessibilityValue(text)
        if geometryChanged || timingChanged {
            needsRebuild=true
            if geometryChanged { invalidateIntrinsicContentSize() }
            // Retained content must stop as soon as collapse starts.
            if !active || reduceMotion { stop() }
            needsLayout=true
        } else if pauseChanged {
            applyPauseState()
        } else if colorChanged {
            // 100332134 updates glyph strings without replacing animation layers.
            CATransaction.begin();CATransaction.setDisableActions(true)
            for row in content.sublayers ?? [] {
                (row.sublayers?.first as? CATextLayer)?.string = attributedText
            }
            CATransaction.commit()
        }
    }
    private var attributedText:NSAttributedString {
        NSAttributedString(string:text,attributes:[.font:NSFont.systemFont(ofSize:size,weight:weight),.kern:0.05,.foregroundColor:textColor])
    }
    // Read-only diagnostics used by the isolated native-view regression harness.
    var animationStartTimes:[CFTimeInterval] { (content.sublayers ?? []).compactMap { $0.animation(forKey:"marquee")?.beginTime } }
    var presentedOrigin:CGFloat? { content.sublayers?.first?.presentation()?.frame.minX }
    var displayedText:String { text }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        needsRebuild=true;needsLayout=true
        if window == nil { stop() }
    }
    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        needsRebuild=true;needsLayout=true
    }
    override func layout() {
        super.layout()
        guard bounds.width > 0 else { stop(); return }
        let scale=window?.backingScaleFactor ?? 2
        CATransaction.begin();CATransaction.setDisableActions(true)
        content.frame=bounds;gradient.frame=bounds;gradient.contentsScale=scale
        let overflows = MarqueeMetrics(textWidth:MarqueeLabel.measure(text,size:size,weight:weight).width,
            viewportWidth:bounds.width,longestTextWidth:longestWidth).overflows
        // 100333abc rebuilds at an overflow boundary, not for every width change.
        if needsRebuild || overflows != lastOverflow || scale != lastScale {
            rebuild(scale:scale,restartClock:!needsRebuild && overflows != lastOverflow)
            needsRebuild=false;lastScale=scale;lastOverflow=overflows
        }
        CATransaction.commit()
    }
    private func rebuild(scale:CGFloat,restartClock:Bool = false) {
        stop();content.sublayers?.forEach { $0.removeFromSuperlayer() }
        let measured=MarqueeLabel.measure(text,size:size,weight:weight)
        let metrics=MarqueeMetrics(textWidth:measured.width,viewportWidth:bounds.width,longestTextWidth:longestWidth)
        content.mask=metrics.overflows ? gradient:nil
        let attributed=attributedText
        let count=metrics.overflows && !reduceMotion && active && window != nil ? 2:1
        for index in 0..<count {
            let origin=index == 0 ? metrics.firstOrigin:metrics.secondOrigin
            let row=CALayer()
            row.frame=CGRect(x:floor(origin*scale)/scale,y:0,width:measured.width,height:measured.height)
            let glyphs=CATextLayer()
            glyphs.contentsScale=scale;glyphs.string=attributed
            glyphs.frame=CGRect(origin:.zero,size:measured)
            row.addSublayer(glyphs);content.addSublayer(row)
            if metrics.overflows && !reduceMotion && active && window != nil && metrics.movementDuration > 0 {
                let move=CABasicAnimation(keyPath:"position.x")
                move.fromValue=row.position.x
                move.toValue=(index == 0 ? metrics.firstDestination:metrics.secondDestination)+measured.width/2
                move.duration=metrics.movementDuration;move.beginTime=metrics.delay
                // 0x100332e04..e14: s0=24, s1=120, Optional<Float> x0=24.
                move.preferredFrameRateRange=CAFrameRateRange(minimum:24,maximum:120,preferred:24)
                let group=CAAnimationGroup()
                group.animations=[move];group.duration=metrics.cycleDuration
                group.beginTime=row.convertTime(!restartClock && cycleStart > 0 ? cycleStart:CACurrentMediaTime(),from:nil)
                group.repeatCount=Float.greatestFiniteMagnitude
                row.add(group,forKey:"marquee")
            }
        }
        if paused { applyPauseState() }
    }

    private func applyPauseState() {
        for row in content.sublayers ?? [] {
            if paused {
                let time = row.convertTime(CACurrentMediaTime(), from: nil)
                row.speed = 0
                row.timeOffset = time
            } else {
                let pausedTime = row.timeOffset
                row.speed = 1
                row.timeOffset = 0
                row.beginTime = 0
                row.beginTime = row.convertTime(CACurrentMediaTime(), from: nil) - pausedTime
            }
        }
    }

    func stop() {
        content.sublayers?.forEach { $0.removeAllAnimations() }
        needsRebuild=true
    }
}

/// Two native rows share a clock. Track identity recreates this pair even when
/// the next song has the same artist or exactly the same measured text width.
struct MusicMarqueePair: View {
    let title:String
    let artist:String
    let active:Bool
    var artistColor:NSColor = NSColor.gray.withAlphaComponent(0.85)
    var onDoubleClick: (() -> Void)? = nil
    @State private var cycleStart = CACurrentMediaTime()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var longestWidth:CGFloat {
        max(MarqueeLabel.measure(title,size:13.5,weight:.semibold).width,
            MarqueeLabel.measure(artist,size:13,weight:.medium).width)
    }
    var body:some View {
        VStack(alignment:.leading,spacing:0.5) {
            MarqueeLabel(text:title,size:13.5,weight:.semibold,color:.white,longestTextWidth:longestWidth,active:active,cycleStart:cycleStart,onDoubleClick:onDoubleClick)
            MarqueeLabel(text:artist,size:13,weight:.medium,color:artistColor,longestTextWidth:longestWidth,active:active,cycleStart:cycleStart,onDoubleClick:onDoubleClick)
        }.onChange(of:active) { _,value in
            if value { cycleStart=CACurrentMediaTime() }
        }.onChange(of:reduceMotion) { _,value in
            if !value { cycleStart=CACurrentMediaTime() }
        }
    }
}
