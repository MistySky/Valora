import XCTest
import Foundation
@testable import Valora

/// V0101: development verification code is compiled out of release builds and
/// the release binary must reject its launch flags before AppKit/services start.
@MainActor
final class LaunchPolicyTests: XCTestCase {
    func testReleaseRejectsEveryDevelopmentFlag() {
        for flag in LaunchPolicy.developmentFlags {
            XCTAssertEqual(LaunchPolicy.rejection(arguments: ["Valora", flag], developmentBuild: false), flag,
                           "release build must reject \(flag)")
        }
    }

    func testReleaseRejectsFlagMixedWithNormalArguments() {
        let arguments = ["Valora", "--settings", "--no-settings", "--verify-lyrics", "/tmp/out"]
        XCTAssertEqual(LaunchPolicy.rejection(arguments: arguments, developmentBuild: false), "--verify-lyrics")
    }

    func testReleaseAllowsNormalLaunchArguments() {
        let normal = [
            ["Valora"],
            ["Valora", "--settings"],
            ["Valora", "--no-settings"],
            ["Valora", "-psn_0_12345"],
            ["Valora", "--settings", "--settings-page", "Lock Screen"]
        ]
        for arguments in normal {
            XCTAssertNil(LaunchPolicy.rejection(arguments: arguments, developmentBuild: false),
                         "normal argument was rejected: \(arguments)")
        }
    }

    func testDevelopmentBuildAcceptsEveryDevelopmentFlag() {
        for flag in LaunchPolicy.developmentFlags {
            XCTAssertNil(LaunchPolicy.rejection(arguments: ["Valora", flag], developmentBuild: true),
                         "development build must accept \(flag)")
        }
    }

    func testDevelopmentFlagsCoverAllStartupModesExceptProduction() {
        // Every non-production startup mode must be reachable only through a
        // flag the release gate rejects, otherwise a release build could enter
        // a dev branch that no longer exists.
        let modes: [(String, AppRuntimeDefaults.StartupMode)] = [
            ("--verify-music", .verifyMusic),
            ("--verify-multidisplay", .verifyMultiDisplay),
            ("--verify-lyrics", .verifyLyrics),
            ("--verify-connectivity", .verifyConnectivity),
            ("--audit-fluidity", .auditFluidity),
            ("--audit-resources", .auditResources),
            ("--audit-resources-short", .auditResources),
            ("--verify-menubar", .verifyMenuBar),
            ("--verify-settings", .verifySettings),
            ("--verify-system-media", .verifySystemMedia),
            ("--preview-music", .previewMusic),
            ("--preview-settings", .previewSettings),
            ("--preview-menu-modules", .previewMenuBarModules),
            ("--audit-menubar-memory", .auditMenuBarMemory),
            ("--audit-calendar-popover", .auditCalendarPopover),
            ("--audit-calendar-popover-fixed", .auditCalendarPopoverFixed),
            ("--audit-calendar-fixed-window", .auditCalendarFixedWindow),
            ("--verify-calendar-parity", .verifyCalendarParity)
        ]
        for (flag, mode) in modes {
            XCTAssertEqual(AppRuntimeDefaults.startupMode(arguments: ["Valora", flag]), mode)
            XCTAssertTrue(LaunchPolicy.developmentFlags.contains(flag),
                          "\(flag) resolves a non-production mode but the release gate does not reject it")
            XCTAssertEqual(LaunchPolicy.rejection(arguments: ["Valora", flag], developmentBuild: false), flag)
        }
        XCTAssertEqual(AppRuntimeDefaults.startupMode(arguments: ["Valora", "--settings"]), .production)
    }

    func testDevelopmentBuildsKeepTheirIsolatedPreferenceSuite() {
        let (qa, suite) = AppRuntimeDefaults.resolve(arguments: ["Valora", "--verify-lyrics"])
        XCTAssertEqual(suite, AppRuntimeDefaults.qaSuiteName)
        // `UserDefaults(suiteName:)` hands out a new object per call, so compare
        // the migrated preferences they share rather than object identity.
        qa.set("qa-probe", forKey: "launchPolicyProbe")
        XCTAssertEqual(UserDefaults(suiteName: AppRuntimeDefaults.qaSuiteName)!
            .string(forKey: "launchPolicyProbe"), "qa-probe")
        qa.removeObject(forKey: "launchPolicyProbe")

        let (standard, standardSuite) = AppRuntimeDefaults.resolve(arguments: ["Valora", "--settings"])
        XCTAssertEqual(standardSuite, AppRuntimeDefaults.standardSuiteName)
        XCTAssertEqual(standard, UserDefaults.standard)
    }

