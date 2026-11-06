#if VALORA_DEVELOPMENT
import AppKit
import Darwin
import Foundation
import QuartzCore
import ReferenceCore

/// Silent fake media source for the resource baseline: it never reads the
/// system Now Playing session, never sends a command and never performs
/// network/audio work. It only lets `MediaController` run its real 0.25 s
/// scheduling while the measurement toggles the music switch.
@MainActor
final class AuditSilentMediaSource: SystemMediaProviding {
    var onSnapshot: (@MainActor (SystemMediaSnapshot?) -> Void)?
    var onError: (@MainActor (String) -> Void)?
    func start() {}
    func stop() {}
    func perform(_ arguments: [String], expected: SystemMediaSnapshot, requireSameTrack: Bool,
                 completion: @escaping @MainActor (Bool) -> Void) {
        completion(false)
    }
}

/// Local fake with real `SystemMediaSnapshot` timestamps and artwork. It feeds
/// the existing `MediaController` time anchor so elapsed/lyrics advance exactly
/// like a live session would, without reading the system player or sending any
/// real command. Seek/track changes are fixture-only.
@MainActor
final class AuditTickingMediaSource: SystemMediaProviding {
    var onSnapshot: (@MainActor (SystemMediaSnapshot?) -> Void)?
    var onError: (@MainActor (String) -> Void)?
    private var timer: Timer?
    private var startedAt = 0.0
    private var baseElapsed = 0.0
    private var playing = true
    private let duration = 240.0
    private var itemID = "baseline-A"
    private var title = "baseline-A"
    private var artist = "baseline-artist"
    private var album = "baseline-album"
    private var artworkBase64: String?
    private(set) var publishCount = 0
    private let publishInterval: TimeInterval = 0.5
    private let now: () -> TimeInterval

    init(now: @escaping () -> TimeInterval = { Date().timeIntervalSince1970 }) {
        self.now = now
    }

    func configure(baseElapsed: Double, playing: Bool, artworkPNG: Data?) {
        self.baseElapsed = max(0, min(duration, baseElapsed))
        self.playing = playing
        self.artworkBase64 = artworkPNG?.base64EncodedString()
        startedAt = now()
    }

    func start() {
        startedAt = now()
        publish()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: publishInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.publish() }
        }
    }

    func stop() { timer?.invalidate(); timer = nil }

    func setPlaying(_ value: Bool) {
        baseElapsed = currentElapsed()
        playing = value
        startedAt = now()
        publish()
    }

    func seek(to seconds: Double) {
        baseElapsed = max(0, min(duration, seconds))
        startedAt = now()
        publish()
    }

    func changeTrack(id: String, title: String, artist: String, artworkPNG: Data?) {
        itemID = id
        self.title = title
        self.artist = artist
        self.artworkBase64 = artworkPNG?.base64EncodedString()
        baseElapsed = 0
        startedAt = Date().timeIntervalSince1970
        publish()
    }

    func currentElapsed() -> Double {
        guard playing else { return baseElapsed }
        return min(duration, baseElapsed + max(0, now() - startedAt))
    }

    func publish() {
        publishCount += 1
        onSnapshot?(snapshot())
    }

    func snapshot() -> SystemMediaSnapshot {
        let epoch = now()
        var payload: [String: Any] = [
            "bundleIdentifier": "com.wangqing.valora.audit",
            "title": title, "artist": artist, "album": album,
            "playing": playing,
            "durationMicros": duration * 1_000_000,
            "elapsedTimeMicros": currentElapsed() * 1_000_000,
            "timestampEpochMicros": epoch * 1_000_000,
            "playbackRate": playing ? 1.0 : 0.0,
            "contentItemIdentifier": itemID
        ]
        if let artworkBase64 { payload["artworkData"] = artworkBase64 }
        return SystemMediaSnapshot(payload)!
    }

    func perform(_ arguments: [String], expected: SystemMediaSnapshot, requireSameTrack: Bool,
                 completion: @escaping @MainActor (Bool) -> Void) {
        if arguments.count == 2, arguments[0] == "seek", let micros = Double(arguments[1]) {
            seek(to: micros / 1_000_000)
            completion(true)
            return
        }
        if arguments.count == 2, arguments[0] == "send", arguments[1] == "2" {
            setPlaying(!playing)
            completion(true)
            return
        }
        completion(false)
    }
}

