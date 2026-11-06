import Foundation

/// Selected lock-screen policy. Battery/focus/keep-awake are intentionally
/// absent from this product slice, and so is the card's material choice: the
/// card has a single fixed material now.
public struct LockMusicPreferences: Equatable, Sendable {
    public var enabled: Bool
    public var musicEnabled: Bool
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
        // The output button controls the collapsed volume bar; no stored
        // "show volume control" switch is exposed.
        showVolume = false
        soundOnLock = values["playSoundOnLock"] as? Bool ?? false
        soundOnUnlock = values["playSoundOnUnlock"] as? Bool ?? true
        // The card sits at the reference's fixed 21% of the screen height; no
        // offset control is exposed.
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

/// Geometry of the lock music card, mirroring the notch player's expansion
/// rules: the card's *top* is fixed and the optional blocks (volume, lyrics)
/// extend it downwards.
///
/// Blocks include the vertical spacing that precedes them, so the four possible
/// states are exactly `H`, `H+V`, `H+L` and `H+V+L` with an unchanged top.
public struct LockCardLayout: Equatable, Sendable {
    /// Player block (padding included). Measured from the real lock card.
    public static let playerHeight: Double = 164
    /// Volume row (24pt) plus the 8pt spacing above it.
    public static let volumeBlock: Double = 24 + 8
    /// Lyric row (32pt), its 8pt spacing and the 4pt bottom padding.
    public static let lyricBlock: Double = 32 + 8 + 4
    /// Tallest visible card: player + volume + lyrics. The host window is
    /// exactly this tall, so there is no invisible click-catching area below
    /// the reserved card region.
    public static let maxCardHeight: Double = playerHeight + volumeBlock + lyricBlock
    public static let canvasHeight: Double = maxCardHeight
    /// Built-in screen: the accepted collapsed-card clearance (a product value,
    /// not measured login-window geometry — macOS does not expose the avatar
    /// bounds through this API).
    public static let loginSafeFraction: Double = 0.21
    /// External/clamshell screens keep the same 21% reference but still reserve
    /// room for the **fully expanded** card above it. The user confirmed 30% was
    /// too high (R2) and asked to restore this value while keeping the wiring;
    /// 21% is a product placement value, **not** a system-provided avatar bound.
    public static let externalReserveFraction: Double = 0.21

    public var screenMinY: Double
    public var screenHeight: Double
    public var verticalOffset: Double
    /// External/clamshell targets reserve room for the **fully expanded** card
    /// above the same reference line the collapsed card uses. That line is a
    /// product placement value (21% of the screen height) — macOS does not expose
    /// the login avatar bounds — so this keeps the layout predictable rather than
    /// guaranteeing the avatar is never covered. The built-in screen keeps the
    /// accepted anchor, where the volume-expanded state sits exactly on the line.
    public var reserveFullExpansion: Bool

    public init(screenMinY: Double = 0, screenHeight: Double,
                verticalOffset: Double = 0, reserveFullExpansion: Bool = false) {
        self.screenMinY = screenMinY
        self.screenHeight = screenHeight
        self.verticalOffset = verticalOffset
        self.reserveFullExpansion = reserveFullExpansion
    }

    /// The original 21% clearance line. V0091 note: this is **not** a measured
    /// login-window safe area — macOS does not expose the avatar bounds here.
    /// It is kept as the collapsed card's bottom line, which is where the
    /// accepted pre-V0088 card sat.
    public var loginSafeBottom: Double {
        screenMinY + screenHeight * Self.loginSafeFraction + verticalOffset
    }

    /// Base line the card is laid out against: the built-in 21% line, or the
    /// higher external reserve when the target screen needs the full expansion.
    public var reservedBottom: Double {
        screenMinY + screenHeight * (reserveFullExpansion ? Self.externalReserveFraction
                                                         : Self.loginSafeFraction)
            + verticalOffset
    }

    /// Extra clearance above the reference line so that opening the **volume**
    /// row still keeps the card's bottom on that line instead of covering the
    /// login avatar. It is exactly the volume block, i.e. the smallest lift that
    /// fixes the reported case; the lyric block below it remains a reported
    /// trade-off rather than something compensated with a guessed offset.
    public static let volumeClearance: Double = volumeBlock

    /// Fixed top edge of the card (screen coordinates, origin bottom-left).
    /// Anchored from the **collapsed** card plus `volumeClearance`.
    ///
    /// Consequences, reported and not silently compensated:
    /// - collapsed card sits `volumeClearance` (32pt) above the old 21% line;
    /// - volume-expanded card's bottom sits on that line;
    /// - adding the lyric row still publishes 44pt below it.
    public var cardTop: Double {
        reservedBottom + (reserveFullExpansion ? Self.maxCardHeight
                                               : Self.playerHeight + Self.volumeClearance)
    }

    /// Height of the visible card for a given set of expanded blocks.
    public func cardHeight(volume: Bool, lyrics: Bool) -> Double {
        Self.playerHeight
            + (volume ? Self.volumeBlock : 0)
            + (lyrics ? Self.lyricBlock : 0)
    }

    /// Bottom edge of the fully expanded card. With the fixed anchor above it
    /// is equal to the login-safe line.
    public var fullyExpandedBottom: Double { cardTop - Self.maxCardHeight }

    /// Origin of the fixed-height host window. The host spans exactly the
    /// reserved card region: its bottom is the login-safe line, never below it.
    public var panelOriginY: Double { fullyExpandedBottom }

    /// On extremely short displays the reserved region cannot fit above the
    /// login-safe line without going off-screen. Callers must not shrink the
    /// card silently; this flag exists to report the conflict.
    public var fitsScreen: Bool { cardTop <= screenMinY + screenHeight }
}
