// Migrated from MistySky/Calmon commit 72235116e1420fa081e8f694991a32809f81498d,
// CalMon/Calendar/CalendarView.swift. The hot-key panel/hotkey exits are not
// migrated; authorized system-event rows are appended to the Calmon detail area.
import SwiftUI

struct CalmonCalendarView: View {
    let model: CalmonCalendarModel
    let maxHeight: CGFloat
    var onClose: () -> Void
    /// The shared monitor/calendar popover supplies one outer scroll view.
    /// Keep false there so the calendar does not introduce a nested scroll.
    var embedsScroll = true
    @Environment(\.colorScheme) private var colorScheme

    private var gridWidth: CGFloat { UIStyle.Metrics.calendarGridWidth }
    private var columnWidth: CGFloat { gridWidth / 7 }

    var body: some View {
        Group {
            if embedsScroll {
                ScrollView(.vertical) { calendarContent }
            } else {
                calendarContent
            }
        }
            .frame(width: UIStyle.Metrics.calendarPanelWidth)
            .frame(maxHeight: embedsScroll ? maxHeight : nil)
            .focusable()
            .focusEffectDisabled()
            .onKeyPress(.leftArrow) { model.moveSelection(byDays: -1); return .handled }
            .onKeyPress(.rightArrow) { model.moveSelection(byDays: 1); return .handled }
            .onKeyPress(.upArrow) { model.moveSelection(byDays: -7); return .handled }
            .onKeyPress(.downArrow) { model.moveSelection(byDays: 7); return .handled }
            .onKeyPress(.escape) { onClose(); return .handled }
            .onKeyPress(.init("t")) { model.resetToToday(); return .handled }
    }

