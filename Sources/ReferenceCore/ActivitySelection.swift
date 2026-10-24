import Foundation

/// Activity tags still used by the fixed music presentation metrics.
public enum ExpandedActivity: UInt8, CaseIterable, Sendable {
    case none = 0, nowPlaying, calendar, duo
}

public enum LiveActivity: UInt8, Sendable {
    case none = 0, locked, adjusting, calendar, playing
}
