import AppKit
import SwiftUI
import XCTest
@testable import Valora

@MainActor
final class IndependentPersistedPermissionTests: XCTestCase {
    func testPersistedEnabledWithoutAuthorizationDoesNotAppearActive() {
        var storedEnabled = true
        let binding = PermissionToggleRouting.make(
            value: Binding(get: { storedEnabled }, set: { storedEnabled = $0 }),
            authorized: false, pending: false,
            begin: {}, cancel: {})
        XCTAssertFalse(binding.wrappedValue,
                       "An old enabled preference is not current authorization or a pending enable intent")
    }



    func testSettingsViewNormalizationDoesNotWriteLoginItemWhenStatusIsStale() async {
        let suite = "com.wangqing.valora.login-normalization.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = RevivalSettings(defaults: defaults)
        let draft = SettingsDraft(defaults: defaults)
        let model = AppModel(settings: settings)
        let navigation = SettingsNavigation()
        var registers = 0
        var unregisters = 0
        let permissions = AppPermissions(loginItem: .requiresApproval,
                                         loginRegister: { _ in registers += 1 },
                                         loginUnregister: { completion in
                                             unregisters += 1
                                             completion(.notRegistered)
                                         })
        settings.bluetoothEnabled = false
        draft.binding("enableCalendar", false).wrappedValue = false
        draft.binding("launchAtLogin", false).wrappedValue = true
        let view = SettingsView(model: model, settings: settings, navigation: navigation,
                                draft: draft, permissions: permissions)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 620, height: 687)
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFrontRegardless()
        try? await Task.sleep(nanoseconds: 300_000_000)
        host.layoutSubtreeIfNeeded()
        XCTAssertFalse(draft.value("launchAtLogin", false))
        permissions.refresh()
        XCTAssertEqual(registers, 0)
        XCTAssertEqual(unregisters, 0)
        // External grant with no user intent must not start registration or
        // unregistration, even if the local old value was true.
        permissions.verificationSet(loginItem: .enabled)
        permissions.verificationResolvePending()
        XCTAssertEqual(registers, 0)
        XCTAssertEqual(unregisters, 0)
        window.close()
    }

    func testExplicitLoginOffUsesInjectedUnregister() {
        var unregisters = 0
        let permissions = AppPermissions(loginItem: .enabled,
                                         loginRegister: { _ in XCTFail("explicit off must not register") },
                                         loginUnregister: { completion in
                                             unregisters += 1
                                             completion(.notRegistered)
                                         })
        var stored = true
        let binding = PermissionToggleRouting.make(
            value: Binding(get: { stored }, set: { stored = $0 }),
            authorized: true, pending: false,
            begin: { XCTFail("explicit off must not begin") },
            cancel: { permissions.disableLoginItem() })
        binding.wrappedValue = false
        XCTAssertEqual(unregisters, 1)
        XCTAssertFalse(stored)
        XCTAssertEqual(permissions.loginItem, .notRegistered)
    }

    func testPendingShowsOnAndCancelReturnsOff() {
        var stored = false
        var cancels = 0
        let pendingBinding = PermissionToggleRouting.make(
            value: Binding(get: { stored }, set: { stored = $0 }),
            authorized: false, pending: true,
            begin: { XCTFail("a pending intent must not request again") },
            cancel: { cancels += 1 })
        XCTAssertTrue(pendingBinding.wrappedValue)
        pendingBinding.wrappedValue = false
        XCTAssertEqual(cancels, 1)
        XCTAssertFalse(stored)
    }

    func testAuthorizedEnabledPreservesOnAndOffStillCancels() {
        var stored = true
        var cancels = 0
        var begins = 0
        let binding = PermissionToggleRouting.make(
            value: Binding(get: { stored }, set: { stored = $0 }),
            authorized: true, pending: false,
            begin: { begins += 1 }, cancel: { cancels += 1 })
        XCTAssertTrue(binding.wrappedValue)
        binding.wrappedValue = true
        XCTAssertTrue(stored)
        XCTAssertEqual(begins, 0)
        binding.wrappedValue = false
        XCTAssertEqual(cancels, 1)
        XCTAssertFalse(stored)
    }

    func testSettingsViewNormalizesPersistedOnWithoutAuthorizationOnFirstAppearance() async {
        let suite = "com.wangqing.valora.persisted-permission-view.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = RevivalSettings(defaults: defaults)
        let draft = SettingsDraft(defaults: defaults)
        let model = AppModel(settings: settings)
        let navigation = SettingsNavigation()
        let permissions = AppPermissions(bluetooth: .denied,
                                         loginItem: .requiresApproval,
                                         calendar: .denied)
        settings.bluetoothEnabled = true
        draft.binding("enableCalendar", false).wrappedValue = true
        draft.binding("launchAtLogin", false).wrappedValue = true
        let view = SettingsView(model: model, settings: settings, navigation: navigation,
                                draft: draft, permissions: permissions)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 620, height: 687)
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFrontRegardless()
        try? await Task.sleep(nanoseconds: 300_000_000)
        host.layoutSubtreeIfNeeded()
        XCTAssertFalse(settings.bluetoothEnabled,
                       "old enabled preference must not appear active without authorization")
        XCTAssertFalse(draft.value("enableCalendar", false))
        XCTAssertFalse(draft.value("launchAtLogin", false))
        // External authorization without a user intent must not resurrect the
        // old on preference.
        permissions.verificationSet(bluetooth: .authorized)
        permissions.verificationResolvePending()
        XCTAssertFalse(settings.bluetoothEnabled)
        window.close()
    }

    func testEnablingAfterAuthorizationLossRequestsAccessDespiteOldPreference() {
        var storedEnabled = true
        var requests = 0
        let binding = PermissionToggleRouting.make(
            value: Binding(get: { storedEnabled }, set: { storedEnabled = $0 }),
            authorized: false, pending: false,
            begin: { requests += 1 }, cancel: {})
        binding.wrappedValue = true
        XCTAssertEqual(requests, 1,
                       "A stale enabled preference must not swallow the user's current authorization attempt")
    }
}