/// Two measurements per display-link callback:
/// - `sender.timestamp` gaps: the display clock's own timestamps (video-refresh
///   clock), not the main-thread arrival latency.
/// - wall-clock arrival gaps: `ProcessInfo.systemUptime` sampled when the
///   callback body runs, which includes scheduling latency.
/// Neither is a rendered/composited frame count.
struct BaselineGapStats: Equatable {
    private(set) var timestampGaps: [Double] = []
    private(set) var arrivalGaps: [Double] = []

    mutating func record(timestampGap: Double?, arrivalGap: Double?) {
        if let timestampGap, timestampGap.isFinite { timestampGaps.append(timestampGap) }
        if let arrivalGap, arrivalGap.isFinite { arrivalGaps.append(arrivalGap) }
    }

    static func percentiles(_ values: [Double]) -> (p50: Double, p95: Double, max: Double, mean: Double) {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return (0, 0, 0, 0) }
        func pick(_ p: Double) -> Double {
            let index = min(sorted.count - 1, max(0, Int((Double(sorted.count - 1) * p).rounded())))
            return sorted[index]
        }
        return (pick(0.5), pick(0.95), sorted.last ?? 0, sorted.reduce(0, +) / Double(sorted.count))
    }

    var summary: [String: Any] {
        let ts = Self.percentiles(timestampGaps)
        let arrival = Self.percentiles(arrivalGaps)
        let callbacks = max(timestampGaps.count, arrivalGaps.count) + (arrivalGaps.isEmpty ? 0 : 1)
        let arrivalSum = arrivalGaps.reduce(0, +)
        return [
            "callbacks": callbacks,
            "timestampCallbacks": timestampGaps.count + (timestampGaps.isEmpty ? 0 : 1),
            "timestampP50Gap": ts.p50,
            "timestampP95Gap": ts.p95,
            "timestampMaxGap": ts.max,
            "timestampMeanGap": ts.mean,
            "arrivalP50Gap": arrival.p50,
            "arrivalP95Gap": arrival.p95,
            "arrivalMaxGap": arrival.max,
            "arrivalMeanGap": arrival.mean,
            "arrivalRateHz": arrivalSum > 0 ? Double(arrivalGaps.count) / arrivalSum : 0.0,
            "definitions": [
                "timestampGap": "difference between CADisplayLink sender.timestamp values (video-refresh clock)",
                "arrivalGap": "ProcessInfo.systemUptime sampled in the callback body (main-thread arrival, includes scheduling)",
                "frames": "neither value is a rendered/composited frame count"
            ]
        ]
    }
}

@MainActor
final class BaselineDisplayLink: NSObject {
    private var link: CADisplayLink?
    private var stats = BaselineGapStats()
    private var lastTimestamp: CFTimeInterval = 0
    private var lastArrival: TimeInterval = 0

    func start(on window: NSWindow) {
        stop()
        let newLink = window.displayLink(target: self, selector: #selector(tick(_:)))
        newLink.add(to: .main, forMode: .common)
        link = newLink
    }

    func reset() {
        stats = BaselineGapStats()
        lastTimestamp = 0
        lastArrival = 0
    }

    func stop() { link?.invalidate(); link = nil }

    @objc private func tick(_ sender: CADisplayLink) {
        let arrival = ProcessInfo.processInfo.systemUptime
        let timestamp = sender.timestamp
        stats.record(timestampGap: lastTimestamp > 0 ? timestamp - lastTimestamp : nil,
                     arrivalGap: lastArrival > 0 ? arrival - lastArrival : nil)
        lastTimestamp = timestamp
        lastArrival = arrival
    }

    func snapshot() -> [String: Any] {
        var value = stats.summary
        value["note"] = "CADisplayLink callbacks on the QA window; not rendered-frame count"
        return value
    }
}

/// V0106 isolated resource/fluidity baseline. One QA window, one silent fake
/// media source, fake lyrics, no status item, no permission, no network, no
/// real media/calendar/device/lock operation. Measurement tool only; compiled
/// out of Release.
@MainActor
enum ResourceBaselineAudit {
    private struct PhaseResult {
        let name: String
        let requestedSeconds: Double
        let actualSeconds: Double
        let resources: [String: Any]
        let timeline: [String: Any]
        let display: [String: Any]
        let samples: [[String: Any]]
        let notes: [String: Any]

        var json: [String: Any] {
            ["name": name, "requestedSeconds": requestedSeconds,
             "actualSeconds": actualSeconds, "resources": resources,
             "timeline": timeline, "display": display,
             "samples": samples, "notes": notes]
        }
    }

