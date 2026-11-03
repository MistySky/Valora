import AppKit
import SwiftUI

struct LockMusicView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: RevivalSettings
    @ObservedObject var coordinator: LockMusicCoordinator
    @Environment(\.accessibilityReduceMotion) private var reducedMotion

    private var card: some View {
        MusicPlayerContent(model: model, settings: settings, width: 345,
                           compensatesForNotch: false, active: coordinator.appeared,
                           translucent: true, showsVolume: $coordinator.showsVolume)
            .padding(.horizontal, 18).padding(.top, 16).padding(.bottom, 14)
            .frame(width: 345)
            .foregroundStyle(.white).colorScheme(.dark)
            .background(LockFrostedBackground(cornerRadius: 28))
            // The source frosted container has no white stroke overlay; that
            // revival-only overlay was visibly tinting the card edge. Keep the
            // card geometry/material unchanged and leave visual comparison for
            // real locked-wallpaper QA.
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            if coordinator.appeared {
                card
                    .transition(reducedMotion ? .opacity : .asymmetric(
                        insertion: .modifier(active: LockScaleAndFade(scale: 0.25, opacity: 0),
                                             identity: LockScaleAndFade(scale: 1, opacity: 1)),
                        removal: .modifier(active: LockScaleAndFade(scale: 0.95, opacity: 0),
                                           identity: LockScaleAndFade(scale: 1, opacity: 1))))
                    .allowsHitTesting(coordinator.visible)
            }
        }
        .padding(.bottom, LockMusicCoordinator.animationMargin)
        .frame(width: 385, height: LockMusicCoordinator.canvasHeight, alignment: .bottom)
        .environment(\.colorScheme, .dark)
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
