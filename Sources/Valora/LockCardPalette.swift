import SwiftUI

/// White playback controls shared by the refractive and system lock materials.
struct LockCardPalette: Equatable {
    var primary: Color
    var secondary: Color
    var waveform: Color
    var track: Color

    /// White-ink palette used by the lock card.
    static let standard = LockCardPalette(
        primary: .white,
        secondary: .white.opacity(0.7),
        waveform: .white.opacity(0.65),
        track: .white.opacity(0.16))
}
