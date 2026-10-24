import Foundation
import CoreGraphics

/// Four floating-point results of ISO 1.7.9 function 0x10024879c.
/// Derived from ARM64 d0–d3, rather than Ghidra's incomplete C return signature.
public struct NotchGeometry: Equatable, Sendable {
    public let compact: CGSize
    public let expanded: CGSize
    public let hasPhysicalNotch: Bool

    public static func calculate(screenWidth: CGFloat, safeAreaTop: CGFloat,
                                 auxiliaryLeftWidth: CGFloat?, auxiliaryRightWidth: CGFloat?,
                                 menuBarHeight: CGFloat, simulated: Bool) -> Self {
        if safeAreaTop > 0, let left = auxiliaryLeftWidth, let right = auxiliaryRightWidth,
           left > 0, right > 0 {
            let width = screenWidth - left - right
            return Self(compact: CGSize(width: width, height: safeAreaTop),
                        expanded: CGSize(width: max(width + 160, 345), height: max(safeAreaTop + 142, 175)),
                        hasPhysicalNotch: true)
        }
        // 0x1002488c0–0x100248994: signed IEEE-754 immediates are -1 and -5.5.
        if simulated {
            return Self(compact: CGSize(width: 140, height: menuBarHeight > 0 ? menuBarHeight - 1 : 24),
                        expanded: CGSize(width: 345, height: 175), hasPhysicalNotch: false)
        }
        return Self(compact: CGSize(width: 74, height: menuBarHeight > 0 ? menuBarHeight - 5.5 : 19.5),
                    expanded: CGSize(width: 321, height: 175), hasPhysicalNotch: false)
    }
}
