import CoreGraphics

/// ISO 1.7.9: 0x1001e3f6c scales an elevated collapsed cutout about its top;
/// 0x1001edebc uses a 0.35-second spring, bounce .45 on entry and .05 on exit.
public enum NotchHoverMetrics: Sendable {
    public static let duration = 0.35
    public static func bounce(entering: Bool) -> Double { entering ? 0.45 : 0.05 }
    public static func scale(inside: Bool, expanded: Bool) -> CGSize {
        inside && !expanded ? CGSize(width:1.075,height:1.15) : CGSize(width:1,height:1)
    }
    public static func localPoint(centeredX: CGFloat, topY: CGFloat, size: CGSize, scale: CGSize) -> CGPoint {
        CGPoint(x:centeredX/scale.width+size.width/2,y:topY/scale.height)
    }
}
