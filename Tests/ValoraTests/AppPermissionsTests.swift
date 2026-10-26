import SwiftUI
import XCTest
@testable import Valora

@MainActor
final class AppPermissionsTests: XCTestCase {
    private func permissions(bluetooth: PermissionAccess = .unknown,
                             login: LoginItemAccess = .notRegistered) -> (AppPermissions,
                                                                          Box, Box, Box, Box) {
        let requests = Box()
        let bluetoothSettings = Box()
        let unusedSettings = Box()
        let unusedCompletion = Box()
        let permissions = AppPermissions(
            bluetooth: bluetooth, loginItem: login,
            bluetoothRequest: { requests.count += 1 },
            openBluetoothSettings: { bluetoothSettings.count += 1 },
            openLoginSettings: { requests.count += 1 })
        return (permissions, requests, bluetoothSettings, unusedSettings, unusedCompletion)
    }

    func testBluetoothStatesGateTheSwitchAndUseTheRightEntry() {
        let (unknown, requests, settings, _, _) = permissions(bluetooth: .unknown)
        XCTAssertTrue(unknown.bluetoothBlocked)
        unknown.requestBluetoothAccess()
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(settings.count, 0)

        let (denied, deniedRequests, deniedSettings, _, _) = permissions(bluetooth: .denied)
        denied.requestBluetoothAccess()
        XCTAssertEqual(deniedRequests.count, 0)
        XCTAssertEqual(deniedSettings.count, 1)

        let (authorized, authorizedRequests, authorizedSettings, _, _) = permissions(bluetooth: .authorized)
        XCTAssertFalse(authorized.bluetoothBlocked)
        authorized.requestBluetoothAccess()
        XCTAssertEqual(authorizedRequests.count, 0)
        XCTAssertEqual(authorizedSettings.count, 0)
    }

    func testSwitchRoutingBeginsOnlyWhenPermissionIsNotAuthorized() {
        var value = false
        var begins = 0
        var cancels = 0
        var binding = PermissionToggleRouting.make(
            value: Binding(get: { value }, set: { value = $0 }),
            authorized: false, pending: false,
            begin: { begins += 1 }, cancel: { cancels += 1 })
        binding.wrappedValue = true
        XCTAssertEqual(begins, 1)
        XCTAssertFalse(value, "an unauthorized switch must not persist the feature as on")
        XCTAssertFalse(binding.wrappedValue)

        binding = PermissionToggleRouting.make(
            value: Binding(get: { value }, set: { value = $0 }),
            authorized: false, pending: true,
            begin: { begins += 1 }, cancel: { cancels += 1 })
        XCTAssertTrue(binding.wrappedValue, "pending intent is visible as an on attempt")
        binding.wrappedValue = false
        XCTAssertEqual(cancels, 1)
        XCTAssertFalse(value)

        binding = PermissionToggleRouting.make(
            value: Binding(get: { value }, set: { value = $0 }),
            authorized: true, pending: false,
            begin: { begins += 1 }, cancel: { cancels += 1 })
        binding.wrappedValue = true
        XCTAssertTrue(value)
        XCTAssertEqual(begins, 1)
    }

    func testBluetoothPendingIntentCompletesOnlyAfterAuthorization() {
        let (pending, requests, _, _, _) = permissions(bluetooth: .notDetermined)
        var opened = 0
        pending.beginBluetoothEnable { opened += 1 }
        XCTAssertTrue(pending.bluetoothEnablePending)
        XCTAssertEqual(requests.count, 1)
        pending.verificationSet(bluetooth: .authorized)
        pending.verificationResolvePending()
        XCTAssertEqual(opened, 1)
        XCTAssertFalse(pending.bluetoothEnablePending)

        let (cancelledPermissions, _, _, _, _) = permissions(bluetooth: .notDetermined)
        cancelledPermissions.beginBluetoothEnable { XCTFail("cancelled intent must not complete") }
        cancelledPermissions.cancelBluetoothEnable()
        cancelledPermissions.verificationSet(bluetooth: .authorized)
        cancelledPermissions.verificationResolvePending()
        XCTAssertFalse(cancelledPermissions.bluetoothEnablePending)
    }

