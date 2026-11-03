import SwiftUI
import AppKit
import AVKit
import ReferenceCore

struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat
    var style: NotchContourStyle = .notch
    var animatableData: AnimatablePair<CGFloat,CGFloat> {
        get { AnimatablePair(topRadius,bottomRadius) }
        set { topRadius = newValue.first; bottomRadius = newValue.second }
    }
    // 1.7.9 0x100278b8c: continuous bottom corners + subtracted top shoulders.
    func path(in r: CGRect) -> Path {
        // 0x100278ff4: pill style uses a continuous rounded rect and clamps
        // its radius to half the height; it has no outward top shoulders.
        if style == .pill {
            return RoundedRectangle(cornerRadius:max(0,min(bottomRadius,r.height/2)),style:.continuous).path(in:r)
        }
        let b = max(0,min(bottomRadius,min(r.width/2,r.height)))
        let t = max(0,min(topRadius,min(24,r.height-b)))
        var p = UnevenRoundedRectangle(topLeadingRadius:0,bottomLeadingRadius:b,bottomTrailingRadius:b,topTrailingRadius:0,style:.continuous).path(in:r)
        guard t > 0 else { return p }
        let left = CGRect(x:r.minX-2*t,y:r.minY,width:2*t,height:2*t)
        let right = CGRect(x:r.maxX,y:r.minY,width:2*t,height:2*t)
        let leftCut = UnevenRoundedRectangle(topLeadingRadius:0,bottomLeadingRadius:0,bottomTrailingRadius:0,topTrailingRadius:t,style:.continuous).path(in:left)
        let rightCut = UnevenRoundedRectangle(topLeadingRadius:t,bottomLeadingRadius:0,bottomTrailingRadius:0,topTrailingRadius:0,style:.continuous).path(in:right)
        p.addPath(Path(left).subtracting(leftCut))
        p.addPath(Path(right).subtracting(rightCut))
        return p
    }
}

