import Foundation
import XCTest
@testable import Valora

@MainActor
final class CalendarHolidayParityTests: XCTestCase {
    private func date(_ day: Int, hour: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        return calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    private func calendar() -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        return c
    }

    private func record(_ title: String, from: Int, to: Int, id: String = UUID().uuidString) -> HolidayEventRecord {
        HolidayEventRecord(id: id, title: title, start: date(from), end: date(to),
                           calendarID: "holiday-source", calendarTitle: "中国节假日")
    }

    func testFixtureDerivesNationalDayRestMakeupAndDoubleNinth() {
        let cal = calendar()
        let range = DateInterval(start: date(1).addingTimeInterval(-20 * 86_400), end: date(31).addingTimeInterval(20 * 86_400))
        let records = [
            record("国庆节", from: 1, to: 2, id: "national"),
            record("国庆节（休）", from: 1, to: 8, id: "rest"),
            record("国庆节（班）", from: 10, to: 11, id: "work"),
            record("重阳节", from: 18, to: 19, id: "double-ninth")
        ]
        let mapped = HolidayProvider.map(records: records, range: range, calendar: cal)
        let oct1 = HolidayProvider.dayKey(date(1), calendar: cal)
        let oct10 = HolidayProvider.dayKey(date(10), calendar: cal)
        let oct18 = HolidayProvider.dayKey(date(18), calendar: cal)
        XCTAssertEqual(mapped.markers[oct1], HolidayProvider.Marker.holiday)
        XCTAssertEqual(mapped.festivals[oct1]?.first?.title, "国庆节")
        XCTAssertEqual(mapped.markers[oct10], HolidayProvider.Marker.workday)
        XCTAssertEqual(mapped.festivals[oct18]?.first?.title, "重阳节")
        XCTAssertTrue(mapped.arrangements[oct1]?.contains { $0.marker == .holiday && $0.title == "国庆节（休）" } == true)
    }

    func testNormalAndArrangementCoexistOnceAndExactDuplicatesCollapse() {
        let cal = calendar()
        let range = DateInterval(start: date(1).addingTimeInterval(-20 * 86_400), end: date(31).addingTimeInterval(20 * 86_400))
        let records = [
            record("国庆节", from: 1, to: 2, id: "normal-1"),
            record("国庆节", from: 1, to: 2, id: "normal-2"),
            record("国庆节（休）", from: 1, to: 8, id: "arr-1"),
            record("国庆节（休）", from: 1, to: 8, id: "arr-2")
        ]
        let mapped = HolidayProvider.map(records: records, range: range, calendar: cal)
        let key = HolidayProvider.dayKey(date(1), calendar: cal)
        let provider = HolidayProvider(calendar: cal, authorizationCheck: { true })
        provider.applyFixture(records: records, range: range)
        let detail = provider.detailFestivals(on: date(1))
        XCTAssertEqual(detail.filter { $0.title == "国庆节" }.count, 1)
        XCTAssertEqual(detail.filter { $0.title == "国庆节（休）" }.count, 1)
        XCTAssertEqual(detail.filter { $0.marker == .holiday }.count, 1)
        XCTAssertEqual(mapped.markers[key], HolidayProvider.Marker.holiday)
    }

    func testCrossMonthRangeDoesNotRelocateFestival() {
        let cal = calendar()
        let september = DateInterval(start: date(1).addingTimeInterval(-30 * 86_400),
                                    end: date(1))
        let october = DateInterval(start: date(1), end: date(31))
        let records = [record("国庆节", from: 1, to: 2)]
        let first = HolidayProvider.map(records: records, range: september, calendar: cal)
        XCTAssertNil(first.festivals[HolidayProvider.dayKey(date(1), calendar: cal)],
                     "a name whose real start is outside the requested range must not move into it")
        let second = HolidayProvider.map(records: records, range: october, calendar: cal)
        XCTAssertEqual(second.festivals[HolidayProvider.dayKey(date(1), calendar: cal)]?.first?.title, "国庆节")
    }

    func testNonHolidayCalendarCandidateAndFixtureMetadata() {
        XCTAssertTrue(HolidayProvider.holidayCalendarCandidate(title: "中国节假日", isReadOnly: true))
        XCTAssertFalse(HolidayProvider.holidayCalendarCandidate(title: "中国节假日", isReadOnly: false))
        XCTAssertFalse(HolidayProvider.holidayCalendarCandidate(title: "家庭日历", isReadOnly: true))
        let provider = HolidayProvider(calendar: calendar(), authorizationCheck: { true })
        provider.applyFixture(records: [record("重阳节", from: 18, to: 19)], range: DateInterval(start: date(1).addingTimeInterval(-20 * 86_400), end: date(31).addingTimeInterval(20 * 86_400)),
                              title: "Fixture 中国节假日")
        XCTAssertEqual(provider.selectedCalendarID, "fixture-holiday")
        XCTAssertEqual(provider.selectedCalendarTitle, "Fixture 中国节假日")
        XCTAssertEqual(provider.sourceStatus, HolidayProvider.SourceStatus.active("Fixture 中国节假日"))
        XCTAssertEqual(provider.detailFestivals(on: date(18)).first?.sourceTitle, "中国节假日")
    }