    static func run(model: AppModel, coordinator: WindowCoordinator,
                    settings: RevivalSettings, defaults: UserDefaults, output: String,
                    short: Bool = false) {
        Task { @MainActor in
            let directory = URL(fileURLWithPath: output, isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if short {
                await runShort(model: model, coordinator: coordinator, settings: settings,
                               defaults: defaults, directory: directory)
                return
            }
            var checks: [[String: Any]] = []
            @MainActor func check(_ name: String, _ passed: Bool) {
                checks.append(["name": name, "passed": passed])
            }
            func settle(_ seconds: Double) async {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            }
            @MainActor func setMusicPreference(_ key: String, _ value: Any) {
                var values = defaults.dictionary(forKey: "referenceSettingsUI") ?? [:]
                values[key] = value
                defaults.set(values, forKey: "referenceSettingsUI")
                settings.reloadPreferences()
            }
            func artwork(_ hue: CGFloat) -> NSImage {
                let image = NSImage(size: NSSize(width: 64, height: 64))
                image.lockFocus()
                NSColor(calibratedHue: hue, saturation: 0.55, brightness: 0.75, alpha: 1).setFill()
                NSBezierPath(rect: NSRect(x: 0, y: 0, width: 64, height: 64)).fill()
                NSColor(calibratedHue: hue + 0.35, saturation: 0.6, brightness: 0.9, alpha: 1).setFill()
                NSBezierPath(ovalIn: NSRect(x: 8, y: 8, width: 48, height: 48)).fill()
                image.unlockFocus()
                return image
            }

            // Silent fake source: the controller owns the real 0.25 s schedule,
            // but no player/session is read and no command is sent.
            model.media = MediaController(model, system: AuditSilentMediaSource(), retryInterval: 1)
            settings.nowPlayingEnabled = false
            model.previewMode = false
            model.media.start()
            await settle(0.4)

            let display = BaselineDisplayLink()
            let panel = coordinator.panel
            check("single QA window is available", panel != nil)
            LyricsFrameProbe.enabled = false

            // 1. All modules off: music switch off, notch hidden.
            settings.showNotch = false
            setMusicPreference("showLyrics", true)
            model.playing = false
            model.elapsed = 0
            await settle(0.8)
            check("music off does not show music activity", !model.showsMusicActivity)
            let musicOff = await measure(name: "steady-music-off-hidden", seconds: 30,
                                         model: model, display: nil, probe: false)
            check("music off has no lyric Timeline callbacks",
                  int(musicOff.timeline, "activeTicks") == 0)

            // 2. Compact fake playback with lyrics.
            settings.showNotch = true
            settings.nowPlayingEnabled = true
            model.playing = true
            model.elapsed = 0.5
            model.title = "baseline-A"
            model.artist = "baseline-artist"
            model.album = "baseline-album"
            model.duration = 240
            model.source = "预览"
            model.artwork = artwork(0.55)
            await settle(1.5)
            check("compact lyrics are visible while playing", model.showsCompactLyrics)
            LyricsFrameProbe.enabled = true
            if let panel { display.start(on: panel) }
            let compactPlay = await measure(name: "steady-compact-play", seconds: 30,
                                            model: model, display: display, probe: true)
            check("compact play produces Timeline callbacks",
                  int(compactPlay.timeline, "activeTicks") > 100)
            check("compact play produces display-link callbacks",
                  int(compactPlay.display, "callbacks") > 100)

            // 3. Paused after the mature idle transition.
            model.playing = false
            await settle(3.2)
            check("pause hides activity after idle", !model.showsCompactLyrics)
            let paused = await measure(name: "steady-paused", seconds: 30,
                                       model: model, display: display, probe: true)
            check("pause stops Timeline callbacks", int(paused.timeline, "activeTicks") == 0)

            // 4. Lyrics off while still playing.
            model.playing = true
            model.elapsed = 0.5
            await settle(0.8)
            setMusicPreference("showLyrics", false)
            await settle(0.8)
            check("lyrics off removes the compact row", !model.showsCompactLyrics)
            let lyricsOff = await measure(name: "steady-lyrics-off", seconds: 30,
                                          model: model, display: display, probe: true)
            check("lyrics off stops Timeline callbacks",
                  int(lyricsOff.timeline, "activeTicks") == 0)
            setMusicPreference("showLyrics", true)
            await settle(1.0)

            // 5. One interaction pass in the same window.
            model.elapsed = 1.2
            await settle(0.6)
            let interaction = await measureInteraction(model: model, coordinator: coordinator,
                                                       display: display, artwork: artwork)

            // 6. Hold fake playback for three minutes (compact, long line).
            model.elapsed = 6.0
            model.playing = true
            model.showsOutputVolume = false
            if model.expanded { coordinator.collapse() }
            await settle(1.0)
            let hold = await measure(name: "hold-3min-fake-play", seconds: 180,
                                     model: model, display: display, probe: true)
            check("three-minute hold keeps the lyric view refreshing",
                  int(hold.timeline, "activeTicks") > 500)

            // 7. Pause after the hold. The row's teardown transition needs to
            // finish before the probe reset; otherwise one removal frame can be
            // recorded as ongoing refresh.
            model.playing = false
            await settle(5.0)
            let pauseAfter = await measure(name: "pause-after-hold", seconds: 30,
                                           model: model, display: display, probe: true)
            check("pause after hold stops Timeline callbacks",
                  int(pauseAfter.timeline, "activeTicks") == 0)
            display.stop()
            LyricsFrameProbe.enabled = false

            let allPassed = checks.allSatisfy { $0["passed"] as? Bool == true }
            let environment: [String: Any] = [
                "os": ProcessInfo.processInfo.operatingSystemVersionString,
                "processorCount": ProcessInfo.processInfo.processorCount,
                "physicalMemoryBytes": ProcessInfo.processInfo.physicalMemory,
                "hostName": ProcessInfo.processInfo.hostName,
                "maxFramesPerSecond": NSScreen.main?.maximumFramesPerSecond ?? 0,
                "screens": NSScreen.screens.map { screen -> [String: Any] in
                    ["name": screen.localizedName,
                     "maxFramesPerSecond": screen.maximumFramesPerSecond,
                     "frame": NSStringFromRect(screen.frame),
                     "scale": screen.backingScaleFactor]
                }
            ]
            var method: [String: Any] = [:]
            method["configuration"] = "debug (VALORA_DEVELOPMENT); not the Release resource cost"
            method["media"] = "AuditSilentMediaSource; MediaController's real 0.25 s schedule, no player read/command"
            method["resourceSampler"] = "getrusage(RUSAGE_SELF) + mach_task_basic_info.resident_size + task_vm_info.phys_footprint, 1 s MainActor samples"
            method["timelineProbe"] = "SwiftUI TimelineView body callback (CompactLyricsView); enabled only for playing phases"
            method["displayLink"] = "NSWindow.displayLink on the single QA window; callback scheduling, not composited frames"
            method["window"] = "one WindowCoordinator panel on the main display; no status item, no activation"
            method["phasesSeconds"] = 30 * 4 + 180 + 30
            method["overhead"] = "1 s MainActor resource sample and one display-link stream during animated phases"
            let limitations: [String] = [
                "CADisplayLink callback gaps are not rendered/composited frame times; no 60 fps or Alcove-parity claim.",
                "Debug-build CPU/RSS differ from the Release app; this is a relative baseline, not a user-facing budget.",
                "Wakeups are unavailable without privileged tooling (powermetrics); not guessed.",
                "Physical dual-screen, real lock/unlock animation, real QQ voice alignment and real device/calendar flows are not measured here.",
                "A static model.elapsed is used for long-line following; this measures animation callbacks, not media-clock drift."
            ]
            var result: [String: Any] = [:]
            result["schema"] = 1
            result["passed"] = allPassed
            result["checks"] = checks
            result["environment"] = environment
            result["method"] = method
            result["limitations"] = limitations
            result["phases"] = [musicOff.json, compactPlay.json, paused.json, lyricsOff.json,
                                interaction.json, hold.json, pauseAfter.json]
            if let data = try? JSONSerialization.data(withJSONObject: result,
                                                       options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: directory.appendingPathComponent("baseline.json"))
            }
            fputs(allPassed ? "RESOURCE BASELINE PASSED\n" : "RESOURCE BASELINE FAILED\n", stderr)
            coordinator.cancelPendingHover()
            NSApp.terminate(nil)
        }
    }

