#if VALORA_DEVELOPMENT
import AppKit
import Darwin
import Foundation
import QuartzCore
import ReferenceCore

/// Synthetic lyrics used only by `--audit-fluidity`. The long line has real
/// word timings and changes to a short line inside the 30s play window; the
/// line-only line keeps its words empty on purpose.
enum FluidityFixtures {
    static func timeline() -> LyricTimeline {
        let longWords = (0..<5).map { index in
            LyricWord(text: "长句片段\(index)，", start: 5 + Double(index) * 3,
                      duration: 3)
        }
        return LyricTimeline(lines: [
            LyricLine(start: 0, text: "短句开头", words: [
                LyricWord(text: "短句", start: 0, duration: 1),
                LyricWord(text: "开头", start: 1, duration: 1)
            ]),
            LyricLine(start: 5, text: longWords.map(\.text).joined(), words: longWords),
            LyricLine(start: 20, text: "第二句短句", words: [
                LyricWord(text: "第二句", start: 20, duration: 1),
                LyricWord(text: "短句", start: 21, duration: 1)
            ]),
            LyricLine(start: 40, text: "这是一句没有逐字时间的长歌词，仅在行时间驱动下显示后半句，不能平均分字伪造逐字同步"),
            LyricLine(start: 60, text: "末尾短句")
        ])
    }
}

/// Counts SwiftUI TimelineView callbacks. The flag is off in all normal app
/// modes; the branch is the only production cost of this QA seam.
@MainActor
enum LyricsFrameProbe {
    struct Snapshot {
        let activeTicks: Int
        let passiveTicks: Int
        let firstElapsed: Double?
        let lastElapsed: Double?
        let lineChanges: Int
        let wordChanges: Int
        let minInterval: Double?
        let maxInterval: Double?
        let meanInterval: Double?
        let firstTickOffset: Double?
        let lastTickOffset: Double?
        let roleTicks: [String: Int]

        var json: [String: Any] {
            [
                "activeTicks": activeTicks,
                "passiveTicks": passiveTicks,
                "firstElapsed": firstElapsed ?? 0,
                "lastElapsed": lastElapsed ?? 0,
                "lineChanges": lineChanges,
                "wordChanges": wordChanges,
                "minInterval": minInterval ?? 0,
                "maxInterval": maxInterval ?? 0,
                "meanInterval": meanInterval ?? 0,
                "firstTickOffset": firstTickOffset ?? 0,
                "lastTickOffset": lastTickOffset ?? 0,
                "roleTicks": roleTicks
            ]
        }
    }

    private struct Stats {
        var ticks = 0
        var firstElapsed: Double?
        var lastElapsed: Double?
        var lastLineStart: Double?
        var lastWordIndex: Int?
        var lineChanges = 0
        var wordChanges = 0
        var lastTick: CFTimeInterval = 0
        var firstTickOffset: Double?
        var lastTickOffset: Double?
        var roleTicks: [String: Int] = [:]
        var minInterval = Double.greatestFiniteMagnitude
        var maxInterval = 0.0
        var intervalSum = 0.0
        var intervalCount = 0
    }

    static var enabled = false
    private static var activeStats = Stats()
    private static var passiveTicks = 0
    private static var phaseStart: CFTimeInterval = 0

    static func reset() {
        activeStats = Stats()
        passiveTicks = 0
    }

    static func markPhaseStart() { phaseStart = CACurrentMediaTime() }

