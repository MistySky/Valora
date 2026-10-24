/// Deterministic part of 1.7.9's expansion lifecycle. Scheduling and SwiftUI
/// completion callbacks belong to the app; stale callbacks are rejected here.
public struct NotchTransitionState: Equatable, Sendable {
    public enum Phase: String, Sendable { case collapsed, expanding, expanded, collapsing }
    public private(set) var phase: Phase = .collapsed
    public private(set) var generation: UInt64 = 0
    public private(set) var expanded = false
    public private(set) var usesExpandedCornerRadius = false
    public private(set) var hasExpandedBackdropLuma = false
    public private(set) var hasProgressiveBlur = false
    // 1.7.9: 0x1001a09e4 keeps the player alive throughout collapse;
    // 0x10019eb38 gates expanded-content interaction until the transition ends.
    public var retainsExpandedContent: Bool { phase != .collapsed }
    public var acceptsExpandedInteraction: Bool { phase == .expanded }
    public init() {}

    /// Duplicate requests must not restart the same transition's clock.
    @discardableResult public mutating func begin(expanding: Bool) -> UInt64? {
        guard expanding != expanded else { return nil }
        generation &+= 1
        usesExpandedCornerRadius = expanded && !expanding
        expanded = expanding
        phase = expanding ? .expanding : .collapsing
        return generation
    }
    public mutating func revealCorners(generation token: UInt64) {
        guard token == generation, phase == .expanding else { return }
        usesExpandedCornerRadius = true
    }
    public mutating func setBackdrop(_ value: Bool, generation token: UInt64) {
        guard token == generation, value == expanded else { return }
        hasExpandedBackdropLuma = value
    }
    public mutating func setBlur(_ value: Bool, generation token: UInt64) {
        guard token == generation, value == expanded else { return }
        hasProgressiveBlur = value
    }
    public mutating func complete(generation token: UInt64) {
        guard token == generation else { return }
        phase = expanded ? .expanded : .collapsed
        usesExpandedCornerRadius = expanded
        hasExpandedBackdropLuma = expanded
        hasProgressiveBlur = expanded
    }
}
