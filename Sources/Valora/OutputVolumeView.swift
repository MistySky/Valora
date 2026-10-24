import SwiftUI

struct OutputVolumeView: View {
    @ObservedObject var model: AppModel
    @State private var draggingUID: String?
    private var volume: Double { model.output.muted ? 0 : model.output.volume }
    var body: some View {
        HStack(spacing:10) {
            Button { model.audio.toggleMute() } label: {
                Image(systemName:model.output.volumeButtonSymbol).font(.system(size:12)).frame(width:24,height:24)
            }.buttonStyle(.plain).accessibilityLabel(model.output.effectivelyMuted ? "取消静音":"静音")
                .disabled(!model.output.canMute && !model.output.canSetVolume)
            GeometryReader { proxy in
                ZStack(alignment:.leading) {
                    Capsule().fill(.white.opacity(0.14))
                    Capsule().fill(.gray).frame(width:proxy.size.width * volume)
                }.frame(height:6).frame(maxHeight:.infinity)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance:0).onChanged { value in
                        model.beginPointerInteraction()
                        if draggingUID == nil { draggingUID = model.output.uid }
                        guard let uid=draggingUID,proxy.size.width>0 else { return }
                        model.audio.setVolume(Double(value.location.x/proxy.size.width),expectedUID:uid)
                    }.onEnded { _ in
                        draggingUID = nil
                        model.endPointerInteraction()
                    })
            }.frame(height:24)
                .accessibilityElement(children:.ignore)
                .accessibilityLabel("系统输出音量")
                .accessibilityValue(model.output.canSetVolume ? "\(Int((volume * 100).rounded()))%":"此输出设备不支持系统音量调节")
                .accessibilityAdjustableAction { direction in
                    model.audio.setVolume(volume + (direction == .increment ? 0.05 : -0.05),expectedUID:model.output.uid)
                }.disabled(!model.output.canSetVolume)
            Image(systemName:"speaker.wave.2.fill").font(.system(size:12)).frame(width:24,height:24).accessibilityHidden(true)
        }.foregroundStyle(.gray)
            .onDisappear { draggingUID = nil; model.endPointerInteraction() }
    }
}