/// Compact/expanded music surface. The selected locked/unlocking glyph is
/// migrated; unrelated battery/focus notification branches remain excluded.
/// Music activity, artwork flip, compact waveform/play control, title marquee
/// and Quick Peek are retained.
struct NotchView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: RevivalSettings
    var compactOnly = false
    var geometryOverride: NotchGeometry? = nil
    /// False for passive screens: they keep compact content, but do not show
    /// peek/expand/flip animations owned by the active interaction screen.
    var allowsDynamic = true
    var onActivate: (() -> Void)? = nil
    @Environment(\.accessibilityReduceMotion) var reducedMotion
    private var geometry: NotchGeometry { geometryOverride ?? model.notchGeometry }
    private var expanded: Bool { compactOnly ? false : model.expanded }
    private var localSize: CGSize {
        if compactOnly {
            return PresentationMetrics.stationarySize(geometry:geometry, simulated:settings.forceSimulatedNotch,
                expanded:.none, hasOutput:false,
                notification:.none,
                liveActivity: model.showsLockActivity ? .locked : (model.showsMusicActivity ? .playing : .none),
                quickPeek:.none,
                tuning:.zero)
        }
        return model.visibleSize
    }
    var width: CGFloat { localSize.width }
    var height: CGFloat { localSize.height }
    private var localContour: NotchContour {
        if compactOnly {
            return .stationary(geometry:geometry, simulated:settings.forceSimulatedNotch,
                expanded:false, expandedCorners:false,
                active:model.showsMusicActivity || model.showsLockActivity,
                visibleHeight:localSize.height)
        }
        return model.contour
    }
    var shape: NotchShape { NotchShape(topRadius:localContour.topRadius,bottomRadius:localContour.bottomRadius,style:localContour.style) }
    private var hasNotch: Bool { geometry.hasPhysicalNotch || settings.forceSimulatedNotch }
    private var nativeNotchSize: CGSize { geometry.compact }
    private var localHoverScale: CGSize { compactOnly ? CGSize(width:1,height:1) : model.hoverScale }
    private var expandedCanvasWidth: CGFloat { compactOnly ? width : model.expandedSize.width }
    private var displayArtist: String { model.artist.replacingOccurrences(of:" - Topic",with:"").trimmingCharacters(in:.whitespacesAndNewlines) }

    var body: some View {
        VStack(spacing:0) {
            ZStack(alignment:.top) {
                shape.fill(.black)
                    .overlay {
                        if NotchWindowDiagnostic.shared.isEnabled {
                            NotchLayoutProbe(phase: String(describing: model.lockIndicator.phase))
                        }
                    }
                if !expanded {
                    VStack(spacing:0) {
                        topStrip
                            // Keep artwork/glyph proportions while the black
                            // cutout stretches more vertically on hover.
                            .scaleEffect(x:1,y:localHoverScale.width/localHoverScale.height)
                        if allowsDynamic, !expanded, !model.isLockStage, model.showsMusicActivity,
                           model.showsCompactLyrics
                            || (!settings.musicPreferences.showLyrics && model.songPeek.visible) {
                            if model.showsCompactLyrics {
                                CompactLyricsView(model:model, width:max(1, width-36),
                                                  auditRole:compactOnly ? "passive" : "active")
                            } else {
                                HStack(spacing:5) {
                                    Image(systemName:"music.note").font(.system(size:11,weight:.semibold))
                                    Text(model.displayTitle + (displayArtist.isEmpty ? "" : " · " + displayArtist))
                                        .font(.system(size:12,weight:.semibold)).lineLimit(1)
                                }.foregroundStyle(.gray).padding(.horizontal,18)
                                    .frame(maxWidth:.infinity, minHeight:32, maxHeight:32, alignment:.center)
                                    .accessibilityLabel("切歌预览，"+model.displayTitle+"，"+displayArtist)
                                    .transition(.opacity.combined(with: .offset(y: -6)))
                            }
                        }
                    }
                }
                // Keep the wrapper mounted so opacity/blur can interpolate from
                // the collapsed state. The player itself survives until cleanup.
                // 0x1001e7588 fixes its width; 0x1001e6cc4 applies opacity + blur.
                VStack(spacing:0) {
                    if !compactOnly, model.presentation.retainsExpandedContent {
                        expandedContent.padding(.horizontal,18).padding(.top,18)
                            .padding(.bottom,16)
                            .fixedSize(horizontal:false,vertical:true)
                            .contextMenu { settingsMenuItem }
                    }
                }
                .frame(width:expandedCanvasWidth,height:height,alignment:.top)
                .opacity(expanded ? 1:0)
                .blur(radius:expanded ? 0:16,opaque:false)
                .allowsHitTesting(model.presentation.acceptsExpandedInteraction)
                .accessibilityHidden(!model.presentation.acceptsExpandedInteraction)
            }
            .frame(width:width,height:height,alignment:.top)
            .clipShape(shape)
            .contentShape(shape)
            .contextMenu { settingsMenuItem }
            .scaleEffect(x:localHoverScale.width,y:localHoverScale.height,anchor:.top)
            // The waveform has its own Button. Even on systems where the parent
            // tap is also recognized, this region must not expand the panel.
            .onTapGesture(coordinateSpace:.local) { point in
                guard !expanded, !model.isSessionLocked else { return }
                let wing = max(0,(width-nativeNotchSize.width)/2)
                if model.showsCompactWaveform, point.x >= width-wing { return }
                expand()
            }
            .accessibilityElement(children:.contain)
            .accessibilityAction(named:"展开刘海") { expand() }
            .accessibilityAction(named:"收起刘海") { collapse() }
            .foregroundStyle(.white).colorScheme(.dark)
            Spacer(minLength:0)
        }.padding(.top,localContour.topInset).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.top)
    }

    @ViewBuilder private var topStrip: some View {
        HStack(spacing:0) {
            Group {
                if model.showsLockActivity {
                    LockActivityGlyph(unlocking: model.lockIndicator.phase == .unlocking)
                        .font(.system(size: 14, weight: .medium))
                        .transition(.opacity)
                        .accessibilityLabel(model.lockIndicator.phase == .unlocking ? "屏幕已解锁" : "屏幕已锁定")
                } else if allowsDynamic, !expanded, !model.isLockStage,
                          let device = model.connectionToast {
                    ConnectionArrivalArtwork(device: device,
                        uses3D: settings.connectivityPreferences.uses3DModels,
                        notch: hasNotch)
                        .id(model.connectionArrivalGeneration)
                        .accessibilityLabel("\(device.name)，已连接")
                } else if !expanded, model.showsMusicActivity {
                    HStack(spacing:0) {
                        TransitioningArtwork(image:model.artwork,identity:model.artworkIdentity,
                            size:CompactArtworkMetrics.side(notch:hasNotch),cornerRadius:CompactArtworkMetrics.corner(notch:hasNotch,elevated:!compactOnly && model.isPointerInside),
                            enabled:allowsDynamic && !settings.musicPreferences.disableArtworkFlip)
                            .scaleEffect(model.playing ? 1:0.85)
                            .animation(reducedMotion ? .easeOut(duration:0.12):.spring(duration:0.6,bounce:0.4),value:model.playing)
                        Spacer(minLength:0)
                    }.padding(.leading,CompactArtworkMetrics.leading(notch:hasNotch))
                        .transition(.opacity)
                } else { Color.clear }
            }.frame(width:max(0,(width-nativeNotchSize.width)/2))
            Color.clear.frame(width:nativeNotchSize.width)
            Group {
                if model.showsLockActivity {
                    Color.clear
                } else if allowsDynamic, !expanded, !model.isLockStage,
                          let device = model.connectionToast {
                    if let battery = device.battery {
                        ConnectionBatteryRing(percent: battery, notch: hasNotch)
                            .accessibilityLabel("耳机电量 \(battery)%")
                    } else { Color.clear }
                } else if !expanded, model.showsCompactWaveform {
                    CompactPlaybackControl(model:model, settings:settings)
                } else { Color.clear }
            }.frame(width:max(0,(width-nativeNotchSize.width)/2))
        }.frame(height:nativeNotchSize.height)
    }

    private var expandedContent: some View {
        // MediaPlayer 0x1000d470c / 0x1000d4b68: non-compact spacing 8,
        // leading/trailing 18, artwork 56, top-aligned row spacing 11.5.
        VStack(spacing:8) {
            MusicPlayerContent(model:model,settings:settings,width:model.expandedSize.width,
                compensatesForNotch:model.notchGeometry.hasPhysicalNotch,
                active:model.presentation.acceptsExpandedInteraction,showsVolume:$model.showsOutputVolume)
            if model.showsLyricsInExpanded {
                CompactLyricsView(model:model, width:max(1, model.expandedSize.width-36),
                                  auditRole:compactOnly ? "passive" : "expanded")
                    .padding(.bottom,4)
            }
        }
    }

    @ViewBuilder private var settingsMenuItem: some View {
        Button(AppMenuCommands.versionText) {}
            .disabled(true)
        Button(AppMenuCommands.settingsTitle) { model.showSettingsAction?() }
            .keyboardShortcut(KeyEquivalent(","), modifiers: .command)
        Divider()
        Button(AppMenuCommands.quitTitle) { model.quitAction?() }
            .keyboardShortcut(KeyEquivalent("q"), modifiers: .command)
    }

    private func expand() {
        guard !model.isSessionLocked else { return }
        onActivate?()
        model.presenter.expand()
    }
    private func collapse() { model.presenter.collapse() }
}

