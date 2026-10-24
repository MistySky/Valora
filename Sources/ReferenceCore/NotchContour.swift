import CoreGraphics

public enum NotchContourStyle: Sendable { case notch, pill }

/// Display-style branch in NotchView 0x1001e1fb8, radius wrapper
/// 0x1001e3a04, and top padding in 0x1001e3f6c. Ghidra's C output omits
/// the wrapper's floating-point return; ARM64 0x1001e3c40 loads 36.0.
public struct NotchContour: Sendable {
    public let style: NotchContourStyle
    public let topRadius: CGFloat
    public let bottomRadius: CGFloat
    public let topInset: CGFloat

    public static func stationary(geometry: NotchGeometry, simulated: Bool,
                                  expanded: Bool, expandedCorners: Bool,
                                  active: Bool, quickPeek: Bool = false,
                                  visibleHeight: CGFloat) -> Self {
        guard geometry.hasPhysicalNotch || simulated else {
            let radius: CGFloat = expanded ? 36 : max(0, visibleHeight) / 2
            return Self(style: .pill, topRadius: radius, bottomRadius: radius, topInset: 2.5)
        }
        let hasActivity = active || quickPeek
        let usesExpanded = expanded && expandedCorners
        return Self(style: .notch,
                    topRadius: (hasActivity ? 8 : 5) + (usesExpanded ? 12 : 0),
                    bottomRadius: (hasActivity ? 11.5 : 10) + (usesExpanded ? 24 : (quickPeek ? 8 : 0)),
                    topInset: 0)
    }
}
