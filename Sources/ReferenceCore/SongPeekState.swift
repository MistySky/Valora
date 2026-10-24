import Foundation

/// Track changes are distinct from artwork refreshes, playback ticks, and source resets.
public struct SongPeekState: Equatable, Sendable {
    public private(set) var identity: String?
    public private(set) var visible = false
    public private(set) var generation: UInt64 = 0
    public init() {}
    @discardableResult public mutating func observe(identity next: String?, eligible: Bool) -> Bool {
        let changed = next != identity
        let hadTrack = identity != nil
        identity = next
        if next == nil || !eligible { cancel(); return false }
        guard changed, hadTrack else { return false }
        generation &+= 1; visible = true
        return true
    }
    public mutating func cancel() { generation &+= 1; visible = false }
    public mutating func reset() { identity = nil; cancel() }
    public mutating func expire(generation token: UInt64) {
        guard token == generation else { return }; visible = false
    }
}
