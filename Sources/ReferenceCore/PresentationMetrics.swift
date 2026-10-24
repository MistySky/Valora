import CoreGraphics

public enum NotchNotification: Int, CaseIterable, Sendable {
    case charging, lowBattery, lowPowerMode, connectedAirPods, lowAirPodsBattery
    case focus, volume, brightness, timeToLeave, none

    /// 0x10022b254 indexes the two double tables at 0x10048c740 / 0x10048c790.
    public func widthAddition(notchOrSimulated: Bool) -> CGFloat {
        let physical: [CGFloat] = [168, 168, 168, 74, 74, 74, 184, 184, 74, 0]
        let floating: [CGFloat] = [156, 156, 156, 62, 62, 62, 172, 172, 62, 0]
        return (notchOrSimulated ? physical : floating)[rawValue]
    }
}

public enum QuickPeek: Int, Sendable { case none, adjusting, calendar, playing }

public enum PresentationMetrics: Sendable {
    /// Stationary, visible state only: user size adjustments and gesture deformation
    /// are deliberately separate. 0x10012aed0 / 0x10012b878 and their width helpers.
    public static func stationarySize(geometry: NotchGeometry, simulated: Bool,
                                      expanded: ExpandedActivity = .none, hasOutput: Bool = false,
                                      notification: NotchNotification = .none,
                                      liveActivity: LiveActivity = .none,
                                      quickPeek: QuickPeek = .none,
                                      tuning: NotchTuning = .zero) -> CGSize {
        if expanded != .none {
            // 0x10012aed0/0x10012b878 return expanded dimensions before +param_1.
            return CGSize(width: geometry.expanded.width,
                          height: geometry.expanded.height + (hasOutput && expanded == .nowPlaying ? 32 : 0))
        }
        let notch = geometry.hasPhysicalNotch || simulated
        var width = geometry.compact.width + notification.widthAddition(notchOrSimulated: notch)
        if liveActivity != .none {
            // Music activity uses the same 74pt increment on physical-notch and
            // non-notch hardware: 140 + 74 = the confirmed 214pt compact width.
            width += notch ? 74 : (liveActivity == .locked ? 46 : 74)
        } else if quickPeek == .calendar || quickPeek == .playing {
            width += quickPeek == .playing ? 74 : (notch ? 74 : 62)
        }
        let peekHeight: CGFloat = quickPeek == .none ? 0 : (quickPeek == .adjusting ? 36.8 : 32)
        return tuning.apply(toCompact: CGSize(width: width, height: geometry.compact.height + peekHeight),
                            physicalNotch: geometry.hasPhysicalNotch)
    }
}

/// Timings traced through 0x10022cd00 and its Swift async descriptors.
/// A timing value alone does not establish visual or interruptible-animation parity.
public enum ExpansionTiming: Sendable {
    public static let duration = 0.45
    public static let cornerDelay = 0.02
    public static let backdropLumaDelay = 0.30000000000000004
    public static let completionDelay = 0.45 + 0.05
    public static func bounce(hasNotification: Bool) -> Double { hasNotification ? 0.1 : 0.4 }
    /// The argument is the binary's second flag; its higher-level caller meaning
    /// has not yet been established, so it must not be labeled a user preference.
    public static func collapseResponse(secondFlag: Bool) -> Double { secondFlag ? 0.25 : 0.4 }
}
