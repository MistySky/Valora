import AppKit
import Foundation
import XCTest
@testable import Valora

@MainActor
final class CalmonCalendarTests: XCTestCase {
    private func makeCalendar(_ timeZone: String = "UTC") -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: timeZone)!
        c.locale = Locale(identifier: "zh_CN")
        return c
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ timeZone: String = "UTC") -> Date {
        makeCalendar(timeZone).date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    func testDefaultMenuBarFormatAndMondayFirstGrid() {
        let now = date(2026, 10, 25)
        let model = CalmonCalendarModel(calendar: makeCalendar(), now: { now })
        XCTAssertEqual(model.menuBarText, "10月25日 周日")
        XCTAssertEqual(model.orderedWeekdaySymbols.first, "周一")
        XCTAssertEqual(model.orderedWeekdaySymbols.last, "周日")
        XCTAssertEqual(model.weeks.flatMap(\.days).filter(\.isCurrentMonth).count, 31)
        XCTAssertEqual(model.detail?.lunarSummary, "丙午年（马）九月十六")
    }

    func testFourFiveSixWeekMonthsAndYearNavigation() {
        let now = date(2026, 2, 1)
        let model = CalmonCalendarModel(calendar: makeCalendar(), now: { now })
        model.showMonth(date(2026, 2, 1))
        XCTAssertEqual(model.weeks.count, 5)
        model.showMonth(date(2021, 2, 1))
        XCTAssertEqual(model.weeks.count, 4)
        model.showMonth(date(2021, 8, 1))
        XCTAssertEqual(model.weeks.count, 6)
        model.showMonth(date(2026, 9, 15))
        model.goToNextYear()
        XCTAssertEqual(model.calendarYear, 2027)
        model.goToPreviousYear()
        XCTAssertEqual(model.calendarYear, 2026)
    }

    func testLunarAndSolarTermsSurviveMigration() {
        let model = CalmonCalendarModel(calendar: makeCalendar(), now: { self.date(2026, 9, 25) })
        XCTAssertEqual(model.lunarDate(for: date(2026, 9, 25), calendar: makeCalendar()).monthDay, "八月十五")
        XCTAssertEqual(model.lunarDate(for: date(2026, 2, 17), calendar: makeCalendar()).ganzhi, "丙午")
        XCTAssertEqual(model.lunarDate(for: date(2025, 7, 25), calendar: makeCalendar()).isLeapMonth, true)
        XCTAssertEqual(HolidayProvider().solarTerm(on: date(2026, 4, 5)), "清明")
        XCTAssertEqual(HolidayProvider().solarTerm(on: date(2026, 12, 22)), "冬至")
    }

    func testResetToTodayUsesInjectedClock() {
        var now = date(2026, 10, 25)
        let model = CalmonCalendarModel(calendar: makeCalendar(), now: { now })
        model.showMonth(date(2020, 1, 1))
        now = date(2026, 10, 26)
        model.resetToToday()
        XCTAssertTrue(makeCalendar().isDate(model.selectedDate, inSameDayAs: now))
        XCTAssertEqual(model.menuBarText, "10月26日 周一")
    }

    func testMondayAndWeekendFlags() {
        let model = CalmonCalendarModel(calendar: makeCalendar(), now: { self.date(2026, 9, 19) })
        XCTAssertEqual(model.orderedWeekdayIsWeekend,
                       [false, false, false, false, false, true, true])
        XCTAssertTrue(model.weeks.flatMap(\.days).first {
            makeCalendar().isDate($0.date, inSameDayAs: self.date(2026, 9, 19))
        }!.isWeekend)
        XCTAssertFalse(model.weeks.flatMap(\.days).first {
            makeCalendar().isDate($0.date, inSameDayAs: self.date(2026, 9, 18))
        }!.isWeekend)
    }
}
