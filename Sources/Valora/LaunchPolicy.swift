import Foundation

/// Launch-argument gate for development-only verification entry points.
///
/// The verification suites, audits and preview surfaces are compiled only into
/// development builds (`VALORA_DEVELOPMENT`, defined for the debug configuration
/// in `Package.swift`). A release build must not silently fall through to
/// production startup — real media, audio, Bluetooth/EventKit permission sources
/// and services — when it receives one of their flags. The decision therefore
/// lives in a pure function and is evaluated in `main.swift` before
/// `NSApplication` is touched.
///
/// `developmentBuild` is a parameter, not a compile-time branch, so the release
/// rule can be exercised from the debug test bundle.
enum LaunchPolicy {
    /// Flags that only exist in a development build: `--verify*`, `--audit*`,
    /// `--preview*`, plus the two media inspection flags that were never part of
    /// the documented QA suite. `--lock-card-preview` has no user-facing switch.
    static let developmentFlags: Set<String> = [
        // verify*
        "--verify-music",
        "--verify-multidisplay",
        "--verify-lyrics",
        "--verify-connectivity",
        "--verify-menubar",
        "--verify-settings",
        "--verify-system-media",
        "--verify-calendar-parity",
        // audit*
        "--audit-fluidity",
        "--audit-resources",
        "--audit-resources-short",
        "--audit-menubar-memory",
        "--audit-calendar-popover",
        "--audit-calendar-popover-fixed",
        "--audit-calendar-fixed-window",
        // preview*
        "--preview-music",
        "--preview-settings",
        "--preview-menu-modules",
        "--preview-long-title",
        // media inspection helpers
        "--lock-card-preview",
        "--expand-media"
    ]

    /// Whether the running binary was compiled as a development build.
    static var isDevelopmentBuild: Bool {
        #if VALORA_DEVELOPMENT
        true
        #else
        false
        #endif
    }

    /// The first development-only flag in `arguments` when this is not a
    /// development build; `nil` means launch may continue normally.
    ///
    /// A development build accepts every flag, because the implementations those
    /// flags reach are part of that build.
    static func rejection(arguments: [String], developmentBuild: Bool) -> String? {
        guard !developmentBuild else { return nil }
        return arguments.first { developmentFlags.contains($0) }
    }

    /// Development modes that cannot run standalone. They are only modifiers of
    /// an isolated synthetic parent (`--preview-music`); the AppDelegate rejects
    /// them before constructing or starting any service, instead of silently
    /// falling back to a live media/audio/Bluetooth/calendar startup. The release
    /// gate already rejects the flags themselves.
    static func developmentStartupRejection(_ mode: AppRuntimeDefaults.StartupMode) -> String? {
        guard case let .invalidDevelopmentCombination(flag) = mode else { return nil }
        return flag
    }
}
