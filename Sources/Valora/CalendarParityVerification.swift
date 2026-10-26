import AppKit
import Foundation

/// Native calendar parity QA with injected holiday fixtures. It never requests
/// or reads real EventKit data; the same Calmon calendar/popover view is used.
enum CalendarParityVerification {
    @MainActor static func run(output: String) {
        Task { @MainActor in
            do {
                let directory = URL(fileURLWithPath: output, isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = TimeZone.current
                func date(_ day: Int, hour: Int = 0) -> Date {
                    calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
                }
                func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0) -> Date {
                    calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
                }
                let range = DateInterval(start: date(1).addingTimeInterval(-30 * 86_400),
                                         end: date(31).addingTimeInterval(30 * 86_400))
                func record(_ title: String, _ from: Int, _ to: Int, _ id: String) -> HolidayEventRecord {
                    HolidayEventRecord(id: id, title: title, start: date(from), end: date(to),
                                       calendarID: "fixture-holiday", calendarTitle: "Fixture 中国节假日")
                }
                let provider = HolidayProvider(calendar: calendar, authorizationCheck: { true })
                provider.applyFixture(records: [
                    record("国庆节", 1, 2, "national"),
                    record("国庆节（休）", 1, 8, "rest"),
                    record("国庆节（班）", 10, 11, "work"),
                    record("重阳节", 18, 19, "double-ninth")
                ], range: range, title: "Fixture 中国节假日")

                let model = CalmonCalendarModel(
                    provider: provider, calendar: calendar,
                    now: { date(1, hour: 12) }, timeZoneProvider: { calendar.timeZone },
                    eventProvider: EmptyParityEvents(), readGate: { true }, preview: true)
                let monitor = SystemMonitor()
                let controller = MenuBarModuleController(
                    monitor: monitor, calendar: model, onSettings: {}, onQuit: {})
                controller.start(startSampling: false)
                defer { controller.stop() }
                try? await Task.sleep(nanoseconds: 250_000_000)
                controller.showCalendarPanel()
                try? await Task.sleep(nanoseconds: 550_000_000)

                var checks: [[String: Any]] = []
                var rendered: [String] = []
                @MainActor func capture(_ name: String, day: Int) async throws {
                    model.showMonth(date(1))
                    model.select(date(day))
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    let window = controller.calendarPopoverWindow
                    guard let view = window?.contentView else { return }
                    view.layoutSubtreeIfNeeded()
                    guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
                    view.cacheDisplay(in: view.bounds, to: rep)
                    guard let png = rep.representation(using: .png, properties: [:]) else { return }
                    try png.write(to: directory.appendingPathComponent(name + ".png"))
                    rendered.append(name)
                    let cell = model.weeks.flatMap(\.days).first { calendar.isDate($0.date, inSameDayAs: date(day)) }
                    checks.append([
                        "day": day,
                        "festivalShort": cell?.festivalShort ?? "nil",
                        "badge": cell?.badge.map { $0 == .holiday ? "休" : "班" } ?? "nil",
                        "showsDot": cell?.showsDot ?? false,
                        "weeks": model.weeks.count,
                        "detailFestivals": model.detail?.festivals.map(\.title) ?? [],
                        "detailMarkers": model.detail?.festivals.compactMap { $0.marker.map { $0 == .holiday ? "休" : "班" } } ?? [],
                        "detailMarker": model.detail?.marker.map { $0 == .holiday ? "休" : "班" } ?? "nil",
                        "source": provider.selectedCalendarTitle ?? "nil"
                    ])
                }
                try await capture("calendar-2026-10-01-national-day", day: 1)
                try await capture("calendar-2026-10-10-makeup-workday", day: 10)
                try await capture("calendar-2026-10-18-double-ninth", day: 18)

                @MainActor func captureMonth(_ name: String, month: Date, day: Int) async throws {
                    if !controller.isCalendarPanelShown {
                        controller.showCalendarPanel()
                        try? await Task.sleep(nanoseconds: 250_000_000)
                    }
                    model.showMonth(month)
                    model.select(month)
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    guard let view = controller.calendarPopoverWindow?.contentView else { return }
                    view.layoutSubtreeIfNeeded()
                    guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
                    view.cacheDisplay(in: view.bounds, to: rep)
                    guard let png = rep.representation(using: .png, properties: [:]) else { return }
                    try png.write(to: directory.appendingPathComponent(name + ".png"))
                    rendered.append(name)
                    checks.append(["view": name, "weeks": model.weeks.count,
                                   "width": Double(view.bounds.width)])
                }
                try await captureMonth("calendar-2027-02-four-weeks", month: date(2027, 2, 1), day: 1)
                try await captureMonth("calendar-2026-03-six-weeks", month: date(2026, 3, 1), day: 1)
                checks.append(["calendarContentWidth": Double(controller.calendarPopoverWindow?.contentView?.bounds.width ?? 0)])
                let result: [String: Any] = [
                    "checks": checks,
                    "rendered": rendered,
                    "fixtureOnly": true,
                    "productionEventKitRead": false,
                    "realUserCalendar": false,
                    "source": provider.selectedCalendarTitle ?? "nil",
                    "selectedDay": model.detail.map { Int(calendar.component(.day, from: $0.date)) } ?? -1
                ]
                try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
                    .write(to: directory.appendingPathComponent("verification.json"))
            } catch {
                fputs("Calendar parity verification failed: \(error)\n", stderr)
            }
            NSApp.terminate(nil)
        }
    }
}

@MainActor
private final class EmptyParityEvents: CalendarEventProviding {
    func events(on day: Date, calendar: Calendar) async -> [CalendarEvent] { [] }
}
