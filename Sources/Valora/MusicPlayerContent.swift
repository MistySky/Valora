import SwiftUI
import AppKit
import ReferenceCore

/// Shared player layout; lock screen opts out of physical-notch padding.
struct MusicPlayerContent:View {
    @ObservedObject var model:AppModel
    @ObservedObject var settings:RevivalSettings
    let width:CGFloat
    let compensatesForNotch:Bool
    let active:Bool
    var translucent=false
    /// Lock-card ink palette; only consulted when `translucent` is set.
    var palette: LockCardPalette? = nil
    @State private var outputHovered=false
    @Binding var showsVolume:Bool
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    private var displayArtist:String { model.artist.replacingOccurrences(of:" - Topic",with:"").trimmingCharacters(in:.whitespacesAndNewlines) }
    var body:some View {
        VStack(spacing:8) {
                HStack(alignment:.top,spacing:11.5){
                    TransitioningArtwork(image:model.artwork,identity:model.artworkIdentity,size:56,cornerRadius:12,enabled:!settings.musicPreferences.disableArtworkFlip)
                        .scaleEffect(model.playing ? 1:0.85)
                        .animation(reducedMotion ? .easeOut(duration:0.12):.spring(duration:0.6,bounce:0.4),value:model.playing)
                    // MarqueeText records in 0x1000d8bb0: title 13.5 semibold,
                    // artist 13 medium, kerning .05, shared text cycle duration.
                    MusicMarqueePair(title:model.displayTitle,artist:displayArtist,active:active,artistColor:translucent ? NSColor(palette?.secondary ?? .white.opacity(0.7)):NSColor.gray.withAlphaComponent(0.85),onDoubleClick: { model.openCurrentMediaSource() })
                        .id(model.mediaBundleIdentifier+"\u{0}"+model.title+"\u{0}"+model.artist+"\u{0}"+model.album)
                        .frame(maxWidth:.infinity,alignment:.leading)
                        .padding(.top,compensatesForNotch ? 23:11)
                        .contentShape(Rectangle())
                        .accessibilityAction(named: "打开当前播放软件") { model.openCurrentMediaSource() }
                        .help("双击打开当前播放软件")
                    PlayerWaveform(model:model, settings:settings, active:active, translucent:translucent, palette:palette).frame(width:24,height:24)
                        .padding(.top,compensatesForNotch ? 16:8)
                        .padding(.leading,4).padding(.trailing,6)
                }.padding(.bottom,translucent ? 0:4)
                MediaProgressView(model:model,settings:settings,trackWidth:width-42,translucent:translucent,palette:palette).id(model.mediaBundleIdentifier+"\u{0}"+model.title+"\u{0}"+model.artist+"\u{0}"+model.album)
                ZStack(alignment:.trailing) {
                  HStack(spacing:32){
                    MediaButton(symbol:"backward.fill",label:"上一首",size:23){model.media.command(5)}.disabled(!model.previewMode && !model.mediaCanSkip)
                    MediaButton(symbol:model.playing ? "pause.fill":"play.fill",label:model.playing ? "暂停":"播放",size:23){model.media.command(2)}.disabled(!model.previewMode && !model.mediaCanControl)
                    MediaButton(symbol:"forward.fill",label:"下一首",size:23){model.media.command(4)}.disabled(!model.previewMode && !model.mediaCanSkip)
                  }.frame(maxWidth:.infinity)
                  Button {
                      model.audio.refresh()
                      withAnimation(reducedMotion ? .easeOut(duration:0.12) : .spring(duration:0.45,bounce:0.1)) {
                          showsVolume.toggle()
                      }
                  } label: {
                      Image(systemName:model.output.symbol).font(.system(size:18,weight:.medium)).imageScale(.medium)
                          .frame(width:20,height:20)
                          .contentTransition(.symbolEffect(.replace))
                          .foregroundStyle(translucent ? (palette?.secondary ?? Color.white.opacity(0.7)):.gray).frame(width:46,height:44)
                          .background(showsVolume || outputHovered ? Color.white.opacity(0.1) : .clear,in:RoundedRectangle(cornerRadius:16))
                  }.buttonStyle(.plain)
                      .onHover { outputHovered=$0 }
                      .accessibilityLabel("音频输出："+(model.output.name.isEmpty ? "不可用":model.output.name))
                      .accessibilityValue(showsVolume ? "音量已展开":"音量已收起")
                      .help("显示或隐藏音量控制")
                }
                if showsVolume {
                    OutputVolumeView(model:model).padding(.horizontal,8).frame(height:24)
                        .transition(.opacity.combined(with:.offset(y:-6)))
                }
        }
    }
}
