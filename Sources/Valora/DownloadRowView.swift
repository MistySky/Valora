// Adapted from TheDynamicPunk/Convoy commit 007a20973923fcd69c42a3571fc299f5b8582dc6
// Views/DownloadRowView.swift (GPL-3.0; see Resources/Licenses/Convoy-GPL-3.0.txt).
// The mature row hierarchy, status pill, SegmentBar, metrics, selection
// affordance and context-menu semantics are retained. The engine DownloadTask
// and DownloadManager references were replaced by immutable snapshots and
// injected actions so the UI never imports the engine.
import AppKit
import SwiftUI

struct DownloadRowActions {
    var pause: (UUID) -> Void = { _ in }
    var start: (UUID) -> Void = { _ in }
    var resume: (UUID) -> Void = { _ in }
    var retry: (UUID) -> Void = { _ in }
    var restart: (UUID) -> Void = { _ in }
    var open: (UUID) -> Void = { _ in }
    var reveal: (UUID) -> Void = { _ in }
    var requestDelete: (UUID) -> Void = { _ in }
}

struct DownloadRowView: View {
    let item: DownloadItemSnapshot
    var isSelected: Bool = false
    var isEmphasized: Bool = true
    var isSelectionModeActive: Bool = false
    var onSelect: (_ shiftHeld: Bool, _ commandHeld: Bool) -> Void = { _, _ in }
    var actions = DownloadRowActions()
    var onRequestDelete: (() -> Void)? = nil
    @State private var isHovering = false
    @Environment(\.appearsActive) private var appearsActive
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let horizontalPadding: CGFloat = 14
    static let iconSize: CGFloat = 40
    static let iconSpacing: CGFloat = 14
    static var textLeading: CGFloat { horizontalPadding + iconSize + iconSpacing }

    private var fileMissing: Bool { item.state == .completed && !item.isFilePresent }

