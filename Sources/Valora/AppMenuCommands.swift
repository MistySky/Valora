import Foundation

/// Shared wording and shortcuts for the menu-bar menu and the notch context
/// menu. The context menu deliberately contains only these base commands.
enum AppMenuCommands {
    static let settingsTitle = "设置…"
    static let quitTitle = "退出 Valora"
    static let settingsKey = ","
    static let quitKey = "q"
    static var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版"
        return "版本 \(version)"
    }
}
