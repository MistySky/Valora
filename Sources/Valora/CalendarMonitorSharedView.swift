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
}

/// One Calmon-material panel: a compact three-row monitor card followed by the
/// existing calendar content. The outer ScrollView is the only scroll view;
/// CalmonCalendarView is embedded with its own scroll disabled.
struct CalendarMonitorSharedView: View {
    @Bindable var monitor: SystemMonitor
    let calendar: CalmonCalendarModel
    @ObservedObject var visibility: MenuBarPanelVisibility
    let maxHeight: CGFloat
    var onClose: () -> Void

    private var snapshot: SystemMonitor.Snapshot { monitor.snapshot }

    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 0) {
                if visibility.monitorVisible {
                    MonitorSummaryCard(snapshot: snapshot)
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

    private var memoryTotal: String { snapshot.memory.map { UIStyle.memoryCapacityString($0.total) } ?? "--" }
    private var memoryRemaining: String { snapshot.memory?.unusedCapacity.map(UIStyle.memoryCapacityString) ?? "--" }
    private var diskTotal: String { snapshot.disk.map { UIStyle.diskCapacityString($0.total) } ?? "--" }
    private var diskRemaining: String { snapshot.disk.map { UIStyle.diskCapacityString($0.available) } ?? "--" }
    private var uptime: String { snapshot.uptime.isEmpty ? "--" : snapshot.uptime }

    var body: some View {
        HStack(spacing: 12) {
            Text("内存 \(memoryTotal) \(memoryRemaining)")
            Text("磁盘 \(diskTotal) \(diskRemaining)")
            Text(uptime)
        }
        .font(UIStyle.Fonts.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .frame(maxWidth: .infinity, alignment: .center)
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
