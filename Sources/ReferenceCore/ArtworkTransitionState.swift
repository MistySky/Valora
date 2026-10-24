import Foundation

/// Latest-only queue: image revisions, rather than player polling or title changes,
/// drive transitions. Completion tokens cannot restore superseded artwork.
public struct ArtworkTransitionState: Equatable, Sendable {
    public enum Phase: String, Sendable { case idle, outgoing, incoming }
    public private(set) var current: String?
    public private(set) var target: String?
    public private(set) var queued: String?
    public private(set) var phase: Phase = .idle
    public private(set) var generation: UInt64 = 0
    public init() {}
    public mutating func set(_ identity: String?, animated: Bool) {
        guard animated, let identity, current != nil else {
            if current == identity && phase == .idle { return }
            generation &+= 1; current = identity; target = nil; queued = nil; phase = .idle
            return
        }
        if phase != .idle { queued = identity == target ? nil : identity; return }
        guard identity != current else { return }
        generation &+= 1; target = identity; queued = nil; phase = .outgoing
    }
    public mutating func finishOutgoing(_ token: UInt64) {
        guard token == generation, phase == .outgoing else { return }
        current = target; phase = .incoming
    }
    public mutating func finishIncoming(_ token: UInt64) {
        guard token == generation, phase == .incoming else { return }
        let next = queued
        target = nil; queued = nil; phase = .idle
        if let next { set(next, animated:true) }
    }
}

public enum ArtworkFlipMetrics: Sendable {
    // 1.7.9 1002db0d0, 1002dafd8, 1002db078, 1002de228.
    public static let outgoingDuration = 0.15
    public static let incomingDuration = 0.275
    public static let incomingBounce = 0.375
    public static let effectDuration = 0.55
    public static let effectDelay = 0.05
    public static func scale(progress: Double, incoming: Bool) -> Double {
        incoming ? 0.0825 + 0.9175 * progress : 1 - 0.9175 * progress
    }
}

public enum MusicProgressStyle: String, Sendable { case monochrome = "Monochrome", colored = "Colored", gradient = "Gradient" }
