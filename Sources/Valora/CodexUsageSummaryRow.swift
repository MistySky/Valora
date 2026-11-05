import Foundation
import SwiftUI

/// Renders the three tokens of the Codex usage line. Pure formatting so it can
/// be tested without a provider, a timer or a window.
enum CodexUsageSummaryFormatter {
    static let placeholder = "—"

    /// `5H 79% 19:00` — remaining quota, never the used value.
    static func fiveHour(_ snapshot: CodexUsageSnapshot, now: Date,
                         calendar: Calendar = .current, locale: Locale = .current) -> String {
        // The user wants the date on the 5H window too; the shared panel has
        // room, and a date avoids ambiguity across midnight.
        "5H \(percent(snapshot.fiveHour?.remainingPercent)) " +
        time(snapshot.fiveHour?.resetsAt, now: now, style: .dateAndTime, calendar: calendar, locale: locale)
    }

    /// `WEEK 97% 11/12 14:00`
    static func week(_ snapshot: CodexUsageSnapshot, now: Date,
                     calendar: Calendar = .current, locale: Locale = .current) -> String {
        "WEEK \(percent(snapshot.week?.remainingPercent)) " +
        time(snapshot.week?.resetsAt, now: now, style: .dateAndTime, calendar: calendar, locale: locale)
    }

    /// `重置卡 2张` — count only; the app never redeems a credit.
    static func resetCredits(_ snapshot: CodexUsageSnapshot) -> String {
        guard let count = snapshot.resetAvailableCount, count >= 0 else {
            return "重置卡 \(placeholder)"
        }
        return "重置卡 \(count)张"
    }

    static func percent(_ value: Double?) -> String {
        guard let value, value.isFinite else { return placeholder }
        return "\(Int(value.rounded()))%"
    }

    enum TimeStyle { case sameDayTime, dateAndTime }

    static func time(_ date: Date?, now: Date, style: TimeStyle,
                     calendar: Calendar = .current, locale: Locale = .current) -> String {
        guard let date else { return placeholder }
        var formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        switch style {
        case .sameDayTime:
            let sameDay = calendar.isDate(date, inSameDayAs: now)
            formatter.dateFormat = sameDay ? "HH:mm" : "MM/dd HH:mm"
        case .dateAndTime:
            formatter.dateFormat = "MM/dd HH:mm"
        }
        return formatter.string(from: date)
    }
}

/// One line between the monitor summary and the calendar. Metrics, colour and
/// margins are identical to `MonitorSummaryCard`; there is no title, icon, ring,
/// hover or progress bar, and nothing here can redeem a credit.
struct CodexUsageSummaryRow: View {
    let snapshot: CodexUsageSnapshot

    var body: some View {
        HStack(spacing: 12) {
            Text(CodexUsageSummaryFormatter.fiveHour(snapshot, now: Date()))
            Text(CodexUsageSummaryFormatter.week(snapshot, now: Date()))
            Text(CodexUsageSummaryFormatter.resetCredits(snapshot))
        }
        .font(UIStyle.Fonts.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .center)
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

    private var accessibilityText: String {
        [
            CodexUsageSummaryFormatter.fiveHour(snapshot, now: Date()),
            CodexUsageSummaryFormatter.week(snapshot, now: Date()),
            CodexUsageSummaryFormatter.resetCredits(snapshot)
        ].joined(separator: "，")
    }
}