    func testLoginPendingIntentCompletesAfterApproval() {
        let (permissions, _, _, _, _) = permissions(login: .requiresApproval)
        var opened = 0
        permissions.beginLoginEnable { opened += 1 }
        XCTAssertTrue(permissions.loginEnablePending)
        permissions.verificationSet(loginItem: .enabled)
        permissions.verificationResolvePending()
        XCTAssertEqual(opened, 1)
        XCTAssertFalse(permissions.loginEnablePending)
    }

    func testCancellingFirstRegistrationUnregistersOnlyOwnedIntent() {
        var registerCallbacks: [(LoginItemAccess) -> Void] = []
        var unregisters = 0
        let permissions = AppPermissions(
            bluetooth: .authorized, loginItem: .notRegistered,
            loginRegister: { registerCallbacks.append($0) },
            loginUnregister: { completion in
                unregisters += 1
                completion(.notRegistered)
            })
        permissions.beginLoginEnable { XCTFail("cancelled registration completed") }
        registerCallbacks[0](.requiresApproval)
        XCTAssertTrue(permissions.loginEnablePending)
        permissions.cancelLoginEnable()
        XCTAssertEqual(unregisters, 1)
        XCTAssertFalse(permissions.loginEnablePending)
    }

    func testFirstLoginRegistrationRequiresApprovalKeepsIntentAlive() {
        var callbacks: [(LoginItemAccess) -> Void] = []
        let permissions = AppPermissions(
            bluetooth: .authorized, loginItem: .notRegistered,
            loginRegister: { completion in callbacks.append(completion) })
        var completed = 0
        permissions.beginLoginEnable { completed += 1 }
        XCTAssertTrue(permissions.loginEnablePending)
        XCTAssertEqual(callbacks.count, 1)
        callbacks[0](.requiresApproval)
        XCTAssertTrue(permissions.loginEnablePending)
        XCTAssertEqual(permissions.loginItem, .requiresApproval)
        permissions.verificationSet(loginItem: .enabled)
        permissions.verificationResolvePending()
        XCTAssertEqual(completed, 1)
        XCTAssertFalse(permissions.loginEnablePending)
    }

    func testLoginApprovalOpensSettingsAndIsBlocked() {
        let (permissions, requests, _, _, _) = permissions(login: .requiresApproval)
        XCTAssertTrue(permissions.loginBlocked)
        permissions.requestLoginItemAccess()
        XCTAssertEqual(requests.count, 1)
        permissions.verificationSet(loginItem: .enabled)
        XCTAssertFalse(permissions.loginBlocked)
    }
}

@MainActor
private final class Box {
    var count = 0
    var granted = false
}

@MainActor
private final class FakeCalendarAuthorization: CalendarAuthorizationProviding {
    var status: CalendarAccess
    private(set) var requests = 0
    private var completion: (@MainActor (CalendarAccess) -> Void)?
    init(_ status: CalendarAccess) { self.status = status }
    func requestFullAccess(_ completion: @escaping @MainActor (CalendarAccess) -> Void) {
        requests += 1
        self.completion = completion
    }
    func complete(_ status: CalendarAccess) {
        self.status = status
        completion?(status)
        completion = nil
    }
}

@MainActor
private final class FailingCalendarAuthorization: CalendarAuthorizationProviding {
    var status: CalendarAccess = .notDetermined
    func requestFullAccess(_ completion: @escaping @MainActor (CalendarAccess) -> Void) {}
    func requestFullAccessWithFailure(
        _ completion: @escaping @MainActor (CalendarAccess, CalendarAuthorizationFailure?) -> Void
    ) {
        completion(.unknown, CalendarAuthorizationFailure(domain: "com.apple.EventKit", code: 42))
    }
}