    private var calendarContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, UIStyle.Metrics.titleGap)
            weekdayRow
                .padding(.bottom, 4)
            monthGrid
            Divider()
                .padding(.vertical, 12)
            detailSection
        }
        .padding(UIStyle.Metrics.contentMargin)
        .frame(width: UIStyle.Metrics.calendarPanelWidth)
    }

    // MARK: - Header

    private var monthTitle: String { model.monthTitle }

    private var header: some View {
        ZStack {
            HStack(spacing: 6) {
                Text(monthTitle)
                    .font(UIStyle.Fonts.panelTitle)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                if model.showsTodayButton {
                    Button("今天") { model.resetToToday() }
                        .buttonStyle(.link)
                        .controlSize(.small)
                        .accessibilityLabel("回到今天")
                }
            }

            HStack(spacing: 0) {
                HStack(spacing: yearChevronGap) {
                    navButton("chevron.left.2", label: "上一年") { model.goToPreviousYear() }
                    navButton("chevron.left", label: "上一个月") { model.goToPreviousMonth() }
                }
                Spacer(minLength: 0)
                HStack(spacing: yearChevronGap) {
                    navButton("chevron.right", label: "下一个月") { model.goToNextMonth() }
                    navButton("chevron.right.2", label: "下一年") { model.goToNextYear() }
                }
            }
        }
        .frame(height: UIStyle.Metrics.calendarHeaderHeight)
    }

    /// Small-calendar navigation button: existing single-chevron size and hit area.
    private var yearChevronGap: CGFloat { 4 }

    private func navButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .frame(width: UIStyle.Metrics.calendarChevronHit, height: UIStyle.Metrics.calendarChevronHit)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .help(label)
    }

    private var weekdayRow: some View {
        let ordered = model.orderedWeekdaySymbols
        let weekend = model.orderedWeekdayIsWeekend
        return HStack(spacing: 0) {
            ForEach(Array(ordered.enumerated()), id: \.offset) { index, symbol in
                Text(symbol)
                    .font(UIStyle.Fonts.weekday)
                    .foregroundStyle(weekend[index] ? UIStyle.Colors.restBadgeBackground : Color.secondary)
                    .frame(width: columnWidth, height: 22)
            }
        }
        .frame(width: gridWidth)
    }

    // MARK: - Grid

    private var monthGrid: some View {
        VStack(spacing: 0) {
            ForEach(model.weeks) { week in
                HStack(spacing: 0) {
                    ForEach(week.days) { day in
                        dayCell(day)
                            .frame(width: columnWidth, height: UIStyle.Metrics.calendarRowHeight)
                    }
                }
            }
        }
        .frame(width: gridWidth)
    }

    private func dayCell(_ day: CalmonCalendarModel.DayCell) -> some View {
        CalendarDayCell(day: day, metrics: .popover, colorScheme: colorScheme) { model.select($0) }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailSection: some View {
        if let detail = model.detail {
            VStack(alignment: .leading, spacing: 8) {
                summaryRow(detail)

                // Relative date and festivals share one information-row style.
                CalendarInfoRow(text: detail.relative, tag: nil, metrics: .popover)

                ForEach(detail.festivals) { festival in
                    CalendarInfoRow(text: festival.title, tag: festival.marker, help: festival.sourceTitle.map { "来源：\($0)" } ?? festival.title, metrics: .popover)
                }

                if detail.festivals.isEmpty, let marker = detail.marker {
                    CalendarInfoRow(text: marker == .holiday ? "休息" : "补班", tag: marker, metrics: .popover)
                }

                if let sourceNote = detail.sourceNote {
                    Text(sourceNote)
                        .font(UIStyle.Fonts.caption)
                        .foregroundStyle(.secondary)
                }

                systemEventsSection
            }
        }
    }

    /// System events use the same authorized, selected-day data as the
    /// Alcove-style single calendar switch. The sample provider is tagged.
    @ViewBuilder
    private var systemEventsSection: some View {
        if model.events.isEmpty {
            switch model.eventState {
            case .loading:
                Text("正在读取日程…")
                    .font(UIStyle.Fonts.caption)
                    .foregroundStyle(.secondary)
            case .notAvailable:
                Text("开启日历授权后显示系统日程")
                    .font(UIStyle.Fonts.caption)
                    .foregroundStyle(.secondary)
            case .loaded:
                EmptyView()
            }
        } else {
            ForEach(model.events) { event in
                CalendarSystemEventRow(event: event, metrics: .popover)
            }
        }
        if model.preview {
            Text("预览样例 · 日历内容为注入样例")
                .font(UIStyle.Fonts.caption)
                .foregroundStyle(.tertiary)
        }
    }

    /// Single-line summary: date + ISO week on the left, lunar year/生肖/月日 on
    /// the right (right side collapses when 农历 is off).
    private func summaryRow(_ detail: CalmonCalendarModel.Detail) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(detail.summaryDate)
                .font(UIStyle.Fonts.body)
                .lineLimit(1)
                .minimumScaleFactor(0.9)
            Spacer(minLength: 8)
            if model.showsLunarInDetail {
                Text(detail.lunarSummary)
                    .font(UIStyle.Fonts.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
            }
        }
    }

}


/// System-event row in the Calmon detail rhythm: time label + light card.
private struct CalendarSystemEventRow: View {
    let event: CalendarEvent
    let metrics: CalendarInfoMetrics

    var body: some View {
        HStack(alignment: .top, spacing: metrics.gap) {
            Text(event.isAllDay ? "全天" : event.start.formatted(date: .omitted, time: .shortened))
                .font(metrics.captionFont)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(width: 42, alignment: .leading)
                .padding(.top, metrics.cardPadding / 2)
            HStack(alignment: .top, spacing: metrics.gap) {
                Rectangle()
                    .fill(UIStyle.Colors.applicationBar)
                    .frame(width: metrics.ruleWidth)
                Text(event.title)
                    .font(metrics.bodyFont)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: metrics.gap)
            }
            .padding(metrics.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: metrics.cardCorner, style: .continuous)
                    .fill(UIStyle.Colors.cardBackground)
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("日程 \(event.title)")
    }
}
