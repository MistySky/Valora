// Derived from MistySky/Calmon commit 72235116e1420fa081e8f694991a32809f81498d,
// CalMon/Calendar/HolidayProvider.swift. Valora keeps its own single
// authorization gate; this provider never requests permission and never reads
// events unless the model's gate and the injected authorization check pass.
import AppKit
import EventKit
import Foundation
import Observation

/// A UI-safe record used by the pure holiday mapping and injected fixtures.
struct HolidayEventRecord: Sendable, Equatable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let calendarID: String?
    let calendarTitle: String?
}

/// UI-safe source metadata used by both the real EventKit transport and the
/// injected fixture. A real EKEventStore is never needed to render/test this.
struct HolidayCalendarDescriptor: Sendable, Equatable {
    let id: String
    let title: String
    let sourceTitle: String
    let isReadOnly: Bool
}

@MainActor
protocol HolidayEventTransport: AnyObject {
    var observesStoreChanges: Bool { get }
    func holidayCalendars() -> [HolidayCalendarDescriptor]
    func events(calendarID: String, range: DateInterval) async -> [HolidayEventRecord]?
}

/// The only owner of a real EKEventStore. The provider asks the factory for
/// this transport lazily, only after start + visible panel + authorization.
@MainActor
final class EventKitHolidayTransport: HolidayEventTransport {
    nonisolated(unsafe) private let store = EKEventStore()
    private let queue = DispatchQueue(label: "com.wangqing.valora.calendar.holiday.real", qos: .utility)
    var observesStoreChanges: Bool { true }

    func holidayCalendars() -> [HolidayCalendarDescriptor] {
        store.calendars(for: .event).map { calendar in
            HolidayCalendarDescriptor(
                id: calendar.calendarIdentifier, title: calendar.title,
                sourceTitle: calendar.source?.title ?? "",
                isReadOnly: calendar.type == .subscription || calendar.isImmutable
                    || !calendar.allowsContentModifications)
        }
    }

    func events(calendarID: String, range: DateInterval) async -> [HolidayEventRecord]? {
        nonisolated(unsafe) let store = self.store
        return await withCheckedContinuation { continuation in
            queue.async {
                guard let calendar = store.calendars(for: .event)
                    .first(where: { $0.calendarIdentifier == calendarID }) else {
                    continuation.resume(returning: nil)
                    return
                }
                let predicate = store.predicateForEvents(withStart: range.start, end: range.end,
                                                         calendars: [calendar])
                let records = store.events(matching: predicate).map { event in
                    HolidayEventRecord(id: event.eventIdentifier ?? UUID().uuidString,
                                       title: event.title ?? "", start: event.startDate,
                                       end: event.endDate, calendarID: calendar.calendarIdentifier,
                                       calendarTitle: calendar.title)
                }
                continuation.resume(returning: records)
            }
        }
    }
}

/// QA transport: records are supplied by the caller and both metadata/event
/// read counters are observable. It never constructs EKEventStore.
@MainActor
final class FixtureHolidayTransport: HolidayEventTransport {
    let calendars: [HolidayCalendarDescriptor]
    let records: [HolidayEventRecord]
    private(set) var calendarReadCount = 0
    private(set) var eventReadCount = 0
    let observesStoreChanges = false

    init(calendars: [HolidayCalendarDescriptor], records: [HolidayEventRecord]) {
        self.calendars = calendars
        self.records = records
    }

    func holidayCalendars() -> [HolidayCalendarDescriptor] {
        calendarReadCount += 1
        return calendars
    }

    func events(calendarID: String, range: DateInterval) async -> [HolidayEventRecord]? {
        eventReadCount += 1
        return records
    }
}

/// Calmon holiday-source provider, restricted to the existing Valora permission
/// flow. It discovers a read-only China holiday calendar from public metadata,
/// fetches only the visible grid range, and maps normal festival rows plus
/// explicit （休）/（班） arrangement rows. No holiday is inferred from a
/// weekend or hard-coded date.
@MainActor
@Observable
final class HolidayProvider {
    enum Marker: String, Equatable, Sendable {
        case holiday
        case workday
    }

