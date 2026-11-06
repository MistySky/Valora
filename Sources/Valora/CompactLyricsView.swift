import AppKit
import SwiftUI
import ReferenceCore

/// Compact lyric row inside the existing QuickPeek boundary. A single local
/// TimelineView supplies both line selection and word fill/reading offset, so
/// the 0.25s global media sample never selects a different line than the
/// continuously interpolated word state.
struct CompactLyricsView: View {
    @ObservedObject var model: AppModel
    let width: CGFloat
    /// Embedded compact lyrics share the top strip rather than a 32pt peek.
    var rowHeight: CGFloat = 32
    var showsNote: Bool = true
    var horizontalInset: CGFloat = 18
    /// Lock-card empty-line layout: show the note alone in the middle instead
    /// of the left-aligned note + blank text area used by the notch strip.
    var centersNoteWhenEmpty: Bool = false
    /// QA-only role tag; production views use the default active role.
    var auditRole: String = "active"
    @State private var metricsCache = LyricMetricsCache()

    private var availableWidth: CGFloat { max(1, width - (showsNote ? 22 : 0)) }

    private func lineEnd(for line: LyricLine) -> TimeInterval {
        let timeline = model.lyrics.timeline
        let next = timeline?.lines.first(where: { $0.start > line.start })?.start
        if let next { return next }
        return max(line.start + 8, model.duration > line.start ? model.duration : line.start + 8)
    }

    private func lineView(_ line: LyricLine?, elapsed: TimeInterval) -> some View {
        let metrics = line.map { metricsCache.metrics(for: $0, identity: model.lyrics.identity) }
        let isLong = (metrics?.totalWidth ?? 0) > availableWidth
        let wordIndex = line.flatMap { line in
            metrics?.currentWord(at: elapsed, line: line)?.index
        }
        #if VALORA_DEVELOPMENT
        // Development-only frame probe; the release view has no audit hook.
        LyricsFrameProbe.record(role: auditRole, elapsed: elapsed,
                                lineStart: line?.start, wordIndex: wordIndex)
        #endif
        return HStack(spacing: 5) {
            if showsNote { noteIcon }
            if let line, let metrics {
                LyricsLineContent(line: line, metrics: metrics, availableWidth: availableWidth,
                                  accent: model.lyricsAccentColor, elapsed: elapsed,
                                  lineEnd: lineEnd(for: line),
                                  fillContainer: isLong)
                    .id("\(line.start)-\(line.text)")
                    .transition(.asymmetric(
                        insertion: .offset(y: 26).combined(with: .opacity),
                        removal: .offset(y: -26).combined(with: .opacity)))
            } else if !centersNoteWhenEmpty {
                Color.clear.frame(width: availableWidth, height: 17)
            }
        }
        .foregroundStyle(.gray)
        .frame(width: max(1, width), height: rowHeight, alignment: isLong ? .leading : .center)
        .padding(.horizontal, horizontalInset)
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(line.map { "歌词，\($0.text)" } ?? "歌词")
        .accessibilityIdentifier("compact.lyrics")
        .animation(.easeInOut(duration: 0.2), value: line.map { "\($0.start)-\($0.text)" })
    }

    private var noteIcon: some View {
        Image(systemName: "music.note")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color(nsColor: model.lyricsAccentColor))
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0,
                                paused: !model.playing || !(model.playbackRate > 0))) { context in
            let elapsed = model.lyricsElapsed(at: context.date)
            let line = model.lyrics.timeline?.line(at: elapsed)
            lineView(line, elapsed: elapsed)
        }
    }
}

struct LyricsLineMetrics: Equatable {
    let wordWidths: [CGFloat]
    let prefixes: [CGFloat]
    let totalWidth: CGFloat

    init(line: LyricLine) {
        var widths: [CGFloat] = []
        var prefixes: [CGFloat] = []
        var prefix: CGFloat = 0
        for word in line.words {
            prefixes.append(prefix)
            let width = MarqueeLabel.measure(word.text, size: 12, weight: .semibold).width
            widths.append(width)
            prefix += width
        }
        wordWidths = widths
        self.prefixes = prefixes
        totalWidth = MarqueeLabel.measure(line.text, size: 12, weight: .semibold).width
    }