    static func record(role: String, elapsed: Double, lineStart: Double?, wordIndex: Int?) {
        guard enabled else { return }
        if role == "passive" {
            passiveTicks += 1
            return
        }
        let now = CACurrentMediaTime()
        let offset = phaseStart > 0 ? now - phaseStart : 0
        var stats = activeStats
        stats.ticks += 1
        stats.roleTicks[role, default: 0] += 1
        if stats.firstTickOffset == nil { stats.firstTickOffset = offset }
        stats.lastTickOffset = offset
        if stats.firstElapsed == nil { stats.firstElapsed = elapsed }
        stats.lastElapsed = elapsed
        if stats.lastTick > 0 {
            let gap = now - stats.lastTick
            stats.minInterval = min(stats.minInterval, gap)
            stats.maxInterval = max(stats.maxInterval, gap)
            stats.intervalSum += gap
            stats.intervalCount += 1
        }
        stats.lastTick = now
        if let previous = stats.lastLineStart {
            if previous != lineStart { stats.lineChanges += 1 }
        } else if lineStart != nil {
            stats.lineChanges += 1
        }
        stats.lastLineStart = lineStart
        if let previous = stats.lastWordIndex {
            if previous != wordIndex { stats.wordChanges += 1 }
        } else if wordIndex != nil {
            stats.wordChanges += 1
        }
        stats.lastWordIndex = wordIndex
        activeStats = stats
    }

    static func snapshot() -> Snapshot {
        let stats = activeStats
        return Snapshot(
            activeTicks: stats.ticks,
            passiveTicks: passiveTicks,
            firstElapsed: stats.firstElapsed,
            lastElapsed: stats.lastElapsed,
            lineChanges: stats.lineChanges,
            wordChanges: stats.wordChanges,
            minInterval: stats.intervalCount > 0 ? stats.minInterval : nil,
            maxInterval: stats.intervalCount > 0 ? stats.maxInterval : nil,
            meanInterval: stats.intervalCount > 0 ? stats.intervalSum / Double(stats.intervalCount) : nil,
            firstTickOffset: stats.firstTickOffset,
            lastTickOffset: stats.lastTickOffset,
            roleTicks: stats.roleTicks
        )
    }
}

/// System display-link callbacks for the audit window. These are scheduling
/// callbacks, not proof of compositor/render frames; the report labels them as
/// such.
@MainActor
final class AuditDisplayLink: NSObject {
    private var link: CADisplayLink?
    private var timestamps: [CFTimeInterval] = []
    private var last: CFTimeInterval = 0
    private var minGap = Double.greatestFiniteMagnitude
    private var maxGap = 0.0
    private var gapSum = 0.0
    private var gapCount = 0