    struct Festival: Identifiable, Equatable, Sendable {
        var id: String
        var title: String
        var sourceTitle: String?
        var marker: Marker? = nil
    }

    enum SourceStatus: Equatable, Sendable {
        case inactive
        case active(String)
        case error(String)
    }

    private struct SolarTermFile: Decodable {
        struct Term: Decodable { let name: String; let date: String }
        let year: Int
        let source: String?
        let sourceURL: String?
        let terms: [Term]
    }

    private(set) var solarTermYears: [Int] = []
    @ObservationIgnored private var solarTermByKey: [String: String] = [:]
    private(set) var revision = 0
    private(set) var sourceStatus: SourceStatus = .inactive
    private(set) var selectedCalendarID: String?
    private(set) var selectedCalendarTitle: String?
    var holidayCalendarTitle: String? { selectedCalendarTitle }
    var hasHolidayCalendar: Bool { selectedCalendarID != nil }

    private var eventsByKey: [String: [Festival]] = [:]
    private var arrangementsByKey: [String: [Festival]] = [:]
    private var markersByKey: [String: Marker] = [:]
    private var loadedRange: DateInterval?
    private var generation: UInt64 = 0
    private var fetchInFlight = false
    private var pendingRange: DateInterval?
    private var discoveryAttempted = false
    private var observer: NSObjectProtocol?
    private let calendar: Calendar
    let authorizationCheck: () -> Bool
    private let transportFactory: @MainActor () -> HolidayEventTransport?
    private var transport: HolidayEventTransport?
    private var fixtureActive = false
    private var started = false
    private var panelVisible = false

    /// Called on the main actor after a fixture or fetched range is published.
    var onHolidayDataChanged: (() -> Void)?

    /// A provider that never creates a real transport; preview/audit paths use
    /// this instead of the system status so QA cannot touch EventKit/Contacts.
    static func nonReading() -> HolidayProvider {
        HolidayProvider(authorizationCheck: { false }, transportFactory: { nil })
    }

    init(calendar: Calendar = .current,
         authorizationCheck: @escaping () -> Bool = { HolidayProvider.systemAuthorized() },
         transportFactory: @escaping @MainActor () -> HolidayEventTransport? = { nil }) {
        self.calendar = calendar
        self.authorizationCheck = authorizationCheck
        self.transportFactory = transportFactory
        loadSolarTerms()
    }

    private func loadSolarTerms() {
        for year in 2025...2027 {
            guard let file: SolarTermFile = Self.decodeResource("\(year)", subdirectory: "SolarTerms") else { continue }
            solarTermYears.append(file.year)
            for term in file.terms { solarTermByKey[term.date] = term.name }
        }
        solarTermYears.sort()
        revision += 1
    }

    private static func decodeResource<T: Decodable>(_ name: String, subdirectory: String) -> T? {
        var candidates: [URL?] = [
            Bundle.main.url(forResource: name, withExtension: "json", subdirectory: subdirectory),
            Bundle.main.url(forResource: name, withExtension: "json"),
            Bundle.main.resourceURL?.appendingPathComponent("\(subdirectory)/\(name).json")
        ]
        #if DEBUG
        // SwiftPM tests/debug runs do not have the app resource copy.
        candidates.append(URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/\(subdirectory)/\(name).json"))
        #endif
        for case let url? in candidates {
            if let data = try? Data(contentsOf: url), let value = try? JSONDecoder().decode(T.self, from: data) {
                return value
            }
        }
        return nil
    }

    func solarTerm(on date: Date) -> String? {
        solarTerm(on: date, calendar: calendar)
    }

    func solarTerm(on date: Date, calendar: Calendar) -> String? {
        solarTermByKey[Self.dayKey(date, calendar: calendar)]
    }

    nonisolated static func systemAuthorized() -> Bool {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess, .authorized: return true
        default: return false
        }
    }

