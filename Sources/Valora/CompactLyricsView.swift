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
    @ObservedObject private var playback: PlaybackProgress
    @State private var metricsCache = LyricMetricsCache()
    @State private var frameCache = LyricsLineFrameCache()

    init(model: AppModel, width: CGFloat, rowHeight: CGFloat = 32,
         showsNote: Bool = true, horizontalInset: CGFloat = 18,
         centersNoteWhenEmpty: Bool = false, auditRole: String = "active",
         playback: PlaybackProgress? = nil) {
        self.model = model
        self.width = width
        self.rowHeight = rowHeight
        self.showsNote = showsNote
        self.horizontalInset = horizontalInset
        self.centersNoteWhenEmpty = centersNoteWhenEmpty
        self.auditRole = auditRole
        self._playback = ObservedObject(wrappedValue: playback ?? model.progress)
    }

    private var availableWidth: CGFloat { max(1, width - (showsNote ? 22 : 0)) }

    /// Built once instead of once per 30Hz frame.
    private static let lineTransition: AnyTransition = .asymmetric(
        insertion: .offset(y: 26).combined(with: .opacity),
        removal: .offset(y: -26).combined(with: .opacity))

    private func lineView(_ line: LyricLine?, elapsed: TimeInterval) -> some View {
        // Everything except the interpolated word progress is identical for
        // every frame of this line; the cache prepares it once and the 30Hz
        // frame only reads it.
        let frame = frameCache.frame(for: line, duration: model.duration,
                                     identity: model.lyrics.identity,
                                     timeline: model.lyrics.timeline,
                                     width: availableWidth, metricsCache: metricsCache)
        let current = line.flatMap { line in
            frame.metrics?.currentWord(at: elapsed, line: line)
        }
        #if VALORA_DEVELOPMENT
        // Development-only frame probe; the release view has no audit hook.
        LyricsFrameProbe.record(role: auditRole, elapsed: elapsed,
                                lineStart: line?.start, wordIndex: current?.index)
        #endif
        return HStack(spacing: 5) {
            if showsNote { noteIcon }
            if let line, let metrics = frame.metrics {
                LyricsLineContent(line: line, metrics: metrics, availableWidth: availableWidth,
                                  accent: model.lyricsAccentColor, elapsed: elapsed,
                                  current: current, lineEnd: frame.lineEnd,
                                  fillContainer: frame.isLong)
                    .id(frame.key)
                    .transition(Self.lineTransition)
            } else if !centersNoteWhenEmpty {
                Color.clear.frame(width: availableWidth, height: 17)
            }
        }
        .foregroundStyle(.gray)
        .frame(width: max(1, width), height: rowHeight, alignment: frame.isLong ? .leading : .center)
        .padding(.horizontal, horizontalInset)
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(frame.label)
        .accessibilityIdentifier("compact.lyrics")
        .animation(.easeInOut(duration: 0.2), value: frame.key)
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

/// Prepared per-line display data. The 30Hz lyric frame only interpolates the
/// word progress; the measured widths, the line end, the accessibility label
/// and the transition identity are the same for every frame of the line, so
/// they are rebuilt only when the line (or its inputs) actually changes.
///
/// The successor boundary is re-derived from the *current* timeline on every
/// call: an earlier/later inserted line can change the line end without
/// changing the line count or the old successor slot, so those local features
/// cannot prove the boundary is unchanged. The lookup is a binary search, not
/// a per-frame scan or string/hash build.
final class LyricsLineFrameCache {
    struct Frame {
        let metrics: LyricsLineMetrics?
        let isLong: Bool
        let lineEnd: TimeInterval
        let label: String
        let key: String
    }

    private struct Entry {
        let line: LyricLine?
        let identity: LyricsTrackIdentity?
        let duration: Double
        let width: CGFloat
        /// Real first line start after the current line in this timeline.
        let nextStart: TimeInterval?
        let frame: Frame
    }

    private var entry: Entry?
    /// Test seams: how many times the expensive work actually ran.
    private(set) var metricsRebuilds = 0
    private(set) var frameRebuilds = 0

    func frame(for line: LyricLine?, duration: Double, identity: LyricsTrackIdentity?,
               timeline: LyricTimeline?, width: CGFloat,
               metricsCache: LyricMetricsCache) -> Frame {
        let nextStart = line.flatMap { Self.nextStart(in: timeline?.lines ?? [], after: $0.start) }
        if let entry, entry.line == line, entry.identity == identity,
           entry.duration == duration, entry.width == width,
           entry.nextStart == nextStart {
            return entry.frame
        }
        frameRebuilds += 1
        let metrics: LyricsLineMetrics?
        if let entry, let line, entry.line == line, entry.identity == identity {
            // Only the successor boundary or the width changed; keep the
            // measured widths instead of re-measuring the line.
            metrics = entry.frame.metrics
        } else {
            metrics = line.map { metricsCache.metrics(for: $0, identity: identity) }
            if line != nil { metricsRebuilds += 1 }
        }
        var lineEnd: TimeInterval = 0
        if let line {
            if let nextStart {
                lineEnd = nextStart
            } else {
                lineEnd = max(line.start + 8,
                              duration > line.start ? duration : line.start + 8)
            }
        }
        let isLong = (metrics?.totalWidth ?? 0) > width
        let label = line.map { "歌词，\($0.text)" } ?? "歌词"
        let key = line.map { "\($0.start)-\($0.text)" } ?? ""
        let frame = Frame(metrics: metrics, isLong: isLong, lineEnd: lineEnd,
                          label: label, key: key)
        entry = Entry(line: line, identity: identity, duration: duration, width: width,
                      nextStart: nextStart, frame: frame)
        return frame
    }

    /// First line whose start is strictly greater than `start` (upper bound).
    /// Ties keep the existing `line(at:)` semantics: a line with the same start
    /// is never its own successor.
    static func nextStart(in lines: [LyricLine], after start: TimeInterval) -> TimeInterval? {
        guard !lines.isEmpty else { return nil }
        var low = 0
        var high = lines.count
        while low < high {
            let mid = (low + high) / 2
            if lines[mid].start > start {
                high = mid
            } else {
                low = mid + 1
            }
        }
        return low < lines.count ? lines[low].start : nil
    }
}

private struct LyricsLineContent: View {
    let line: LyricLine
    let metrics: LyricsLineMetrics
    let availableWidth: CGFloat
    let accent: NSColor
    let elapsed: TimeInterval
    let current: (index: Int, fraction: Double)?
    let lineEnd: TimeInterval
    let fillContainer: Bool

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
