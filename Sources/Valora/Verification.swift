import AppKit
import SwiftUI
import QuartzCore
import CryptoKit
import ReferenceCore

/// Opt-in developer integration test. Uses synthetic data, a separate
/// preference domain, and the real NSHostingView/controller. It does not start
/// production media polling or send player/volume commands.
enum MusicPresentationVerification {
    @MainActor static func run(model: AppModel, coordinator: WindowCoordinator, output: String) {
        Task { @MainActor in
            let directory = URL(fileURLWithPath: output, isDirectory: true)
            var checks: [[String: Any]] = []
            @MainActor func check(_ name: String, _ passed: Bool) {
                checks.append(["name": name, "passed": passed,
                               "generation": model.presentation.generation,
                               "phase": model.presentation.phase.rawValue])
            }
            func settle(_ seconds: Double = 0.7) async {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            }
            @MainActor func capture(_ name: String) throws {
                guard let view = coordinator.panel.contentView else { return }
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
            func artworkFixture(_ left: NSColor, _ right: NSColor) -> NSImage {
                let image = NSImage(size: NSSize(width:64,height:64))
                image.lockFocus()
                left.setFill(); NSBezierPath(rect:NSRect(x:0,y:0,width:32,height:64)).fill()
                right.setFill(); NSBezierPath(rect:NSRect(x:32,y:0,width:32,height:64)).fill()
                image.unlockFocus(); return image
            }
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let qaDefaults = UserDefaults(suiteName: AppRuntimeDefaults.qaSuiteName)!
                qaDefaults.removeObject(forKey: "referenceSettingsUI")
                model.settings.reloadPreferences()
                model.settings.nowPlayingEnabled = true
                model.settings.showNotch = true
                model.settings.hoverEnabled = false
                model.settings.autoCollapse = false
                model.settings.hideWhenIdle = false
                model.settings.forceSimulatedNotch = false
                model.settings.showRemainingTime = true
                model.previewMode = true
                model.title = "音乐面板预览"
                model.artist = "布局与过渡检查 · 非真实播放"
                model.playing = true
                model.duration = 236
                model.elapsed = 74
                // Let a queued display/geometry place() from the QA settings
                // reset settle before starting the expansion clock.
                await settle(0.35)
                model.pinned = true
                coordinator.expand()
                check("expanding retains content but rejects player interaction", model.presentation.retainsExpandedContent
                      && !model.presentation.acceptsExpandedInteraction)
                await settle()
                check("expansion settles with all lifecycle flags", model.presentation.phase == .expanded
                      && model.presentation.usesExpandedCornerRadius && model.presentation.hasExpandedBackdropLuma
                      && model.presentation.hasProgressiveBlur)
                check("expanded size follows display geometry", model.visibleSize == model.notchGeometry.expanded)
                check("display selects the correct contour", model.contour.style == (model.notchGeometry.hasPhysicalNotch ? .notch : .pill))
                try capture("expanded-music")

                var completions = 0
                model.presenter.collapse { completions += 1 }
                model.presenter.collapse { completions += 1 }
                check("collapsing retains content but rejects player interaction", model.presentation.retainsExpandedContent
                      && !model.presentation.acceptsExpandedInteraction)
                await settle()
                check("duplicate collapse completions drain once each", completions == 2)
                check("collapse cleans every visual flag", model.presentation.phase == .collapsed
                      && !model.presentation.usesExpandedCornerRadius && !model.presentation.hasExpandedBackdropLuma
                      && !model.presentation.hasProgressiveBlur)
                check("compact activity preserves native height", model.visibleSize.height == model.nativeNotchSize.height)
                try capture("compact-music")

                // Native layer lifecycle, separate from real pointer/player tests.
                let waveform = CompactWaveformView(frame:NSRect(x:0,y:0,width:20,height:20))
                waveform.configure(image:nil,color:.blue,playing:true,reducedMotion:false,identity:"fixture")
                check("detached compact waveform does not run a timer", !waveform.isTicking)
                let waveformHost = NSView(frame:waveform.frame)
                let waveformWindow = NSWindow(contentRect:waveform.frame,styleMask:.borderless,backing:.buffered,defer:false)
                waveformWindow.isReleasedWhenClosed = false
                waveformWindow.contentView = waveformHost
                waveformHost.addSubview(waveform); waveform.layout()
                check("compact native waveform uses five centered two point bars", waveform.bars.count == 5
                    && waveform.bars.allSatisfy { $0.bounds.width == 2 }
                    && waveform.bars.map { $0.position.x } == [3,6.5,10,13.5,17])
                check("attached playing waveform starts one clock", waveform.isTicking)
                let toneFixture = artworkFixture(.systemBlue,.systemRed)
                waveform.configure(image:toneFixture,color:.blue,playing:true,reducedMotion:false,identity:"fixture")
                waveform.layout()
                let textureRenders = waveform.textureRenderCount
                check("waveform renders a filtered artwork texture", waveform.hasArtworkTexture && textureRenders > 0)
                waveform.configure(image:toneFixture,color:.blue,playing:true,reducedMotion:false,identity:"fixture")
                waveform.layout()
                check("unchanged artwork does not repeat image filtering", waveform.textureRenderCount == textureRenders)
                waveform.configure(image:nil,color:.blue,playing:false,reducedMotion:false,identity:"fixture")
                waveform.layout()
                check("missing artwork clears previous waveform texture", !waveform.hasArtworkTexture)
                check("pause stops clock and settles each bar to two points", !waveform.isTicking && waveform.bars.allSatisfy { $0.bounds.height == 2 })
                waveform.configure(image:nil,color:.blue,playing:true,reducedMotion:true,identity:"fixture")
                check("reduce motion renders bars without clock", !waveform.isTicking)
                waveform.frame = NSRect(x:0,y:0,width:24,height:24)
                waveform.configure(image:nil,color:.blue,playing:true,reducedMotion:false,identity:"fixture",profile:.expanded)
                waveform.layout()
                check("expanded waveform restores recovered six bar envelope", waveform.bars.count == 6
                    && waveform.bars.map { $0.position.x } == [2,6,10,14,18,22]
                    && waveform.bars.allSatisfy { (2...15).contains($0.bounds.height) })
                waveform.configure(image:nil,color:.blue,playing:true,reducedMotion:false,identity:"fixture",profile:.expanded,suspended:true)
                check("retained inactive player suspends waveform clock", !waveform.isTicking)
                waveform.configure(image:nil,color:.blue,playing:true,reducedMotion:false,identity:"fixture",profile:.expanded)
                check("reopened expanded player resumes native clock", waveform.isTicking)
                waveform.removeFromSuperview()
                check("dismantled waveform releases animation clock", !waveform.isTicking)
                waveformWindow.close()

                // Deterministic rendering/controller regression. Pointer events
                // are disabled in this QA mode; this is not a physical-hover test.
                model.presenter.pointerEntered(true)
                await settle()
                check("compact hover scales the full cutout", model.isPointerInside
                      && model.hoverScale == CGSize(width:1.075,height:1.15))
                try capture("compact-music-hover")
                model.presenter.pointerEntered(false)
                await settle()
                check("hover exit restores scale", model.hoverScale == CGSize(width:1,height:1))
                model.settings.autoCollapse = true
                coordinator.expand()
                coordinator.pointerChanged(true)
                coordinator.pointerChanged(false)
                check("pointer exit begins collapse during expansion", !model.expanded && model.presentation.phase == .collapsing)
                coordinator.pointerChanged(true)
                coordinator.expand()
                await settle()
                check("reentry can interrupt pointer-exit collapse", model.expanded && model.presentation.phase == .expanded)
                model.pinned = true; coordinator.pointerChanged(false)
                check("explicit pinned preview does not auto collapse", model.expanded)
                model.pinned = false; coordinator.collapse(); await settle()
                model.settings.autoCollapse = false

                model.output = AudioOutputState(uid:"qa",volume:0.5,muted:false,canMute:true,canSetVolume:true)
                check("audible volume shows small speaker and mute action", model.output.volumeButtonSymbol == "speaker.wave.1.fill" && !model.output.effectivelyMuted)
                model.output.muted = true
                check("native mute shows slash even with retained volume", model.output.volumeButtonSymbol == "speaker.slash.fill" && model.output.effectivelyMuted)
                model.output.muted = false; model.output.volume = 0
                check("zero slider shows slash without native mute bit", model.output.volumeButtonSymbol == "speaker.slash.fill" && model.output.effectivelyMuted)
                coordinator.expand(); await settle()
                model.showsOutputVolume = true
                await settle()
                check("output row adds 32 points", model.visibleSize.height == model.expandedSize.height + 32)
                try capture("output-volume-open")
                coordinator.collapse()
                check("collapse clears output before its completion", !model.showsOutputVolume)
                await settle(0.03)
                coordinator.expand(); await settle()
                check("interrupted collapse reopens without output row", !model.showsOutputVolume
                      && model.visibleSize.height == model.expandedSize.height)
                try capture("reopened-volume-hidden")
                model.showsOutputVolume = true
                coordinator.collapse(); await settle()
                coordinator.expand(); await settle()
                check("completed collapse also resets output for next expansion", !model.showsOutputVolume
                      && model.visibleSize.height == model.expandedSize.height)
                coordinator.collapse(); await settle()

                for _ in 0..<12 {
                    coordinator.expand(); await settle(0.01)
                    coordinator.collapse(); await settle(0.01)
                }
                coordinator.expand(); await settle()
                check("24 interrupted transitions settle expanded", model.presentation.phase == .expanded
                      && model.presentation.hasExpandedBackdropLuma && model.presentation.usesExpandedCornerRadius)
                coordinator.collapse(); await settle()
                check("final collapse still completes after interruptions", model.presentation.phase == .collapsed)

                // Same dictionary bindings used by the settings UI. Values that
                // were removed from the UI are fixed and must ignore legacy keys.
                let draft = SettingsDraft(defaults: qaDefaults)
                model.title = "设置联动验证"
                model.mediaBundleIdentifier = "com.test.player"
                model.frontmostBundleIdentifier = "com.apple.finder"
                let fixed = model.settings.musicPreferences
                check("fixed music policies ignore legacy values",
                      fixed.idleDuration == 3 && !fixed.disableWaveform && !fixed.disableArtworkFlip
                      && !fixed.hideWhileSourceIsActive && !fixed.hideSongTitleExtras
                      && fixed.quickPeekEnabled && fixed.whenSongChanges && fixed.peekDuration == 2)
                check("compact waveform remains enabled", model.showsMusicActivity && model.showsCompactWaveform)
                model.frontmostBundleIdentifier = model.mediaBundleIdentifier
                await settle(0.1)
                check("source foreground no longer hides the music activity", model.showsMusicActivity && model.hasTrack)
                model.frontmostBundleIdentifier = "com.apple.finder"
                let reloaded = RevivalSettings(defaults: qaDefaults)
                check("retained visible settings survive a new settings instance", reloaded.musicPreferences == model.settings.musicPreferences)

                // Quick Peek is defined for a physical or simulated notch. The
                // test host can be on an external non-notch display; make the
                // synthetic check deterministic without changing the product.
                let forcedPeek = !model.notchGeometry.hasPhysicalNotch
                if forcedPeek { model.settings.forceSimulatedNotch = true }
                model.presenter.cancelPeek(reset: true)
                model.presenter.trackChanged(identity: "first")
                check("initial track does not produce a change preview", !model.songPeek.visible)
                model.presenter.trackChanged(identity: "second")
                check("subsequent track opens the fixed two second preview", model.songPeek.visible)
                try capture("quick-peek")
                await settle(2.2)
                check("fixed quick peek expires after two seconds", !model.songPeek.visible)
                if forcedPeek { model.settings.forceSimulatedNotch = false }

                let firstArt = artworkFixture(.systemRed,.systemBlue)
                let secondArt = artworkFixture(.systemGreen,.systemOrange)
                let thirdArt = artworkFixture(.systemPurple,.systemYellow)
                let firstPalette = ArtworkPalette.extract(firstArt)
                let secondPalette = ArtworkPalette.extract(secondArt)
                let thirdPalette = ArtworkPalette.extract(thirdArt)
                check("palette retains distinct fixture colors", firstPalette.colors.count >= 2)
                check("identical artwork has stable revision", ArtworkPalette.extract(firstArt).identity == firstPalette.identity)
                check("missing artwork has no previous palette", ArtworkPalette.extract(nil).colors.isEmpty)
                check("white filter uses relative luminance", ArtworkPalette.luminance(NSColor(srgbRed:1,green:1,blue:1,alpha:1)) >= 0.98)
                let artworkController = ArtworkTransitionController()
                artworkController.update(image:firstArt,identity:firstPalette.identity,animated:true)
                check("first artwork is shown without flipping", artworkController.state.phase == .idle && artworkController.image != nil)
                artworkController.update(image:secondArt,identity:secondPalette.identity,animated:true)
                artworkController.update(image:thirdArt,identity:thirdPalette.identity,animated:true)
                await settle(1.9)
                check("rapid artwork revisions settle on newest image", artworkController.state.current == thirdPalette.identity && artworkController.state.phase == .idle)
                artworkController.update(image:firstArt,identity:firstPalette.identity,animated:true)
                artworkController.update(image:secondArt,identity:secondPalette.identity,animated:false)
                await settle(0.9)
                check("disabled flip rejects obsolete completion", artworkController.state.current == secondPalette.identity && artworkController.state.phase == .idle)
                artworkController.stop()

                model.title = "封面与进度条对照"
                model.artist = "合成双色封面 · 非原版截图"
                model.playing = true; model.duration = 240; model.elapsed = 168
                model.artwork = firstArt
                coordinator.collapse(); await settle()
                try capture("compact-filtered-artwork-waveform")
                coordinator.expand(); await settle()
                for style in ["Monochrome","Colored","Gradient"] {
                    draft.binding("progressStyle","Monochrome").wrappedValue = style
                    await settle()
                    check("progress style reaches runtime: " + style, model.settings.musicPreferences.progressStyle.rawValue == style)
                    try capture("progress-" + style.lowercased())
                }
                model.artwork = secondArt
                await settle(0.08)
                try capture("artwork-outgoing")
                await settle(0.22)
                try capture("artwork-incoming")
                await settle()
                try capture("artwork-settled")
                model.artwork = thirdArt
                await settle()
                check("artwork flip remains fixed enabled", !model.settings.musicPreferences.disableArtworkFlip)
                model.artwork = nil
                await settle()
                check("missing artwork clears color palette", model.artworkColors.isEmpty && model.artworkIdentity.isEmpty)
                try capture("progress-no-artwork")
                coordinator.collapse(); await settle()

                // Exercise actual CALayer clocks, not only metric arithmetic.
                // Native marquee probe lives in its own plain window so the
                // SwiftUI host's layer-tree updates cannot clear its animations.
                let probeWindow = NSWindow(contentRect:NSRect(x:0,y:0,width:300,height:80),
                                           styleMask:[.borderless],backing:.buffered,defer:false)
                probeWindow.isReleasedWhenClosed = false
                let probeHost = NSView(frame:NSRect(x:0,y:0,width:300,height:80))
                probeWindow.contentView = probeHost
                probeWindow.orderFrontRegardless()
                let probe = MarqueeLabelView(frame:NSRect(x:20,y:30,width:120,height:22))
                let peer = MarqueeLabelView(frame:NSRect(x:20,y:54,width:120,height:22))
                probeHost.addSubview(probe)
                probeHost.addSubview(peer)
                let longTitle = "长标题滚动验证：山川与星河之间的旋律"
                let longArtist = "同一位歌手与另一位歌手的合作作品"
                let longest = max(MarqueeLabel.measure(longTitle,size:13.5,weight:.semibold).width,
                                  MarqueeLabel.measure(longArtist,size:13.5,weight:.semibold).width)
                let epoch = CACurrentMediaTime()
                @MainActor func configureProbe(_ text:String = longTitle, color:NSColor = .white, active:Bool = true, reduce:Bool = false, epoch:Double = epoch) {
                    probe.configure(text:text,size:13.5,weight:.semibold,color:color,longestWidth:longest,
                                    reduceMotion:reduce,active:active,cycleStart:epoch)
                    probe.layoutSubtreeIfNeeded()
                    CATransaction.flush()
                }
                configureProbe()
                peer.configure(text:longArtist,size:13.5,weight:.semibold,color:.gray,longestWidth:longest,
                               reduceMotion:false,active:true,cycleStart:epoch)
                peer.layoutSubtreeIfNeeded(); CATransaction.flush()
                check("two native rows share exact animation epoch", probe.animationStartTimes.count == 2 && probe.animationStartTimes == peer.animationStartTimes)
                await settle(0.25)
                let origin = probe.presentedOrigin
                check("marquee holds its readable prefix during initial delay", origin.map { abs($0-4.5) < 1 } ?? false)
                await settle(1.4)
                check("native presentation layer actually scrolls after delay", probe.presentedOrigin.map { $0 < (origin ?? 0)-2 } ?? false)
                let starts = probe.animationStartTimes
                configureProbe(color:.systemOrange)
                check("color update preserves animation clock", probe.animationStartTimes == starts)
                probe.setFrameSize(NSSize(width:110,height:22)); probe.layoutSubtreeIfNeeded()
                check("overflowing resize preserves animation clock", probe.animationStartTimes == starts)
                probe.setFrameSize(NSSize(width:longest+20,height:22)); probe.layoutSubtreeIfNeeded()
                check("fitting text removes scrolling animation", probe.animationStartTimes.isEmpty)
                probe.setFrameSize(NSSize(width:120,height:22)); probe.layoutSubtreeIfNeeded()
                check("overflow boundary starts a fresh cycle", probe.animationStartTimes.count == 2 && probe.animationStartTimes != starts)
                configureProbe(active:false)
                check("collapse stops retained native text animation", probe.animationStartTimes.isEmpty)
                configureProbe(epoch:CACurrentMediaTime())
                check("reopening restarts native text animation", probe.animationStartTimes.count == 2)
                configureProbe(reduce:true)
                check("reduced motion has no scrolling layer", probe.animationStartTimes.isEmpty)
                configureProbe("短标题", epoch:CACurrentMediaTime())
                check("new short title has no old scrolling layer", probe.animationStartTimes.isEmpty && probe.displayedText == "短标题")
                configureProbe(epoch:CACurrentMediaTime())
                probe.removeFromSuperview(); peer.removeFromSuperview()
                check("detached native text stops animation", probe.animationStartTimes.isEmpty && peer.animationStartTimes.isEmpty)
                probeWindow.orderOut(nil); probeWindow.close()

                model.title = longTitle; model.artist = longArtist; model.artwork = firstArt; model.playing = true
                coordinator.expand(); await settle()
                @MainActor func marqueeViews(_ view: NSView) -> [MarqueeLabelView] {
                    (view as? MarqueeLabelView).map { [$0] } ?? view.subviews.flatMap { marqueeViews($0) }
                }
                let actualRows = coordinator.panel.contentView.map { marqueeViews($0) } ?? []
                check("expanded SwiftUI player mounts both native marquee rows", actualRows.count == 2 && actualRows.allSatisfy { $0.animationStartTimes.count == 2 })
                let playingClocks = actualRows.map { $0.animationStartTimes }
                try capture("long-title-playing")
                model.playing = false; await settle()
                check("pause does not reset title or artist scroll clock", actualRows.map { $0.animationStartTimes } == playingClocks)
                try capture("long-title-paused")
                for index in 0..<8 { model.playing = index % 2 == 0; await settle(0.035) }
                model.playing = true; await settle()
                check("rapid pause resume preserves marquee and latest playing state", model.playing && actualRows.map { $0.animationStartTimes } == playingClocks)
                try capture("long-title-resumed")
                coordinator.collapse(); await settle(0.05)
                check("collapsing player disables retained scrolling", actualRows.allSatisfy { $0.animationStartTimes.isEmpty })
                model.title = "最终曲目"; model.artist = "新歌手"; model.artwork = thirdArt
                coordinator.expand(); await settle()
                let reopenedRows = coordinator.panel.contentView.map { marqueeViews($0) } ?? []
                check("interrupted collapse shows only newest song text", Set(reopenedRows.map { $0.displayedText }) == Set(["最终曲目","新歌手"]))
                try capture("interrupted-reopen-latest-track")
                coordinator.collapse(); await settle()
                check("completed collapse dismantles expanded marquee views", coordinator.panel.contentView.map { marqueeViews($0).isEmpty } ?? false)

                model.title = "耳机按钮样式检查"; model.artist = "合成数据 · 非原版画面"
                model.output = AudioOutputState(uid:"appearance",name:"AirPods Pro 2",modelUID:"2014 4c",kind:"bluetooth")
                coordinator.expand(); await settle()
                check("playback output uses recovered Pro symbol", model.output.symbol == "airpods.pro")
                try capture("headphone-output-button")
                coordinator.collapse(); await settle()

                // Exercise the physical-notch layout even when the current main
                // display is external. These renders are synthetic, not references.
                let displayGeometry = model.notchGeometry
                model.notchGeometry = .calculate(screenWidth: 1728, safeAreaTop: 32,
                    auxiliaryLeftWidth: 771.5, auxiliaryRightWidth: 771.5, menuBarHeight: 32, simulated: false)
                model.title = "音乐面板预览"; model.playing = true; model.artwork = firstArt
                coordinator.expand(); await settle()
                check("physical notch resolves confirmed dimensions and corners", model.visibleSize == CGSize(width: 345, height: 175)
                      && model.contour.topRadius == 20 && model.contour.bottomRadius == 35.5 && model.contour.topInset == 0)
                try capture("physical-expanded-music")
                coordinator.collapse(); await settle()
                model.title = "暂无播放"
                check("physical compact uses confirmed notch width", model.visibleSize == CGSize(width: 185, height: 32))
                try capture("physical-compact")

                // Display branch: "All displays" creates compact secondary
                // panels. Only exercised when a second physical display exists.
                let screenCount = NSScreen.screens.count
                var secondaryRendered = false
                if screenCount > 1 {
                    model.title = "音乐面板预览"; model.artist = "布局与过渡检查 · 非真实播放"
                    model.playing = true; model.duration = 236; model.elapsed = 74; model.artwork = firstArt
                    draft.binding("showOnDisplay", "Main display").wrappedValue = "All displays"
                    await settle(0.8)
                    let panels = coordinator.verificationSecondaryPanels
                    check("all displays mounts a compact panel per extra display", panels.count == screenCount - 1)
                    let ids = coordinator.verificationScreenIDs
                    check("all displays exposes an interactive panel for every screen", ids.count == screenCount)
                    if ids.count > 1 {
                        coordinator.verificationActivateScreen(ids[1])
                        await settle(0.35)
                        check("secondary panel can become the active interaction screen",
                              coordinator.verificationActiveScreenID == ids[1])
                        coordinator.expand()
                        await settle(0.35)
                        check("active secondary screen expands", model.expanded)
                        coordinator.verificationActivateScreen(ids[0])
                        await settle(0.35)
                        check("switching active screen collapses the previous panel", !model.expanded)
                    }
                    check("secondary compact panel sits at the selected display top center", panels.allSatisfy { panel in
                        guard let screen = NSScreen.screens.dropFirst().first else { return false }
                        return abs(panel.frame.midX - screen.frame.midX) < 1 && abs(panel.frame.maxY - screen.frame.maxY) < 1
                    })
                    if let view = panels.first?.view {
                        view.layoutSubtreeIfNeeded()
                        if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                            view.cacheDisplay(in: view.bounds, to: bitmap)
                            if let png = bitmap.representation(using: .png, properties: [:]) {
                                try png.write(to: directory.appendingPathComponent("secondary-compact.png"))
                                secondaryRendered = true
                            }
                        }
                    }
                    check("secondary compact panel captured", secondaryRendered)
                    draft.binding("showOnDisplay", "All displays").wrappedValue = "Main display"
                    await settle(0.8)
                    check("returning to main display removes secondary panels", coordinator.verificationSecondaryPanels.isEmpty)
                }

                qaDefaults.removeObject(forKey: "referenceSettingsUI")
                model.settings.reloadPreferences()
                let result: [String: Any] = ["passed": checks.allSatisfy { $0["passed"] as? Bool == true },
                    "checks": checks,
                    "nativeSize": NSStringFromSize(displayGeometry.compact),
                    "expandedSize": NSStringFromSize(displayGeometry.expanded),
                    "rendering": "NSHostingView cacheDisplay; synthetic artwork/title",
                    "originalPixelParityVerified": false,
                    "productionMediaStarted": false,
                    "playerCommandSent": false,
                    "physicalScreenCount": screenCount,
                    "secondaryCompactRendered": secondaryRendered]
                let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
                try data.write(to: directory.appendingPathComponent("verification.json"))
            } catch {
                fputs("Music presentation verification failed: \(error)\n", stderr)
            }
            NSApp.terminate(nil)
        }
    }
}

