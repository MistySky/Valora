import Foundation

/// Recovered interaction rules, independent of the player's transport.
/// 0x1003d09ec: relative drag; 0x1003cf7b4: absolute tap;
/// 0x1003cfe8c: ignore taps for 0.1 s after a drag ends.
public struct MediaProgressState: Sendable {
    public private(set) var dragOrigin: Double?
    public private(set) var dragValue: Double?
    public private(set) var lastDragEnd: Double?
    public init() {}
    public static func validDuration(_ duration: Double) -> Bool { duration.isFinite && duration > 0 }
    public static func clamp(_ elapsed: Double, duration: Double) -> Double {
        guard validDuration(duration), elapsed.isFinite else { return 0 }
        return min(duration, max(0, elapsed))
    }
    public mutating func drag(elapsed: Double, duration: Double, translation: Double, trackWidth: Double) -> Double? {
        guard Self.validDuration(duration), translation.isFinite, trackWidth.isFinite else { return nil }
        if dragOrigin == nil { dragOrigin = Self.clamp(elapsed, duration: duration) }
        let value = Self.clamp(dragOrigin! + translation / max(1, trackWidth) * duration, duration: duration)
        dragValue = value
        return value
    }
    public mutating func endDrag(at time: Double) -> Double? {
        guard let value = dragValue else { return nil }
        lastDragEnd = time
        cancelDrag()
        return value
    }
    public mutating func cancelDrag() { dragOrigin = nil; dragValue = nil }
    public func tap(x: Double, trackWidth: Double, duration: Double, at time: Double) -> Double? {
        guard Self.validDuration(duration), x.isFinite, trackWidth.isFinite,
              lastDragEnd.map({ time - $0 >= 0.1 }) ?? true else { return nil }
        return Self.clamp(x / max(1, trackWidth) * duration, duration: duration)
    }
}
