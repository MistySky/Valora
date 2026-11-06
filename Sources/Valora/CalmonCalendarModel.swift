// Migrated from MistySky/Calmon commit 72235116e1420fa081e8f694991a32809f81498d,
// CalMon/Calendar/CalendarModel.swift. Valora injects its own clock/timezone and
// authorized event provider; Calmon preferences and automatic holiday loading are
// replaced by fixed display defaults and panel-visible-only reads.
import AppKit
import Foundation
import Observation

/// Owns the visible month, the selected day, the day grid and the selected-day
/// detail. It reads festivals/lunar data from `HolidayProvider` but never talks
/// to the monitoring module.
@MainActor
@Observable
final class CalmonCalendarModel {

    // MARK: - Types

    struct LunarDate: Equatable {
        var year: Int
        var month: Int
        var day: Int
        var isLeapMonth: Bool
        var monthName: String
        var dayName: String
        var zodiac: String
        var ganzhi: String

        var monthDay: String { isLeapMonth ? "闰\(monthName)\(dayName)" : "\(monthName)\(dayName)" }
        var display: String { "\(ganzhi)年 · \(monthDay) · 属\(zodiac)" }
    }

    struct Detail {
        var date: Date
        /// Single-line left summary: "2026年09月25日（第39周）".
        var summaryDate: String
        /// Single-line right summary: "丙午年（马）八月十五".
        var lunarSummary: String
        var relative: String
        var festivals: [HolidayProvider.Festival]
        var marker: HolidayProvider.Marker?
        var sourceNote: String?
    }

    struct DayCell: Identifiable {
        var id: String
        var date: Date
        var dayNumber: Int
        var isCurrentMonth: Bool
        var isToday: Bool
        var isSelected: Bool
        /// Saturday/Sunday by calendar weekday (not the week-start preference).
        var isWeekend: Bool
        var lunar: LunarDate
        var solarTerm: String?
        var festivalShort: String?
        var secondLine: String?
        var badge: HolidayProvider.Marker?
        var showsDot: Bool
        var accessibilityLabel: String
    }

    struct Week: Identifiable {
        var id: String
        var days: [DayCell]
    }

    enum EventState: Equatable {
        case notAvailable
        case loading
        case loaded
    }

    // MARK: - State

    private(set) var visibleMonth: Date
    private(set) var selectedDate: Date
    private(set) var today: Date
    private(set) var weeks: [Week] = []
    private(set) var detail: Detail?
    private(set) var menuBarText: String = ""

    private static let showWeekday = true
    private static let showLunar = true
    private static let showChineseHolidays = true
    private static let weekStartsOnMonday = true

    private var calendar: Calendar
    private let provider: HolidayProvider
    private var holidayReadAllowed: Bool { Self.showChineseHolidays && readGate() }
    private let now: () -> Date
    private let timeZoneProvider: () -> TimeZone
    private let readGate: () -> Bool
    let preview: Bool
    private var observers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var started = false
    private var panelVisible = false
    private var calendarModuleVisible = false

    private static let lunarMonths = ["正月", "二月", "三月", "四月", "五月", "六月", "七月", "八月", "九月", "十月", "冬月", "腊月"]
    private static let lunarDayNames = [
        "初一", "初二", "初三", "初四", "初五", "初六", "初七", "初八", "初九", "初十",
        "十一", "十二", "十三", "十四", "十五", "十六", "十七", "十八", "十九", "二十",
        "廿一", "廿二", "廿三", "廿四", "廿五", "廿六", "廿七", "廿八", "廿九", "三十"
    ]
    private static let weekdayNames = ["星期日", "星期一", "星期二", "星期三", "星期四", "星期五", "星期六"]
    private static let weekdayShort = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
    private static let zodiacNames = ["鼠", "牛", "虎", "兔", "龙", "蛇", "马", "羊", "猴", "鸡", "狗", "猪"]
    private static let stems = ["甲", "乙", "丙", "丁", "戊", "己", "庚", "辛", "壬", "癸"]
    private static let branches = ["子", "丑", "寅", "卯", "辰", "巳", "午", "未", "申", "酉", "戌", "亥"]

