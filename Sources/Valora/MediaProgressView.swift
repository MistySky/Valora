import SwiftUI
import ReferenceCore

/// 1.7.9 progress style branches (1000f35bc / 1000f260c).
/// Palette extraction and CALayer interpolation still have parity differences.
struct MediaProgressView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: RevivalSettings
    var trackWidth:CGFloat? = nil
    var translucent=false
    @State private var progress = MediaProgressState()
    @GestureState private var isDragging = false
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    private var durationIsValid: Bool { MediaProgressState.validDuration(model.duration) }
    private var elapsed: Double { progress.dragValue ?? MediaProgressState.clamp(model.elapsed,duration:model.duration) }
    private var fraction: Double { durationIsValid ? elapsed / model.duration : 0 }
    private var textColor: Color { isDragging ? .white : (translucent ? .white.opacity(0.7):.gray.opacity(0.8)) }
    private var fillColors: [Color] {
        if translucent { return [textColor] } // Original hasTranslucency branch is monochrome.
        // 1000f35bc filters every palette color by luminance < .98 before
        // the style branch; gradient is not an exception.
        let palette = model.artworkColors.filter { ArtworkPalette.luminance($0) < 0.98 }
        switch settings.musicPreferences.progressStyle {
        case .monochrome: return [isDragging ? .white : .gray.opacity(0.8)]
        case .colored:
            return palette.first.map { [Color(nsColor:$0)] } ?? [.gray.opacity(0.8)]
        case .gradient:
            return palette.isEmpty ? [.gray.opacity(0.8)] : palette.map { Color(nsColor:$0) }
        }
    }
    var body: some View {
        HStack(spacing:9) {
            Text(durationIsValid ? timestamp(elapsed):"-:--")
                .foregroundStyle(textColor).fixedSize()
            GeometryReader { geometry in
                ZStack(alignment:.leading) {
                    Capsule().fill(.gray.opacity(0.25))
                    Capsule().fill(LinearGradient(colors:fillColors,startPoint:.leading,endPoint:.trailing))
                        .mask(alignment:.leading) {
                            Capsule().frame(width:max(0,geometry.size.width * fraction))
                        }
                }
                .frame(height:isDragging ? 9:6)
                .frame(maxHeight:.infinity)
                .contentShape(Rectangle())
                .animation(reducedMotion ? nil:.spring(response:0.45,dampingFraction:1),value:isDragging)
                .gesture(DragGesture(minimumDistance:2)
                    .updating($isDragging) { _,state,_ in state = durationIsValid && (model.previewMode || model.mediaCanSeek) }
                    .onChanged { value in
                        if durationIsValid, model.previewMode || model.mediaCanSeek {
                            model.beginPointerInteraction()
                        }
                        _ = progress.drag(elapsed:model.elapsed,duration:model.duration,
                            translation:value.translation.width,trackWidth:geometry.size.width)
                    }
                    .onEnded { value in
                        _ = progress.drag(elapsed:model.elapsed,duration:model.duration,
                            translation:value.translation.width,trackWidth:geometry.size.width)
                        if let target = progress.endDrag(at:ProcessInfo.processInfo.systemUptime) { model.media.seek(target) }
                        model.endPointerInteraction()
                    })
                .simultaneousGesture(SpatialTapGesture().onEnded { value in
                    if let target = progress.tap(x:value.location.x,trackWidth:geometry.size.width,
                        duration:model.duration,at:ProcessInfo.processInfo.systemUptime) {
                        model.media.seek(target)
                    }
                })
            }.frame(height:18)
                .accessibilityElement(children:.ignore)
                .accessibilityLabel("播放进度")
                .accessibilityValue(durationIsValid ? "\(timestamp(elapsed)) / \(timestamp(model.duration))":"不可用")
                .accessibilityAdjustableAction { direction in
                    guard durationIsValid else { return }
                    let delta: Double = direction == .increment ? 5:-5
                    model.media.seek(MediaProgressState.clamp(elapsed+delta,duration:model.duration))
                }
            Button {
                settings.showRemainingTime.toggle()
            } label: {
                Text(durationIsValid ? (settings.showRemainingTime ? "-"+timestamp(model.duration-elapsed):timestamp(model.duration)):"-:--")
                    .foregroundStyle(textColor).fixedSize()
            }.buttonStyle(.plain)
                .accessibilityLabel(settings.showRemainingTime ? "剩余时间，点击显示总时长":"总时长，点击显示剩余时间")
        }
        .font(.system(size:10,weight:.medium)).monospacedDigit()
        .frame(width:max(1,trackWidth ?? model.expandedSize.width-42))
        .disabled(!model.hasTrack || !durationIsValid || !(model.previewMode || model.mediaCanSeek))
        .onChange(of:isDragging) { _,dragging in
            if !dragging { progress.cancelDrag(); model.endPointerInteraction() }
        }
        .onDisappear { progress.cancelDrag(); model.endPointerInteraction() }
    }
    private func timestamp(_ value:Double)->String {
        guard value.isFinite, value >= 0, value < Double(Int.max) else { return "-:--" }
        let seconds = Int(value)
        return "\(seconds/60):"+String(format:"%02d",seconds%60)
    }
}