    /// The gate must run before `NSApplication` is created, i.e. before AppKit
    /// and before any service can start. This is a structural source assertion:
    /// it needs no second app instance and no AppKit launch.
    func testReleaseGateRunsBeforeAppKitStarts() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let main = try String(contentsOf: root.appendingPathComponent("Sources/Valora/main.swift"),
                              encoding: .utf8)
        let gate = try XCTUnwrap(main.range(of: "LaunchPolicy.rejection"))
        let appKit = try XCTUnwrap(main.range(of: "NSApplication.shared"))
        XCTAssertLessThan(gate.lowerBound, appKit.lowerBound,
                          "the development-flag gate must precede NSApplication.shared")
    }

    /// Source-level evidence that the implementation is excluded by a compile
    /// condition rather than a runtime `if`: the verification files and the
    /// AppDelegate branches are wrapped in `#if VALORA_DEVELOPMENT`, and the
    /// define exists only for the debug configuration.
    func testVerificationImplementationIsBehindACompileCondition() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let gated = [
            "Verification.swift", "CalendarParityVerification.swift", "ConnectivityVerification.swift",
            "LyricsVerification.swift", "MultiDisplayVerification.swift", "FluidityAudit.swift",
            "MenuBarMemoryAudit.swift", "CalendarFixedWindowAudit.swift", "CalendarPopoverAudit.swift",
            "LockCardPreview.swift", "MenuBarAuditValidity.swift",
            "ResourceBaselineAudit.swift"
        ]
        for name in gated {
            let text = try String(contentsOf: root.appendingPathComponent("Sources/Valora/\(name)"),
                                  encoding: .utf8)
            XCTAssertTrue(text.hasPrefix("#if VALORA_DEVELOPMENT"),
                          "\(name) is not behind the development compile condition")
            XCTAssertTrue(text.hasSuffix("#endif\n") || text.hasSuffix("#endif"),
                          "\(name) has no closing development condition")
        }
        let package = try String(contentsOf: root.appendingPathComponent("Package.swift"), encoding: .utf8)
        XCTAssertTrue(package.contains(".define(\"VALORA_DEVELOPMENT\", .when(configuration: .debug))"),
                      "the development define must be debug-only")
        let delegate = try String(contentsOf: root.appendingPathComponent("Sources/Valora/AppDelegate.swift"),
                                  encoding: .utf8)
        XCTAssertTrue(delegate.contains("#if VALORA_DEVELOPMENT"),
                      "AppDelegate verification branches are not compile-conditioned")
        XCTAssertTrue(delegate.contains("#if !VALORA_DEVELOPMENT"),
                      "release AppDelegate has no defence-in-depth startup guard")
    }

    /// The launch path must keep the shared controller construction outside the
    /// development regions. Regression for the first V0101 attempt, which gated
    /// `model.media/audio/bluetooth` together with the QA branches and crashed a
    /// release launch on a nil implicit unwrap.
    func testSharedLaunchPathIsNotInsideTheDevelopmentRegion() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let delegate = try String(contentsOf: root.appendingPathComponent("Sources/Valora/AppDelegate.swift"),
                                  encoding: .utf8)
        var depth = 0
        var regions: [(line: String, depth: Int)] = []
        for line in delegate.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#if VALORA_DEVELOPMENT") || trimmed.hasPrefix("#if !VALORA_DEVELOPMENT") {
                depth += 1
                continue
            }
            if trimmed.hasPrefix("#endif") {
                depth -= 1
                continue
            }
            if depth == 0 { regions.append((String(line), depth)) }
        }
        let shared = ["model.media = MediaController(model)",
                      "model.audio = AudioOutputController(model)",
                      "model.bluetooth = ConnectivityController(model",
                      "coordinator = WindowCoordinator(model)",
                      "lockMusic = LockMusicCoordinator("]
        for needle in shared {
            XCTAssertTrue(regions.contains { $0.line.contains(needle) },
                          "shared launch code is inside a development region: \(needle)")
        }
    }

    /// `--lock-card-preview` is a valid isolated development preview: QA suite,
    /// explicit non-production mode, and (per the source-order test below) it
    /// returns before any real service starts.
    func testLockCardPreviewResolvesToAnIsolatedPreview() {
        let arguments = ["Valora", "--lock-card-preview"]
        XCTAssertTrue(AppRuntimeDefaults.isQAMode(arguments: arguments))
        XCTAssertEqual(AppRuntimeDefaults.startupMode(arguments: arguments), .lockCardPreview)
        XCTAssertEqual(AppRuntimeDefaults.resolve(arguments: arguments).suiteName,
                       AppRuntimeDefaults.qaSuiteName)
        XCTAssertEqual(LaunchPolicy.rejection(arguments: arguments, developmentBuild: false),
                       "--lock-card-preview")
        XCTAssertNil(LaunchPolicy.developmentStartupRejection(
            AppRuntimeDefaults.startupMode(arguments: arguments)))
    }

    /// Standalone `--expand-media` cannot be honoured without a real media
    /// session. It must resolve to an explicit invalid mode that the launch path
    /// rejects before any service, never to `.production`.
    func testExpandMediaStandaloneIsRejectedBeforeAnyService() {
        let arguments = ["Valora", "--expand-media"]
        let mode = AppRuntimeDefaults.startupMode(arguments: arguments)
        XCTAssertTrue(AppRuntimeDefaults.isQAMode(arguments: arguments),
                      "development inspection must not use normal user preferences")
        XCTAssertNotEqual(mode, .production,
                          "development inspection must not silently start live services")
        XCTAssertEqual(LaunchPolicy.developmentStartupRejection(mode), "--expand-media")
        XCTAssertEqual(AppRuntimeDefaults.resolve(arguments: arguments).suiteName,
                       AppRuntimeDefaults.qaSuiteName)
        XCTAssertEqual(LaunchPolicy.rejection(arguments: arguments, developmentBuild: false),
                       "--expand-media")
    }

    /// `--preview-long-title` and `--expand-media` only modify `--preview-music`.
    func testDevelopmentModifiersRequireTheSyntheticPreviewParent() {
        let longTitle = AppRuntimeDefaults.startupMode(arguments: ["Valora", "--preview-long-title"])
        XCTAssertNotEqual(longTitle, .production)
        XCTAssertEqual(LaunchPolicy.developmentStartupRejection(longTitle), "--preview-long-title")

        let withParent = ["Valora", "--preview-music", "--preview-long-title"]
        XCTAssertEqual(AppRuntimeDefaults.startupMode(arguments: withParent), .previewMusic)
        XCTAssertNil(LaunchPolicy.developmentStartupRejection(
            AppRuntimeDefaults.startupMode(arguments: withParent)))

        let expandWithParent = ["Valora", "--preview-music", "--expand-media"]
        XCTAssertEqual(AppRuntimeDefaults.startupMode(arguments: expandWithParent), .previewMusic)
        XCTAssertNil(LaunchPolicy.developmentStartupRejection(
            AppRuntimeDefaults.startupMode(arguments: expandWithParent)))
        XCTAssertTrue(AppRuntimeDefaults.isQAMode(arguments: expandWithParent))
    }

    /// The rejection must happen before the shared controllers are built, and the
    /// isolated lock preview must return before any service is started.
    func testDevelopmentRejectionAndPreviewOrdering() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let delegate = try String(contentsOf: root.appendingPathComponent("Sources/Valora/AppDelegate.swift"),
                                  encoding: .utf8)
        let rejection = try XCTUnwrap(delegate.range(of: "LaunchPolicy.developmentStartupRejection(startupMode)"))
        let controllers = try XCTUnwrap(delegate.range(of: "model.media = MediaController(model)"))
        XCTAssertLessThan(rejection.lowerBound, controllers.lowerBound,
                          "unsupported development modes must be rejected before controllers exist")

        let preview = try XCTUnwrap(delegate.range(of: "lockCardPreview = LockCardPreviewController(model)"))
        let services = try XCTUnwrap(delegate.range(of: "model.media.start()"))
        XCTAssertLessThan(preview.lowerBound, services.lowerBound,
                          "the isolated lock preview must return before real services start")
    }

    /// Compile-time proof that the debug QA entry points still exist. These
    /// types only exist when the Valora target is built with
    /// `VALORA_DEVELOPMENT`, so this test fails to compile if the debug boundary
    /// accidentally removes them.
    func testDevelopmentVerificationEntryPointsExistInDebugBuilds() {
        XCTAssertNotNil(MusicPresentationVerification.self)
        XCTAssertNotNil(SettingsVerification.self)
        XCTAssertNotNil(SystemMediaVerification.self)
        XCTAssertNotNil(MenuBarIconVerification.self)
        XCTAssertNotNil(CalendarParityVerification.self)
        XCTAssertNotNil(ConnectivityVerification.self)
        XCTAssertNotNil(LyricsVerification.self)
        XCTAssertNotNil(MultiDisplayVerification.self)
        XCTAssertNotNil(FluidityAudit.self)
        XCTAssertNotNil(MenuBarMemoryAudit.self)
        XCTAssertNotNil(CalendarFixedWindowAudit.self)
        XCTAssertNotNil(CalendarPopoverAudit.self)
        XCTAssertNotNil(LockCardPreviewController.self)
    }
}
