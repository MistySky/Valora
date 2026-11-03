import SwiftUI

/// Lock card colour policy, following the decompiled macOS 26+ branch:
///
/// - `100187f28.c:1055–1065` sets the **background** colour scheme to light, so
///   the glass container itself is always built in the light appearance.
/// - `100187f28.c:1078–1088` picks the **foreground** colour scheme
///   independently from `LockManager._isWallpaperNearlyWhite`: a nearly white
///   wallpaper gets the light scheme (dark ink), everything else the dark scheme
///   (white ink).
/// - The same flag also drives the private glass `variant` (2 vs 5), which has
///   no public API; see the V0043 report.
///
/// The policy is expressed here so the split is explicit and testable. The
/// wallpaper-brightness input itself is not available in Valora yet, so the
/// default is the "not nearly white" branch, which is what every observed
/// lock-screen capture used.
struct LockCardPalette: Equatable {
    var primary: Color
    var secondary: Color
    var waveform: Color
    var track: Color

    static let onLightWallpaper = LockCardPalette(
        primary: .black,
        secondary: .black.opacity(0.7),
        waveform: .black.opacity(0.65),
        track: .black.opacity(0.16))

    static let onDarkWallpaper = LockCardPalette(
        primary: .white,
        secondary: .white.opacity(0.7),
        waveform: .white.opacity(0.65),
        track: .white.opacity(0.16))
}

struct LockCardAppearance: Equatable {
    /// `LockManager._isWallpaperNearlyWhite` equivalent.
    var wallpaperIsNearlyWhite: Bool

    /// Background appearance of the glass, fixed to light by the original.
    var glassScheme: ColorScheme { .light }

    /// Foreground appearance: dark scheme (white ink) unless the wallpaper is
    /// nearly white.
    var contentScheme: ColorScheme { wallpaperIsNearlyWhite ? .light : .dark }

    var palette: LockCardPalette {
        wallpaperIsNearlyWhite ? .onLightWallpaper : .onDarkWallpaper
    }

    /// Current default: an ordinary (non nearly-white) wallpaper.
    static let standard = LockCardAppearance(wallpaperIsNearlyWhite: false)
}
