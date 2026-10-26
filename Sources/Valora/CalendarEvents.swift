import EventKit
import Foundation

/// One read-only system calendar event for the selected day. Only the fields
/// required by the Calmon detail row are carried; no notes, attendees,
/// locations, alarms or other personal content is read.
struct CalendarEvent: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    /// Public calendar provenance; used only to keep the selected holiday
    /// source out of the personal-event detail rows. No notes/attendees are read.
    let calendarIdentifier: String?
    let calendarTitle: String?

    init(id: String, title: String, start: Date, end: Date, isAllDay: Bool,
         calendarIdentifier: String? = nil, calendarTitle: String? = nil) {
        self.id = id; self.title = title; self.start = start; self.end = end
        self.isAllDay = isAllDay
        self.calendarIdentifier = calendarIdentifier; self.calendarTitle = calendarTitle
    }
}

@MainActor
protocol CalendarEventProviding: AnyObject {
    func events(on day: Date, calendar: Calendar) async -> [CalendarEvent]
}

/// Read-only EventKit adapter. It is constructed only for the production
/// calendar model, and the model's panel-visibility + consent gate must pass
/// before `events` is called. The store is created on a utility queue; no write
/// or source discovery is performed.
@MainActor
final class EventKitCalendarEventProvider: CalendarEventProviding {
    private let queue = DispatchQueue(label: "com.wangqing.valora.calendar.events", qos: .utility)

    func events(on day: Date, calendar: Calendar) async -> [CalendarEvent] {
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        return await withCheckedContinuation { continuation in
            queue.async {
                let store = EKEventStore()
                let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
                let values = store.events(matching: predicate).map { event in
                    CalendarEvent(
                        id: event.eventIdentifier ?? UUID().uuidString,
                        title: event.title ?? "未命名日程",
                        start: event.startDate,
                        end: event.endDate,
                        isAllDay: event.isAllDay,
                        calendarIdentifier: event.calendar?.calendarIdentifier,
                        calendarTitle: event.calendar?.title)
                }.sorted {
                    if $0.isAllDay != $1.isAllDay { return $0.isAllDay }
                    return $0.start < $1.start
                }
                continuation.resume(returning: values)
            }
        }
    }
}

/// Isolated sample provider for previews and injected QA. Never contacts
/// EventKit and is always labelled as sample data.
@MainActor
final class PreviewCalendarEvents: CalendarEventProviding {
    func events(on day: Date, calendar: Calendar) async -> [CalendarEvent] {
        let start = calendar.startOfDay(for: day)
        let timedStart = calendar.date(byAdding: .hour, value: 10, to: start) ?? start
        let timedEnd = calendar.date(byAdding: .hour, value: 11, to: start) ?? start
        return [
            CalendarEvent(id: "preview-all-day", title: "样例全天日程",
                          start: start, end: start, isAllDay: true),
            CalendarEvent(id: "preview-timed", title: "样例日程",
                          start: timedStart, end: timedEnd, isAllDay: false)
        ]
    }
}
