import XCTest
import AppKit
@testable import Valora
import ReferenceCore

private actor CountingInlineLyricsProvider: LyricsProviding {
    private(set) var count = 0
    func lyrics(for request: LyricsRequest) async throws -> LyricsFetchResult {
        count += 1
        return .timed(LyricTimeline(lines: [LyricLine(start: 0, text: "同一份歌词")]))
    }
}

/// Model/policy tests only: no windows, hardware actions or live media reads.
@MainActor
final class MusicDisplayPolicyTests: XCTestCase {
    private func display(_ id: String, builtIn: Bool = false, active: Bool = true,
                         origin: CGPoint = .zero) -> DisplayDescriptor {
        DisplayDescriptor(id: id, name: id,
                          frame: CGRect(origin: origin, size: CGSize(width: 1728, height: 1117)),
                          safeAreaTop: builtIn ? 32 : 0,
                          auxiliaryLeftWidth: builtIn ? 771.5 : nil,
                          auxiliaryRightWidth: builtIn ? 771.5 : nil,
                          menuBarHeight: 32, isBuiltIn: builtIn, isActive: active)
    }

    func testLockPrefersOnlineBuiltInEvenWhenExternalIsMain() {
        XCTAssertEqual(LockDisplayPolicy.select(from: [display("external"), display("internal", builtIn: true)])?.id,
                       "internal")
    }

    func testClamshellAndDesktopUseMainExternalFallback() {
        let external = display("main", origin: CGPoint(x: -1728, y: 200))
        for all in [[external, display("internal", builtIn: true, active: false)],
                    [external, display("secondary")]] {
            XCTAssertEqual(LockDisplayPolicy.select(from: all)?.frame, external.frame)
        }
        XCTAssertNil(LockDisplayPolicy.select(from: []))
        XCTAssertNil(LockDisplayPolicy.select(from: [display("internal", builtIn: true, active: false)]))
    }

    func testOpenLidAndUnplugRecomputeOneTargetWithoutMusicSelection() {
        let main = display("external")
        let internalScreen = display("internal", builtIn: true)
        XCTAssertEqual(LockDisplayPolicy.select(from: [main, internalScreen])?.id, "internal")
        XCTAssertEqual(LockDisplayPolicy.select(from: [main])?.id, "external")
        XCTAssertEqual(LockDisplayPolicy.select(from: [internalScreen])?.id, "internal")
        XCTAssertTrue(LockDisplayPolicy.geometry(for: internalScreen).hasPhysicalNotch)
        XCTAssertFalse(LockDisplayPolicy.geometry(for: main).hasPhysicalNotch)
        XCTAssertEqual(LockDisplayPolicy.geometry(for: main).compact.height, 26.5)
    }

    func testInlineOnlyChangesCompactPositionAndPreservesExpandedLyrics() {
        let suite = "valora.display-policy.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(["showLyrics": true, "inlineLyrics": true], forKey: "referenceSettingsUI")
        let settings = RevivalSettings(defaults: defaults)
        let model = AppModel(settings: settings)
        model.title = "Fixture"
        model.lyrics = LyricsDisplayState(status: .ready,
            timeline: LyricTimeline(lines: [LyricLine(start: 0, text: "歌词测试")]))
        model.notchGeometry = LockDisplayPolicy.geometry(for: display("external"))
        model.inlineLyricsDisplayEligible = true
        let timeline = model.lyrics.timeline
        XCTAssertTrue(model.showsInlineLyrics)
        XCTAssertFalse(model.showsCompactLyrics)
        XCTAssertEqual(model.visibleSize.height, model.notchGeometry.compact.height)
        XCTAssertTrue(model.showsLyricsInExpanded)

        model.inlineLyricsDisplayEligible = false // physical or multiple targets
        XCTAssertFalse(model.showsInlineLyrics)
        XCTAssertTrue(model.showsCompactLyrics)
        XCTAssertEqual(model.visibleSize.height, model.notchGeometry.compact.height + 32)
        XCTAssertEqual(model.lyrics.timeline, timeline)

        defaults.set(["showLyrics": true, "inlineLyrics": false], forKey: "referenceSettingsUI")
        settings.reloadPreferences()
        model.inlineLyricsDisplayEligible = true
        XCTAssertFalse(model.showsInlineLyrics)
        XCTAssertTrue(model.showsCompactLyrics)
        XCTAssertTrue(model.showsLyricsInExpanded)
    }