    func testGridAndDetailUseFixtureWithoutHardcodedHoliday() {
        let cal = calendar()
        let range = DateInterval(start: date(1).addingTimeInterval(-20 * 86_400), end: date(31).addingTimeInterval(20 * 86_400))
        let provider = HolidayProvider(calendar: cal, authorizationCheck: { true })
        provider.applyFixture(records: [
            record("国庆节", from: 1, to: 2), record("国庆节（休）", from: 1, to: 8),
            record("国庆节（班）", from: 10, to: 11), record("重阳节", from: 18, to: 19)
        ], range: range)
        let model = CalmonCalendarModel(
            provider: provider,
            calendar: cal,
            now: { self.date(1, hour: 12) },
            timeZoneProvider: { cal.timeZone },
            readGate: { true }, preview: true)
        model.showMonth(date(1))
        model.select(date(1))
        let oct1 = model.weeks.flatMap(\.days).first { cal.isDate($0.date, inSameDayAs: date(1)) }
        let oct10 = model.weeks.flatMap(\.days).first { cal.isDate($0.date, inSameDayAs: date(10)) }
        let oct18 = model.weeks.flatMap(\.days).first { cal.isDate($0.date, inSameDayAs: date(18)) }
        XCTAssertEqual(oct1?.festivalShort, "国庆节")
        XCTAssertEqual(oct1?.badge, HolidayProvider.Marker.holiday)
        XCTAssertEqual(oct1?.showsDot, true)
        XCTAssertEqual(oct10?.badge, HolidayProvider.Marker.workday)
        XCTAssertNil(oct10?.festivalShort)
        XCTAssertEqual(oct18?.festivalShort, "重阳节")
        let detail = model.detail
        XCTAssertEqual(detail?.festivals.filter { $0.title == "国庆节" }.count, 1)
        XCTAssertEqual(detail?.festivals.filter { $0.title == "国庆节（休）" }.count, 1)
        XCTAssertEqual(detail?.marker, HolidayProvider.Marker.holiday)
    }

    func testGateOffClearsHolidayDisplayAndStopsReaders() async {
        let cal = calendar()
        var allowed = true
        let provider = HolidayProvider(calendar: cal, authorizationCheck: { allowed })
        provider.applyFixture(records: [record("国庆节", from: 1, to: 2), record("国庆节（休）", from: 1, to: 2)],
                              range: DateInterval(start: date(1).addingTimeInterval(-20 * 86_400),
                                                  end: date(31).addingTimeInterval(20 * 86_400)))
        let model = CalmonCalendarModel(provider: provider, calendar: cal, now: { self.date(1, hour: 8) },
                                        readGate: { allowed }, preview: true)
        model.start()
        model.select(date(1))
        model.setPanelVisibility(panel: true, calendarModule: true)
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(model.weeks.flatMap(\.days).first { cal.isDate($0.date, inSameDayAs: self.date(1)) }?.badge,
                       HolidayProvider.Marker.holiday)
        allowed = false
        model.refreshCalendarHolidays()
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertNil(model.weeks.flatMap(\.days).first { cal.isDate($0.date, inSameDayAs: self.date(1)) }?.badge,
                     "revoking the read gate must not leave cached holiday badges visible")
        XCTAssertTrue(model.detail?.festivals.isEmpty ?? false)
        model.stop()
    }



}