@MainActor
final class CalendarPermissionTests: XCTestCase {
    func testCalendarNotDeterminedRequestsOnceAndCompletesAfterFullAccess() {
        let provider = FakeCalendarAuthorization(.notDetermined)
        let permissions = AppPermissions(calendar: .notDetermined, calendarProvider: provider)
        var completed = 0
        permissions.beginCalendarEnable { completed += 1 }
        XCTAssertTrue(permissions.calendarEnablePending)
        XCTAssertEqual(provider.requests, 1)
        permissions.beginCalendarEnable { completed += 1 }
        XCTAssertEqual(provider.requests, 1, "pending intent must not request twice")
        provider.complete(.fullAccess)
        XCTAssertEqual(completed, 1)
        XCTAssertFalse(permissions.calendarEnablePending)
        XCTAssertTrue(permissions.calendar.canReadEvents)
    }

    func testCalendarDeniedGuidesSettingsAndCancelReturnsOff() {
        var opened = 0
        let provider = FakeCalendarAuthorization(.denied)
        let permissions = AppPermissions(calendar: .denied, calendarProvider: provider,
                                         openCalendarSettings: { opened += 1 })
        var completed = 0
        permissions.beginCalendarEnable { completed += 1 }
        XCTAssertEqual(opened, 1)
        XCTAssertEqual(provider.requests, 0)
        XCTAssertTrue(permissions.calendarEnablePending)
        permissions.cancelCalendarEnable()
        XCTAssertFalse(permissions.calendarEnablePending)
        XCTAssertEqual(completed, 0)
    }

    func testCalendarWriteOnlyIsNotReadableAndFailureStaysOff() {
        let provider = FakeCalendarAuthorization(.writeOnly)
        let permissions = AppPermissions(calendar: .writeOnly, calendarProvider: provider)
        XCTAssertTrue(permissions.calendarBlocked)
        XCTAssertFalse(permissions.calendar.canReadEvents)
        var completed = 0
        permissions.beginCalendarEnable { completed += 1 }
        provider.complete(.writeOnly)
        XCTAssertEqual(completed, 0)
        XCTAssertFalse(permissions.calendarEnablePending)
        XCTAssertFalse(permissions.calendar.canReadEvents)
        XCTAssertNotNil(permissions.message)
    }

    func testCalendarRequestFailureIsDiagnosticNotDenied() {
        let provider = FailingCalendarAuthorization()
        let permissions = AppPermissions(calendar: .notDetermined, calendarProvider: provider)
        var completed = 0
        permissions.beginCalendarEnable { completed += 1 }
        XCTAssertEqual(completed, 0)
        XCTAssertFalse(permissions.calendarEnablePending)
        XCTAssertEqual(permissions.calendar, .unknown)
        XCTAssertTrue(permissions.message?.contains("com.apple.EventKit") == true)
        XCTAssertTrue(permissions.message?.contains("42") == true)
    }

    func testCalendarExternalFullAccessWithoutPendingDoesNotEnableIntent() {
        let provider = FakeCalendarAuthorization(.notDetermined)
        let permissions = AppPermissions(calendar: .notDetermined, calendarProvider: provider)
        permissions.verificationSet(calendar: .fullAccess)
        XCTAssertTrue(permissions.calendar.canReadEvents)
        XCTAssertFalse(permissions.calendarEnablePending)
        // The actual switch remains off because only a user Binding click can
        // create an enable intent; status alone does not do so.
        var settingsValue = false
        let binding = PermissionToggleRouting.make(
            value: Binding(get: { settingsValue }, set: { settingsValue = $0 }),
            authorized: permissions.calendar == .fullAccess,
            pending: permissions.calendarEnablePending,
            begin: { XCTFail("no pending intent should be synthesized from external status") },
            cancel: {})
        XCTAssertFalse(binding.wrappedValue)
        XCTAssertFalse(settingsValue)
    }

    func testCalendarStatusMappingKeepsWriteOnlyDistinct() {
        XCTAssertEqual(EventKitCalendarAuthorization.map(.fullAccess), .fullAccess)
        XCTAssertEqual(EventKitCalendarAuthorization.map(.writeOnly), .writeOnly)
        XCTAssertNotEqual(EventKitCalendarAuthorization.map(.writeOnly), .fullAccess)
        XCTAssertEqual(EventKitCalendarAuthorization.map(.denied), .denied)
        XCTAssertEqual(EventKitCalendarAuthorization.map(.restricted), .restricted)
        XCTAssertEqual(EventKitCalendarAuthorization.map(.notDetermined), .notDetermined)
    }
}