    var body: some View {
        HStack(alignment: .center, spacing: Self.iconSpacing) {
            categoryIcon
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(item.filename)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(fileMissing ? .secondary : .primary)
                    statusPill.fixedSize()
                    Spacer(minLength: 8)
                    if item.state == .downloading || item.state == .waiting {
                        Text("\(Int(item.progress * 100))%")
                            .font(.system(size: 12, weight: .semibold).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .fixedSize()
                    }
                }
                if !fileMissing && showsProgressBar { progressBar }
                if fileMissing {
                    metric(icon: "questionmark.folder", text: "Moved or deleted")
                } else if item.state == .waiting {
                    HStack(spacing: 10) {
                        metric(icon: "internaldrive", text: sizeMetricText)
                        Text("|").font(.system(size: 11)).foregroundStyle(.tertiary)
                        Text("Queued — waiting for a free slot")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                } else if isActive {
                    ViewThatFits(in: .horizontal) {
                        activeMetrics(showsTimeLeft: true, showsParts: true)
                        activeMetrics(showsTimeLeft: true, showsParts: false)
                        activeMetrics(showsTimeLeft: false, showsParts: false)
                    }
                } else if item.state == .completed {
                    HStack(spacing: 14) {
                        metric(icon: "checkmark.circle", text: "Completed")
                        metric(icon: "internaldrive", text: formatBytes(item.totalBytes))
                    }
                } else if item.state == .failed {
                    Text(item.errorDescription ?? "Download failed")
                        .font(.system(size: 12)).foregroundStyle(.red)
                        .lineLimit(4).fixedSize(horizontal: false, vertical: true)
                        .help(item.errorDescription ?? "Download failed")
                } else if item.state == .paused {
                    HStack(spacing: 10) {
                        metric(icon: "internaldrive", text: sizeMetricText)
                        if let parts = partsMetric { metric(icon: parts.icon, text: parts.text) }
                    }
                } else if item.state == .urlExpired {
                    HStack(spacing: 14) {
                        metric(icon: "internaldrive", text: sizeMetricText)
                        Text("|").font(.system(size: 11)).foregroundStyle(.tertiary)
                        Text("Link expired — tap Re-link to continue")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                } else if item.state == .destinationMissing {
                    HStack(spacing: 14) {
                        metric(icon: "internaldrive", text: sizeMetricText)
                        Text("|").font(.system(size: 11)).foregroundStyle(.tertiary)
                        Text("Original folder can't be found — choose a new one to continue")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                } else if item.state == .awaitingDuplicateResolution {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 11)).foregroundStyle(.orange)
                        Text("A duplicate was found — nothing more is downloading until you decide")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            actionButtons
        }
        .padding(.vertical, 12)
        .padding(.horizontal, Self.horizontalPadding)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected
                    ? (isEmphasized && appearsActive ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.12))
                    : isHovering ? Color(nsColor: .unemphasizedSelectedContentBackgroundColor).opacity(0.5) : Color.clear)
        )
        .opacity(fileMissing ? 0.55 : 1)
        .contentShape(Rectangle())
        .onTapGesture {
            guard isSelectionModeActive else { return }
            let flags = NSEvent.modifierFlags
            onSelect(flags.contains(.shift), flags.contains(.command))
        }
        .onHover { isHovering = $0 }
        .contextMenu { contextMenuItems }
    }

    private var isActive: Bool {
        [.downloading, .starting, .validating, .refreshingLink].contains(item.state)
    }

    private var categoryIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill((fileMissing ? Color.gray : categoryColor).opacity(0.15))
                .frame(width: Self.iconSize, height: Self.iconSize)
            Image(systemName: fileMissing ? "questionmark.folder" : categoryIconName)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(fileMissing ? Color.gray : categoryColor)
        }
        .overlay(alignment: .topLeading) {
            if isHovering || isSelected || isSelectionModeActive {
                Button(action: { onSelect(false, false) }) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 14))
                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                        .background(Circle().fill(Color(nsColor: .windowBackgroundColor)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(isSelected ? "Deselect" : "Select")
                .offset(x: -4, y: -4)
                .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isHovering)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
        .overlay(alignment: .bottomTrailing) {
            if !fileMissing {
                Image(systemName: statusIconName)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white).padding(3)
                    .background(Circle().fill(statusColor)).offset(x: 4, y: 4)
            }
        }
    }

    private var categoryIconName: String {
        let ext = (item.filename as NSString).pathExtension.lowercased()
        if ["mp4", "mov", "mkv", "avi", "webm", "m4v"].contains(ext) { return "film" }
        if ["mp3", "m4a", "wav", "flac", "aac"].contains(ext) { return "waveform" }
        if ["zip", "rar", "7z", "tar", "gz"].contains(ext) { return "archivebox" }
        if ["pdf", "txt", "md", "doc", "docx", "rtf"].contains(ext) { return "doc.text" }
        return "doc"
    }

    private var categoryColor: Color {
        switch categoryIconName {
        case "film": return .purple
        case "waveform": return .pink
        case "archivebox": return .orange
        case "doc.text": return .blue
        default: return .gray
        }
    }

    private var statusPill: some View {
        Group {
            if fileMissing {
                Text("Moved")
                    .font(.system(size: 10, weight: .semibold)).textCase(.uppercase)
                    .foregroundStyle(.gray).padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.gray.opacity(0.13), in: Capsule())
            } else if item.state != .completed {
                Text(statusText)
                    .font(.system(size: 10, weight: .semibold)).textCase(.uppercase)
                    .foregroundStyle(statusColor).padding(.horizontal, 6).padding(.vertical, 2)
                    .background(statusColor.opacity(0.13), in: Capsule())
            }
        }
    }

    private var statusIconName: String {
        switch item.state {
        case .waiting: return "clock.fill"
        case .starting, .validating, .refreshingLink, .downloading: return "arrow.down"
        case .paused: return "pause.fill"
        case .completed: return "checkmark"
        case .failed: return "exclamationmark"
        case .cancelled: return "xmark"
        case .urlExpired: return "link.slash"
        case .destinationMissing: return "questionmark.folder"
        case .awaitingDuplicateResolution: return "exclamationmark.circle.fill"
        case .unknown: return "questionmark"
        }
    }

    private var statusColor: Color {
        switch item.state {
        case .waiting, .urlExpired, .destinationMissing, .awaitingDuplicateResolution: return .orange
        case .starting, .validating, .refreshingLink, .downloading: return .blue
        case .paused: return .yellow
        case .completed: return .green
        case .failed: return .red
        case .cancelled, .unknown: return .gray
        }
    }

    private var statusText: String {
        switch item.state {
        case .waiting: return "Waiting"
        case .starting, .validating, .refreshingLink: return "Starting"
        case .downloading: return "Downloading"
        case .paused: return "Paused"
        case .completed: return "Completed"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        case .urlExpired: return "Expired"
        case .destinationMissing: return "Folder Missing"
        case .awaitingDuplicateResolution: return "Needs Your Input"
        case .unknown: return "Unknown"
        }
    }

    private var sizeMetricText: String {
        item.hasUnknownTotalSize ? formatBytes(item.downloadedBytes)
            : "\(formatBytes(item.downloadedBytes)) / \(formatBytes(item.totalBytes))"
    }

    private var partsMetric: (icon: String, text: String)? {
        guard item.hasUnknownTotalSize, item.totalSegments > 0 else { return nil }
        return ("square.grid.3x3", "\(item.completedSegments) of \(item.totalSegments) parts")
    }

    private var progressBar: some View {
        DownloadSegmentBar(segments: item.segments, layout: item.segmentLayout,
                           progress: item.progress, color: statusColor,
                           split: showsParts ? 1 : 0)
            .frame(height: 7)
            .animation(.easeOut(duration: 0.25), value: item.progress)
            .animation(reduceMotion ? nil : .smooth(duration: 0.55), value: showsParts)
            .accessibilityElement()
            .accessibilityLabel("Progress")
            .accessibilityValue(progressAccessibilityValue)
    }

    private var showsProgressBar: Bool {
        [.waiting, .starting, .validating, .refreshingLink, .downloading,
         .paused, .urlExpired, .destinationMissing].contains(item.state)
    }

    private var showsParts: Bool {
        item.state == .downloading && !item.isMerging && !item.segments.isEmpty
    }

    private var progressAccessibilityValue: String {
        let percent = "\(Int(item.progress * 100)) percent"
        if item.totalSegments > 0 { return "\(percent), \(item.completedSegments) of \(item.totalSegments) parts" }
        if showsParts, item.segmentLayout == "lanes" { return "\(percent), \(item.activeSegments) connections active" }
        return percent
    }

    private func metric(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 10))
            Text(text).font(.system(size: 11.5).monospacedDigit()).lineLimit(1)
        }.foregroundStyle(.secondary)
    }

    private func activeMetrics(showsTimeLeft: Bool, showsParts: Bool) -> some View {
        HStack(spacing: 10) {
            metric(icon: "internaldrive", text: sizeMetricText)
            metric(icon: "gauge.with.dots.needle.67percent", text: formatSpeed(item.speed))
            if showsTimeLeft, item.estimatedTimeRemaining > 0 {
                metric(icon: "clock", text: formatTime(item.estimatedTimeRemaining) + " left")
            }
            if showsParts, let parts = partsMetric { metric(icon: parts.icon, text: parts.text) }
        }
    }

    @ViewBuilder private var actionButtons: some View {
        HStack(spacing: 6) {
            if fileMissing {
                // Right-click still offers Delete.
            } else if isActive {
                RowIconButton(icon: "pause.fill", tint: .primary) { actions.pause(item.id) }
                    .help("Pause download")
            } else if item.state == .waiting {
                RowIconButton(icon: "play.fill", tint: .blue) { actions.start(item.id) }
                    .help("Start this download now")
            } else if item.state == .paused {
                RowIconButton(icon: "play.fill", tint: .blue) { actions.resume(item.id) }
                    .help("Resume download")
            } else if item.state == .completed {
                RowIconButton(icon: "folder", tint: .primary) { actions.reveal(item.id) }
                    .help("Show in Finder")
                RowIconButton(icon: "arrow.up.forward.app", tint: .primary) { actions.open(item.id) }
                    .help("Open file")
            } else if item.state == .failed {
                RowIconButton(icon: "arrow.clockwise", tint: .blue) { actions.retry(item.id) }
                    .help("Retry download")
            }
        }
    }

    @ViewBuilder private var contextMenuItems: some View {
        if fileMissing {
            Text("File not found at saved location")
        } else if isActive {
            Button("Pause") { actions.pause(item.id) }
        } else if item.state == .waiting {
            Button("Start") { actions.start(item.id) }
        } else if item.state == .paused {
            Button("Resume") { actions.resume(item.id) }
        } else if item.state == .failed {
            Button("Retry") { actions.retry(item.id) }
            Button("Restart from Beginning") { actions.restart(item.id) }
        }
        if item.state == .completed && !fileMissing {
            Button("Show in Finder") { actions.reveal(item.id) }
            Button("Open") { actions.open(item.id) }
        }
        if !fileMissing {
            Button("Copy URL") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(item.sourceURL, forType: .string)
            }
            if item.state == .completed {
                Button("Copy File Path") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(item.destinationPath, forType: .string)
                }
            }
        }
        Divider()
        Button("Delete…", role: .destructive) {
            if let onRequestDelete { onRequestDelete() } else { actions.requestDelete(item.id) }
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var size = Double(max(0, bytes)); var unit = 0
        while size >= 1024 && unit < units.count - 1 { size /= 1024; unit += 1 }
        return String(format: "%.1f %@", size, units[unit])
    }
    private func formatSpeed(_ bytesPerSecond: Int64) -> String {
        let units = ["B/s", "KB/s", "MB/s", "GB/s"]
        var speed = Double(max(0, bytesPerSecond)); var unit = 0
        while speed >= 1024 && unit < units.count - 1 { speed /= 1024; unit += 1 }
        return String(format: "%.1f %@", speed, units[unit])
    }
    private func formatTime(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds)); let hours = total / 3600
        let minutes = (total % 3600) / 60; let secs = total % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, secs)
                         : String(format: "%d:%02d", minutes, secs)
    }
}

private struct RowIconButton: View {
    let icon: String
    let tint: Color
    let action: () -> Void
    @State private var isHovering = false
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint).frame(width: 28, height: 28)
                .background(Circle().fill(isHovering ? Color(nsColor: .quaternaryLabelColor).opacity(0.5) : Color.clear))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