@MainActor
extension CalendarHolidayParityTests {
    func testHolidayTransportIsLazyAndFixtureNeverCreatesRealStore() async {
        let cal = calendar()
        let range = DateInterval(start: date(1).addingTimeInterval(-30 * 86_400),
                                 end: date(31).addingTimeInterval(30 * 86_400))
        let records = [record("国庆节", from: 1, to: 2)]
        let fixture = FixtureHolidayTransport(calendars: [
            HolidayCalendarDescriptor(id: "fixture-calendar", title: "中国节假日",
                                      sourceTitle: "Fixture", isReadOnly: true)
        ], records: records)
        var factoryCount = 0
        let provider = HolidayProvider(calendar: cal, authorizationCheck: { true }, transportFactory: {
            factoryCount += 1
            return fixture
        })
        provider.ensureEvents(range: range)
        XCTAssertEqual(factoryCount, 0, "inactive/unstarted provider must not create transport")
        provider.start()
        provider.ensureEvents(range: range)
        XCTAssertEqual(factoryCount, 0, "started but hidden provider must not create transport")
        provider.setPanelVisible(true)
        provider.ensureEvents(range: range)
        try? await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(factoryCount, 1)
        XCTAssertEqual(fixture.calendarReadCount, 1)
        XCTAssertEqual(fixture.eventReadCount, 1)
        XCTAssertEqual(provider.selectedCalendarID, "fixture-calendar")
        XCTAssertEqual(provider.systemFestivals(on: date(1)).first?.title, "国庆节")

        provider.setPanelVisible(false)
        provider.ensureEvents(range: range)
        provider.refreshSource()
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(fixture.calendarReadCount, 1, "hidden provider must not read metadata")
        XCTAssertEqual(fixture.eventReadCount, 1, "hidden provider must not read events")
        provider.stop()
        provider.ensureEvents(range: range)
        XCTAssertEqual(factoryCount, 1, "stop must not create a replacement transport")
    }

    func testHideBeforeQueuedTransportTaskRunsPerformsNoReadAndReopensCleanly() async {
        let cal = calendar()
        let gate = GatedHolidayTransport()
        let provider = HolidayProvider(calendar: cal, authorizationCheck: { true }, transportFactory: { gate })
        provider.start()
        provider.setPanelVisible(true)
        let range = DateInterval(start: date(1), end: date(31))
        provider.ensureEvents(range: range)
        provider.setPanelVisible(false)
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(gate.readCount, 0,
                       "hide before the queued Task executes must create zero transport reads")
        XCTAssertEqual(provider.systemFestivals(on: date(1)).count, 0)

        provider.setPanelVisible(true)
        provider.ensureEvents(range: range)
        for _ in 0..<20 where gate.readCount == 0 { await Task.yield() }
        XCTAssertEqual(gate.readCount, 1, "reopening should allow a fresh transport read")
        gate.resumeNext(with: [record("国庆节", from: 1, to: 2)])
        try? await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(provider.systemFestivals(on: date(1)).first?.title, "国庆节")
        provider.stop()
    }

    func testUnauthorizedProviderNeverCreatesTransport() {
        let cal = calendar()
        var factoryCount = 0
        let provider = HolidayProvider(calendar: cal, authorizationCheck: { false }, transportFactory: {
            factoryCount += 1
            return FixtureHolidayTransport(calendars: [], records: [])
        })
        provider.start()
        provider.setPanelVisible(true)
        provider.ensureEvents(range: DateInterval(start: date(1), end: date(31)))
        provider.refreshSource()
        XCTAssertEqual(factoryCount, 0)
    }

    func testRapidRangesCoalesceAndLateResultIsRejectedAfterHide() async {
        let cal = calendar()
        let gate = GatedHolidayTransport()
        let provider = HolidayProvider(calendar: cal, authorizationCheck: { true }, transportFactory: { gate })
        provider.start()
        provider.setPanelVisible(true)
        let october = DateInterval(start: date(1), end: date(31))
        let november = DateInterval(start: date(31), end: date(31).addingTimeInterval(30 * 86_400))
        provider.ensureEvents(range: october)
        for _ in 0..<20 where gate.readCount == 0 { await Task.yield() }
        XCTAssertEqual(gate.readCount, 1)
        provider.ensureEvents(range: november)
        await Task.yield()
        XCTAssertEqual(gate.readCount, 1, "a second range while one request is in flight must be coalesced")
        gate.resumeNext(with: [record("国庆节", from: 1, to: 2)])
        for _ in 0..<20 where gate.readCount < 2 { await Task.yield() }
        XCTAssertEqual(gate.readCount, 2, "the latest range should start after the old result is discarded")
        provider.setPanelVisible(false)
        gate.resumeNext(with: [record("国庆节", from: 1, to: 2)])
        try? await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(provider.systemFestivals(on: date(1)).count, 0,
                       "a late result after hide must not repopulate holiday data")
        provider.stop()
    }
}

@MainActor
private final class GatedHolidayTransport: HolidayEventTransport {
    let observesStoreChanges = false
    private(set) var readCount = 0
    private var continuations: [CheckedContinuation<[HolidayEventRecord]?, Never>] = []

    func holidayCalendars() -> [HolidayCalendarDescriptor] {
        [HolidayCalendarDescriptor(id: "fixture-calendar", title: "中国节假日",
                                   sourceTitle: "Fixture", isReadOnly: true)]
    }

    func events(calendarID: String, range: DateInterval) async -> [HolidayEventRecord]? {
        readCount += 1
        return await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func resumeNext(with records: [HolidayEventRecord]?) {
        guard !continuations.isEmpty else { return }
        continuations.removeFirst().resume(returning: records)
    }
}
