// Migrated from MistySky/Calmon commit 72235116e1420fa081e8f694991a32809f81498d,
// CalMon/Calendar/CalendarComponents.swift. Hot-key panel scaling was removed;
// the popover metrics and day-cell rendering are retained.
import SwiftUI

/// Sizes/fonts for the Calmon month grid in the menu-bar popover.
struct CalendarGridMetrics {
    var columnWidth: CGFloat
    var rowHeight: CGFloat
    var highlight: CGFloat
    var badgeSize: CGFloat
    var badgeCorner: CGFloat
    var badgeInset: CGFloat
    var dotSize: CGFloat
    var dotArea: CGFloat
    var dayFont: Font
    var dayFontToday: Font
    var secondaryFont: Font
    var badgeFont: Font
    var textSpacing: CGFloat

    static var popover: CalendarGridMetrics {
        CalendarGridMetrics(
            columnWidth: UIStyle.Metrics.calendarGridWidth / 7,
            rowHeight: UIStyle.Metrics.calendarRowHeight,
            highlight: UIStyle.Metrics.dayHighlight,
            badgeSize: UIStyle.Metrics.badgeSize,
            badgeCorner: UIStyle.Metrics.badgeCorner,
            badgeInset: UIStyle.Metrics.badgeInset,
            dotSize: UIStyle.Metrics.festivalDot,
            dotArea: UIStyle.Metrics.festivalDotArea,
            dayFont: UIStyle.Fonts.dayNumber,
            dayFontToday: UIStyle.Fonts.dayNumberToday,
            secondaryFont: UIStyle.Fonts.gridSecondary,
            badgeFont: UIStyle.Fonts.badge,
            textSpacing: 1
        )
    }

}

/// One Calmon month-grid day cell.
struct CalendarDayCell: View {
    let day: CalmonCalendarModel.DayCell
    let metrics: CalendarGridMetrics
    let colorScheme: ColorScheme
    let onSelect: (Date) -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                ZStack {
                    // Rounded square marker (user request) instead of a circle.
                    if day.isToday {
                        RoundedRectangle(cornerRadius: metrics.highlight * UIStyle.Metrics.dayHighlightCornerRatio, style: .continuous)
                            .fill(UIStyle.Colors.today)
                            .frame(width: metrics.highlight, height: metrics.highlight)
                    } else if day.isSelected {
                        RoundedRectangle(cornerRadius: metrics.highlight * UIStyle.Metrics.dayHighlightCornerRatio, style: .continuous)
                            .fill(UIStyle.selectedDayFill(colorScheme))
                            .frame(width: metrics.highlight, height: metrics.highlight)
                    }
                    VStack(spacing: metrics.textSpacing) {
                        Text("\(day.dayNumber)")
                            .font(day.isToday ? metrics.dayFontToday : metrics.dayFont)
                            .monospacedDigit()
                            .foregroundStyle(numberColor)
                        if let second = day.secondLine {
                            Text(second)
                                .font(metrics.secondaryFont)
                                .foregroundStyle(secondLineColor)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(maxWidth: metrics.columnWidth - 4)
                        }
                    }
                }
                .frame(height: metrics.highlight)

                Circle()
                    .fill(UIStyle.Colors.festivalDot)
                    .frame(width: metrics.dotSize, height: metrics.dotSize)
                    .opacity(day.showsDot ? 1 : 0)
                    .frame(height: metrics.dotArea)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let badge = day.badge {
                CalendarBadge(marker: badge, size: metrics.badgeSize, corner: metrics.badgeCorner, font: metrics.badgeFont)
                    .opacity(day.isCurrentMonth ? 1 : UIStyle.Metrics.adjacentMonthOpacity)
                    .offset(x: -metrics.badgeInset, y: metrics.badgeInset)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onSelect(day.date) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(day.accessibilityLabel)
        .accessibilityAddTraits(day.isSelected ? [.isSelected, .isButton] : .isButton)
    }

    private var numberColor: Color {
        Self.numberColor(
            isToday: day.isToday,
            isCurrentMonth: day.isCurrentMonth,
            isWeekend: day.isWeekend,
            badge: day.badge
        )
    }

