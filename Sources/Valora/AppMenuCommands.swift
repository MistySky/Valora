import Foundation

/// Shared wording and shortcuts for the menu-bar menu and the notch context
/// menu. The context menu deliberately contains only these base commands.
/// Single read-only source for the version + build shown in the UI. Both values
/// come from the packaged Info.plist, so the About page, the menu and the
/// packaging metadata cannot drift.
enum AppVersion {
    static var shortVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
    }

    /// `0.2.0 (2)` when the bundle carries a build number.
    static var display: String {
        let build = self.build
        return build.isEmpty ? shortVersion : "\(shortVersion) (\(build))"
    }
}

enum AppMenuCommands {
    static let settingsTitle = "设置…"
    static let quitTitle = "退出 Valora"
    static let settingsKey = ","
    static let quitKey = "q"
    static var versionText: String { "版本 \(AppVersion.display)" }
}