    /// One scripted pass: expand → volume → collapse, short/long line, fake
    /// track + artwork change. No repeated open/close loop.
    private static func measureInteraction(model: AppModel, coordinator: WindowCoordinator,
                                           display: BaselineDisplayLink,
                                           artwork: @escaping (CGFloat) -> NSImage) async -> PhaseResult {
        LyricsFrameProbe.reset()
        display.reset()
        LyricsFrameProbe.markPhaseStart()
        let startedWall = ProcessInfo.processInfo.systemUptime
        let startedCPU = cpuSeconds()
        var samples: [[String: Any]] = []
        var steps: [[String: Any]] = []
        var nextSample = startedWall + 1
        var stepIndex = 0
        let script: [(Double, String, @MainActor () -> Void)] = [
            (0.0, "expand", { coordinator.expand() }),
            (2.0, "volume-on", { model.showsOutputVolume = true }),
            (4.0, "volume-off", { model.showsOutputVolume = false }),
            (5.0, "collapse", { coordinator.collapse() }),
            (6.0, "short-to-long", { model.elapsed = 6.0 }),
            (8.0, "long-to-short", { model.elapsed = 21.0 }),
            (10.0, "track-change", {
                model.title = "baseline-B"
                model.artist = "second-artist"
                model.artwork = artwork(0.05)
            }),
            (12.0, "track-back", {
                model.title = "baseline-A"
                model.artist = "baseline-artist"
                model.artwork = artwork(0.55)
            })
        ]
        let total = 15.0
        samples.append(sample(at: 0, wall: startedWall, cpu: startedCPU))
        while true {
            let now = ProcessInfo.processInfo.systemUptime
            let elapsed = now - startedWall
            if elapsed >= total { break }
            while stepIndex < script.count, script[stepIndex].0 <= elapsed {
                script[stepIndex].2()
                steps.append(["at": script[stepIndex].0, "action": script[stepIndex].1])
                stepIndex += 1
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
            let after = ProcessInfo.processInfo.systemUptime
            if after >= nextSample {
                samples.append(sample(at: after - startedWall, wall: after, cpu: cpuSeconds()))
                nextSample += 1
            }
        }
        let endWall = ProcessInfo.processInfo.systemUptime
        let endCPU = cpuSeconds()
        samples.append(sample(at: endWall - startedWall, wall: endWall, cpu: endCPU))
        return PhaseResult(name: "interaction-once", requestedSeconds: total,
                           actualSeconds: endWall - startedWall,
                           resources: resourceSummary(samples: samples, startWall: startedWall,
                                                      endWall: endWall, startCPU: startedCPU,
                                                      endCPU: endCPU),
                           timeline: LyricsFrameProbe.snapshot().json,
                           display: display.snapshot(), samples: samples,
                           notes: ["steps": steps])
    }

    /// Bounded R1 run: optimized-QA host, one fake anchor with timestamps,
    /// compact play (link on/off), one interaction pass, pause. ~105 s.
    private static func runShort(model: AppModel, coordinator: WindowCoordinator,
                                 settings: RevivalSettings, defaults: UserDefaults,
                                 directory: URL) async {
        var checks: [[String: Any]] = []
        @MainActor func check(_ name: String, _ passed: Bool) {
            checks.append(["name": name, "passed": passed])
        }
        func settle(_ seconds: Double) async {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        }
        @MainActor func setMusicPreference(_ key: String, _ value: Any) {
            var values = defaults.dictionary(forKey: "referenceSettingsUI") ?? [:]
            values[key] = value
            defaults.set(values, forKey: "referenceSettingsUI")
            settings.reloadPreferences()
        }

        let source = AuditTickingMediaSource()
        source.configure(baseElapsed: 0.5, playing: true, artworkPNG: Self.artworkPNG(0.55))
        model.media = MediaController(model, system: source, retryInterval: 1)
        settings.nowPlayingEnabled = false
        model.previewMode = false
        model.media.start()
        await settle(0.4)

        let display = BaselineDisplayLink()
        let panel = coordinator.panel
        check("single QA window is available", panel != nil)

        settings.showNotch = true
        setMusicPreference("showLyrics", true)
        settings.nowPlayingEnabled = true
        for _ in 0..<100 where model.lyrics.status != .ready {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        await settle(1.5)
        check("fake anchor advanced before measurement", model.elapsed > 1.0)
        check("compact lyrics are visible", model.showsCompactLyrics)
        check("music activity is visible", model.showsMusicActivity)

        LyricsFrameProbe.enabled = true
        if let panel { display.start(on: panel) }
        let startElapsed = model.elapsed
        let play = await measure(name: "opt-compact-play-30", seconds: 30,
                                 model: model, display: display, probe: true, panel: panel)
        check("fake anchor advanced during 30 s compact play", model.elapsed - startElapsed > 25)
        check("lyrics crossed lines during play", int(play.timeline, "lineChanges") >= 2)
        check("word index/fraction changed during play", int(play.timeline, "wordChanges") >= 2)
        check("compact play produced Timeline callbacks", int(play.timeline, "activeTicks") > 100)
        check("compact play produced display-link callbacks", int(play.display, "callbacks") > 100)

        display.stop()
        LyricsFrameProbe.reset()
        let noLink = await measure(name: "opt-compact-play-30-no-displaylink", seconds: 30,
                                   model: model, display: nil, probe: true, panel: panel)
        check("play continues without the display-link sampler",
              int(noLink.timeline, "activeTicks") > 100)
        if let panel { display.start(on: panel) }

        let interaction = await measureInteractionShort(
            model: model, coordinator: coordinator, display: display, source: source,
            panel: panel, artworkA: Self.artworkPNG(0.55), artworkB: Self.artworkPNG(0.05))
        check("interaction kept the lyric view refreshing",
              int(interaction.timeline, "activeTicks") > 100)
        check("interaction recorded the full script",
              (interaction.notes["steps"] as? [[String: Any]])?.count == 8)

        let pauseStartElapsed = model.elapsed
        source.setPlaying(false)
        await settle(5.5)
        let paused = await measure(name: "opt-pause-30", seconds: 30,
                                   model: model, display: display, probe: true, panel: panel)
        check("pause stops Timeline callbacks", int(paused.timeline, "activeTicks") == 0)
        check("pause freezes the fake anchor",
              abs(model.elapsed - pauseStartElapsed) < 0.2)

        display.stop()
        LyricsFrameProbe.enabled = false

        let allPassed = checks.allSatisfy { $0["passed"] as? Bool == true }
        let screens: [[String: Any]] = NSScreen.screens.map { screen in
            ["name": screen.localizedName,
             "maxFramesPerSecond": screen.maximumFramesPerSecond,
             "frame": NSStringFromRect(screen.frame),
             "scale": screen.backingScaleFactor]
        }
        let environment: [String: Any] = [
            "os": ProcessInfo.processInfo.operatingSystemVersionString,
            "processorCount": ProcessInfo.processInfo.processorCount,
            "physicalMemoryBytes": ProcessInfo.processInfo.physicalMemory,
            "hostName": ProcessInfo.processInfo.hostName,
            "screens": screens,
            "panelScreen": screenInfo(panel)
        ]
        var method: [String: Any] = [:]
        method["configuration"] = "release-optimized QA host (swift -c release + -DVALORA_DEVELOPMENT); not the shipping Release artifact"
        method["media"] = "AuditTickingMediaSource: local SystemMediaSnapshot with elapsed/timestamp/artwork; MediaController's real 0.25 s anchor; no player read or command"
        method["resourceSampler"] = "getrusage(RUSAGE_SELF) + mach_task_basic_info.resident_size + task_vm_info.phys_footprint, 1 s MainActor samples"
        method["cpuPeak"] = "max of per-sample CPU-second differences / elapsed difference (1 s resolution); phase cpuPercent is cumulative average"
        method["timelineProbe"] = "SwiftUI TimelineView body callback (CompactLyricsView)"
        method["displayLink"] = "two gap definitions: sender.timestamp gaps and wall-clock arrival gaps; neither is a composited frame"
        method["window"] = "one WindowCoordinator panel on the main display; no status item, no activation"
        let limitations: [String] = [
            "Optimized QA is not the shipping Release app bundle; it uses the development define only for instrumentation.",
            "CADisplayLink timestamp/arrival gaps are not rendered/composited frame times; no 60 fps or Alcove-parity claim.",
            "Wakeups remain unavailable without privileged tooling.",
            "Production audio 0.5 s polling, real media/lock/dual-screen/voice and full shipping resource cost are still unmeasured.",
            "One bounded run; the earlier 6-minute baseline is not rerun."
        ]
        var result: [String: Any] = [:]
        result["schema"] = 1
        result["mode"] = "short-r1-optimized-qa"
        result["passed"] = allPassed
        result["checks"] = checks
        result["environment"] = environment
        result["method"] = method
        result["limitations"] = limitations
        result["sourcePublishes"] = source.publishCount
        result["phases"] = [play.json, noLink.json, interaction.json, paused.json]
        if let data = try? JSONSerialization.data(withJSONObject: result,
                                                   options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: directory.appendingPathComponent("short-baseline.json"))
        }
        fputs(allPassed ? "SHORT BASELINE PASSED\n" : "SHORT BASELINE FAILED\n", stderr)
        coordinator.cancelPendingHover()
        NSApp.terminate(nil)
    }

    private static func measureInteractionShort(model: AppModel, coordinator: WindowCoordinator,
                                                display: BaselineDisplayLink,
                                                source: AuditTickingMediaSource,
                                                panel: NSWindow?,
                                                artworkA: Data?, artworkB: Data?) async -> PhaseResult {
        LyricsFrameProbe.reset()
        display.reset()
        LyricsFrameProbe.markPhaseStart()
        let startedWall = ProcessInfo.processInfo.systemUptime
        let startedCPU = cpuSeconds()
        var samples: [[String: Any]] = []
        var steps: [[String: Any]] = []
        var nextSample = startedWall + 1
        var stepIndex = 0
        let script: [(Double, String, @MainActor () -> Void)] = [
            (0.0, "expand", { coordinator.expand() }),
            (2.0, "volume-on", { model.showsOutputVolume = true }),
            (4.0, "volume-off", { model.showsOutputVolume = false }),
            (5.0, "collapse", { coordinator.collapse() }),
            (6.0, "fixture-seek-long-line", { source.seek(to: 6.0) }),
            (8.0, "fixture-seek-second-short", { source.seek(to: 21.0) }),
            (10.0, "fixture-track-B", {
                source.changeTrack(id: "baseline-B", title: "baseline-B",
                                   artist: "second-artist", artworkPNG: artworkB)
            }),
            (12.0, "fixture-track-A", {
                source.changeTrack(id: "baseline-A", title: "baseline-A",
                                   artist: "baseline-artist", artworkPNG: artworkA)
            })
        ]
        let total = 15.0
        samples.append(sample(at: 0, wall: startedWall, cpu: startedCPU))
        while true {
            let now = ProcessInfo.processInfo.systemUptime
            let elapsed = now - startedWall
            if elapsed >= total { break }
            while stepIndex < script.count, script[stepIndex].0 <= elapsed {
                script[stepIndex].2()
                steps.append(["at": script[stepIndex].0, "action": script[stepIndex].1,
                              "elapsed": model.elapsed])
                stepIndex += 1
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
            let after = ProcessInfo.processInfo.systemUptime
            if after >= nextSample {
                samples.append(sample(at: after - startedWall, wall: after, cpu: cpuSeconds()))
                nextSample += 1
            }
        }
        let endWall = ProcessInfo.processInfo.systemUptime
        let endCPU = cpuSeconds()
        samples.append(sample(at: endWall - startedWall, wall: endWall, cpu: endCPU))
        var notes = finalNotes(model: model, panel: panel)
        notes["steps"] = steps
        return PhaseResult(name: "opt-interaction-once", requestedSeconds: total,
                           actualSeconds: endWall - startedWall,
                           resources: resourceSummary(samples: samples, startWall: startedWall,
                                                      endWall: endWall, startCPU: startedCPU,
                                                      endCPU: endCPU),
                           timeline: LyricsFrameProbe.snapshot().json,
                           display: display.snapshot(), samples: samples, notes: notes)
    }

    private static func measure(name: String, seconds: Double, model: AppModel,
                                display: BaselineDisplayLink?, probe: Bool,
                                panel: NSWindow? = nil) async -> PhaseResult {
        if probe { LyricsFrameProbe.reset(); LyricsFrameProbe.markPhaseStart() }
        display?.reset()
        let startWall = ProcessInfo.processInfo.systemUptime
        let startCPU = cpuSeconds()
        var samples: [[String: Any]] = []
        var nextSample = startWall + 1
        samples.append(sample(at: 0, wall: startWall, cpu: startCPU))
        while true {
            let now = ProcessInfo.processInfo.systemUptime
            let elapsed = now - startWall
            if elapsed >= seconds { break }
            let wait = min(1, seconds - elapsed)
            try? await Task.sleep(nanoseconds: UInt64(max(0.01, wait) * 1_000_000_000))
            let after = ProcessInfo.processInfo.systemUptime
            if after >= nextSample || seconds - (after - startWall) < 0.05 {
                samples.append(sample(at: after - startWall, wall: after, cpu: cpuSeconds()))
                nextSample += 1
            }
        }
        let endWall = ProcessInfo.processInfo.systemUptime
        let endCPU = cpuSeconds()
        samples.append(sample(at: endWall - startWall, wall: endWall, cpu: endCPU))
        return PhaseResult(name: name, requestedSeconds: seconds,
                           actualSeconds: endWall - startWall,
                           resources: resourceSummary(samples: samples, startWall: startWall,
                                                      endWall: endWall, startCPU: startCPU,
                                                      endCPU: endCPU),
                           timeline: LyricsFrameProbe.snapshot().json,
                           display: display?.snapshot() ?? ["callbacks": 0, "note": "display link stopped for this phase"],
                           samples: samples,
                           notes: finalNotes(model: model, panel: panel))
    }

    private static func finalNotes(model: AppModel, panel: NSWindow?) -> [String: Any] {
        let line = model.currentLyricLine
        return ["screen": screenInfo(panel),
                "finalElapsed": model.elapsed,
                "finalLineStart": line?.start ?? -1,
                "finalLineText": line?.text ?? ""]
    }

    private static func screenInfo(_ window: NSWindow?) -> [String: Any] {
        guard let screen = window?.screen else { return ["available": false] }
        return ["available": true,
                "name": screen.localizedName,
                "maxFramesPerSecond": screen.maximumFramesPerSecond,
                "frame": NSStringFromRect(screen.frame),
                "scale": screen.backingScaleFactor]
    }

    private static func artworkPNG(_ hue: CGFloat) -> Data? {
        let image = NSImage(size: NSSize(width: 64, height: 64))
        image.lockFocus()
        NSColor(calibratedHue: hue, saturation: 0.55, brightness: 0.75, alpha: 1).setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 64, height: 64)).fill()
        NSColor(calibratedHue: hue + 0.35, saturation: 0.6, brightness: 0.9, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 8, y: 8, width: 48, height: 48)).fill()
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    private static func resourceSummary(samples: [[String: Any]], startWall: Double, endWall: Double,
                                        startCPU: Double, endCPU: Double) -> [String: Any] {
        let rss = samples.compactMap { $0["rssBytes"] as? UInt64 }
        let footprint = samples.compactMap { $0["physicalFootprintBytes"] as? UInt64 }
        var peak = 0.0
        for index in 1..<max(1, samples.count) {
            guard let previousCPU = samples[index - 1]["cpuSeconds"] as? Double,
                  let currentCPU = samples[index]["cpuSeconds"] as? Double,
                  let previousElapsed = samples[index - 1]["elapsedSeconds"] as? Double,
                  let currentElapsed = samples[index]["elapsedSeconds"] as? Double else { continue }
            let wall = currentElapsed - previousElapsed
            // Only full sampling intervals: the phase-end sample can follow the
            // last 1 s sample by a few milliseconds, and dividing by that tiny
            // wall time would fabricate a spike. Resolution is ~1 s.
            if wall >= 0.8 { peak = max(peak, (currentCPU - previousCPU) / wall * 100) }
        }
        let cpuPercent = endWall > startWall ? (endCPU - startCPU) / (endWall - startWall) * 100 : 0
        return [
            "cpuSeconds": endCPU - startCPU,
            "cpuPercentSingleCore": cpuPercent,
            "cpuPeakSingleCore": peak,
            "cpuPeakResolutionSeconds": 1,
            "cpuPeakMinIntervalSeconds": 0.8,
            "rssMinBytes": rss.min() ?? 0,
            "rssMaxBytes": rss.max() ?? 0,
            "rssFirstBytes": rss.first ?? 0,
            "rssLastBytes": rss.last ?? 0,
            "rssMeanBytes": rss.isEmpty ? 0 : rss.reduce(0, +) / UInt64(rss.count),
            "footprintMinBytes": footprint.min() ?? 0,
            "footprintMaxBytes": footprint.max() ?? 0,
            "footprintFirstBytes": footprint.first ?? 0,
            "footprintLastBytes": footprint.last ?? 0,
            "footprintMeanBytes": footprint.isEmpty ? 0 : footprint.reduce(0, +) / UInt64(footprint.count),
            "sampleIntervalSeconds": 1,
            "sampleCount": samples.count
        ]
    }

    private static func sample(at elapsed: Double, wall: Double, cpu: Double) -> [String: Any] {
        ["elapsedSeconds": elapsed, "wallSeconds": wall, "cpuSeconds": cpu,
         "rssBytes": residentBytes(), "physicalFootprintBytes": physicalFootprint()]
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

    private static func physicalFootprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size
                                            / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), rebound, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : 0
    }

    private static func int(_ dictionary: [String: Any], _ key: String) -> Int {
        (dictionary[key] as? NSNumber)?.intValue ?? 0
    }
}
#endif