    /// Day-number colour: weekends and holidays are red, but a weekend that is a
    /// make-up workday (调休上班) stays normal, so red really means "off".
    static func numberColor(
        isToday: Bool,
        isCurrentMonth: Bool,
        isWeekend: Bool,
        badge: HolidayProvider.Marker?
    ) -> Color {
        if isToday { return .white }
        let isOff = isWeekend || badge == .holiday
        let isMakeUpWorkday = badge == .workday
        if !isCurrentMonth {
            // Adjacent-month days stay dimmed; weekends/holidays keep the red but
            // at the same dimming as the badges, so the weekend columns read the
            // same while the month boundary is still obvious.
            if isMakeUpWorkday || !isOff { return Color(nsColor: .tertiaryLabelColor) }
            return UIStyle.Colors.restBadgeBackground.opacity(UIStyle.Metrics.adjacentMonthOpacity)
        }
        if isMakeUpWorkday { return .primary }
        if isOff { return UIStyle.Colors.restBadgeBackground }
        return .primary
    }

    private var secondLineColor: Color {
        if day.isToday { return .white }
        if !day.isCurrentMonth { return Color(nsColor: .tertiaryLabelColor) }
        return .secondary
    }
}

/// 休/班 corner badge.
struct CalendarBadge: View {
    let marker: HolidayProvider.Marker
    let size: CGFloat
    let corner: CGFloat
    let font: Font

    var body: some View {
        let isHoliday = marker == .holiday
        return Text(isHoliday ? "休" : "班")
            .font(font)
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(isHoliday ? UIStyle.Colors.restBadgeBackground : UIStyle.Colors.workBadgeBackground)
            )
            .accessibilityHidden(true)
    }
}

/// Sizes/fonts for a detail information row, scaled per surface.
struct CalendarInfoMetrics {
    var labelWidth: CGFloat
    var gap: CGFloat
    var cardPadding: CGFloat
    var cardCorner: CGFloat
    var ruleWidth: CGFloat
    var bodyFont: Font
    var captionFont: Font
    var badgeFont: Font
    var minHeight: CGFloat
    var tagPadding: CGFloat
    /// Panel event cards center their "全天" column against the card; the
    /// popover keeps the original top-aligned label.
    var labelCentered: Bool

    static var popover: CalendarInfoMetrics {
        CalendarInfoMetrics(
            labelWidth: 28,
            gap: 8,
            cardPadding: UIStyle.Metrics.cardPadding,
            cardCorner: UIStyle.Metrics.cardCorner,
            ruleWidth: 3,
            bodyFont: UIStyle.Fonts.body,
            captionFont: UIStyle.Fonts.caption,
            badgeFont: UIStyle.Fonts.badge,
            minHeight: 0,
            tagPadding: 8,
            labelCentered: false
        )
    }

}

/// One detail row: narrow "全天" column + light rounded card with a green rule.
struct CalendarInfoRow: View {
    let text: String
    let tag: HolidayProvider.Marker?
    var help: String?
    let metrics: CalendarInfoMetrics

    private var alignment: VerticalAlignment { metrics.labelCentered ? .center : .top }

    var body: some View {
        HStack(alignment: alignment, spacing: metrics.gap) {
            Text("全天")
                .font(metrics.captionFont)
                .foregroundStyle(.secondary)
                .frame(width: metrics.labelWidth, alignment: .leading)
                .padding(.top, metrics.labelCentered ? 0 : metrics.cardPadding / 2)

            HStack(alignment: .top, spacing: metrics.gap) {
                Rectangle()
                    .fill(UIStyle.Colors.festivalDot)
                    .frame(width: metrics.ruleWidth)
                Text(text)
                    .font(metrics.bodyFont)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: metrics.gap)
                if let tag {
                    CalendarTag(marker: tag, font: metrics.badgeFont, horizontalPadding: metrics.tagPadding)
                }
            }
            .padding(metrics.cardPadding)
            .frame(maxWidth: .infinity, minHeight: metrics.minHeight, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: metrics.cardCorner, style: .continuous)
                    .fill(UIStyle.Colors.cardBackground)
            )
        }
        .frame(minHeight: metrics.minHeight > 0 ? metrics.minHeight : nil)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("全天 \(text)")
        .help(help ?? "")
    }
}

/// 休息/补班 capsule tag.
struct CalendarTag: View {
    let marker: HolidayProvider.Marker
    let font: Font
    let horizontalPadding: CGFloat

    var body: some View {
        let isHoliday = marker == .holiday
        return Text(isHoliday ? "休息" : "补班")
            .font(font)
            .foregroundStyle(.white)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(isHoliday ? UIStyle.Colors.restBadgeBackground : UIStyle.Colors.workBadgeBackground)
            )
    }
}