    /// Called when the calendar panel becomes visible or the read gate changes.
    /// No request is made; an unavailable/unauthorized source simply stays empty.
    func refreshSource() {
        guard started, panelVisible, authorizationCheck() else {
            invalidateEvents()
            sourceStatus = .inactive
            return
        }
        guard !fixtureActive else { return }
        guard !discoveryAttempted else { return }
        discoveryAttempted = true
        let transport = ensureTransport()
        guard let transport else { return }
        let calendars = transport.holidayCalendars()
        let matched = calendars.filter {
            Self.holidayCalendarCandidate(title: $0.title, sourceTitle: $0.sourceTitle,
                                         isReadOnly: $0.isReadOnly)
        }
        guard let chosen = matched.first(where: { $0.id == selectedCalendarID }) ?? matched.first else {
            selectedCalendarID = nil
            selectedCalendarTitle = nil
            sourceStatus = .inactive
            invalidateEvents()
            onHolidayDataChanged?()
            return
        }
        selectedCalendarID = chosen.id
        selectedCalendarTitle = chosen.title
        sourceStatus = .active(chosen.title)
        loadedRange = nil
    }

    /// Ensures the visible grid + selected-day range is loaded. Only the current
    /// range is kept; no all-history/all-subscription read occurs.
    func ensureEvents(range: DateInterval) {
        guard started, panelVisible, authorizationCheck() else {
            invalidateEvents()
            sourceStatus = .inactive
            return
        }
        if fixtureActive {
            // Fixture data is entirely local; never fall back to a real store.
            return
        }
        if selectedCalendarID == nil { refreshSource() }
        guard let calendarID = selectedCalendarID else { return }
        if let loadedRange, loadedRange.start <= range.start, loadedRange.end >= range.end {
            return
        }
        loadEvents(range: range, calendarID: calendarID)
    }

    private func loadEvents(range: DateInterval, calendarID: String) {
        guard started, panelVisible, authorizationCheck(), !fixtureActive else { return }
        guard let transport = ensureTransport() else { return }
        generation &+= 1
        let requestedGeneration = generation
        if fetchInFlight {
            pendingRange = range
            return
        }
        fetchInFlight = true
        Task { @MainActor [weak self, transport] in
            guard let self else { return }
            // Re-check at the actual transport execution boundary, not only in
            // the caller that queued the Task. A hide/stop/revoke between these
            // two points must perform zero transport reads.
            guard self.started, self.panelVisible, self.authorizationCheck(),
                  !self.fixtureActive, requestedGeneration == self.generation,
                  self.selectedCalendarID == calendarID else {
                self.rejectBeforeTransport(generation: requestedGeneration,
                                           calendarID: calendarID)
                return
            }
            let records = await transport.events(calendarID: calendarID, range: range)
            let mapped = records.map { Self.map(records: $0, range: range, calendar: self.calendar) }
            self.finishFetch(generation: requestedGeneration, range: range,
                             calendarID: calendarID, title: self.selectedCalendarTitle ?? "",
                             records: mapped)
        }
    }

    /// Release the in-flight latch when a queued Task is rejected before it
    /// touches transport. If the panel is still active and a newer range was
    /// queued, start exactly that latest range; otherwise leave for a later open.
    private func rejectBeforeTransport(generation requestedGeneration: UInt64, calendarID: String) {
        fetchInFlight = false
        guard started, panelVisible, authorizationCheck(), !fixtureActive,
              let pending = pendingRange, let selected = selectedCalendarID else { return }
        pendingRange = nil
        loadEvents(range: pending, calendarID: selected)
    }

    private func finishFetch(generation requestedGeneration: UInt64, range: DateInterval, calendarID: String,
                             title: String,
                             records: (festivals: [String: [Festival]], arrangements: [String: [Festival]], markers: [String: Marker])?) {
        fetchInFlight = false
        guard started, panelVisible, authorizationCheck() else {
            invalidateEvents()
            return
        }
        if requestedGeneration == generation, selectedCalendarID == calendarID, let records {
            eventsByKey = records.festivals
            arrangementsByKey = records.arrangements
            markersByKey = records.markers
            loadedRange = range
            sourceStatus = .active(title)
            revision += 1
            onHolidayDataChanged?()
        } else if selectedCalendarID == calendarID, authorizationCheck() {
            // A newer range is already queued; do not publish this old result.
        } else {
            invalidateEvents()
        }
        if let pending = pendingRange, selectedCalendarID != nil, authorizationCheck() {
            pendingRange = nil
            // A rebuild triggered by this publication can queue the same range;
            // it is already covered by the result that just landed.
            if let covered = loadedRange, covered.start <= pending.start, covered.end >= pending.end {
                return
            }
            loadEvents(range: pending, calendarID: selectedCalendarID!)
        }
    }

