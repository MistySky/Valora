import AppKit
import Observation
import SwiftUI

/// Observable visibility state shared by the two status-item routes. The
/// controller updates these values immediately when Settings changes, so an
/// already-open panel drops/adds its section without keeping hidden providers
/// alive.
@MainActor
final class MenuBarPanelVisibility: ObservableObject {
    @Published var monitorVisible = true
    @Published var calendarVisible = true
    /// Codex usage line has its own switch: it can show while the monitor is
    /// off (the calendar entry still opens the shared panel).
    @Published var codexUsageVisible = false
}

/// One Calmon-material panel: a compact three-row monitor card followed by the
/// existing calendar content. The outer ScrollView is the only scroll view;
/// CalmonCalendarView is embedded with its own scroll disabled.
struct CalendarMonitorSharedView: View {
    @Bindable var monitor: SystemMonitor
    let calendar: CalmonCalendarModel
    /// Owned by the app; nil when the feature was never enabled.
    var codex: CodexUsageProvider?
    @ObservedObject var visibility: MenuBarPanelVisibility
    let maxHeight: CGFloat
    var onClose: () -> Void

    private var snapshot: SystemMonitor.Snapshot { monitor.snapshot }

    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 0) {
                if visibility.monitorVisible {
                    MonitorSummaryCard(
                        snapshot: snapshot,
                        codex: visibility.codexUsageVisible ? codex?.snapshot : nil)
                } else if visibility.codexUsageVisible, let codex {
                    // Monitor card hidden but its switch off: the Codex line keeps
                    // its own compact card so the calendar entry still shows it.
                    MonitorSummaryCard(snapshot: snapshot, codex: codex.snapshot, showsStats: false)
                }
                if visibility.calendarVisible {
                    CalmonCalendarView(
                        model: calendar,
                        maxHeight: maxHeight,
                        onClose: onClose,
                        embedsScroll: false)
                }
            }
            .frame(width: UIStyle.Metrics.menuBarPopoverWidth)
        }
        .frame(width: UIStyle.Metrics.menuBarPopoverWidth)
        .frame(maxHeight: maxHeight)
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.escape) { onClose(); return .handled }
    }
}

/// Deliberately small: three aligned rows, no rings, process list, search,
/// CPU split, device model or system-version blocks.
struct MonitorSummaryCard: View {
    let snapshot: SystemMonitor.Snapshot
    /// Optional Codex usage line inside the same card, separated by a hairline so
    /// the two summaries sit close together instead of as two stacked cards.
    var codex: CodexUsageSnapshot? = nil
    /// `false` renders only the Codex line (monitor switch off).
    var showsStats: Bool = true

    private var memoryTotal: String { snapshot.memory.map { UIStyle.memoryCapacityString($0.total) } ?? "--" }
    private var memoryRemaining: String { snapshot.memory?.unusedCapacity.map(UIStyle.memoryRemainingString) ?? "--" }
    private var diskTotal: String { snapshot.disk.map { UIStyle.diskCapacityString($0.total) } ?? "--" }
    private var diskRemaining: String { snapshot.disk.map { UIStyle.diskCapacityString($0.available) } ?? "--" }
    private var uptime: String { snapshot.uptime.isEmpty ? "--" : snapshot.uptime }

    private var statsRow: some View {
        GridRow {
            Text("内存 \(memoryTotal) \(memoryRemaining)")
            Text("磁盘 \(diskTotal) \(diskRemaining)")
            Text(uptime)
        }
    }

    private var codexRow: some View {
        GridRow {
            Text(CodexUsageSummaryFormatter.fiveHour(codexSnapshot, now: now))
            Text(CodexUsageSummaryFormatter.week(codexSnapshot, now: now))
            Text(CodexUsageSummaryFormatter.resetCredits(codexSnapshot))
        }
    }

    private var codexSnapshot: CodexUsageSnapshot { codex ?? .initial }
    private var now: Date { Date() }

    var body: some View {
        // One Grid so both rows share column widths: 内存/5H, 磁盘/WEEK and
        // 已运行/重置卡 line up instead of each row spacing itself.
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
            if showsStats {
                statsRow
            }
            if codex != nil {
                if showsStats {
                    GridRow {
                        Rectangle()
                            .fill(Color.primary.opacity(0.12))
                            .frame(height: 1)
                            .gridCellColumns(3)
                    }
                }
                codexRow
            }
        }
        .font(UIStyle.Fonts.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(UIStyle.Metrics.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: UIStyle.Metrics.cardCorner, style: .continuous)
                .fill(UIStyle.Colors.cardBackground)
        )
        .padding(UIStyle.Metrics.contentMargin)
        .frame(width: UIStyle.Metrics.menuBarPopoverWidth)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("内存 \(memoryTotal)，剩余 \(memoryRemaining)，磁盘 \(diskTotal)，剩余 \(diskRemaining)，\(uptime)")
    }
}

/// Pure formatting decisions for the three-row summary. Missing values always
/// render as `--`; no zero or sample-language value is synthesized.
enum MonitorSummaryFormat {
    static func total(_ value: String?) -> String {
        "总计 \(value ?? "--")"
    }
    static func remaining(_ value: String?) -> String {
        "剩余 \(value ?? "--")"
    }
    static func uptime(_ value: String) -> String {
        value.isEmpty ? "--" : value
    }
}
