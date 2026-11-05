import AppKit
import SwiftUI
import ReferenceCore

/// The lock music card on its own. Shared by the real lock surface and the
/// `--lock-card-preview` inspection path, so what is checked there is exactly
/// what the lock shows.
struct LockMusicCard: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: RevivalSettings
    var active: Bool
    @Binding var showsVolume: Bool
    /// Lock colour policy: light glass + wallpaper-dependent ink.
    var appearance: LockCardAppearance = .standard

    var body: some View {
        // Player first, then the optional lyric row, both inside one stack: the
        // glass is only a background and receives the exact content size, so the
        // visible frame grows downwards from the card's fixed top.
        VStack(spacing: 8) {
            MusicPlayerContent(model: model, settings: settings, width: 345,
                               compensatesForNotch: false, active: active,
                               translucent: true, palette: appearance.palette,
                               showsVolume: $showsVolume)
            if settings.musicPreferences.showLyrics, model.lyrics.timeline != nil {
                CompactLyricsView(model: model, width: max(1, 345 - 36))
                    .padding(.bottom, 4)
                    .transition(.opacity.combined(with: .offset(y: -6)))
            }
        }
        .padding(.horizontal, 18).padding(.top, 16).padding(.bottom, 14)
        .frame(width: 345)
        .foregroundStyle(appearance.palette.primary)
        .background {
            LockGlassSurface(cornerRadius: LockGlassCorner.radius)
        }
    }
}

struct LockMusicView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: RevivalSettings
    @ObservedObject var coordinator: LockMusicCoordinator
    @Environment(\.accessibilityReduceMotion) private var reducedMotion

    private var card: some View {
        LockMusicCard(model: model, settings: settings,
                      active: coordinator.appeared,
                      showsVolume: $coordinator.showsVolume)
    }

    var body: some View {
        VStack(spacing: 0) {
            if coordinator.appeared {
                card
                    .transition(reducedMotion ? .opacity : .asymmetric(
                        // The original slides the lock card up from below; a
                        // scale-in from 25% read as a two-stage pop.
                        insertion: .modifier(active: LockSlideAndFade(offset: 32, opacity: 0),
                                             identity: LockSlideAndFade(offset: 0, opacity: 1)),
                        removal: .modifier(active: LockScaleAndFade(scale: 0.95, opacity: 0),
                                           identity: LockScaleAndFade(scale: 1, opacity: 1))))
                    .allowsHitTesting(coordinator.visible)
            }
        }
        // Top-aligned inside a fixed-height panel: the card's top never moves,
        // content (volume bar, lyric row) extends downwards only.
        .frame(width: 385, height: LockMusicCoordinator.canvasHeight, alignment: .top)
        // No root colour scheme override: it used to reach the glass background
        // and forced the liquid glass into its dark variant. The card content
        // sets its own `.colorScheme(.dark)` above.
        .animation(reducedMotion ? .easeOut(duration: 0.12)
                   : .spring(duration: 0.6, bounce: 0.3).delay(0.075),
                   value: coordinator.appeared)
        .accessibilityHidden(!coordinator.visible)
    }
}

private struct LockScaleAndFade: ViewModifier {
    var scale: CGFloat
    var opacity: Double
    func body(content: Content) -> some View {
        content.scaleEffect(scale, anchor: .center).opacity(opacity)
    }
}

/// Upward slide used when the lock card appears: the card rises from below the
/// notch instead of growing out of a small copy of itself.
private struct LockSlideAndFade: ViewModifier {
    var offset: CGFloat
    var opacity: Double
    func body(content: Content) -> some View {
        content.offset(y: offset).opacity(opacity)
    }
}
