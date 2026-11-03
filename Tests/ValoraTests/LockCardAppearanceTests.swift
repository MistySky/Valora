import SwiftUI
import XCTest
@testable import Valora

/// Fixture tests for the lock colour policy. They do not read the wallpaper and
/// create no window: they only pin the mapping the decompiled macOS 26+ branch
/// describes (light glass background, foreground chosen by wallpaper
/// brightness).
final class LockCardAppearanceTests: XCTestCase {
    func testStandardAppearanceKeepsLightGlassAndWhiteInk() {
        let appearance = LockCardAppearance.standard
        XCTAssertFalse(appearance.wallpaperIsNearlyWhite)
        XCTAssertEqual(appearance.glassScheme, .light,
                       "the glass background is always built in the light scheme")
        XCTAssertEqual(appearance.contentScheme, .dark,
                       "an ordinary wallpaper uses the dark scheme, i.e. white ink")
        XCTAssertEqual(appearance.palette.primary, .white)
        XCTAssertEqual(appearance.palette, .onDarkWallpaper)
    }

    func testNearlyWhiteWallpaperSwitchesToDarkInkOnLightGlass() {
        let appearance = LockCardAppearance(wallpaperIsNearlyWhite: true)
        XCTAssertEqual(appearance.glassScheme, .light)
        XCTAssertEqual(appearance.contentScheme, .light,
                       "a nearly white wallpaper flips the foreground to the light scheme")
        XCTAssertEqual(appearance.palette.primary, .black)
        XCTAssertEqual(appearance.palette, .onLightWallpaper)
    }

    func testBackgroundAndForegroundAreIndependent() {
        // The whole point of the split: changing the ink never changes the glass
        // appearance, and vice versa.
        for nearlyWhite in [true, false] {
            let appearance = LockCardAppearance(wallpaperIsNearlyWhite: nearlyWhite)
            XCTAssertEqual(appearance.glassScheme, .light)
        }
        XCTAssertNotEqual(LockCardPalette.onDarkWallpaper, LockCardPalette.onLightWallpaper)
    }

    func testPaletteSecondaryAndTrackStayDerivedFromPrimary() {
        XCTAssertEqual(LockCardPalette.onDarkWallpaper.secondary, Color.white.opacity(0.7))
        XCTAssertEqual(LockCardPalette.onLightWallpaper.secondary, Color.black.opacity(0.7))
        XCTAssertEqual(LockCardPalette.onDarkWallpaper.track, Color.white.opacity(0.16))
        XCTAssertEqual(LockCardPalette.onLightWallpaper.track, Color.black.opacity(0.16))
    }
}
