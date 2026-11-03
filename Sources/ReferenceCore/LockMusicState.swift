import Foundation

/// Selected lock-screen policy. Battery/focus/keep-awake are intentionally
/// absent from this product slice.
public struct LockMusicPreferences: Equatable, Sendable {
    public var enabled: Bool
    public var musicEnabled: Bool
    public var glass: Bool
    public var showVolume: Bool
    public var soundOnLock: Bool
    public var soundOnUnlock: Bool
    public var idleSeconds: Double
    public var offset: Double

    public init(values: [String: Any] = [:]) {
        enabled = values["enableLockScreen"] as? Bool ?? true
        // The lock page exposes only the master switch and the two sounds. The
        // music card follows the Now Playing module switch, which the lock
        // coordinator supplies; the archived lock-only preference is no longer
        // read, so a stale `allowNowPlayingWidgetWhenLocked=false` cannot
        // silently veto the module's own switch.
        musicEnabled = true
        // Selected fixed Glass branch; Clear is not exposed in this slice.
        glass = true
        // The output button controls the collapsed volume bar; no stored
        // "show volume control" switch is exposed.
        showVolume = false
        soundOnLock = values["playSoundOnLock"] as? Bool ?? false
        soundOnUnlock = values["playSoundOnUnlock"] as? Bool ?? true
        // Selected policy is fixed: no idle-duration or offset control is
        // exposed, and stale archived preferences must not change it.
        idleSeconds = 10 * 60
        offset = 0
    }
}

public struct LockMusicState: Equatable, Sendable {
    public private(set) var visible = false
    public private(set) var deadline: Double?
    public private(set) var generation: UInt64 = 0
    private var input: Input?
    private struct Input: Equatable {
        var locked: Bool; var sleeping: Bool; var hasTrack: Bool; var playing: Bool
        var identity: String; var enabled: Bool; var seconds: Double
    }
    public init() {}
    public mutating func update(locked: Bool, sleeping: Bool, hasTrack: Bool, playing: Bool,
                                identity: String, preferences: LockMusicPreferences, now: Double) {
        let next = Input(locked: locked, sleeping: sleeping, hasTrack: hasTrack, playing: playing,
                         identity: identity, enabled: preferences.enabled && preferences.musicEnabled,
                         seconds: preferences.idleSeconds)
        guard next != input else { return }
        input = next
        generation &+= 1
        deadline = nil
        guard locked, !sleeping, hasTrack, next.enabled else { visible = false; return }
        if playing { visible = true } else {
            visible = next.seconds > 0
            if visible { deadline = now + next.seconds }
        }
    }
    public mutating func expire(token: UInt64, now: Double) {
        guard token == generation, let deadline, now >= deadline else { return }
        visible = false
        self.deadline = nil
    }
    public mutating func hide() {
        visible = false
        deadline = nil
        generation &+= 1
        input = nil
    }
}
