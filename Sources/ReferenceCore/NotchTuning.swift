import CoreGraphics
import Foundation

/// Maps the existing SettingsView candidate keys to the recovered original
/// `notchAdjustedWidth`/`notchAdjustedHeight` semantics.
///
/// Static evidence:
/// - 0x10012acf8 filters the width parameter and returns 0 unless the screen has
///   safeAreaTop > 0 and both auxiliary top areas are non-empty.
/// - 0x10012ade4 does the same for the height parameter.
/// - 0x10012aed0 / 0x10012b878 add the filtered parameter to compact geometry;
///   their expanded branches return before the addition.
/// - 0x1002310e0 / 0x10023cfd0 / 0x100245d70 consume _notchAdjustedWidth/Height.
///
/// This is static reconstruction, not visual/runtime proof. The range clamp and
/// 1-point minimum are local UI/safety policy, not recovered original limits.
public struct NotchTuning: Equatable, Sendable {
    public static let widthRange: ClosedRange<Double> = -40...40
    public static let heightRange: ClosedRange<Double> = -10...10

    public let widthOffset: Double
    public let heightOffset: Double

    public init(widthOffset: Double = 0, heightOffset: Double = 0) {
        self.widthOffset = Self.clamp(widthOffset, to: Self.widthRange)
        self.heightOffset = Self.clamp(heightOffset, to: Self.heightRange)
    }
    public init(values: [String: Any] = [:]) {
        self.init(
            widthOffset: (values["notchWidthOffset"] as? NSNumber)?.doubleValue ?? 0,
            heightOffset: (values["notchHeightOffset"] as? NSNumber)?.doubleValue ?? 0)
    }

    /// Applies only to physical-notch compact/peek/notification geometry.
    /// Expanded sizes are intentionally left untouched by the caller.
    /// `physicalNotch` must come from NotchGeometry.hasPhysicalNotch; simulated
    /// mode cannot bypass the hardware gate (0x10012acf8/0x10012ade4).
    public func apply(toCompact size: CGSize, physicalNotch: Bool) -> CGSize {
        guard physicalNotch else { return size }
        return CGSize(width: max(1, size.width + widthOffset),
                      height: max(1, size.height + heightOffset))
    }
    public static let zero = NotchTuning()

    private static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}
