import AppKit
import SwiftUI

struct LockGlassSetting: View {
    @Binding var intensity: Double
    @State private var dragValue: Double?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("液态玻璃")
                .font(.system(size: 13.5))
                .frame(minWidth: 72, alignment: .leading)
            VStack(spacing: 8) {
                LockGlassSettingPreview(intensity: dragValue ?? intensity)
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
                HStack(spacing: 7) {
                    Image(systemName: "square.on.square")
                        .help("更通透")
                        .accessibilityHidden(true)
                    Slider(value: sliderValue, in: 0...1, onEditingChanged: { editing in
                        if editing { dragValue = intensity } else { finishDrag() }
                    }) {
                        Text("锁屏播放卡玻璃浓度")
                    }
                    .labelsHidden()
                    .accessibilityValue((dragValue ?? intensity).formatted(.percent.precision(.fractionLength(0))))
                    .accessibilityHint("向右调节可加深播放卡的底色")
                    Image(systemName: "square.fill.on.square.fill")
                        .help("更深")
                        .accessibilityHidden(true)
                }
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .onDisappear { finishDrag() }
    }

    // Dragging updates the sample locally. Keyboard and accessibility changes
    // outside a drag save directly, and a completed drag saves once.
    private var sliderValue: Binding<Double> {
        Binding(
            get: { dragValue ?? intensity },
            set: { value in
                if dragValue != nil { dragValue = value } else { intensity = value }
            }
        )
    }

    private func finishDrag() {
        if let dragValue, dragValue != intensity { intensity = dragValue }
        dragValue = nil
    }
}

private struct LockGlassSettingPreview: View {
    let intensity: Double
    // A small stock thumbnail keeps this sample independent of personal
    // wallpapers and media. The gradient also works without the system asset.
    private static let coastline = NSImage(contentsOfFile:
        "/System/Library/Desktop Pictures/.thumbnails/Big Sur Coastline.heic")

    var body: some View {
        ZStack {
            HStack(spacing: 9) {
                Image(systemName: "music.note")
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 28, height: 28)
                    .background(LinearGradient(colors: [.indigo, .cyan], startPoint: .topLeading,
                                               endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 6))
                VStack(alignment: .leading, spacing: 2) {
                    Text("海岸线").font(.system(size: 12, weight: .semibold))
                    Text("播放卡片预览").font(.system(size: 10))
                }
                Spacer(minLength: 6)
                Image(systemName: "play.fill").font(.system(size: 12))
            }
            .foregroundStyle(.white)
            .padding(10)
            .background { LockGlassSurface(intensity: intensity, cornerRadius: 13) }
            .padding(.horizontal, 18)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 104)
        .background {
            if let coastline = Self.coastline {
                Image(nsImage: coastline).resizable().scaledToFill()
            } else {
                LinearGradient(colors: [.indigo, .cyan, .orange], startPoint: .bottomLeading,
                               endPoint: .topTrailing)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