struct Artwork: View {
    let image: NSImage?
    let size: CGFloat
    var cornerRadius: CGFloat? = nil
    var body: some View {
        Group {
            if let image {
                Image(nsImage:image).resizable().aspectRatio(contentMode:.fill)
            } else {
                ZStack {
                    LinearGradient(colors:[Color(white:0.22),Color(white:0.08)],startPoint:.topLeading,endPoint:.bottomTrailing)
                    Image(systemName:"music.note").font(.system(size:size*0.38)).foregroundStyle(.white.opacity(0.5))
                }
            }
        }.frame(width:size,height:size)
            .clipShape(RoundedRectangle(cornerRadius:cornerRadius ?? size*0.14,style:.continuous))
            .accessibilityLabel("专辑封面")
    }
}

struct MediaButton: View {
    let symbol: String
    let label: String
    let size: CGFloat
    var action: () -> Void
    var body: some View {
        Button(action:action) {
            Image(systemName:symbol).font(.system(size:size,weight:.semibold)).frame(width:38,height:44)
        }.buttonStyle(.plain).help(label).accessibilityLabel(label)
    }
}


struct AirPodsMovie: NSViewRepresentable {
    let name: String
    final class Coordinator {
        var player: AVQueuePlayer?
        var looper: AVPlayerLooper?
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .none
        view.videoGravity = .resizeAspect
        view.showsFullScreenToggleButton = false
        // Decorative connection previews must never replace the real media session.
        view.updatesNowPlayingInfoCenter = false
        if let url = Bundle.main.url(forResource: name, withExtension: "mp4",
                                     subdirectory: "AirPods") {
            let player = AVQueuePlayer()
            context.coordinator.player = player
            context.coordinator.looper = AVPlayerLooper(player: player,
                                                        templateItem: AVPlayerItem(url: url))
            view.player = player
            player.isMuted = true
            player.play()
        }
        return view
    }
    func updateNSView(_ view: AVPlayerView, context: Context) {}
    static func dismantleNSView(_ view: AVPlayerView, coordinator: Coordinator) {
        coordinator.player?.pause()
        coordinator.looper?.disableLooping()
        view.player = nil
        coordinator.looper = nil
        coordinator.player = nil
    }
}