/// Deterministic renders of our own settings view hierarchy. No external
/// application polling, permissions, commands, or production preference writes.
enum SettingsVerification {
    @MainActor static func run(model: AppModel, output: String) {
        Task { @MainActor in
            do {
                let directory = URL(fileURLWithPath: output, isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let suite = AppRuntimeDefaults.qaSuiteName
                let defaults = UserDefaults(suiteName: suite)!
                defaults.removePersistentDomain(forName: suite)
                let draft = SettingsDraft(defaults: defaults)
                let settings = RevivalSettings(defaults: defaults)
                settings.forceSimulatedNotch = false
                settings.hoverEnabled = false
                let navigation = SettingsNavigation()
                let root = SettingsView(model:model,settings:settings,navigation:navigation,draft:draft)
                    .environment(\.controlActiveState, .active).environment(\.colorScheme, .light)
                let (window, host) = SettingsWindowFactory.make(rootView: root)
                host.appearance = NSAppearance(named: .aqua)
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                var rendered: [String] = []
                @MainActor func capture(_ name: String) throws {
                    host.layoutSubtreeIfNeeded()
                    guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                    if let png = bitmap.representation(using: .png, properties: [:]) {
                        try png.write(to: directory.appendingPathComponent(name + ".png"))
                        rendered.append(name)
                    }
                }
                @MainActor func captureWindowChrome(_ name: String) throws {
                    guard let chrome = window.contentView?.superview else { return }
                    chrome.layoutSubtreeIfNeeded()
                    guard let bitmap = chrome.bitmapImageRepForCachingDisplay(in: chrome.bounds) else { return }
                    chrome.cacheDisplay(in: chrome.bounds, to: bitmap)
                    if let png = bitmap.representation(using: .png, properties: [:]) {
                        try png.write(to: directory.appendingPathComponent(name + ".png"))
                        rendered.append(name)
                    }
                }
                try? await Task.sleep(nanoseconds: 200_000_000)
                try captureWindowChrome("Window-chrome")
                for page in SettingsPage.allCases {
                    navigation.revealBottom = false
                    navigation.page = page
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    let name = page.rawValue.replacingOccurrences(of: " ", with: "-")
                    try capture(name)
                    navigation.revealBottom = true
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    try capture(name + "-bottom")
                }
                // Same active light condition as the original reference.
                navigation.page = .general; navigation.revealBottom = false
                settings.hoverEnabled = true
                try? await Task.sleep(nanoseconds: 200_000_000)
                try capture("General-hover-on")
                settings.hoverEnabled = false
                draft.binding("showOnDisplay", "Main display").wrappedValue = "All displays"
                try? await Task.sleep(nanoseconds: 200_000_000)
                try capture("General-all-displays")
                draft.binding("showOnDisplay", "All displays").wrappedValue = "Main display"
                navigation.page = .nowPlaying; navigation.revealBottom = false
                host.appearance = NSAppearance(named: .darkAqua)
                host.rootView = SettingsView(model:model,settings:settings,navigation:navigation,draft:draft)
                    .environment(\.controlActiveState, .active).environment(\.colorScheme, .dark)
                try? await Task.sleep(nanoseconds: 200_000_000)
                try capture("Now-Playing-dark")
                // Retained setting round-trip; fixed policy values are checked by tests.
                draft.binding("hoverDelay", 0.0).wrappedValue = 0.25
                draft.binding("progressStyle", "Monochrome").wrappedValue = "Gradient"
                let restored = SettingsDraft(defaults: defaults)
                let savedDelay: Double = restored.value("hoverDelay", 0.0)
                let savedStyle: String = restored.value("progressStyle", "")
                let persisted = savedDelay == 0.25 && savedStyle == "Gradient"
                let isolated = suite != Bundle.main.bundleIdentifier
                let trafficLights: [[String: Any]] = {
                    guard let theme = window.contentView?.superview else { return [] }
                    let ids = ["trafficLight.close", "trafficLight.minimize", "trafficLight.zoom"]
                    var result: [[String: Any]] = []
                    @MainActor func walk(_ view: NSView) {
                        if let identifier = view.identifier?.rawValue, ids.contains(identifier) {
                            let frame = view.convert(view.bounds, to: theme)
                            result.append(["id": identifier, "frame": NSStringFromRect(frame),
                                           "enabled": (view as? NSButton)?.isEnabled ?? false])
                        }
                        view.subviews.forEach(walk)
                    }
                    walk(theme)
                    return result.sorted { ($0["id"] as? String ?? "") < ($1["id"] as? String ?? "") }
                }()
                let report: [String: Any] = [
                    "pagesRendered": rendered,
                    "preferencePersistenceVerified": persisted,
                    "preferencesUseIsolatedDomain": isolated,
                    "windowPoints": [620, 687],
                    "sidebarPoints": 225,
                    "renderedPages": SettingsPage.allCases.map(\.rawValue),
                    "capturesAreOurOwnViewHierarchy": true,
                    "pixelParityVerified": false,
                    "featureBackendsVerified": false,
                    "productionWindowFactoryUsed": true,
                    "displayLanguage": "zh-Hans",
                    "preferenceKeysAndSelectionValuesUnchanged": true,
                    "trafficLightButtons": trafficLights,
                    "windowChromeCaptured": rendered.contains("Window-chrome"),
                    "actualWindowFramePoints": [window.frame.width, window.frame.height],
                    "windowGeometryVerified": window.frame.size == NSSize(width: 620, height: 687) && host.bounds.size == NSSize(width: 620, height: 687),
                    "userModificationRules": "no login item, automation, audio capture or preference write executed by this verifier"
                ]
                try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: directory.appendingPathComponent("verification.json"))
                window.orderOut(nil)
            } catch {
                fputs("Settings render failed: \(error)\n", stderr)
            }
            NSApp.terminate(nil)
        }
    }
}

