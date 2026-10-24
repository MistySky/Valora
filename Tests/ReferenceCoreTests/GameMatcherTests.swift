import XCTest
@testable import ReferenceCore

final class GameMatcherTests: XCTestCase {
    func testRecoveredLeagueBundleIdentifiers() {
        for id in GameMatcher.bundleIdentifiers {
            XCTAssertTrue(GameMatcher.matches(bundleIdentifier: id, path: nil, category: nil), id)
        }
    }
    func testPathFragmentsAndCategoryFallback() {
        XCTAssertTrue(GameMatcher.matches(bundleIdentifier: nil, path: "/Applications/League of Legends.app", category: nil))
        XCTAssertTrue(GameMatcher.matches(bundleIdentifier: nil, path: "/Applications/Riot Client.app", category: nil))
        XCTAssertTrue(GameMatcher.matches(bundleIdentifier: "com.example.unknown", path: nil, category: "public.app-category.games"))
    }
    func testNonGamesDoNotMatch() {
        XCTAssertFalse(GameMatcher.matches(bundleIdentifier: "com.tencent.QQMusicMac", path: "/Applications/QQMusic.app", category: "public.app-category.music"))
        XCTAssertFalse(GameMatcher.matches(bundleIdentifier: nil, path: nil, category: nil))
    }
}