/// Revival two-piece lock glyph: 14pt medium; the current revival values
/// rotate the top half -24° and move it x+2/y-2 after unlock. Those constants
/// are revival parameters; original evidence establishes the split glyph but
/// does not prove these exact values. The whole-symbol fallback is only for
/// systems without the private lock.top/lock.bottom symbols.
private struct LockActivityGlyph: View {
    var unlocking = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static let hasHalves =
        NSImage(systemSymbolName: "lock.top", accessibilityDescription: nil) != nil &&
        NSImage(systemSymbolName: "lock.bottom", accessibilityDescription: nil) != nil
    var body: some View {
        ZStack {
            if Self.hasHalves {
                Image(systemName: "lock.bottom")
                Image(systemName: "lock.top")
                    .rotationEffect(.degrees(unlocking ? -24 : 0), anchor: .bottomTrailing)
                    .offset(x: unlocking ? 2 : 0, y: unlocking ? -2 : 0)
            } else {
                Image(systemName: unlocking ? "lock.open.fill" : "lock.fill")
                    .contentTransition(.symbolEffect(.replace))
            }
        }
        .animation(reduceMotion ? .easeOut(duration: 0.12) : .spring(duration: 0.45, bounce: 0.2),
                   value: unlocking)
    }
}

struct ConnectionArrivalArtwork: View {
    let device: AudioDevice
    let uses3D: Bool
    let notch: Bool
    @State private var entered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ConnectionArtwork(device: device,
                          uses3D: ConnectionArtworkPolicy.usesMovie(appearance: uses3D,
                                                                      reduceMotion: reduceMotion),
                          notch: notch)
            .scaleEffect(reduceMotion || entered ? 1 : 0.7, anchor: .bottom)
            .offset(y: reduceMotion || entered ? 0 : 6)
            .opacity(entered ? 1 : 0)
            .task {
                withAnimation(reduceMotion ? .easeOut(duration: 0.12)
                                           : .spring(duration: 0.45, bounce: 0.1)) {
                    entered = true
                }
            }
    }
}

struct ConnectionArtwork: View {
    let device: AudioDevice
    let uses3D: Bool
    let notch: Bool
    var body: some View {
        Group {
            if uses3D, let movie = device.movie,
               Bundle.main.url(forResource: movie, withExtension: "mp4",
                               subdirectory: "AirPods") != nil {
                AirPodsMovie(name: movie).id(device.id + movie)
                    .frame(width: ConnectionArtworkMetrics.movieSize(notch: notch),
                           height: ConnectionArtworkMetrics.movieSize(notch: notch))
                    .offset(y: ConnectionArtworkMetrics.movieOffset(notch: notch))
            } else {
                Image(systemName: device.symbol)
                    .font(.system(size: ConnectionArtworkMetrics.symbolSize(notch: notch),
                                  weight: .medium))
                    .imageScale(.medium)
            }
        }
    }
}

struct ConnectionBatteryRing: View {
    let percent: Int
    let notch: Bool
    var body: some View {
        let fraction = min(1, max(0, Double(percent) / 100))
        let color: Color = percent <= 20 ? .red : .green
        ZStack {
            Circle().stroke(color.opacity(0.2), lineWidth: notch ? 2.5 : 2)
            Circle().trim(from: 0, to: fraction)
                .stroke(color, style: StrokeStyle(lineWidth: notch ? 2.5 : 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }.frame(width: notch ? 14 : 12, height: notch ? 14 : 12)
    }
}
