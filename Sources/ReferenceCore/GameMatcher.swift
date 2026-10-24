import Foundation

/// 1.7.9 GameManager tracked bundle IDs/path fragments recovered from the
/// binary. The category fallback covers other native games without guessing a
/// store/library path.
public enum GameMatcher: Sendable {
    public static let bundleIdentifiers: Set<String> = [
        "com.riotgames.leagueoflegends",
        "com.riotgames.leagueoflegends.gameclient",
        "com.riotgames.leagueclient",
        "com.riotgames.leagueclientux",
    ]
    public static let pathFragments = ["League of Legends", "Riot Client"]

    public static func matches(bundleIdentifier: String?, path: String?, category: String?) -> Bool {
        if let bundleIdentifier, bundleIdentifiers.contains(bundleIdentifier) { return true }
        if let path, pathFragments.contains(where: { path.localizedCaseInsensitiveContains($0) }) { return true }
        return category == "public.app-category.games"
    }
}
