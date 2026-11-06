import AppKit
import Foundation
import XCTest
@testable import Valora


@MainActor
final class IndependentCalendarLifecycleTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    private func date(_ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2021, month: month, day: day, hour: 12))!
    }





    func testFollowingTodayAcrossMonthBoundaryMovesVisibleMonth() async {
        var now = date(2, 28)
        let model = CalmonCalendarModel(calendar: calendar, now: { now })
        model.start()
        now = date(3, 1)
        NotificationCenter.default.post(name: .NSCalendarDayChanged, object: nil)
        try? await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(calendar.component(.month, from: model.visibleMonth), 3)
        XCTAssertTrue(model.weeks.flatMap(\.days).contains { $0.isCurrentMonth && $0.isToday && $0.isSelected })
        model.stop()
    }



    func testNativeCalendarStatusItemUpdatesOnTheFirstDayChange() async throws {
        var now = date(3, 1)
        let model = CalmonCalendarModel(calendar: calendar, now: { now },
                                        readGate: { false }, preview: true)
        let monitor = SystemMonitor()
        monitor.verificationApply(snapshot: SystemMonitor.Snapshot())
        let controller = MenuBarModuleController(monitor: monitor, calendar: model,
                                                 onSettings: {}, onQuit: {})
        controller.start(startSampling: false)
        defer {
            controller.stop()
            model.stop()
        }
        XCTAssertEqual(controller.calendarStatusText, "3月1日 周一")
        now = date(3, 2)
        NotificationCenter.default.post(name: .NSCalendarDayChanged, object: nil)
        try? await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(controller.calendarStatusText, "3月2日 周二",
                       "the visible native date must update immediately, not one publication late")
    }




    func testStoppedModelRemovesDateObserversAndRejectsOldCallbacks() async {
        var now = date(3, 1)
        let model = CalmonCalendarModel(calendar: calendar, now: { now })
        model.start()
        let before = model.menuBarText
        model.stop()
        now = date(3, 2)
        NotificationCenter.default.post(name: .NSCalendarDayChanged, object: nil)
        try? await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(model.menuBarText, before)
    }

    func testUnauthorizedBaseCalendarStillBrowses() {
        let model = CalmonCalendarModel(calendar: calendar, now: { self.date(3, 1) },
                                        readGate: { false })
        model.start()
        model.setPanelVisibility(panel: true, calendarModule: true)
        XCTAssertEqual(model.weeks.flatMap(\.days).filter(\.isCurrentMonth).count, 31)
        model.stop()
    }

    func testTimeZoneChangeUpdatesCalendarTimeZone() async {
        var zone = TimeZone(secondsFromGMT: 0)!
        let model = CalmonCalendarModel(calendar: calendar, now: { self.date(3, 1) },
                                        timeZoneProvider: { zone })
        model.start()
        zone = TimeZone(secondsFromGMT: 3600)!
        NotificationCenter.default.post(name: .NSSystemTimeZoneDidChange, object: nil)
        try? await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(model.currentTimeZone.secondsFromGMT(), 3600)
        model.stop()
    }
}
