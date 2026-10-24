import Foundation

/// Fixed product policy for the Valora connectivity slice.
///
/// The user-confirmed UI has only the total switch. Appearance is automatic:
/// the artwork branch selects a recognized model movie when available and the
/// existing symbol fallback otherwise. Legacy `connectivityModel` values are
/// intentionally ignored. Duration, low-battery warning, threshold and sound
/// are fixed and do not read hidden legacy values.
public struct ConnectivityPreferences: Equatable, Sendable {
    public let uses3DModels: Bool
    public let duration: Double
    public let warnOnLowBattery: Bool
    public let lowBatteryThreshold: Int
    public let playSoundOnLowBattery: Bool

    public init(values: [String: Any] = [:]) {
        // Keep the stored-type initializer for settings reload compatibility,
        // but never let an old appearance selection override automatic mode.
        _ = values
        uses3DModels = true
        duration = 5
        warnOnLowBattery = true
        lowBatteryThreshold = 20
        playSoundOnLowBattery = true
    }
}

public enum ConnectionArtworkPolicy: Sendable {
    /// Reduce Motion is a symbol fallback, not a third appearance mode.
    public static func usesMovie(appearance: Bool, reduceMotion: Bool) -> Bool {
        appearance && !reduceMotion
    }
}

public enum ConnectionArtworkMetrics: Sendable {
    /// 1002b5fec + 1002b1594/16fc, 1002b6390 + 1001e1ce8.
    public static func movieSize(notch: Bool) -> Double { notch ? 32 : 28 }
    public static func movieOffset(notch: Bool) -> Double { notch ? -0.5 : -1 }
    public static func symbolSize(notch: Bool) -> Double { notch ? 15 : 13 }
}
