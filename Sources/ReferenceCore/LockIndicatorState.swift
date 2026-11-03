import Foundation

/// The lock badge has explicit, cancellable presentation stages. The stages
/// are deliberately small: `locking` keeps normal content during its bounded
/// collapse, `locked` owns the badge, `unlocking` shows the open glyph while
/// the lock surface collapses, and `restoring` hides the badge before the
/// latest normal music content is allowed back.
public struct LockIndicatorState: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case hidden, locking, neutralizing, locked, unlocking, restoring
    }
    public private(set) var phase: Phase = .hidden
    public private(set) var generation: UInt64 = 0
    public init() {}

    /// Badge geometry/content is visible only after the normal-content
    /// collapse and while the unlock glyph is being shown.
    public var showsBadge: Bool { phase == .locked || phase == .unlocking }
    public var isLocking: Bool { phase == .locking }
    /// Both sides of the transition temporarily use the neutral base notch:
    /// before a lock badge expands, and after an unlock badge retracts.
    public var isNeutralGeometry: Bool { phase == .neutralizing || phase == .restoring }

    /// Existing simple state update retained for callers that only need the
    /// original locked/unlocking distinction.
    public mutating func update(locked: Bool, enabled: Bool, sleeping: Bool) {
        let next: Phase = (!enabled || sleeping) ? .hidden
            : (locked ? .locked : (phase == .locked ? .unlocking : phase))
        guard phase != next else { return }
        phase = next
        generation &+= 1
    }

    public mutating func forceHidden() {
        guard phase != .hidden else { return }
        phase = .hidden
        generation &+= 1
    }

    /// Startup/sleep-wake reconciliation: already locked is a settled badge,
    /// not an animated lock edge.
    public mutating func forceLocked() {
        guard phase != .locked else { return }
        phase = .locked
        generation &+= 1
    }

    @discardableResult
    public mutating func beginLocking() -> UInt64 {
        if phase != .locking { phase = .locking; generation &+= 1 }
        return generation
    }

    @discardableResult
    public mutating func beginNeutralizing() -> UInt64 {
        if phase != .neutralizing { phase = .neutralizing; generation &+= 1 }
        return generation
    }

    @discardableResult
    public mutating func completeLocking(token: UInt64) -> Bool {
        // Keep compatibility with the older direct locking test; the runtime
        // normally passes through neutralizing first.
        guard token == generation, phase == .neutralizing || phase == .locking else { return false }
        phase = .locked
        generation &+= 1
        return true
    }

    @discardableResult
    public mutating func beginUnlocking() -> UInt64 {
        if phase != .unlocking { phase = .unlocking; generation &+= 1 }
        return generation
    }

    /// Keep the legacy finish behavior (directly hidden) for existing callers;
    /// the coordinator uses the staged restore transition below.
    public mutating func finishUnlock(token: UInt64) {
        guard token == generation, phase == .unlocking else { return }
        phase = .hidden
        generation &+= 1
    }

    @discardableResult
    public mutating func finishUnlockToRestoring(token: UInt64) -> Bool {
        guard token == generation, phase == .unlocking else { return false }
        phase = .restoring
        generation &+= 1
        return true
    }

    @discardableResult
    public mutating func finishRestoring(token: UInt64) -> Bool {
        guard token == generation, phase == .restoring else { return false }
        phase = .hidden
        generation &+= 1
        return true
    }
}