    func testGeneralOnlyContainsApplicationControls() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Sources/Valora/SettingsView.swift"), encoding: .utf8)
        let start = try XCTUnwrap(source.range(of: "private var general:"))
        let end = try XCTUnwrap(source.range(of: "private var musicDisplaySettings:"))
        let general = String(source[start.lowerBound..<end.lowerBound])
        XCTAssertTrue(general.contains("Launch at login"))
        XCTAssertTrue(general.contains("showApplicationMenuBarIcon"))
        for key in ["forceSimulatedNotch", "showOnDisplay", "hoverEnabled", "inlineLyrics"] {
            XCTAssertFalse(general.contains(key))
        }
        XCTAssertTrue(source.contains("musicDisplaySettings\n"))
        XCTAssertFalse(MusicPreferences().inlineLyrics)
    }

    func testInlinePreferencePersistsWithoutStartingAnotherLyricsRequest() async throws {
        let suite = "valora.inline-request.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(["showLyrics": true], forKey: "referenceSettingsUI")
        let settings = RevivalSettings(defaults: defaults)
        let model = AppModel(settings: settings)
        model.title = "Fixture"; model.artist = "Artist"; model.duration = 200
        let provider = CountingInlineLyricsProvider()
        let controller = LyricsController(model: model, provider: provider)
        controller.start()
        defer { controller.cancel() }
        try await Task.sleep(for: .milliseconds(60))
        XCTAssertEqual(model.lyrics.status, .ready)
        let timeline = model.lyrics.timeline
        let draft = SettingsDraft(defaults: defaults)
        draft.binding("inlineLyrics", false).wrappedValue = true
        settings.reloadPreferences()
        controller.mediaMetadataChanged()
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertTrue(RevivalSettings(defaults: defaults).musicPreferences.inlineLyrics)
        XCTAssertEqual(model.lyrics.timeline, timeline)
        let count = await provider.count
        XCTAssertEqual(count, 1, "position changes must reuse the loaded timeline")
    }

    /// V0096: lock display selection stays independent, but the *shape* follows
    /// the existing force-simulated switch on screens without a real notch.
    func testLockGeometryFollowsSimulationOnlyWithoutPhysicalNotch() {
        let external = DisplayDescriptor(id: "ext", name: "External",
            frame: CGRect(x: -1920, y: 300, width: 1920, height: 1080), safeAreaTop: 0,
            auxiliaryLeftWidth: nil, auxiliaryRightWidth: nil, menuBarHeight: 25)
        let builtIn = DisplayDescriptor(id: "internal", name: "Built-in",
            frame: CGRect(x: 0, y: 0, width: 1728, height: 1117), safeAreaTop: 32,
            auxiliaryLeftWidth: 771.5, auxiliaryRightWidth: 771.5, menuBarHeight: 32,
            isBuiltIn: true)

        let capsule = LockDisplayPolicy.geometry(for: external, simulated: false)
        let simulated = LockDisplayPolicy.geometry(for: external, simulated: true)
        XCTAssertFalse(capsule.hasPhysicalNotch)
        // The simulated shape differs in size/contour, not in the hardware flag.
        XCTAssertNotEqual(capsule.compact.height, simulated.compact.height,
                          "switch on must use the simulated notch shape")
        XCTAssertEqual(simulated.compact.height, 24, accuracy: 0.001)
        XCTAssertEqual(capsule.compact.height, 19.5, accuracy: 0.001)

        // A real notch keeps hardware geometry even with the switch on.
        let hardware = LockDisplayPolicy.geometry(for: builtIn, simulated: true)
        XCTAssertTrue(hardware.hasPhysicalNotch)
        XCTAssertEqual(hardware.compact.height, LockDisplayPolicy.geometry(for: builtIn).compact.height)
    }
}