    // MARK: - Init

    init(provider: HolidayProvider? = nil,
         calendar: Calendar = .current,
         now: @escaping () -> Date = Date.init,
         timeZoneProvider: @escaping () -> TimeZone = { TimeZone.current },
         readGate: @escaping () -> Bool = { false },
         preview: Bool = false) {
        // Production AppDelegate injects the real provider explicitly. A
        // default/preview/test model must never reach the system EventKit
        // transport by accident.
        self.provider = provider ?? HolidayProvider.nonReading()
        self.calendar = calendar
        self.now = now
        self.timeZoneProvider = timeZoneProvider
        self.readGate = readGate
        self.preview = preview
        let date = now()
        let start = calendar.startOfDay(for: date)
        self.today = start
        self.visibleMonth = Self.monthStart(for: date, calendar: calendar)
        self.selectedDate = start
        self.provider.onHolidayDataChanged = { [weak self] in self?.rebuild() }
        rebuild()
    }

    /// Whether the selected-day detail should show the lunar line. The grid and
    /// menu bar already follow the same preference through `rebuild()`.
    var showsLunarInDetail: Bool { Self.showLunar }

    // MARK: - Navigation

    func resetToToday() {
        let date = now()
        today = calendar.startOfDay(for: date)
        visibleMonth = Self.monthStart(for: date, calendar: calendar)
        selectedDate = today
        rebuild()
        refreshCalendarHolidays()
    }

    func goToPreviousMonth() { changeMonth(by: -1) }
    func goToNextMonth() { changeMonth(by: 1) }

    /// Year paging is a single 12-month step through the same code path, so the
    /// day-of-month keeps its clamped value and only one rebuild runs.
    func goToPreviousYear() { changeMonth(by: -12) }
    func goToNextYear() { changeMonth(by: 12) }

    /// Shows a specific month (used by keyboard navigation and tests).
    func showMonth(_ date: Date) {
        visibleMonth = Self.monthStart(for: date, calendar: calendar)
        rebuild()
    }

    /// Weekday header labels in display order, following the week-start preference.
    var orderedWeekdaySymbols: [String] {
        let symbols = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        let first = Self.weekStartsOnMonday ? 1 : 0
        return (0..<7).map { symbols[($0 + first) % 7] }
    }

    /// True where the header column is Saturday or Sunday, in display order.
    var orderedWeekdayIsWeekend: [Bool] {
        let weekend = [true, false, false, false, false, false, true]   // 周日…周六
        let first = Self.weekStartsOnMonday ? 1 : 0
        return (0..<7).map { weekend[($0 + first) % 7] }
    }

    private func changeMonth(by value: Int) {
        guard let next = calendar.date(byAdding: .month, value: value, to: visibleMonth) else { return }
        visibleMonth = Self.monthStart(for: next, calendar: calendar)
        if !calendar.isDate(selectedDate, equalTo: visibleMonth, toGranularity: .month) {
            // Keep the same day-of-month when possible, clamped to month length.
            let day = calendar.component(.day, from: selectedDate)
            let length = calendar.range(of: .day, in: .month, for: visibleMonth)?.count ?? 28
            var components = calendar.dateComponents([.year, .month], from: visibleMonth)
            components.day = min(day, length)
            selectedDate = calendar.startOfDay(for: calendar.date(from: components) ?? visibleMonth)
        }
        rebuild()
        refreshCalendarHolidays()
    }

    func select(_ date: Date) {
        let start = calendar.startOfDay(for: date)
        selectedDate = start
        if !calendar.isDate(start, equalTo: visibleMonth, toGranularity: .month) {
            visibleMonth = Self.monthStart(for: start, calendar: calendar)
        }
        rebuild()
        refreshCalendarHolidays()
    }

