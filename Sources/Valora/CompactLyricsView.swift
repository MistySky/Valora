import AppKit
import SwiftUI
import ReferenceCore

/// The compact QuickPeek row reused for line lyrics. It deliberately has no
/// player page of its own: the active screen owns this 32pt row, passive screens
/// keep their ordinary compact content.
struct CompactLyricsView: View {
    @ObservedObject var model: AppModel
    let width: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var lineText: String? {
        guard let line = model.currentLyricLine, !line.text.isEmpty else { return nil }
        return line.text
    }

    private var displayedText: String { lineText ?? model.lyricFallbackText }
    private var isLyric: Bool { lineText != nil }
    private var textColor: NSColor { NSColor.gray.withAlphaComponent(isLyric ? 0.94 : 0.82) }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "music.note")
                .font(.system(size: 11, weight: .semibold))
            if let lineText, !lineText.isEmpty,
               MarqueeLabel.measure(lineText, size: 12, weight: .semibold).width > max(1, width - 22) {
                MarqueeLabel(text: lineText, size: 12, weight: .semibold,
                             color: textColor, longestTextWidth: max(1, width - 22),
                             active: true, paused: !model.playing)
                    .frame(width: max(1, width - 22), height: 17, alignment: .leading)
                    .clipped()
            } else {
                Text(displayedText)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .foregroundStyle(.gray)
        .frame(width: max(1, width), height: 32, alignment: .leading)
        .padding(.horizontal, 18)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isLyric ? "歌词，\(displayedText)" : "歌曲，\(displayedText)")
        .accessibilityIdentifier("compact.lyrics")
    }
}
