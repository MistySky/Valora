import SwiftUI
import XCTest
@testable import Valora

/// The lock card's ink policy after V0100: one white-ink palette matching the
/// dark glass surface that `LockGlassSurface` actually pins. The previous
/// near-white-wallpaper / glass-scheme experiment had no production input and
/// was removed with it; these tests pin what production reads now.
final class LockCardPaletteTests: XCTestCase {
    func testStandardPaletteIsWhiteInk() {
        let palette = LockCardPalette.standard
        XCTAssertEqual(palette, .standard)
        XCTAssertEqual(palette.primary, .white)
    }

    func testSecondaryAndTrackStayDerivedFromPrimary() {
        XCTAssertEqual(LockCardPalette.standard.secondary, Color.white.opacity(0.7))
        XCTAssertEqual(LockCardPalette.standard.waveform, Color.white.opacity(0.65))
        XCTAssertEqual(LockCardPalette.standard.track, Color.white.opacity(0.16))
    }
}