    func moveSelection(byDays days: Int) {
        guard let next = calendar.date(byAdding: .day, value: days, to: selectedDate) else { return }
        select(next)
    }

    func moveSelection(byMonths months: Int) {
        changeMonth(by: months)
    }

    // MARK: - Rebuild

    func rebuild() {
        var display = calendar
        display.firstWeekday = Self.weekStartsOnMonday ? 2 : 1

        let monthStart = Self.monthStart(for: visibleMonth, calendar: display)
        let daysInMonth = display.range(of: .day, in: .month, for: monthStart)?.count ?? 30
        let weekdayOfFirst = display.component(.weekday, from: monthStart)
        let offset = (weekdayOfFirst - display.firstWeekday + 7) % 7
        guard let gridStart = display.date(byAdding: .day, value: -offset, to: monthStart) else { return }
        let totalCells = daysInMonth + offset
        let weekCount = max(4, Int(ceil(Double(totalCells) / 7.0)))

        var newWeeks: [Week] = []
        var cursor = gridStart
        for weekIndex in 0..<weekCount {
            var days: [DayCell] = []
            for _ in 0..<7 {
                days.append(makeCell(date: cursor, monthStart: monthStart, display: display))
                guard let next = display.date(byAdding: .day, value: 1, to: cursor) else { break }
                cursor = next
            }
            newWeeks.append(Week(id: "week-\(weekIndex)-\(days.first.map { Self.key($0.date, display) } ?? "")", days: days))
        }
        weeks = newWeeks
        detail = makeDetail()
        menuBarText = makeMenuBarText()
        refreshHolidayRangeIfVisible(display: display)
    }

    private func makeCell(date: Date, monthStart: Date, display: Calendar) -> DayCell {
        let dayNumber = display.component(.day, from: date)
        let isCurrentMonth = display.isDate(date, equalTo: monthStart, toGranularity: .month)
        let isToday = display.isDate(date, inSameDayAs: today)
        let isSelected = display.isDate(date, inSameDayAs: selectedDate)
        // Calendar.weekday: 1 = Sunday, 7 = Saturday.
        let weekday = display.component(.weekday, from: date)
        let isWeekend = weekday == 1 || weekday == 7
        let lunar = lunarDate(for: date, calendar: display)

        let solarTerm = provider.solarTerm(on: date, calendar: display)
        let marker = holidayReadAllowed ? provider.marker(on: date) : nil
        var festivalShort: String?
        if holidayReadAllowed, let first = provider.systemFestivals(on: date).first {
            festivalShort = first.title
        }
        let secondLine: String?
        if let festivalShort {
            secondLine = festivalShort
        } else if let solarTerm {
            secondLine = solarTerm
        } else if Self.showLunar {
            secondLine = lunar.dayName
        } else {
            secondLine = nil
        }

        let showsDot = festivalShort != nil || solarTerm != nil || marker != nil
        var accessibility = "\(display.component(.year, from: date))年\(display.component(.month, from: date))月\(dayNumber)日 \(Self.weekdayNames[max(0, min(6, display.component(.weekday, from: date) - 1))])"
        if Self.showLunar { accessibility += "，农历\(lunar.monthDay)" }
        if let solarTerm { accessibility += "，\(solarTerm)" }
        if let festivalShort { accessibility += "，\(festivalShort)" }
        if let marker { accessibility += marker == .holiday ? "，休息日" : "，补班" }
        if isToday { accessibility += "，今天" }
        if !isCurrentMonth { accessibility += "，邻月" }

        return DayCell(
            id: Self.key(date, display),
            date: date,
            dayNumber: dayNumber,
            isCurrentMonth: isCurrentMonth,
            isToday: isToday,
            isSelected: isSelected,
            isWeekend: isWeekend,
            lunar: lunar,
            solarTerm: solarTerm,
            festivalShort: festivalShort,
            secondLine: secondLine,
            badge: marker,
            showsDot: showsDot,
            accessibilityLabel: accessibility
        )
    }

