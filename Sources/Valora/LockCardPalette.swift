import SwiftUI

/// Lock card ink palette.
///
/// Every observed lock capture is white ink on dark glass, and `LockGlassSurface`
/// pins the dark appearance (`.darkAqua` + private variant 5) for the material.
/// The near-white-wallpaper branch (`_isWallpaperNearlyWhite`) has no input in
/// Valora, so the light palette and its scheme plumbing are gone rather than kept
/// as unreachable experiment state.
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
