import SwiftUI
import XCTest
@testable import Valora

@MainActor
final class AppPermissionsTests: XCTestCase {
    private func permissions(bluetooth: PermissionAccess = .unknown,
                             audio: PermissionAccess = .unknown,
                             login: LoginItemAccess = .notRegistered) -> (AppPermissions,
                                                                          Box, Box, Box, Box) {
        let requests = Box()
        let bluetoothSettings = Box()
        let audioSettings = Box()
        let audioCompletion = Box()
        let permissions = AppPermissions(
            bluetooth: bluetooth, audioCapture: audio, loginItem: login,
            bluetoothRequest: { requests.count += 1 },
            openBluetoothSettings: { bluetoothSettings.count += 1 },
            audioRequest: { completion in
                audioCompletion.count += 1
                completion(audioCompletion.granted)
            },
            openAudioSettings: { audioSettings.count += 1 },
            openLoginSettings: { requests.count += 1 })
        return (permissions, requests, bluetoothSettings, audioSettings, audioCompletion)
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

    func testAudioUnknownAttemptsAndDeniedOpensSettings() {
        let (unknown, _, _, _, _) = permissions(audio: .unknown)
        XCTAssertTrue(unknown.audioBlocked)
        unknown.requestAudioCapture()
        XCTAssertEqual(unknown.audioCapture, .unknown, "default injectable request reports no permission")

        let (granted, _, _, _, completion) = permissions(audio: .unknown)
        completion.granted = true
        granted.requestAudioCapture()
        XCTAssertEqual(granted.audioCapture, .authorized)
        XCTAssertFalse(granted.audioBlocked)

        let (denied, _, _, deniedSettings, _) = permissions(audio: .denied)
        denied.requestAudioCapture()
        XCTAssertEqual(deniedSettings.count, 1)
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

    func testCancelledAudioIntentIgnoresLateCallback() {
        var callbacks: [(Bool) -> Void] = []
        let permissions = AppPermissions(
            bluetooth: .authorized, audioCapture: .unknown, loginItem: .enabled,
            audioRequest: { completion in callbacks.append(completion) })
        var oldOpened = 0
        permissions.beginAudioEnable { oldOpened += 1 }
        let oldCallback = callbacks[0]
        permissions.cancelAudioEnable()
        var newOpened = 0
        permissions.beginAudioEnable { newOpened += 1 }
        oldCallback(true)
        XCTAssertEqual(oldOpened, 0, "a callback from a cancelled intent must not complete it")
        XCTAssertTrue(permissions.audioEnablePending, "the new intent remains pending")
        XCTAssertEqual(newOpened, 0)
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

    func testAudioReturnUsesProductionRefreshAsyncAttempt() {
        var currentAudio: PermissionAccess = .denied
        var callbacks: [(Bool) -> Void] = []
        var opened = 0
        let permissions = AppPermissions(
            bluetooth: .authorized, audioCapture: .denied, loginItem: .notRegistered,
            audioRequest: { callbacks.append($0) },
            openAudioSettings: { opened += 1 },
            refreshStateProvider: { (.authorized, currentAudio, .notRegistered) })
        var completed = 0
        permissions.beginAudioEnable { completed += 1 }
        XCTAssertEqual(opened, 1)
        XCTAssertTrue(permissions.audioEnablePending)
        currentAudio = .authorized
        permissions.refresh()
        XCTAssertEqual(callbacks.count, 1)
        XCTAssertEqual(completed, 0, "async attempt must not complete from old/synchronous state")
        permissions.refresh()
        XCTAssertEqual(callbacks.count, 1, "repeated activation must not start a concurrent attempt")
        callbacks[0](true)
        XCTAssertEqual(completed, 1)
        XCTAssertFalse(permissions.audioEnablePending)
        permissions.refresh()
        XCTAssertEqual(completed, 1)
    }

    func testAudioReturnFailureAndCancellationDoNotEnable() {
        var callbacks: [(Bool) -> Void] = []
        let permissions = AppPermissions(
            bluetooth: .authorized, audioCapture: .denied, loginItem: .notRegistered,
            audioRequest: { callbacks.append($0) },
            openAudioSettings: {},
            refreshStateProvider: { (.authorized, .authorized, .notRegistered) })
        var completed = 0
        permissions.beginAudioEnable { completed += 1 }
        permissions.refresh()
        callbacks[0](false)
        XCTAssertEqual(completed, 0)
        XCTAssertFalse(permissions.audioEnablePending)
        XCTAssertEqual(permissions.audioCapture, .unknown)

        var callbacks2: [(Bool) -> Void] = []
        let cancelled = AppPermissions(
            bluetooth: .authorized, audioCapture: .denied, loginItem: .notRegistered,
            audioRequest: { callbacks2.append($0) },
            openAudioSettings: {},
            refreshStateProvider: { (.authorized, .authorized, .notRegistered) })
        var cancelledCompletion = 0
        cancelled.beginAudioEnable { cancelledCompletion += 1 }
        cancelled.refresh()
        cancelled.cancelAudioEnable()
        callbacks2[0](true)
        XCTAssertEqual(cancelledCompletion, 0)
        XCTAssertFalse(cancelled.audioEnablePending)
    }

    func testCancellingFirstRegistrationUnregistersOnlyOwnedIntent() {
        var registerCallbacks: [(LoginItemAccess) -> Void] = []
        var unregisters = 0
        let permissions = AppPermissions(
            bluetooth: .authorized, audioCapture: .authorized, loginItem: .notRegistered,
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
            bluetooth: .authorized, audioCapture: .authorized, loginItem: .notRegistered,
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