    /// Pure injected-fixture path for QA. It uses no EventKit store.
    func applyFixture(records: [HolidayEventRecord], range: DateInterval,
                      title: String = "Fixture 节假日") {
        fixtureActive = true
        selectedCalendarID = "fixture-holiday"
        selectedCalendarTitle = title
        discoveryAttempted = true
        let mapped = Self.map(records: records, range: range, calendar: calendar)
        eventsByKey = mapped.festivals
        arrangementsByKey = mapped.arrangements
        markersByKey = mapped.markers
        loadedRange = range
        sourceStatus = .active(title)
        revision += 1
        onHolidayDataChanged?()
    }

    func clearFixture() {
        fixtureActive = false
        selectedCalendarID = nil
        selectedCalendarTitle = nil
        discoveryAttempted = false
        sourceStatus = .inactive
        invalidateEvents()
    }

    func invalidateEvents() {
        generation &+= 1
        pendingRange = nil
        eventsByKey = [:]
        arrangementsByKey = [:]
        markersByKey = [:]
        loadedRange = nil
        revision += 1
    }

    func setPanelVisible(_ visible: Bool) {
        panelVisible = visible
        if !visible {
            generation &+= 1
            pendingRange = nil
            removeObserver()
            return
        }
        if started, authorizationCheck() {
            _ = ensureTransport()
            observeStoreIfNeeded()
        }
    }

    func stop() {
        started = false
        panelVisible = false
        fixtureActive = false
        removeObserver()
        transport = nil
        discoveryAttempted = false
        selectedCalendarID = nil
        selectedCalendarTitle = nil
        invalidateEvents()
    }

    func start() {
        started = true
        if panelVisible, authorizationCheck() {
            _ = ensureTransport()
            observeStoreIfNeeded()
        }
    }

    private func ensureTransport() -> HolidayEventTransport? {
        if let transport { return transport }
        guard started, panelVisible, authorizationCheck(), !fixtureActive else { return nil }
        let new = transportFactory()
        transport = new
        observeStoreIfNeeded()
        return new
    }