    private func makeDetail() -> Detail {
        let lunar = lunarDate(for: selectedDate, calendar: calendar)
        let isoWeek = Self.isoWeekNumber(for: selectedDate, timeZone: calendar.timeZone)
        let festivals = provider.detailFestivals(on: selectedDate).sorted {
            $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
        let marker = holidayReadAllowed ? provider.marker(on: selectedDate) : nil
        let visibleFestivals = holidayReadAllowed ? festivals : []

        var sourceNote: String?
        switch provider.sourceStatus {
        case .error:
            sourceNote = "系统节日暂不可用"
        default:
            sourceNote = nil
        }

        let year = calendar.component(.year, from: selectedDate)
        let month = calendar.component(.month, from: selectedDate)
        let day = calendar.component(.day, from: selectedDate)
        let summaryDate = String(format: "%04d年%02d月%02d日（第%d周）", year, month, day, isoWeek)
        let lunarSummary = "\(lunar.ganzhi)年（\(lunar.zodiac)）\(lunar.monthDay)"

        return Detail(
            date: selectedDate,
            summaryDate: summaryDate,
            lunarSummary: lunarSummary,
            relative: relativeText(for: selectedDate),
            festivals: visibleFestivals,
            marker: marker,
            sourceNote: sourceNote
        )
    }

    /// Shows the "回到今天" control only when it would change anything.
    var showsTodayButton: Bool {
        !calendar.isDate(selectedDate, inSameDayAs: today)
            || !calendar.isDate(visibleMonth, equalTo: today, toGranularity: .month)
    }

    // MARK: - Read-only panel formatting (no duplicated date logic)

    var selectedGregorianTitle: String {
        let year = calendar.component(.year, from: selectedDate)
        let month = calendar.component(.month, from: selectedDate)
        let day = calendar.component(.day, from: selectedDate)
        return "\(year)年\(month)月\(day)日"
    }

    var selectedWeekdayText: String {
        let index = calendar.component(.weekday, from: selectedDate) - 1
        return Self.weekdayNames[max(0, min(6, index))]
    }

    var selectedISOWeekText: String {
        "第 \(Self.isoWeekNumber(for: selectedDate, timeZone: calendar.timeZone)) 周"
    }

    var selectedLunarSummary: String { detail?.lunarSummary ?? "" }

    private func makeMenuBarText() -> String {
        let month = calendar.component(.month, from: today)
        let day = calendar.component(.day, from: today)
        var text = "\(month)月\(day)日"
        if Self.showWeekday {
            let index = calendar.component(.weekday, from: today) - 1
            text += " " + Self.weekdayShort[max(0, min(6, index))]
        }
        return text
    }

    // MARK: - Lunar

    func lunarDate(for date: Date, calendar: Calendar) -> LunarDate {
        var chinese = Calendar(identifier: .chinese)
        chinese.timeZone = calendar.timeZone
        chinese.locale = Locale(identifier: "zh_CN")
        let components = chinese.dateComponents([.year, .month, .day, .isLeapMonth], from: date)
        let cycleYear = components.year ?? 1
        let lunarYear = cycleYear + 1983
        let month = components.month ?? 1
        let day = components.day ?? 1
        let leap = components.isLeapMonth ?? false
        let offset = ((lunarYear - 1984) % 60 + 60) % 60
        let stem = Self.stems[offset % 10]
        let branch = Self.branches[offset % 12]
        let zodiac = Self.zodiacNames[offset % 12]
        let monthName = Self.lunarMonths[max(0, min(11, month - 1))]
        let dayName = Self.lunarDayNames[max(0, min(29, day - 1))]
        return LunarDate(year: lunarYear, month: month, day: day, isLeapMonth: leap, monthName: monthName, dayName: dayName, zodiac: zodiac, ganzhi: stem + branch)
    }

    private var visibleGridRange: DateInterval? {
        guard let first = weeks.first?.days.first, let last = weeks.last?.days.last,
              let end = calendar.date(byAdding: .day, value: 1, to: last.date) else { return nil }
        return DateInterval(start: calendar.startOfDay(for: first.date), end: end)
    }

    private func refreshHolidayRangeIfVisible(display: Calendar? = nil) {
        guard holidayReadAllowed, panelVisible, calendarModuleVisible,
              let range = visibleGridRange else { return }
        provider.ensureEvents(range: range)
        // The selected day is inside the visible grid when the panel is open;
        // the provider's range cache covers both grid and detail.
    }

    // MARK: - Lifecycle and authorized system-event reads

    var currentTimeZone: TimeZone { calendar.timeZone }
    var isStartedForTest: Bool { started }
    var calendarYear: Int { calendar.component(.year, from: visibleMonth) }
    var monthTitle: String {
        "\(calendar.component(.year, from: visibleMonth))年\(calendar.component(.month, from: visibleMonth))月"
    }

    func start() {
        guard !started else { return }
        started = true
        provider.start()
        observeSystem()
    }

    func stop() {
        started = false
        panelVisible = false
        calendarModuleVisible = false
        provider.stop()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        workspaceObservers.removeAll()
    }

    func setPanelVisibility(panel: Bool, calendarModule: Bool) {
        panelVisible = panel
        calendarModuleVisible = calendarModule
        provider.setPanelVisible(panel && calendarModule)
        if panel && calendarModule {
            refreshHolidayRangeIfVisible()
            refreshCalendarHolidays()
        }
    }

    /// Refresh only the trusted holiday range. Personal calendar events are not
    /// read or displayed in this product slice.
    func refreshCalendarHolidays() {
        guard started, panelVisible, calendarModuleVisible, readGate() else {
            if !readGate() {
                provider.invalidateEvents()
                rebuild()
            }
            return
        }
        refreshHolidayRangeIfVisible()
    }

    // MARK: - System observations

    private func observeSystem() {
        let center = NotificationCenter.default
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [Notification.Name.NSCalendarDayChanged, .NSSystemClockDidChange] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.started else { return }
                    self.handleDayChange()
                }
            })
        }
        observers.append(center.addObserver(forName: .NSSystemTimeZoneDidChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.started else { return }
                self.handleTimeZoneChange()
            }
        })
        workspaceObservers.append(workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.started else { return }
                self.handleTimeZoneChange()
            }
        })
    }

    private func handleDayChange() {
        guard started else { return }
        let newToday = calendar.startOfDay(for: now())
        let wasTodaySelected = calendar.isDate(selectedDate, inSameDayAs: today)
        today = newToday
        if wasTodaySelected {
            selectedDate = newToday
            visibleMonth = Self.monthStart(for: newToday, calendar: calendar)
        } else {
            visibleMonth = Self.monthStart(for: visibleMonth, calendar: calendar)
        }
        rebuild()
        refreshCalendarHolidays()
    }

    private func handleTimeZoneChange() {
        guard started else { return }
        calendar.timeZone = timeZoneProvider()
        handleDayChange()
    }

    /// Wake is a fresh date-boundary/timezone rebuild, not a polling tick.
    func handleWake() {
        handleTimeZoneChange()
    }

    // MARK: - Helpers

    nonisolated static func monthStart(for date: Date, calendar: Calendar) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.startOfDay(for: calendar.date(from: components) ?? date)
    }

    nonisolated static func key(_ date: Date, _ calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    nonisolated static func isoWeekNumber(for date: Date, timeZone: TimeZone) -> Int {
        var iso = Calendar(identifier: .iso8601)
        iso.timeZone = timeZone
        return iso.component(.weekOfYear, from: date)
    }

    func relativeText(for date: Date) -> String {
        if calendar.isDate(date, inSameDayAs: today) { return "今天" }
        let days = calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: date)).day ?? 0
        if days > 0 { return "距今天还有 \(days) 天" }
        return "距今天已过 \(abs(days)) 天"
    }
}
