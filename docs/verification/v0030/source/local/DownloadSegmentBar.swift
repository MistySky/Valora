// Adapted from TheDynamicPunk/Convoy commit 007a20973923fcd69c42a3571fc299f5b8582dc6
// Views/SegmentBar.swift (GPL-3.0; see Resources/Licenses/Convoy-GPL-3.0.txt).
// Only the engine SegmentMap type was replaced with Valora's immutable
// DownloadSegmentSnapshot; capsule/parts/ripple drawing is retained.
@preconcurrency import SwiftUI

struct DownloadSegmentBar: View, @preconcurrency Animatable {
    var segments: [DownloadSegmentSnapshot]
    var layout: String?
    var progress: Double
    var color: Color
    var split: Double

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(progress, split) }
        set { (progress, split) = (newValue.first, newValue.second) }
    }

    private static let ripple = 0.3
    private var isLanes: Bool { layout == "lanes" }

    var body: some View {
        Canvas { context, size in
            let t = min(1, max(0, split))
            if t > 0, !segments.isEmpty { drawParts(in: context, size: size, t: t) }
            else { drawCapsule(in: context, size: size) }
        }
    }

    private var track: Color { Color(nsColor: .quaternaryLabelColor).opacity(0.4) }
    private func fillShading(to x: CGFloat) -> GraphicsContext.Shading {
        .linearGradient(Gradient(colors: [color.opacity(0.75), color]),
                        startPoint: .zero, endPoint: CGPoint(x: x, y: 0))
    }
    private static func capsule(_ rect: CGRect) -> Path {
        Path(roundedRect: rect, cornerRadius: min(rect.width, rect.height) / 2, style: .circular)
    }
    private func capsuleFillWidth(_ width: CGFloat) -> CGFloat { max(4, width * min(1, max(0, progress))) }

    private func drawCapsule(in context: GraphicsContext, size: CGSize) {
        context.fill(Self.capsule(CGRect(origin: .zero, size: size)), with: .color(track))
        let width = capsuleFillWidth(size.width)
        context.fill(Self.capsule(CGRect(x: 0, y: 0, width: width, height: size.height)),
                     with: fillShading(to: width))
    }

    private func drawParts(in context: GraphicsContext, size: CGSize, t: Double) {
        var context = context
        context.clip(to: Self.capsule(CGRect(origin: .zero, size: size)))
        let width = size.width, height = size.height
        let spans = segments
        func mix(_ a: CGFloat, _ b: CGFloat, _ t: Double) -> CGFloat { a + (b - a) * t }
        let narrowest = spans.map { ($0.end - $0.start) * width }.min() ?? 0
        let fullGap: CGFloat = isLanes ? 2 : (narrowest >= 3 ? 1 : 0)
        let fetchedTotal = spans.reduce(0) { $0 + ($1.end - $1.start) * $1.filled } * width
        let capsuleFill = capsuleFillWidth(width)
        let scale = fetchedTotal > 0 ? capsuleFill / fetchedTotal : 0
        let firstFilled = spans.firstIndex { $0.filled > 0 }
        let lastFilled = spans.lastIndex { $0.filled > 0 }
        var tracks = Path()
        var fills: [Int: Path] = [:]
        var marks: [(path: Path, opacity: Double)] = []
        var packed: CGFloat = 0

        for (i, span) in spans.enumerated() {
            let delay = spans.count > 1 ? Self.ripple * Double(i) / Double(spans.count - 1) : 0
            let local = min(1, max(0, (t - delay) / (1 - Self.ripple)))
            let gap = fullGap * local
            let nextStart = i + 1 < spans.count ? spans[i + 1].start : 1
            let end = mix(nextStart, span.end, local)
            let x0 = span.start * width + (span.start > 0 ? gap / 2 : 0)
            let x1 = end * width - (end < 1 ? gap / 2 : 0)
            let fetched = (span.end - span.start) * span.filled * width * scale
            defer { packed += fetched }
            guard x1 > x0 else { continue }
            let cell = CGRect(x: x0, y: 0, width: x1 - x0, height: height)
            tracks.addPath(Path(roundedRect: cell, cornerRadius: 1.5 * local))
            if span.filled > 0 {
                let target: CGRect
                var opacity: Double
                if isLanes {
                    target = CGRect(x: x0, y: 0, width: cell.width * span.filled, height: height)
                    opacity = 1
                } else {
                    target = cell
                    opacity = 0.35 + 0.65 * span.filled
                    if span.isActive { opacity = max(opacity, 0.45) }
                }
                let rect = CGRect(x: mix(packed, target.minX, local), y: 0,
                                  width: mix(fetched, target.width, local), height: height)
                let leading = mix(i == firstFilled ? height / 2 : 0, 1.5, local)
                let trailing = mix(i == lastFilled ? height / 2 : 0, 1.5, local)
                let shape = UnevenRoundedRectangle(
                    topLeadingRadius: leading, bottomLeadingRadius: leading,
                    bottomTrailingRadius: trailing, topTrailingRadius: trailing, style: .circular
                ).path(in: rect)
                let key = Int((mix(1, opacity, local) * 100).rounded())
                fills[key, default: Path()].addPath(shape)
                if isLanes, span.isActive, span.filled < 1, rect.width > 2 {
                    let tick = Path(CGRect(x: rect.maxX - 1.5, y: 0, width: 1.5, height: height))
                    marks.append((tick, 0.85 * max(0, local - 0.6) / 0.4))
                }
            } else if !isLanes, span.isActive {
                marks.append((Path(roundedRect: cell, cornerRadius: 1.5 * local), local))
            }
        }
        context.fill(tracks, with: .color(track))
        let shading = fillShading(to: mix(capsuleFill, width, t))
        for (key, path) in fills {
            var layer = context
            layer.opacity = Double(key) / 100
            layer.fill(path, with: shading)
        }
        if fetchedTotal == 0 {
            var nub = context
            nub.opacity = 1 - t
            nub.fill(Self.capsule(CGRect(x: 0, y: 0, width: capsuleFill, height: height)),
                     with: fillShading(to: capsuleFill))
        }
        let markColor: Color = isLanes ? .white : color.opacity(0.45)
        for mark in marks where mark.opacity > 0 {
            var layer = context
            layer.opacity = mark.opacity
            layer.fill(mark.path, with: .color(markColor))
        }
    }
}
