import AppKit
import Foundation
import XCTest
@testable import Valora

@MainActor
private final class HeldCalendarEvents: CalendarEventProviding {
    var days: [Date] = []
    var maximumInFlight = 0
    private var continuations: [CheckedContinuation<[CalendarEvent], Never>] = []

    func events(on day: Date, calendar: Calendar) async -> [CalendarEvent] {
        days.append(day)
        return await withCheckedContinuation { continuation in
            continuations.append(continuation)
            maximumInFlight = max(maximumInFlight, continuations.count)
        }
    }

    func completeAll() {
        let pending = continuations
        continuations.removeAll()
        pending.forEach { $0.resume(returning: []) }
    }
}

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

    func testStoppedCalendarCannotStartAnotherEventRead() async {
        let provider = HeldCalendarEvents()
        var allowed = false
        let model = CalmonCalendarModel(calendar: calendar, now: { self.date(2, 28) },
                                        eventProvider: provider, readGate: { allowed })
        model.start()
        model.stop()
        allowed = true
        model.refreshEvents()
        try? await Task.sleep(for: .milliseconds(40))
        XCTAssertTrue(provider.days.isEmpty, "stop must reject later refresh work")
        provider.completeAll()
        model.stop()
    }

    func testRapidSelectionDoesNotAccumulateUncancelledEventReads() async {
        let provider = HeldCalendarEvents()
        var allowed = false
        let model = CalmonCalendarModel(calendar: calendar, now: { self.date(2, 28) },
                                        eventProvider: provider, readGate: { allowed })
        model.start()
        allowed = true
        model.setPanelVisibility(panel: true, calendarModule: true)
        model.select(date(3, 1))
        try? await Task.sleep(for: .milliseconds(40))
        model.select(date(3, 2))
        try? await Task.sleep(for: .milliseconds(40))
        XCTAssertLessThanOrEqual(provider.maximumInFlight, 1,
                                 "cancelling a Task must not enqueue another unbounded EventKit query")
        provider.completeAll()
        try? await Task.sleep(for: .milliseconds(40))
        XCTAssertEqual(provider.days.last, calendar.startOfDay(for: date(3, 2)))
        provider.completeAll()
        model.stop()
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

    func testGateRevokedBeforeScheduledReadPreventsProviderCall() async {
        let provider = HeldCalendarEvents()
        var allowed = false
        let model = CalmonCalendarModel(calendar: calendar, now: { self.date(3, 1) },
                                        eventProvider: provider, readGate: { allowed })
        model.start()
        allowed = true
        model.setPanelVisibility(panel: true, calendarModule: true)
        model.refreshEvents()
        allowed = false
        try? await Task.sleep(for: .milliseconds(40))
        XCTAssertTrue(provider.days.isEmpty,
                      "the real read must recheck consent after its scheduled task begins")
        provider.completeAll()
        model.stop()
    }

    func testNativeCalendarStatusItemUpdatesOnTheFirstDayChange() async throws {
        var now = date(3, 1)
        let model = CalmonCalendarModel(calendar: calendar, now: { now },
                                        eventProvider: PreviewCalendarEvents(),
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

    func testHiddenPanelAndHiddenModuleDoNotReadUntilOpened() async {
        let provider = HeldCalendarEvents()
        var allowed = true
        let model = CalmonCalendarModel(calendar: calendar, now: { self.date(3, 1) },
                                        eventProvider: provider, readGate: { allowed })
        model.start()
        model.setPanelVisibility(panel: false, calendarModule: true)
        model.select(date(3, 2))
        try? await Task.sleep(for: .milliseconds(40))
        XCTAssertTrue(provider.days.isEmpty)
        model.setPanelVisibility(panel: true, calendarModule: false)
        model.refreshEvents()
        try? await Task.sleep(for: .milliseconds(40))
        XCTAssertTrue(provider.days.isEmpty)
        model.setPanelVisibility(panel: true, calendarModule: true)
        try? await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(provider.days.count, 1)
        provider.completeAll()
        model.stop()
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
                                        eventProvider: PreviewCalendarEvents(), readGate: { false })
        model.start()
        model.setPanelVisibility(panel: true, calendarModule: true)
        XCTAssertTrue(model.events.isEmpty)
        XCTAssertEqual(model.eventState, .notAvailable)
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
