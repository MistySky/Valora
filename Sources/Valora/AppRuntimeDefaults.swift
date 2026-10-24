import Foundation

/// One resolution point for the settings store used by both AppModel and the
/// SettingsDraft. Production uses `.standard`; QA/preview modes share one
/// isolated suite so a click in SettingsView is visible to the backend model
/// without touching Valora's normal preferences.
enum AppRuntimeDefaults {
    static let qaSuiteName = "com.wangqing.valora.qa"
    static let standardSuiteName = "standard"

    private static let qaArguments: Set<String> = [
        "--verify-music",
        "--verify-multidisplay",
        "--verify-lyrics",
        "--verify-menubar",
        "--verify-settings",
        "--verify-system-media",
        "--verify-audio-tap",
        "--preview-music",
        "--preview-settings"
    ]

    static func isQAMode(arguments: [String]) -> Bool {
        arguments.contains { qaArguments.contains($0) }
    }

    enum StartupMode: Equatable {
        case production
        case verifyAudioTap
        case verifyMusic
        case verifyMultiDisplay
        case verifyLyrics
        case verifyMenuBar
        case verifySettings
        case verifySystemMedia
        case previewMusic
        case previewSettings

        var isSyntheticPreview: Bool {
            self == .previewMusic || self == .previewSettings
        }
    }

    static func startupMode(arguments: [String]) -> StartupMode {
        if arguments.contains("--verify-audio-tap") { return .verifyAudioTap }
        if arguments.contains("--verify-music") { return .verifyMusic }
        if arguments.contains("--verify-multidisplay") { return .verifyMultiDisplay }
        if arguments.contains("--verify-lyrics") { return .verifyLyrics }
        if arguments.contains("--verify-menubar") { return .verifyMenuBar }
        if arguments.contains("--verify-settings") { return .verifySettings }
        if arguments.contains("--verify-system-media") { return .verifySystemMedia }
        if arguments.contains("--preview-settings") { return .previewSettings }
        if arguments.contains("--preview-music") { return .previewMusic }
        return .production
    }

    static func resolve(arguments: [String]) -> (defaults: UserDefaults, suiteName: String) {
        if isQAMode(arguments: arguments) {
            return (UserDefaults(suiteName: qaSuiteName)!, qaSuiteName)
        }
        return (.standard, standardSuiteName)
    }

    /// Optional path argument following `flag`.
    static func value(after flag: String, arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.count > index + 1 else { return nil }
        return arguments[index + 1]
    }
}