    func start(on window: NSWindow) {
        stop()
        let link = window.displayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func reset() {
        timestamps.removeAll(keepingCapacity: true)
        last = 0
        minGap = Double.greatestFiniteMagnitude
        maxGap = 0
        gapSum = 0
        gapCount = 0
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    @objc private func tick(_ sender: CADisplayLink) {
        let stamp = sender.timestamp
        timestamps.append(stamp)
        if last > 0 {
            let gap = stamp - last
            minGap = min(minGap, gap)
            maxGap = max(maxGap, gap)
            gapSum += gap
            gapCount += 1
        }
        last = stamp
    }

    func snapshot() -> [String: Any] {
        [
            "callbacks": timestamps.count,
            "minGap": gapCount > 0 ? minGap : 0,
            "maxGap": gapCount > 0 ? maxGap : 0,
            "meanGap": gapCount > 0 ? gapSum / Double(gapCount) : 0,
            "note": "CADisplayLink callbacks for the audit NSWindow; not rendered-frame count"
        ]
    }
}

/// Cooperative fake provider. It never performs network or media work and
/// counts request starts, cancellations and completions for the A→B→A probe.
actor AuditLyricsProvider: LyricsProviding {
    struct Stats: Sendable {
        let calls: Int
        let cancellations: Int
        let completions: Int
        let inFlight: Int
        var json: [String: Any] {
            ["calls": calls, "cancellations": cancellations,
             "completions": completions, "inFlight": inFlight]
        }
    }

    private let result: LyricsFetchResult
    private var delayNanoseconds: UInt64 = 0
    private var calls = 0
    private var cancellations = 0
    private var completions = 0
    private var inFlight = 0

    init(result: LyricsFetchResult) { self.result = result }

    func setDelayNanoseconds(_ value: UInt64) { delayNanoseconds = value }
    func resetStats() { calls = 0; cancellations = 0; completions = 0; inFlight = 0 }

    func lyrics(for request: LyricsRequest) async throws -> LyricsFetchResult {
        calls += 1
        inFlight += 1
        do {
            if delayNanoseconds > 0 {
                try await Task.sleep(nanoseconds: delayNanoseconds)
            }
            completions += 1
            inFlight -= 1
            return result
        } catch {
            cancellations += 1
            inFlight -= 1
            throw error
        }
    }

    func stats() -> Stats {
        Stats(calls: calls, cancellations: cancellations,
              completions: completions, inFlight: inFlight)
    }
}

/// Isolated performance/resource audit. No production media, audio tap,
/// network, login item, settings write or device operation is started.
@MainActor
enum FluidityAudit {
    private struct PhaseResult {
        let name: String
        let requestedSeconds: Double
        let actualSeconds: Double
        let resources: [String: Any]
        let timeline: [String: Any]
        let display: [String: Any]
        let provider: [String: Any]
        let samples: [[String: Any]]

        var json: [String: Any] {
            ["name": name, "requestedSeconds": requestedSeconds,
             "actualSeconds": actualSeconds, "resources": resources,
             "timeline": timeline, "display": display,
             "provider": provider, "samples": samples]
        }
    }

    static func run(model: AppModel, coordinator: WindowCoordinator,
                    provider: AuditLyricsProvider, settings: RevivalSettings,
                    defaults: UserDefaults, output: String) {
        Task { @MainActor in
            let directory = URL(fileURLWithPath: output, isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var checks: [[String: Any]] = []
            var pauseDiagnostics: [String: Any] = [:]
            var rapidProvider: [String: Any] = [:]
            @MainActor func check(_ name: String, _ passed: Bool) {
                checks.append(["name": name, "passed": passed])
            }
            func settle(_ seconds: Double = 0.4) async {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            }
            @MainActor func setMusicPreference(_ key: String, _ value: Any) {
                var values = defaults.dictionary(forKey: "referenceSettingsUI") ?? [:]
                values[key] = value
                defaults.set(values, forKey: "referenceSettingsUI")
                settings.reloadPreferences()
            }

            let display = AuditDisplayLink()
            await settle(0.8)
            check("fake lyrics reached ready", model.lyrics.status == .ready)
            check("compact lyric row is visible", model.showsCompactLyrics)
            let initialProviderStats = await provider.stats()
            let initialProvider = initialProviderStats.json

            // Baseline: same visible SwiftUI lyric view, but no display-link
            // sampler and no Timeline probe. This is the measurement-overhead
            // comparison, not a separate product mode.
            model.elapsed = 0.5
            model.playing = true
            LyricsFrameProbe.enabled = false
            display.stop()
            let baseline = await measure(name: "baseline-play-no-probe", seconds: 10,
                                         model: model, coordinator: coordinator,
                                         provider: provider, display: display)

            LyricsFrameProbe.enabled = true
            display.start(on: coordinator.panel)
            let play = await measure(name: "compact-play-word-sync", seconds: 30,
                                     model: model, coordinator: coordinator,
                                     provider: provider, display: display)
            check("compact play produced Timeline callbacks", int(play.timeline, "activeTicks") > 30)
            check("compact play advanced elapsed", double(play.timeline, "lastElapsed")
                  - double(play.timeline, "firstElapsed") > 20)
            check("compact play crossed short/long lines", int(play.timeline, "lineChanges") >= 2)
            check("compact play advanced real words", int(play.timeline, "wordChanges") >= 2)
            check("stable play did not repeat the lyric request", int(play.provider, "calls") == 0)
            check("compact play had display-link callbacks", int(play.display, "callbacks") > 30)

            model.elapsed = 1.2
            model.playing = true
            model.showsOutputVolume = true
            coordinator.expand()
            await settle(0.6)
            check("expanded player keeps lyric row", model.expanded && model.showsLyricsInExpanded)
            let expanded = await measure(name: "expanded-with-volume", seconds: 5,
                                         model: model, coordinator: coordinator,
                                         provider: provider, display: display)
            check("expanded timeline keeps refreshing", int(expanded.timeline, "activeTicks") > 5)
            check("expanded does not mount a second compact lyric Timeline",
                  roleTicks(expanded.timeline, "expanded") > 5
                  && roleTicks(expanded.timeline, "active") == 0)
            model.showsOutputVolume = false
            await settle(0.25)
            check("expanded lyric survives volume-row hide", model.expanded && model.showsLyricsInExpanded)
            model.showsOutputVolume = true
            await settle(0.25)
            coordinator.collapse()
            await settle(0.5)
            check("collapse restores compact lyric row", !model.expanded && model.showsCompactLyrics)

            model.elapsed = 5.5
            await settle(0.25)
            check("seek to long line selects timed words",
                  (model.currentLyricLine?.words.count ?? 0) > 0)
            model.elapsed = 1.2
            await settle(0.25)
            check("backward seek selects short line", model.currentLyricLine?.text == "短句开头")
            model.elapsed = 21.2
            await settle(0.25)
            check("forward seek selects later short line", model.currentLyricLine?.text == "第二句短句")
            model.playing = true
            LyricsFrameProbe.reset()
            let resumed = await measure(name: "resumed-after-seek", seconds: 5,
                                         model: model, coordinator: coordinator,
                                         provider: provider, display: display)
            check("resume after seek refreshes timeline", int(resumed.timeline, "activeTicks") > 5)

            model.playing = false
            await settle(0.25)
            let pausedLine = model.currentLyricLine?.text
            let pausedBeforeIdle = await measure(name: "paused-before-idle", seconds: 1,
                                                 model: model, coordinator: coordinator,
                                                 provider: provider, display: display)
            check("pause stops Timeline callbacks before mature idle",
                  int(pausedBeforeIdle.timeline, "activeTicks") == 0)
            check("pause preserves selected lyric line before mature idle",
                  pausedLine != nil && model.currentLyricLine?.text == pausedLine)
            // Let the mature 3s paused-media idle transition finish before the
            // long-pause sample; that transition is not lyric animation.
            await settle(1.0)
            let paused = await measure(name: "paused-through-idle", seconds: 30,
                                       model: model, coordinator: coordinator,
                                       provider: provider, display: display)
            let pausedLineAfter = model.currentLyricLine?.text
            check("pause has no Timeline refresh after idle transition",
                  int(paused.timeline, "activeTicks") == 0)
            check("paused activity follows mature idle hide",
                  !model.showsCompactLyrics && !model.mediaIdle.visible)
            pauseDiagnostics = ["before": pausedLine ?? "nil", "after": pausedLineAfter ?? "nil",
                                 "ticks": int(paused.timeline, "activeTicks"),
                                 "lastTickOffset": double(paused.timeline, "lastTickOffset")]
            model.playing = true
            await settle(0.25)

            model.elapsed = 40.5
            await settle(0.25)
            check("line-only long LRC has no fake words", model.currentLyricLine?.words.isEmpty == true)
            let lineOnly = await measure(name: "line-only-long", seconds: 8,
                                         model: model, coordinator: coordinator,
                                         provider: provider, display: display)
            check("line-only long LRC still refreshes timeline", int(lineOnly.timeline, "activeTicks") > 5)
            check("line-only long LRC creates no word transitions", int(lineOnly.timeline, "wordChanges") == 0)

            settings.showNotch = false
            await settle(0.4)
            check("hidden notch panel is not visible", !coordinator.panel.isVisible)
            let hidden = await measure(name: "hidden-notch", seconds: 30,
                                       model: model, coordinator: coordinator,
                                       provider: provider, display: display)
            check("hide stops Timeline callbacks", int(hidden.timeline, "activeTicks") == 0)
            settings.showNotch = true
            await settle(0.5)
            check("showing notch restores compact lyrics", model.showsCompactLyrics)

            setMusicPreference("showLyrics", false)
            await settle(0.4)
            check("lyrics-off removes the compact row", !model.showsCompactLyrics)
            let lyricsOff = await measure(name: "lyrics-off", seconds: 20,
                                          model: model, coordinator: coordinator,
                                          provider: provider, display: display)
            check("lyrics-off stops Timeline callbacks", int(lyricsOff.timeline, "activeTicks") == 0)
            setMusicPreference("showLyrics", true)
            await settle(0.8)
            check("lyrics-on restores ready state", model.lyrics.status == .ready)

            let ids = coordinator.verificationScreenIDs
            var passive: PhaseResult?
            if ids.count > 1 {
                coordinator.verificationActivateScreen(ids[1])
                await settle(0.5)
                check("active screen moved to injected external display",
                      coordinator.verificationActiveScreenID == ids[1])
                check("one passive panel remains", coordinator.verificationSecondaryPanels.count == 1)
                let passiveResult = await measure(name: "passive-external-active", seconds: 20,
                                                  model: model, coordinator: coordinator,
                                                  provider: provider, display: display)
                passive = passiveResult
                check("active screen still refreshes lyrics", int(passiveResult.timeline, "activeTicks") > 5)
                check("passive screen performs no lyric Timeline callbacks",
                      int(passiveResult.timeline, "passiveTicks") == 0)
                coordinator.verificationActivateScreen(ids[0])
                await settle(0.4)
            } else {
                check("injected multi-screen audit has passive panel", false)
            }

            await provider.setDelayNanoseconds(800_000_000)
            await provider.resetStats()
            LyricsFrameProbe.reset()
            model.title = "audit-A"
            await settle(0.15)
            model.title = "audit-B"
            await settle(0.15)
            model.title = "audit-A"
            await settle(2.2)
            let rapid = await provider.stats()
            rapidProvider = rapid.json
            check("quick A→B→A starts all requests", rapid.calls >= 3)
            check("quick A→B→A cancels stale requests", rapid.cancellations >= 2)
            check("quick A→B→A leaves no provider request in flight", rapid.inFlight == 0)
            check("final A resolves to ready lyrics", model.lyrics.status == .ready)
            check("lyrics controller owns no dangling request task",
                  model.lyricsController?.verificationTaskIsActive == false)

            display.stop()
            LyricsFrameProbe.enabled = false
            let allPassed = checks.allSatisfy { $0["passed"] as? Bool == true }
            let environment: [String: Any] = [
                "os": ProcessInfo.processInfo.operatingSystemVersionString,
                "processorCount": ProcessInfo.processInfo.processorCount,
                "physicalMemoryBytes": ProcessInfo.processInfo.physicalMemory,
                "hostName": ProcessInfo.processInfo.hostName
            ]
            var method: [String: Any] = [:]
            method["media"] = "fake AppModel; no MediaController/audio/network started"
            method["resourceSampler"] = "getrusage(RUSAGE_SELF) + mach_task_basic_info.resident_size, 1s samples"
            method["timelineProbe"] = "SwiftUI TimelineView body callback, 30Hz local lyric timeline"
            method["displayLink"] = "NSWindow.displayLink on the audit NSWindow; scheduling callbacks, not rendered frames"
            method["measurementOverhead"] = "one 1s MainActor resource sample, one display-link callback stream, one disabled-by-default Timeline probe branch; baseline-play-no-probe is recorded separately"
            let totalPhaseSeconds = 10 + 30 + 5 + 5 + 1 + 30 + 8 + 30 + 20 + 20
            method["phasesTotalSeconds"] = totalPhaseSeconds
            var phases: [[String: Any]] = [baseline.json, play.json, expanded.json,
                                           resumed.json, pausedBeforeIdle.json, paused.json,
                                           lineOnly.json, hidden.json, lyricsOff.json]
            if let passive { phases.append(passive.json) }
            let limitations: [String] = [
                "CADisplayLink callbacks are not equal to displayed/rendered frames; no compositor frame counter or human smoothness claim.",
                "Injected two-screen display is not physical dual-screen verification.",
                "Fake word timing is not real QQ voice alignment; real alignment remains for user hardware/network testing.",
                "CPU/RSS are process-wide and hardware/OS specific; no universal threshold is asserted."
            ]
            var result: [String: Any] = [:]
            result["passed"] = allPassed
            result["checks"] = checks
            result["environment"] = environment
            result["method"] = method
            result["initialProvider"] = initialProvider
            result["phases"] = phases
            result["limitations"] = limitations
            result["pauseDiagnostics"] = pauseDiagnostics
            result["rapidProvider"] = rapidProvider
            if let data = try? JSONSerialization.data(withJSONObject: result,
                                                       options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: directory.appendingPathComponent("audit.json"))
            }
            fputs(allPassed ? "AUDIT PASSED\n" : "AUDIT FAILED\n", stderr)
            NSApp.terminate(nil)
        }
    }

    private static func measure(name: String, seconds: Double, model: AppModel,
                                coordinator: WindowCoordinator,
                                provider: AuditLyricsProvider,
                                display: AuditDisplayLink) async -> PhaseResult {
        await provider.resetStats()
        // Let the state change that opened this phase settle before resetting
        // counters; otherwise a single transition frame can look like ongoing
        // animation in the paused/hidden phases.
        try? await Task.sleep(nanoseconds: 750_000_000)
        LyricsFrameProbe.reset()
        display.reset()
        LyricsFrameProbe.markPhaseStart()
        let requested = seconds
        let startWall = ProcessInfo.processInfo.systemUptime
        let startCPU = cpuSeconds()
        var samples: [[String: Any]] = []
        var nextSample = startWall + 1
        samples.append(sample(at: 0, wall: startWall, cpu: startCPU))
        while true {
            let now = ProcessInfo.processInfo.systemUptime
            let elapsed = now - startWall
            if elapsed >= requested { break }
            let wait = min(1, requested - elapsed)
            try? await Task.sleep(nanoseconds: UInt64(max(0.01, wait) * 1_000_000_000))
            let after = ProcessInfo.processInfo.systemUptime
            if after >= nextSample || requested - (after - startWall) < 0.05 {
                samples.append(sample(at: after - startWall, wall: after,
                                      cpu: cpuSeconds()))
                nextSample += 1
            }
        }
        let endWall = ProcessInfo.processInfo.systemUptime
        let endCPU = cpuSeconds()
        samples.append(sample(at: endWall - startWall, wall: endWall, cpu: endCPU))
        let rssValues = samples.compactMap { $0["rssBytes"] as? UInt64 }
        let cpuPercent = endWall > startWall
            ? (endCPU - startCPU) / (endWall - startWall) * 100 : 0
        let providerStats = await provider.stats()
        let resources: [String: Any] = [
            "cpuSeconds": endCPU - startCPU,
            "cpuPercent": cpuPercent,
            "rssMinBytes": rssValues.min() ?? 0,
            "rssMaxBytes": rssValues.max() ?? 0,
            "rssMeanBytes": rssValues.isEmpty ? 0 : rssValues.reduce(0, +) / UInt64(rssValues.count),
            "sampleIntervalSeconds": 1,
            "sampleCount": samples.count
        ]
        return PhaseResult(name: name, requestedSeconds: requested,
                           actualSeconds: endWall - startWall, resources: resources,
                           timeline: LyricsFrameProbe.snapshot().json,
                           display: display.snapshot(),
                           provider: providerStats.json, samples: samples)
    }

    private static func sample(at elapsed: Double, wall: Double, cpu: Double) -> [String: Any] {
        ["elapsedSeconds": elapsed, "wallSeconds": wall, "cpuSeconds": cpu,
         "rssBytes": residentBytes()]
    }

    private static func cpuSeconds() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        let user = Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1_000_000
        let system = Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1_000_000
        return user + system
    }

    private static func residentBytes() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size
                                            / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), rebound, &count)
            }
        }
        return result == KERN_SUCCESS ? UInt64(info.resident_size) : 0
    }

    private static func int(_ dictionary: [String: Any], _ key: String) -> Int {
        (dictionary[key] as? NSNumber)?.intValue ?? 0
    }

    private static func double(_ dictionary: [String: Any], _ key: String) -> Double {
        (dictionary[key] as? NSNumber)?.doubleValue ?? 0
    }

    private static func roleTicks(_ dictionary: [String: Any], _ role: String) -> Int {
        guard let roles = dictionary["roleTicks"] as? [String: Int] else { return 0 }
        return roles[role] ?? 0
    }
}
#endif