    func currentWord(at time: TimeInterval, line: LyricLine) -> (index: Int, fraction: Double)? {
        guard !line.words.isEmpty, time.isFinite, time >= line.start else { return nil }
        var index: Int?
        for (offset, word) in line.words.enumerated() {
            guard word.start <= time else { break }
            index = offset
        }
        guard let index, index < line.words.count else { return nil }
        let word = line.words[index]
        let fraction = word.duration > 0
            ? min(1, max(0, (time - word.start) / word.duration)) : 0
        return (index, fraction)
    }
}

/// Metrics are computed once per line identity and reused for every 30Hz frame.
final class LyricMetricsCache {
    private var entries: [String: LyricsLineMetrics] = [:]
    private var order: [String] = []

    func metrics(for line: LyricLine, identity: LyricsTrackIdentity? = nil) -> LyricsLineMetrics {
        // Include the full word segmentation, not just text/start. A line that
        // changes from one QRC word to several must never reuse old width
        // arrays with a new word index.
        let identityKey = identity.map {
            "\($0.title)\u{1f}\($0.artist)\u{1f}\($0.album)\u{1f}\($0.durationSeconds)"
        } ?? ""
        let wordsKey = line.words.map {
            "\($0.start)\u{1f}\($0.duration)\u{1f}\($0.text)"
        }.joined(separator: "\u{1e}")
        let key = "\(identityKey)\u{1d}\(line.start)\u{1d}\(line.text)\u{1d}\(wordsKey)"
        if let value = entries[key] { return value }
        let value = LyricsLineMetrics(line: line)
        entries[key] = value
        order.append(key)
        if order.count > 8 {
            let old = order.removeFirst()
            entries.removeValue(forKey: old)
        }
        return value
    }
}

private struct LyricsLineContent: View {
    let line: LyricLine
    let metrics: LyricsLineMetrics
    let availableWidth: CGFloat
    let accent: NSColor
    let elapsed: TimeInterval
    let lineEnd: TimeInterval
    let fillContainer: Bool

    private var current: (index: Int, fraction: Double)? {
        metrics.currentWord(at: elapsed, line: line)
    }

    private var fillWidth: CGFloat {
        guard let current, current.index < metrics.prefixes.count,
              current.index < metrics.wordWidths.count else { return 0 }
        return LyricsLineLayout.fillWidth(prefixWidth: metrics.prefixes[current.index],
                                          currentWordWidth: metrics.wordWidths[current.index],
                                          fraction: current.fraction,
                                          totalWidth: metrics.totalWidth)
    }

    private var readingOffset: CGFloat {
        guard fillContainer else { return 0 }
        if let current, metrics.totalWidth > availableWidth,
           current.index < metrics.prefixes.count,
           current.index < metrics.wordWidths.count {
            let before = metrics.prefixes[current.index]
            let currentWidth = metrics.wordWidths[current.index]
            // Use the real fraction through the word (including
            // multi-character source words) rather than a fixed word center.
            return LyricsLineLayout.followingOffset(prefixWidth: before,
                                                     currentWordWidth: currentWidth,
                                                     fraction: current.fraction,
                                                     totalWidth: metrics.totalWidth,
                                                     availableWidth: availableWidth)
        }
        // Line-only LRC fallback: gray text, no fake word fill; slide over the
        // real line lifetime so the second half remains readable.
        guard line.words.isEmpty, lineEnd > line.start else { return 0 }
        let rawProgress = min(1, max(0, (elapsed - line.start) / (lineEnd - line.start)))
        // Hold the opening prefix briefly, then use the remaining line time for
        // the single gray-line slide. This keeps the sentence start readable
        // without pretending to have word-level timing.
        let hold = 0.15
        let progress = max(0, min(1, (rawProgress - hold) / (1 - hold)))
        return LyricsLineLayout.lineOnlyOffset(progress: progress,
                                                totalWidth: metrics.totalWidth,
                                                availableWidth: availableWidth)
    }

    private var base: some View {
        ZStack(alignment: .leading) {
            Text(line.text).foregroundStyle(.gray)
            Text(line.text)
                .foregroundStyle(Color(nsColor: accent))
                .mask(alignment: .leading) { Rectangle().frame(width: fillWidth) }
        }
        .font(.system(size: 12, weight: .semibold))
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }

    var body: some View {
        if fillContainer {
            base
                .offset(x: -readingOffset)
                .frame(width: availableWidth, height: 17, alignment: .leading)
                .clipped()
                .accessibilityLabel("歌词，\(line.text)")
        } else {
            base
                .frame(height: 17)
                .accessibilityLabel("歌词，\(line.text)")
        }
    }
}
