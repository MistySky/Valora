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
    /// Connectivity snapshot for the optional device row. Nil in previews/QA
    /// that do not own the production controller.
    var appModel: AppModel? = nil
    var settings: RevivalSettings? = nil
    @ObservedObject var visibility: MenuBarPanelVisibility
    let maxHeight: CGFloat
    var onClose: () -> Void

    private var snapshot: SystemMonitor.Snapshot { monitor.snapshot }

    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 0) {
                if let appModel, let settings {
                    MonitorSummarySection(monitor: monitor, codex: codex,
                                          visibility: visibility,
                                          appModel: appModel, settings: settings)
                } else if visibility.monitorVisible {
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

/// Observes the connectivity snapshot so the device line can appear/disappear
/// without turning the card into a second owner of the model. The card is shown
/// when stats, Codex or a recognized connected headphone needs a row; the
/// calendar route itself is unchanged.
struct MonitorSummarySection: View {
    @Bindable var monitor: SystemMonitor
    var codex: CodexUsageProvider?
    @ObservedObject var visibility: MenuBarPanelVisibility
    @ObservedObject var appModel: AppModel
    @ObservedObject var settings: RevivalSettings

    var body: some View {
        let device = DeviceBatteryRow.data(devices: appModel.devices,
                                           enabled: settings.bluetoothEnabled)
        let codexSnapshot = visibility.codexUsageVisible ? codex?.snapshot : nil
        if visibility.monitorVisible || codexSnapshot != nil || device != nil {
            MonitorSummaryCard(snapshot: monitor.snapshot, codex: codexSnapshot,
                               device: device, showsStats: visibility.monitorVisible)
        }
    }
}

/// Deliberately small: three aligned rows, no rings, process list, search,
/// CPU split, device model or system-version blocks.
struct MonitorSummaryCard: View {
    let snapshot: SystemMonitor.Snapshot
    /// Optional Codex usage line inside the same card, separated by a hairline so
    /// the two summaries sit close together instead of as two stacked cards.
    var codex: CodexUsageSnapshot? = nil
    /// Optional device line inside the same Grid, after the monitor/Codex rows.
    var device: DeviceBatteryRowData? = nil
    /// `false` renders only the Codex/device lines (monitor switch off).
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

    private var accessibilityText: String {
        MonitorSummaryAccessibility.label(
            showsStats: showsStats,
            codex: codex,
            device: device,
            stats: MonitorSummaryAccessibility.Stats(
                memoryTotal: memoryTotal, memoryRemaining: memoryRemaining,
                diskTotal: diskTotal, diskRemaining: diskRemaining, uptime: uptime),
            now: now)
    }

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
            if let device {
                if showsStats || codex != nil {
                    GridRow {
                        Rectangle()
                            .fill(Color.primary.opacity(0.12))
                            .frame(height: 1)
                            .gridCellColumns(3)
                    }
                }
                // Three real Grid cells aligned with 内存/5H, 磁盘/WEEK and
                // 已运行/重置卡: name | left+right | case.
                GridRow {
                    Text(device.name)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(device.ears)
                        .lineLimit(1)
                    Text(device.caseText)
                        .lineLimit(1)
                }
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
        .accessibilityLabel(accessibilityText)
    }
}

/// Accessibility text built from the rows that are really visible: the monitor
/// row only when `showsStats`, the Codex row only when a snapshot exists. No
/// fabricated monitor or quota text when a row is absent.
enum MonitorSummaryAccessibility {
    struct Stats: Equatable {
        var memoryTotal: String
        var memoryRemaining: String
        var diskTotal: String
        var diskRemaining: String
        var uptime: String
    }

    static func label(showsStats: Bool, codex: CodexUsageSnapshot?,
                      device: DeviceBatteryRowData? = nil,
                      stats: Stats, now: Date) -> String {
        var parts: [String] = []
        if showsStats {
            parts.append("内存 \(stats.memoryTotal)，剩余 \(stats.memoryRemaining)")
            parts.append("磁盘 \(stats.diskTotal)，剩余 \(stats.diskRemaining)")
            parts.append(stats.uptime)
        }
        if let codex {
            parts.append(CodexUsageSummaryFormatter.fiveHour(codex, now: now))
            parts.append(CodexUsageSummaryFormatter.week(codex, now: now))
            parts.append(CodexUsageSummaryFormatter.resetCredits(codex))
        }
        if let device {
            parts.append(device.accessibility)
        }
        return parts.joined(separator: "，")
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
