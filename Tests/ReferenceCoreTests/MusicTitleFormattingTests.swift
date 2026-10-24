import XCTest
@testable import ReferenceCore

final class MusicTitleFormattingTests: XCTestCase {
    func testDisabledPreservesRawTitleExactly() {
        let raw = "  Song (Live) [Remix]\n"
        XCTAssertEqual(MusicTitleFormatting.displayTitle(raw, hideExtras: false), raw)
        XCTAssertFalse(MusicPreferences().hideSongTitleExtras)
    }
    func testNestedAndCrossedBracketsUseIndependentDepths() {
        XCTAssertEqual(clean("Song (Live [2026]) [Mix (Alt)]"), "Song")
        XCTAssertEqual(clean("A ([x)] B"), "A  B")
        XCTAssertEqual(clean("A (B (C)) D"), "A  D")
    }
    func testUnmatchedClosersRemainAndOpenersHideRemainder() {
        XCTAssertEqual(clean("Song ) ] End"), "Song ) ] End")
        XCTAssertEqual(clean("Song (unfinished"), "Song")
        XCTAssertEqual(clean("Song [unfinished"), "Song")
        XCTAssertEqual(clean("A ([)] B"), "A  B")
    }
    func testEmptyProcessedTitleFallsBackToTrimmedOriginal() {
        XCTAssertEqual(clean("  (Live) [Mix]  "), "(Live) [Mix]")
        XCTAssertEqual(clean("\n\t "), "")
        XCTAssertEqual(clean("("), "(")
    }
    func testUnicodeCharactersAndFullWidthBracketsArePreserved() {
        XCTAssertEqual(clean("  中文 👩🏽‍💻 é (Live) ［原版］（现场）  "), "中文 👩🏽‍💻 é  ［原版］（现场）")
    }
    private func clean(_ title: String) -> String {
        MusicTitleFormatting.displayTitle(title, hideExtras: true)
    }
}
