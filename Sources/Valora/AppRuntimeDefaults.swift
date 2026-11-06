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
        "--audit-resources",
        "--audit-resources-short",
        "--verify-menubar",
        "--verify-settings",
        "--verify-system-media",
        "--preview-music",
        "--preview-settings",
        "--preview-menu-modules",
        "--audit-menubar-memory",
        "--audit-calendar-popover",
        "--audit-calendar-popover-fixed",
        "--audit-calendar-fixed-window",
        "--verify-calendar-parity",
        // Development preview/inspection entries that are not part of the
        // documented verify/audit suites but still must isolate preferences.
        "--lock-card-preview",
        "--expand-media",
        "--preview-long-title"
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
        case auditResources
        case verifyMenuBar
        case verifySettings
        case verifySystemMedia
        case previewMusic
        case previewSettings
        case previewMenuBarModules
        case auditMenuBarMemory
        case auditCalendarPopover
        case auditCalendarPopoverFixed
        case auditCalendarFixedWindow
        case verifyCalendarParity
        /// Desktop lock-card material/layout preview; isolated, no services.
        case lockCardPreview
        /// Auxiliary development flag that cannot run without its synthetic
        /// parent (`--preview-music`); the associated value is the flag itself.
        case invalidDevelopmentCombination(String)

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
        if arguments.contains("--audit-resources")
            || arguments.contains("--audit-resources-short") { return .auditResources }
        if arguments.contains("--verify-menubar") { return .verifyMenuBar }
        if arguments.contains("--verify-settings") { return .verifySettings }
        if arguments.contains("--verify-system-media") { return .verifySystemMedia }
        if arguments.contains("--preview-menu-modules") { return .previewMenuBarModules }
        if arguments.contains("--audit-menubar-memory") { return .auditMenuBarMemory }
        if arguments.contains("--audit-calendar-fixed-window") { return .auditCalendarFixedWindow }
        if arguments.contains("--verify-calendar-parity") { return .verifyCalendarParity }
        if arguments.contains("--audit-calendar-popover-fixed") { return .auditCalendarPopoverFixed }
        if arguments.contains("--audit-calendar-popover") { return .auditCalendarPopover }
        if arguments.contains("--preview-settings") { return .previewSettings }
        if arguments.contains("--preview-music") { return .previewMusic }
        // Standalone development extras. `--preview-music` wins when combined,
        // because its synthetic preview already expands the panel; the extras
        // only remain valid as modifiers of that parent.
        if arguments.contains("--lock-card-preview") { return .lockCardPreview }
        if arguments.contains("--expand-media") { return .invalidDevelopmentCombination("--expand-media") }
        if arguments.contains("--preview-long-title") { return .invalidDevelopmentCombination("--preview-long-title") }
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
