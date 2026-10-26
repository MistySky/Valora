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
        "--verify-connectivity",
        "--audit-fluidity",
        "--verify-menubar",
        "--verify-settings",
        "--verify-system-media",
        "--preview-music",
        "--preview-settings",
        "--preview-menu-modules",
        "--verify-menu-modules",
        "--verify-menu-layout",
        "--audit-menubar-memory",
        "--audit-calendar-popover",
        "--audit-calendar-popover-fixed",
        "--audit-calendar-fixed-window",
        "--verify-codex-usage-live",
        "--verify-downloads",
        "--verify-download-layout",
        "--audit-download-menu",
        "--verify-calendar-parity"
    ]

    static func isQAMode(arguments: [String]) -> Bool {
        arguments.contains { qaArguments.contains($0) }
    }

    enum StartupMode: Equatable {
        case production
        case verifyMusic
        case verifyMultiDisplay
        case verifyLyrics
        case verifyConnectivity
        case auditFluidity
        case verifyMenuBar
        case verifySettings
        case verifySystemMedia
        case previewMusic
        case previewSettings
        case previewMenuBarModules
        case verifyMenuBarModules
        case verifyMenuLayout
        case auditMenuBarMemory
        case auditCalendarPopover
        case auditCalendarPopoverFixed
        case auditCalendarFixedWindow
        case verifyCodexUsageLive
        case verifyDownloads
        case verifyDownloadLayout
        case auditDownloadMenu
        case verifyCalendarParity

        var isSyntheticPreview: Bool {
            self == .previewMusic || self == .previewSettings || self == .previewMenuBarModules
        }
    }

    static func startupMode(arguments: [String]) -> StartupMode {
        if arguments.contains("--verify-music") { return .verifyMusic }
        if arguments.contains("--verify-multidisplay") { return .verifyMultiDisplay }
        if arguments.contains("--verify-lyrics") { return .verifyLyrics }
        if arguments.contains("--verify-connectivity") { return .verifyConnectivity }
        if arguments.contains("--audit-fluidity") { return .auditFluidity }
        if arguments.contains("--verify-menubar") { return .verifyMenuBar }
        if arguments.contains("--verify-settings") { return .verifySettings }
        if arguments.contains("--verify-system-media") { return .verifySystemMedia }
        if arguments.contains("--verify-menu-modules") { return .verifyMenuBarModules }
        if arguments.contains("--verify-menu-layout") { return .verifyMenuLayout }
        if arguments.contains("--preview-menu-modules") { return .previewMenuBarModules }
        if arguments.contains("--audit-menubar-memory") { return .auditMenuBarMemory }
        if arguments.contains("--audit-calendar-fixed-window") { return .auditCalendarFixedWindow }
        if arguments.contains("--verify-codex-usage-live") { return .verifyCodexUsageLive }
        if arguments.contains("--verify-downloads") { return .verifyDownloads }
        if arguments.contains("--verify-download-layout") { return .verifyDownloadLayout }
        if arguments.contains("--audit-download-menu") { return .auditDownloadMenu }
        if arguments.contains("--verify-calendar-parity") { return .verifyCalendarParity }
        if arguments.contains("--audit-calendar-popover-fixed") { return .auditCalendarPopoverFixed }
        if arguments.contains("--audit-calendar-popover") { return .auditCalendarPopover }
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
