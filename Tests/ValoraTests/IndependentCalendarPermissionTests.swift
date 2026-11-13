import XCTest
import SwiftUI
@testable import Valora

@MainActor
private final class IndependentCalendarSource: CalendarAuthorizationProviding {
    var status: CalendarAccess = .notDetermined
    var callbacks: [@MainActor (CalendarAccess) -> Void] = []
    func requestFullAccess(_ completion: @escaping @MainActor (CalendarAccess) -> Void) {
        callbacks.append(completion)
    }
}

@MainActor
final class IndependentCalendarPermissionTests: XCTestCase {
    func testDefaultProviderLoadsAuthorizationBeforeAnyRefresh() {
        // Status-only read: no permission request, event query or window.
        let expected = EventKitCalendarAuthorization().status
        XCTAssertNotEqual(expected, .unknown)
        let permissions = AppPermissions()
        XCTAssertEqual(permissions.calendar, expected,
                       "production must not expose a synthetic unknown before settings appears")
    }

    func testRecreatedSettingsPreserveExplicitOnAndOffWithExistingAuthorization() {
        let suite = "com.wangqing.valora.calendar-relaunch.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let source = IndependentCalendarSource()
        source.status = .fullAccess
        for enabled in [true, false] {
            SettingsDraft(defaults: defaults).binding("enableCalendar", false).wrappedValue = enabled
            let restored = SettingsDraft(defaults: UserDefaults(suiteName: suite)!)
            let permissions = AppPermissions(calendarProvider: source)
            let binding = PermissionToggleRouting.make(
                value: restored.binding("enableCalendar", false),
                authorized: permissions.calendar.canReadEvents, pending: false,
                begin: { XCTFail("restoring settings must not request authorization") },
                cancel: {})
            XCTAssertEqual(binding.wrappedValue, enabled)
            XCTAssertEqual(restored.value("enableCalendar", false), enabled)
            XCTAssertTrue(source.callbacks.isEmpty)
        }
    }

    func testOldCalendarRequestCannotCompleteNewToggleIntent() {
        let source = IndependentCalendarSource()
        let permissions = AppPermissions(calendarProvider: source)
        var enabled = false
        func binding() -> Binding<Bool> {
            PermissionToggleRouting.make(value: Binding(get: { enabled }, set: { enabled = $0 }),
                authorized: permissions.calendar.canReadEvents,
                pending: permissions.calendarEnablePending,
                begin: { permissions.beginCalendarEnable { enabled = true } },
                cancel: { permissions.cancelCalendarEnable() })
        }
        binding().wrappedValue = true
        XCTAssertEqual(source.callbacks.count, 1)
        binding().wrappedValue = false
        XCTAssertFalse(binding().wrappedValue)
        binding().wrappedValue = true
        XCTAssertEqual(source.callbacks.count, 2)
        source.callbacks[0](.fullAccess)
        XCTAssertFalse(enabled)
        XCTAssertTrue(permissions.calendarEnablePending)
        source.callbacks[1](.fullAccess)
        XCTAssertTrue(enabled)
        XCTAssertFalse(permissions.calendarEnablePending)
    }

    func testReturningFromCalendarSettingsCompletesOnlyActiveIntent() {
        let source = IndependentCalendarSource()
        source.status = .denied
        var settingsOpened = 0
        let permissions = AppPermissions(calendarProvider: source,
            openCalendarSettings: { settingsOpened += 1 },
            refreshStateProvider: { (.authorized, .notRegistered) })
        var enabled = 0
        permissions.beginCalendarEnable { enabled += 1 }
        XCTAssertEqual(settingsOpened, 1)
        source.status = .fullAccess
        permissions.refresh()
        XCTAssertEqual(enabled, 1)
        XCTAssertFalse(permissions.calendarEnablePending)
        permissions.refresh()
        XCTAssertEqual(enabled, 1)
        source.status = .denied
        permissions.refresh()
        permissions.beginCalendarEnable { enabled += 1 }
        permissions.cancelCalendarEnable()
        source.status = .fullAccess
        permissions.refresh()
        XCTAssertEqual(enabled, 1, "external authorization after cancellation must not enable")
    }
}