/// Read-only check of the real macOS Now Playing session through the bundled
/// adapter. It never sends a player command and records only non-private flags.
enum SystemMediaVerification {
    @MainActor static func run(output: String) {
        Task { @MainActor in
            let directory = URL(fileURLWithPath: output, isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let source = SystemMediaSource()
                var snapshots = 0
                var latest: SystemMediaSnapshot?
                var errors: [String] = []
                source.onSnapshot = { snapshot in
                    snapshots += 1
                    if let snapshot { latest = snapshot }
                }
                source.onError = { errors.append($0) }
                source.start()
                let deadline = Date().addingTimeInterval(3.5)
                while Date() < deadline && snapshots == 0 {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
                // Observe a second window after first delivery, then stop and
                // confirm that a restart produces a fresh stream.
                try? await Task.sleep(nanoseconds: 500_000_000)
                source.stop()
                let afterStop = snapshots
                try? await Task.sleep(nanoseconds: 300_000_000)
                let stoppedSnapshots = snapshots
                var restartedSnapshot = false
                let restartToken = snapshots
                source.onSnapshot = { snapshot in
                    snapshots += 1
                    if snapshot != nil, snapshots > restartToken { restartedSnapshot = true }
                }
                source.start()
                let restartDeadline = Date().addingTimeInterval(3.5)
                while Date() < restartDeadline && !restartedSnapshot {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
                source.stop()
                let sanitized: [String: Any] = [
                    "snapshotDelivered": latest != nil,
                    "snapshotCountAtLeastOne": snapshots > 0,
                    "titleNonEmpty": latest.map { !$0.title.isEmpty } ?? false,
                    "artistNonEmpty": latest.map { !$0.artist.isEmpty } ?? false,
                    "albumNonEmpty": latest.map { !$0.album.isEmpty } ?? false,
                    "playing": latest?.playing ?? false,
                    "durationValid": latest.map { MediaProgressState.validDuration($0.duration) } ?? false,
                    "elapsedWithinDuration": latest.map { $0.elapsed <= $0.duration + 0.001 } ?? false,
                    "hasArtworkData": latest.map { ($0.artwork?.count ?? 0) > 0 } ?? false,
                    "contentItemIdentifierPresent": latest.map { !$0.contentItemIdentifier.isEmpty } ?? false,
                    "prohibitsSkip": latest?.prohibitsSkip ?? false,
                    "streamStoppedBeforeRestart": afterStop >= 0 && stoppedSnapshots == afterStop || afterStop == 0,
                    "restartDeliveredFreshSnapshot": restartedSnapshot,
                    "errors": errors,
                    "playerCommandSent": false,
                    "volumeOrPermissionWrite": false,
                    "privateMetadataRecorded": false
                ]
                try JSONSerialization.data(withJSONObject: sanitized, options: [.prettyPrinted, .sortedKeys])
                    .write(to: directory.appendingPathComponent("system-media.json"))
            } catch {
                fputs("System media verification failed: \(error)\n", stderr)
            }
            NSApp.terminate(nil)
        }
    }
}

/// Read-only verification of the actual grayscale NSStatusItem image and its
/// live status-bar window. The real-screen menu-bar crops are recorded by the
/// caller; this mode never starts media or sends player commands.
enum MenuBarIconVerification {
    @MainActor static func run(statusItem: NSStatusItem, output: String) {
        Task { @MainActor in
            let directory = URL(fileURLWithPath: output, isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? await Task.sleep(nanoseconds: 800_000_000)

            let button = statusItem.button
            let image = button?.image
            let iconURL = Bundle.main.resourceURL?.appendingPathComponent("AppIcon.icns")
            let iconData = iconURL.flatMap { try? Data(contentsOf: $0) }
            let iconSHA = iconData.map { SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined() }
            let menuIconURL = Bundle.main.resourceURL?.appendingPathComponent("MenuBarIcon.png")
            let menuIconData = menuIconURL.flatMap { try? Data(contentsOf: $0) }
            let menuIconSHA = menuIconData.map { SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined() }

            func render(_ image: NSImage?, pixels: Int, name: String) -> [String: Any]? {
                guard let image,
                      let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                 colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
                      let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = context
                image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels),
                           from: .zero, operation: .sourceOver, fraction: 1)
                context.flushGraphics()
                NSGraphicsContext.restoreGraphicsState()
                guard let png = rep.representation(using: .png, properties: [:]) else { return nil }
                let url = directory.appendingPathComponent(name + ".png")
                try? png.write(to: url)
                var colorful = 0
                var sampled = 0
                let step = max(1, pixels / 64)
                for y in stride(from: 0, to: pixels, by: step) {
                    for x in stride(from: 0, to: pixels, by: step) {
                        guard let color = rep.colorAt(x: x, y: y), color.alphaComponent > 0.5 else { continue }
                        sampled += 1
                        if color.saturationComponent > 0.15 { colorful += 1 }
                    }
                }
                return [
                    "path": url.path,
                    "pixels": pixels,
                    "bytes": png.count,
                    "sha256": SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined(),
                    "cornerAlphas": [rep.colorAt(x: 2, y: 2)?.alphaComponent ?? -1,
                                     rep.colorAt(x: pixels - 3, y: 2)?.alphaComponent ?? -1,
                                     rep.colorAt(x: 2, y: pixels - 3)?.alphaComponent ?? -1,
                                     rep.colorAt(x: pixels - 3, y: pixels - 3)?.alphaComponent ?? -1],
                    "sampledOpaquePixels": sampled,
                    "colorfulFraction": sampled > 0 ? Double(colorful) / Double(sampled) : 0
                ]
            }

            func imagePreview(background: NSColor, name: String) -> [String: Any]? {
                guard let image,
                      let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 36, pixelsHigh: 36,
                                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                 colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
                      let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = context
                background.setFill()
                NSRect(x: 0, y: 0, width: 36, height: 36).fill()
                image.draw(in: NSRect(x: 0, y: 0, width: 36, height: 36),
                           from: .zero, operation: .sourceOver, fraction: 1)
                context.flushGraphics()
                NSGraphicsContext.restoreGraphicsState()
                guard let png = rep.representation(using: .png, properties: [:]) else { return nil }
                let url = directory.appendingPathComponent(name + ".png")
                try? png.write(to: url)
                return ["path": url.path, "pixels": 36, "bytes": png.count,
                        "background": background.description,
                        "note": "offscreen grayscale image preview, not a real menu-bar capture"]
            }

            var windowCapture: [String: Any]?
            var windowInfo: [String: Any] = [:]
            if let window = button?.window {
                windowInfo = [
                    "window_number": window.windowNumber,
                    "window_frame_points": NSStringFromRect(window.frame),
                    "screen_frame_points": NSScreen.main.map { NSStringFromRect($0.frame) } ?? NSNull(),
                    "button_accessibility_frame_points": button.map { NSStringFromRect($0.accessibilityFrame()) } ?? NSNull()
                ]
                if let view = window.contentView {
                    view.layoutSubtreeIfNeeded()
                    if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                        view.cacheDisplay(in: view.bounds, to: bitmap)
                        if let png = bitmap.representation(using: .png, properties: [:]) {
                            let url = directory.appendingPathComponent("status-item-window.png")
                            try? png.write(to: url)
                            windowCapture = [
                                "path": url.path,
                                "pixels": [bitmap.pixelsWide, bitmap.pixelsHigh],
                                "bytes": png.count,
                                "sha256": SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined()
                            ]
                        }
                    }
                }
                // On a multi-display setup the status item's NSWindow and AX
                // frames can refer to the off-screen host rather than the
                // visible menu-bar replica. Do not publish them as a trusted
                // screen-capture rectangle; the narrow real-screen crops are
                // recorded separately by the verification shell step.
                windowInfo["frame_trusted_for_screen_capture"] = false
            }

            let result: [String: Any] = [
                "generated_at": ISO8601DateFormatter().string(from: Date()),
                "app": Bundle.main.bundlePath,
                "app_bundle_icon_path": iconURL?.path ?? NSNull(),
                "app_bundle_icon_sha256": iconSHA ?? NSNull(),
                "menubar_icon_path": menuIconURL?.path ?? NSNull(),
                "menubar_icon_sha256": menuIconSHA ?? NSNull(),
                "menubar_source": "Borderless ribbon V template PNG representations (20/40/60 pixels); isTemplate=true",
                "desaturation_method": "system template tint from ribbon alpha mask",
                "source_set": "generated borderless ribbon V based on user light artwork",
                "source_is_full_app_icon": false,
                "status_item_length": statusItem.length,
                "button_image_present": image != nil,
                "button_image_size": image.map { [Double($0.size.width), Double($0.size.height)] } ?? NSNull(),
                "button_image_is_template": image?.isTemplate ?? NSNull(),
                "button_image_representations": image?.representations.map {
                    ["width": $0.pixelsWide, "height": $0.pixelsHigh, "alpha": $0.hasAlpha]
                } ?? [],
                "button_image_scaling": button.map { $0.imageScaling.rawValue } ?? NSNull(),
                "button_image_position": button.map { $0.imagePosition.rawValue } ?? NSNull(),
                "button_accessibility_label": button?.accessibilityLabel() ?? NSNull(),
                "rendered_16": render(image, pixels: 16, name: "status-button-16") ?? NSNull(),
                "rendered_18": render(image, pixels: 18, name: "status-button-18") ?? NSNull(),
                "rendered_36": render(image, pixels: 36, name: "status-button-36") ?? NSNull(),
                "rendered_54": render(image, pixels: 54, name: "status-button-54") ?? NSNull(),
                "grayscale_preview_light": imagePreview(background: NSColor(srgbRed: 0.867, green: 0.898, blue: 0.925, alpha: 1),
                                                        name: "grayscale-preview-light") ?? NSNull(),
                "grayscale_preview_dark": imagePreview(background: NSColor(srgbRed: 0.110, green: 0.110, blue: 0.118, alpha: 1),
                                                       name: "grayscale-preview-dark") ?? NSNull(),
                "window": windowInfo,
                "status_item_window_capture": windowCapture ?? NSNull(),
                "screen_capture_note": "This is an offscreen status-item control render, not a real-screen capture. Automatic status-item window/AX frames are not trusted on multi-display setups; any real menu-bar crop is recorded separately and must not be inferred from this render.",
                "player_command_sent": false,
                "music_media_started": false,
                "private_content_collected": false
            ]
            if let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: directory.appendingPathComponent("menubar-verification.json"))
            }
            NSApp.terminate(nil)
        }
    }
}
