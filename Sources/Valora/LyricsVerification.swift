#if VALORA_DEVELOPMENT
import AppKit
import SwiftUI
import ReferenceCore

/// Isolated QA renderer for the compact/expanded lyric row. It uses injected
/// displays, a static provider and synthetic playback state; it never starts
/// the media source, audio tap or network.
enum LyricsVerification {
    @MainActor static func run(model: AppModel, coordinator: WindowCoordinator, output: String) {
        Task { @MainActor in
            let directory = URL(fileURLWithPath: output, isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var checks: [[String: Any]] = []
            @MainActor func check(_ name: String, _ passed: Bool) {
                checks.append(["name": name, "passed": passed])
            }
            func settle(_ seconds: Double = 0.35) async {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            }
            @MainActor func capture(_ name: String, view: NSView?) throws {
                guard let view else { return }
                view.layoutSubtreeIfNeeded()
                guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
                view.cacheDisplay(in: view.bounds, to: bitmap)
                guard let png = bitmap.representation(using: .png, properties: [:]) else { return }
                try png.write(to: directory.appendingPathComponent(name + ".png"))
                let canvas = NSImage(size: view.bounds.size)
                canvas.lockFocus()
                NSColor(calibratedWhite: 0.94, alpha: 1).setFill()
                NSBezierPath(rect: view.bounds).fill()
                let captured = NSImage(size: view.bounds.size)
                captured.addRepresentation(bitmap)
                captured.draw(in: view.bounds)
                canvas.unlockFocus()
                if let tiff = canvas.tiffRepresentation,
                   let composite = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                    try composite.write(to: directory.appendingPathComponent(name + "-review.png"))
                }
            }
            @MainActor func artworkFixture() -> NSImage {
                let image = NSImage(size: NSSize(width: 64, height: 64))
                image.lockFocus()
                NSColor(calibratedRed: 0.16, green: 0.62, blue: 0.55, alpha: 1).setFill()
                NSBezierPath(rect: NSRect(x: 0, y: 0, width: 64, height: 64)).fill()
                NSColor(calibratedRed: 0.86, green: 0.48, blue: 0.22, alpha: 1).setFill()
                NSBezierPath(rect: NSRect(x: 0, y: 0, width: 32, height: 64)).fill()
                image.unlockFocus()
                return image
            }

            await settle(0.45)
            check("static provider produces timed lyrics", model.lyrics.status == .ready)
            check("compact lyric row stays visible", model.showsCompactLyrics)
            check("compact lyric row uses the 32pt auxiliary area",
                  model.visibleSize.height > model.notchGeometry.compact.height)
            check("artwork color is available for lyric fill", !model.artworkColors.isEmpty)

            model.elapsed = 1.2
            await settle(0.2)
            check("short lyric resolves from playback time",
                  model.currentLyricLine?.text == "短句歌词")
            check("short lyric has real word timing",
                  model.currentLyricLine?.words.count == 2)
            try? capture("lyrics-short", view: coordinator.panel.contentView)

            model.elapsed = 5.0
            await settle(0.2)
            check("long lyric resolves from playback time",
                  (model.currentLyricLine?.text ?? "").hasPrefix("这是一句很长的歌词"))
            check("long lyric carries word timing",
                  (model.currentLyricLine?.words.count ?? 0) > 2)
            try? capture("lyrics-long", view: coordinator.panel.contentView)

            model.playing = false
            await settle(0.25)
            check("pause keeps the current lyric line", model.currentLyricLine?.text == "这是一句很长的歌词，需要在紧凑区域中慢速从左向右跟随当前字，同时保持当前唱到的部分可见")
            try? capture("lyrics-paused", view: coordinator.panel.contentView)
            model.playing = true
            await settle(0.2)
            try? capture("lyrics-resumed", view: coordinator.panel.contentView)

            model.elapsed = 6.8
            await settle(0.2)
            check("long lyric follows the current word", model.currentLyricLine?.words.count == 4)
            try? capture("lyrics-reading-window", view: coordinator.panel.contentView)

            model.elapsed = 9.2
            await settle(0.02)
            try? capture("lyrics-transition-frame", view: coordinator.panel.contentView)
            await settle(0.25)
            check("seek moves to the new lyric line", model.currentLyricLine?.text == "第二句")
            try? capture("lyrics-seek", view: coordinator.panel.contentView)
            model.elapsed = 1.2
            await settle(0.2)
            check("backward seek returns to the correct lyric line", model.currentLyricLine?.text == "短句歌词")
            try? capture("lyrics-seek-back", view: coordinator.panel.contentView)

            model.elapsed = 12.2
            await settle(0.2)
            check("line-only long LRC uses its line text", (model.currentLyricLine?.text ?? "").hasPrefix("这是一句没有逐字时间"))
            check("line-only long LRC has no word timing", model.currentLyricLine?.words.isEmpty == true)
            try? capture("lyrics-line-only-before", view: coordinator.panel.contentView)
            model.elapsed = 18.5
            await settle(0.2)
            try? capture("lyrics-line-only-after", view: coordinator.panel.contentView)
            model.elapsed = 12.2
            await settle(0.2)
            try? capture("lyrics-line-only-reset", view: coordinator.panel.contentView)
            model.elapsed = 20.2
            await settle(0.2)
            check("line-only short LRC stays static", model.currentLyricLine?.text == "第三句")
            try? capture("lyrics-line-only-short", view: coordinator.panel.contentView)

            model.elapsed = 7
            await settle(0.2)
            check("blank interstitial clears the previous line",
                  model.currentLyricLine?.text == "" && model.currentLyricLine != nil)
            try? capture("lyrics-interstitial", view: coordinator.panel.contentView)

            model.elapsed = 1.2
            let expandedLine = model.currentLyricLine?.text
            model.showsOutputVolume = true
            coordinator.expand()
            await settle(0.6)
            check("expanded player keeps lyrics at the bottom", model.expanded && model.showsLyricsInExpanded)
            check("expanded lyric is below the original player and volume",
                  model.visibleSize.height >= model.expandedSize.height + 64)
            try? capture("lyrics-expanded-bottom", view: coordinator.panel.contentView)
            model.showsOutputVolume = false
            coordinator.collapse()
            await settle(0.6)
            check("collapse restores the compact lyric row",
                  !model.expanded && model.showsCompactLyrics && model.currentLyricLine?.text == expandedLine)
            try? capture("lyrics-collapsed-restored", view: coordinator.panel.contentView)

            model.lyrics = LyricsDisplayState(status: .noLyrics, identity: model.lyrics.identity)
            model.elapsed = 1
            await settle(0.2)
            check("no-lyrics does not leave a song-title placeholder",
                  model.currentLyricLine == nil && !model.showsCompactLyrics)
            try? capture("lyrics-no-row", view: coordinator.panel.contentView)

            model.lyrics = LyricsDisplayState(status: .ready,
                timeline: LyricTimeline(lines: [
                    LyricLine(start: 1, text: "短句歌词", words: [
                        LyricWord(text: "短句", start: 1, duration: 0.5),
                        LyricWord(text: "歌词", start: 1.5, duration: 0.5)
                    ]),
                    LyricLine(start: 5, text: "这是一句很长的歌词，需要在紧凑区域中慢速从左向右跟随当前字，同时保持当前唱到的部分可见", words: [
                        LyricWord(text: "这是一句很长的歌词，", start: 5, duration: 1.2),
                        LyricWord(text: "需要在紧凑区域中", start: 6.2, duration: 1.2),
                        LyricWord(text: "慢速从左向右跟随当前字，", start: 7.4, duration: 1.4),
                        LyricWord(text: "同时保持当前唱到的部分可见", start: 8.8, duration: 1.2)
                    ]),
                    LyricLine(start: 7, text: ""),
                    LyricLine(start: 9, text: "第二句", words: [
                        LyricWord(text: "第二句", start: 9, duration: 1)
                    ])
                ]),
                identity: model.lyrics.identity)
            model.elapsed = 5.5
            model.presenter.cancelPeek(reset: true)
            model.presenter.trackChanged(identity: "v0012-a")
            model.presenter.trackChanged(identity: "v0012-b")
            await settle(0.15)
            check("lyrics-on suppresses the song-change title prompt", !model.songPeek.visible)
            try? capture("lyrics-on-no-song-info", view: coordinator.panel.contentView)

            // Same-geometry baseline: with lyrics off the original centered
            // song-change prompt must return and still expire normally.
            let qaDefaults = UserDefaults(suiteName: AppRuntimeDefaults.qaSuiteName)!
            qaDefaults.set(["showOnDisplay": "All displays", "showLyrics": false],
                           forKey: "referenceSettingsUI")
            model.settings.reloadPreferences()
            model.presenter.cancelPeek(reset: true)
            model.presenter.trackChanged(identity: "off-a")
            model.presenter.trackChanged(identity: "off-b")
            await settle(0.35)
            check("lyrics-off restores the original song-change prompt", model.songPeek.visible)
            try? capture("lyrics-off-song-peek", view: coordinator.panel.contentView)
            qaDefaults.set(["showOnDisplay": "All displays", "showLyrics": true],
                           forKey: "referenceSettingsUI")
            model.settings.reloadPreferences()
            await settle(0.4)
            check("re-enabling lyrics restores the lyric row", model.lyrics.status == .ready)

            let ids = coordinator.verificationScreenIDs
            if ids.count > 1 {
                coordinator.verificationActivateScreen(ids[1])
                await settle(0.25)
                check("lyrics follow the active screen", coordinator.verificationActiveScreenID == ids[1])
                try? capture("lyrics-active-external", view: coordinator.panel.contentView)
                try? capture("lyrics-passive-builtin", view: coordinator.verificationSecondaryPanels.first?.view)
                coordinator.verificationActivateScreen(ids[0])
                await settle(0.2)
            }

            // Same non-notch screen, simulated on/off: compact music width must
            // stay 214pt and expanded width 345pt while lyrics remain valid.
            if ids.count > 1 {
                coordinator.verificationActivateScreen(ids[1])
                await settle(0.25)
                model.elapsed = 1.2
                model.settings.forceSimulatedNotch = false
                await settle(0.5)
                check("non-notch pill compact width is 214pt",
                      !model.notchGeometry.hasPhysicalNotch && model.visibleSize.width == 214)
                check("non-notch pill keeps lyrics without force-simulated",
                      model.showsCompactLyrics && model.lyrics.status == .ready)
                check("non-notch pill keeps pill contour", model.contour.style == .pill)
                try? capture("lyrics-nonnotch-pill-compact", view: coordinator.panel.contentView)

                model.settings.forceSimulatedNotch = true
                await settle(0.5)
                check("non-notch simulated compact width is also 214pt",
                      model.visibleSize.width == 214)
                check("force-simulated shape switch does not clear lyrics",
                      model.showsCompactLyrics && model.lyrics.status == .ready)
                check("non-notch simulated keeps notch contour", model.contour.style == .notch)
                try? capture("lyrics-nonnotch-simulated-compact", view: coordinator.panel.contentView)

                model.showsOutputVolume = true
                coordinator.expand()
                await settle(0.6)
                check("non-notch simulated expanded width is 345pt",
                      model.expanded && model.visibleSize.width == 345)
                try? capture("lyrics-nonnotch-simulated-expanded", view: coordinator.panel.contentView)
                model.showsOutputVolume = false
                coordinator.collapse()
                await settle(0.4)
            }

            let result: [String: Any] = ["passed": checks.allSatisfy { $0["passed"] as? Bool == true },
                                         "checks": checks,
                                         "provider": "static QA, no network/media/audio",
                                         "screenCount": coordinator.verificationPanelCount]
            if let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: directory.appendingPathComponent("verification.json"))
            }
            UserDefaults(suiteName: AppRuntimeDefaults.qaSuiteName)?.removeObject(forKey: "referenceSettingsUI")
            NSApp.terminate(nil)
        }
    }
}
#endif
