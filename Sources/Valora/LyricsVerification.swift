import AppKit
import SwiftUI
import ReferenceCore

/// Isolated QA renderer for the compact line-lyrics row. It uses injected
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
            @MainActor func marqueeViews(_ view: NSView) -> [MarqueeLabelView] {
                var result: [MarqueeLabelView] = []
                if let marquee = view as? MarqueeLabelView { result.append(marquee) }
                for child in view.subviews { result.append(contentsOf: marqueeViews(child)) }
                return result
            }
            @MainActor func flushCompactLayout() {
                coordinator.panel.contentView?.layoutSubtreeIfNeeded()
                CATransaction.flush()
            }

            await settle(0.45)
            check("static provider produces timed lyrics", model.lyrics.status == .ready)
            check("compact lyric row stays visible", model.showsCompactLyrics)
            check("compact lyric row uses the 32pt auxiliary area",
                  model.visibleSize.height > model.notchGeometry.compact.height)

            model.elapsed = 1
            await settle(0.2)
            check("short lyric resolves from playback time",
                  model.currentLyricLine?.text == "短句歌词")
            try? capture("lyrics-short", view: coordinator.panel.contentView)
            check("short lyric does not create a marquee", marqueeViews(coordinator.panel.contentView ?? NSView()).isEmpty)

            model.elapsed = 5
            await settle(0.2)
            check("long lyric resolves from playback time",
                  (model.currentLyricLine?.text ?? "").hasPrefix("这是一句很长的歌词"))
            try? capture("lyrics-long", view: coordinator.panel.contentView)
            let marquee = marqueeViews(coordinator.panel.contentView ?? NSView()).first
            check("long lyric uses the existing marquee view", marquee != nil)
            flushCompactLayout()
            let movingStart = marquee?.presentedOrigin
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            flushCompactLayout()
            let movingEnd = marquee?.presentedOrigin
            check("long lyric moves while playing", movingStart != nil && movingEnd != nil && movingStart != movingEnd)

            model.playing = false
            await settle(0.2)
            flushCompactLayout()
            let pausedStart = marquee?.presentedOrigin
            try? await Task.sleep(nanoseconds: 400_000_000)
            flushCompactLayout()
            let pausedEnd = marquee?.presentedOrigin
            check("pause stops the long lyric marquee in place",
                  pausedStart != nil && pausedEnd != nil && abs((pausedEnd ?? 0) - (pausedStart ?? 0)) < 0.5)
            try? capture("lyrics-paused", view: coordinator.panel.contentView)

            model.playing = true
            await settle(0.7)
            flushCompactLayout()
            let resumed = marquee?.presentedOrigin
            check("resume continues the marquee", resumed != nil && resumed != pausedEnd)
            try? capture("lyrics-resumed", view: coordinator.panel.contentView)

            model.elapsed = 9
            await settle(0.2)
            check("seek moves to the new lyric line", model.currentLyricLine?.text == "第二句")
            try? capture("lyrics-seek", view: coordinator.panel.contentView)

            model.elapsed = 7
            await settle(0.2)
            check("blank interstitial clears the previous line",
                  model.currentLyricLine?.text == "" && model.currentLyricLine != nil)
            try? capture("lyrics-interstitial", view: coordinator.panel.contentView)

            model.elapsed = 5
            coordinator.expand()
            await settle(0.6)
            check("expanded player hides the compact lyric row", model.expanded && !model.showsCompactLyrics)
            try? capture("lyrics-expanded-no-row", view: coordinator.panel.contentView)
            coordinator.collapse()
            await settle(0.6)
            check("collapse restores the lyric row at current progress",
                  !model.expanded && model.showsCompactLyrics && model.currentLyricLine != nil)
            try? capture("lyrics-collapsed-restored", view: coordinator.panel.contentView)

            model.lyrics = LyricsDisplayState(status: .noLyrics, identity: model.lyrics.identity)
            model.elapsed = 1
            await settle(0.2)
            check("no-lyrics falls back to title and artist",
                  model.currentLyricLine == nil && model.lyricFallbackText.contains("晴天"))
            try? capture("lyrics-fallback", view: coordinator.panel.contentView)

            model.lyrics = LyricsDisplayState(status: .ready,
                timeline: LyricTimeline(lines: [
                    LyricLine(start: 1, text: "短句歌词"),
                    LyricLine(start: 5, text: "这是一句很长的歌词，需要在紧凑区域中慢速从右向左滚动显示，同时保持当前唱到的部分可见"),
                    LyricLine(start: 7, text: ""),
                    LyricLine(start: 9, text: "第二句")
                ]),
                identity: model.lyrics.identity)
            model.elapsed = 5
            model.presenter.cancelPeek(reset: true)
            model.presenter.trackChanged(identity: "v0011-a")
            model.presenter.trackChanged(identity: "v0011-b")
            await settle(0.15)
            check("song-change prompt wins over a ready lyric",
                  model.songPeek.visible && model.currentLyricLine != nil)
            let peekMarqueeCount = marqueeViews(coordinator.panel.contentView ?? NSView()).count
            check("song-change prompt removes the lyric marquee", peekMarqueeCount == 0)
            try? capture("lyrics-song-peek-priority", view: coordinator.panel.contentView)
            await settle(0.8)
            try? capture("lyrics-song-peek-settled", view: coordinator.panel.contentView)
            model.presenter.cancelPeek(reset: true)
            await settle(0.2)
            check("lyric returns after the song-change prompt", model.currentLyricLine != nil)
            try? capture("lyrics-after-peek", view: coordinator.panel.contentView)

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
