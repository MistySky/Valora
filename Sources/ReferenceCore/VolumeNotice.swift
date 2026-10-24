import Foundation

public struct VolumeNotice: Equatable, Sendable {
    public var volume: Double
    public var muted: Bool
    public init(volume: Double, muted: Bool) {
        self.volume = min(1, max(0, volume))
        self.muted = muted
    }
}

public enum VolumeHUDStyle: String, CaseIterable, Equatable, Sendable {
    case white = "White"
    case accent = "Accent"
    case decibel = "Decibel"
}

public enum VolumeHUDSpeed: String, CaseIterable, Equatable, Sendable {
    case smooth = "Smooth"
    case fast = "Fast"
    case instant = "Instant"

    /// Coalescing delay before the CoreAudio write. Kept visible to the
    /// controller so the setting changes the real write response, not just UI.
    public var writeDelay: TimeInterval {
        switch self {
        case .smooth: return 0.030
        case .fast: return 0.012
        case .instant: return 0
        }
    }

    /// How long the local target overrides a stale polling snapshot.
    public var callbackSuppression: TimeInterval {
        switch self {
        case .smooth: return 0.220
        case .fast: return 0.140
        case .instant: return 0.080
        }
    }

    /// Delay before refreshing after a write completes.
    public var refreshDelay: TimeInterval {
        switch self {
        case .smooth: return 0.120
        case .fast: return 0.060
        case .instant: return 0.020
        }
    }

    /// HUD bar/text animation duration. Instant deliberately disables animation.
    public var animationDuration: Double {
        switch self {
        case .smooth: return 0.24
        case .fast: return 0.10
        case .instant: return 0
        }
    }
}

public struct VolumePreferences: Equatable, Sendable {
    public var enabled: Bool
    public var duration: Double
    public var allowWhenLocked: Bool
    public var allowWhenFocused: Bool
    public var style: VolumeHUDStyle
    public var showPercentage: Bool
    public var hideLabel: Bool
    public var speed: VolumeHUDSpeed
    public var showSymbol: Bool
    public var showDevice: Bool

    public init(values: [String: Any] = [:]) {
        enabled = values["enableVolume"] as? Bool ?? true
        // 1.5 s is the current observable original duration. It is a local
        // functional default, not a recovered registered default.
        let rawDuration = (values["volumeDuration"] as? NSNumber)?.doubleValue
        duration = rawDuration?.isFinite == true ? min(5, max(0, rawDuration!)) : 1.5
        allowWhenLocked = values["allowVolumeWhenLocked"] as? Bool ?? true
        allowWhenFocused = values["allowVolumeWhenFocused"] as? Bool ?? true
        style = VolumeHUDStyle(rawValue: values["volumeStyle"] as? String ?? "") ?? .white
        showPercentage = values["showVolumePercentage"] as? Bool ?? true
        hideLabel = values["hideVolumeLabel"] as? Bool ?? true
        speed = VolumeHUDSpeed(rawValue: values["volumeSpeed"] as? String ?? "") ?? .smooth
        showSymbol = values["showVolumeSymbol"] as? Bool ?? true
        showDevice = values["showVolumeDevice"] as? Bool ?? false
    }
}

/// Pure presentation selection shared by the HUD and its tests. It never turns
/// normalized volume into a dB measurement; Decibel remains a visual style.
public struct VolumeHUDContent: Equatable, Sendable {
    public var style: VolumeHUDStyle
    public var speed: VolumeHUDSpeed
    public var percentage: Int
    public var percentageText: String?
    public var label: String?
    public var symbol: String?
    public var accessibilityLabel: String
    public var accessibilityValue: String
    public var accessibilityHint: String?

    public init(notice: VolumeNotice, preferences: VolumePreferences,
                deviceName: String = "", deviceSymbol: String = "") {
        let volume = notice.muted ? 0 : min(1, max(0, notice.volume))
        percentage = Int((volume * 100).rounded())
        percentageText = preferences.showPercentage ? "\(percentage)%" : nil
        style = preferences.style
        speed = preferences.speed
        let name = deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        // Show device takes priority for the text/identity. Hide label hides the
        // generic "音量" label, not a real device name explicitly requested.
        label = preferences.showDevice && !name.isEmpty ? name : (preferences.hideLabel ? nil : "音量")
        let fallback = notice.muted || volume <= 0 ? "speaker.slash.fill" : "speaker.wave.1.fill"
        symbol = preferences.showSymbol ? (preferences.showDevice && !deviceSymbol.isEmpty ? deviceSymbol : fallback) : nil
        accessibilityLabel = preferences.showDevice && !name.isEmpty ? "系统音量，\(name)" : "系统音量"
        accessibilityValue = "\(percentage)%"
        accessibilityHint = preferences.style == .decibel
            ? "分段样式仅显示归一化音量，不是 dB 测量" : nil
    }
}