    private func observeStoreIfNeeded() {
        guard observer == nil, transport?.observesStoreChanges == true else { return }
        observer = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.started, self.panelVisible,
                      self.authorizationCheck(), !self.fixtureActive else { return }
                self.discoveryAttempted = false
                self.refreshSource()
            }
        }
    }

    private func removeObserver() {
        observer.map { NotificationCenter.default.removeObserver($0) }
        observer = nil
    }

    // MARK: - Source discovery

    nonisolated static func holidayCalendarCandidate(title: String, sourceTitle: String,
                                                     isReadOnly: Bool) -> Bool {
        let title = normalize(title)
        let source = normalize(sourceTitle)
        let hasHoliday = title.contains("节假日") || title.contains("节日") || title.contains("holiday")
        let chinaSource = title.contains("中国") || title.contains("china") || title.contains("chinese")
            || source.contains("中国") || source.contains("china") || source.contains("chinese")
        return hasHoliday && isReadOnly && chinaSource
    }

    nonisolated static func holidayCalendarCandidate(_ calendar: EKCalendar) -> Bool {
        let readOnly = calendar.type == .subscription || calendar.isImmutable || !calendar.allowsContentModifications
        if holidayCalendarCandidate(title: calendar.title, isReadOnly: readOnly) { return true }
        let title = normalize(calendar.title)
        let source = normalize(calendar.source?.title ?? "")
        let hasHoliday = title.contains("节假日") || title.contains("节日") || title.contains("holiday")
        let chinaSource = source.contains("中国") || source.contains("china") || source.contains("chinese")
        return hasHoliday && readOnly && chinaSource
    }

    nonisolated static func holidayCalendarCandidate(title: String) -> Bool {
        let normalized = normalize(title)
        let hasChina = normalized.contains("中国") || normalized.contains("china")
            || normalized.contains("chinese") || normalized.contains("prc")
        let hasHoliday = normalized.contains("节假日") || normalized.contains("节日") || normalized.contains("holiday")
        return hasChina && hasHoliday
    }

    nonisolated static func holidayCalendarCandidate(title: String, isReadOnly: Bool) -> Bool {
        holidayCalendarCandidate(title: title) && isReadOnly
    }

    // MARK: - Mapping

    nonisolated static func map(records: [HolidayEventRecord], range: DateInterval,
                                calendar: Calendar) -> (festivals: [String: [Festival]], arrangements: [String: [Festival]], markers: [String: Marker]) {
        var festivals: [String: [Festival]] = [:]
        var arrangements: [String: [Festival]] = [:]
        var markers: [String: Marker] = [:]
        for record in records {
            let rawTitle = record.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rawTitle.isEmpty else { continue }
            let marker = marker(forTitle: rawTitle)
            let firstDay = calendar.startOfDay(for: max(record.start, range.start))
            let limit = min(record.end, range.end)
            var day = firstDay
            var guardCount = 0
            while day < limit && guardCount < 400 {
                let key = Self.dayKey(day, calendar: calendar)
                if let marker {
                    markers[key] = marker
                    let arrangement = Festival(
                        id: "\(record.id)-\(key)", title: rawTitle,
                        sourceTitle: record.calendarTitle, marker: marker)
                    var list = arrangements[key] ?? []
                    if !list.contains(where: { normalize($0.title) == normalize(rawTitle) }) {
                        list.append(arrangement)
                    }
                    arrangements[key] = list
                }
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
                guardCount += 1
            }
            if marker == nil {
                let name = festivalTitle(rawTitle)
                guard !name.isEmpty else { continue }
                let trueStart = calendar.startOfDay(for: record.start)
                guard trueStart >= calendar.startOfDay(for: range.start), trueStart < range.end else { continue }
                let key = Self.dayKey(trueStart, calendar: calendar)
                let festival = Festival(
                    id: "\(record.id)-\(key)", title: name,
                    sourceTitle: record.calendarTitle)
                var list = festivals[key] ?? []
                if !list.contains(where: { normalize($0.title) == normalize(name) }) {
                    list.append(festival)
                }
                festivals[key] = list
            }
        }
        return (festivals, arrangements, markers)
    }

    nonisolated static func marker(forTitle title: String) -> Marker? {
        if title.contains("（休）") || title.contains("(休)") { return .holiday }
        if title.contains("（班）") || title.contains("(班)") { return .workday }
        switch normalize(title) {
        case "休", "休息", "放假", "holiday": return .holiday
        case "班", "上班", "补班", "workday": return .workday
        default: return nil
        }
    }

    nonisolated static func festivalTitle(_ title: String) -> String {
        title
            .replacingOccurrences(of: "（休）", with: "")
            .replacingOccurrences(of: "(休)", with: "")
            .replacingOccurrences(of: "（班）", with: "")
            .replacingOccurrences(of: "(班)", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func systemFestivals(on date: Date) -> [Festival] {
        eventsByKey[Self.dayKey(date, calendar: calendar)] ?? []
    }

    func marker(on date: Date) -> Marker? {
        markersByKey[Self.dayKey(date, calendar: calendar)]
    }

    func detailFestivals(on date: Date) -> [Festival] {
        let key = Self.dayKey(date, calendar: calendar)
        var result = eventsByKey[key] ?? []
        for arrangement in arrangementsByKey[key] ?? [] {
            if !result.contains(where: { Self.normalize($0.title) == Self.normalize(arrangement.title) }) {
                result.append(arrangement)
            }
        }
        // Deduplicate exact repeated records without deleting two distinct
        // personal events (this list only contains selected holiday-source rows).
        var seen = Set<String>()
        return result.filter { seen.insert("\(Self.normalize($0.title))|\($0.marker?.rawValue ?? "")").inserted }
    }

    nonisolated static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    nonisolated static func normalize(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
