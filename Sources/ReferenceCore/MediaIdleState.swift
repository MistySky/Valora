import Foundation

/// Paused live-activity grace period, separate from retained track metadata and
/// the original's additional hideIdleDeadline policy.
public struct MediaIdleState: Equatable, Sendable {
    public struct Input: Equatable, Sendable {
        public var identity: String?
        public var playing: Bool
        public var enabled: Bool
        public var pointerInside: Bool
        public var outputNotification: Bool
        public var duration: Double
        public init(identity: String?, playing: Bool, enabled: Bool = true,
                    pointerInside: Bool = false, outputNotification: Bool = false, duration: Double = 3) {
            self.identity = identity; self.playing = playing; self.enabled = enabled
            self.pointerInside = pointerInside; self.outputNotification = outputNotification
            self.duration = duration.isFinite ? min(10, max(0, duration)) : 3
        }
    }
    public private(set) var input: Input?
    public private(set) var visible = true
    public private(set) var pending = false
    public private(set) var generation: UInt64 = 0
    public init() {}

    /// Repeated metadata polls must not move a pending deadline.
    @discardableResult public mutating func update(_ next: Input) -> Bool {
        guard next != input else { return false }
        let previous = input
        input = next; generation &+= 1; pending = false
        guard next.enabled, next.identity != nil else { visible = false; return true }
        if next.playing || previous?.identity != next.identity || previous?.enabled != true {
            visible = true
        }
        pending = visible && !next.playing && !next.pointerInside && !next.outputNotification
        return true
    }
    @discardableResult public mutating func expire(generation token: UInt64) -> Bool {
        guard token == generation, pending, let input,
              input.enabled, input.identity != nil, !input.playing,
              !input.pointerInside, !input.outputNotification else { return false }
        pending = false; visible = false
        return true
    }
}
