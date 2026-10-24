import Foundation

public enum VolumeKeyAction: Equatable, Sendable {
    case up, down, mute

    /// NX_KEYTYPE_SOUND_UP/DOWN/MUTE from IOKit's ev_keymap.h.
    public static func action(keyCode: Int) -> Self? {
        switch keyCode {
        case 0: return .up
        case 1: return .down
        case 7: return .mute
        default: return nil
        }
    }
}

public enum VolumeStep: Sendable {
    public static let normal = 1.0 / 16.0
    public static let fine = 1.0 / 64.0
    public static func target(current: Double, action: VolumeKeyAction, fine: Bool) -> Double {
        guard action != .mute else { return min(1, max(0, current)) }
        let delta = fine ? Self.fine : Self.normal
        return min(1, max(0, current + (action == .up ? delta : -delta)))
    }
}
