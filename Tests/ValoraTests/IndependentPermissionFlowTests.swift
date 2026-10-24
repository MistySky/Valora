import XCTest
import Combine
@testable import Valora

@MainActor
final class IndependentPermissionFlowTests: XCTestCase {
    func testCancellingBluetoothIntentPublishesVisiblePendingChange() {
        let permissions = AppPermissions(bluetooth: .notDetermined,
                                         audioCapture: .unknown,
                                         loginItem: .notRegistered)
        var notifications = 0
        let token = permissions.objectWillChange.sink { notifications += 1 }
        defer { token.cancel() }
        permissions.beginBluetoothEnable {}
        XCTAssertTrue(permissions.bluetoothEnablePending)
        notifications = 0
        permissions.cancelBluetoothEnable()
        XCTAssertFalse(permissions.bluetoothEnablePending)
        XCTAssertGreaterThan(notifications, 0,
                             "Settings must redraw pending -> off even while no backend preference changed")
    }

    func testAudioApprovalReturnedFromSettingsCompletesPendingIntent() {
        var settingsOpened = 0
        let permissions = AppPermissions(bluetooth: .authorized,
                                         audioCapture: .denied,
                                         loginItem: .notRegistered,
                                         openAudioSettings: { settingsOpened += 1 })
        var enabled = 0
        permissions.beginAudioEnable { enabled += 1 }
        XCTAssertEqual(settingsOpened, 1)
        XCTAssertTrue(permissions.audioEnablePending)
        permissions.verificationSet(audioCapture: .authorized)
        permissions.verificationResolvePending()
        XCTAssertEqual(enabled, 1,
                       "Returning with audio authorized must complete the pending switch intent once")
        XCTAssertFalse(permissions.audioEnablePending)
        permissions.verificationResolvePending()
        XCTAssertEqual(enabled, 1)
    }
    func testCancelledLoginRegistrationCannotCompleteNewIntent() {
        var callbacks: [(LoginItemAccess) -> Void] = []
        let permissions = AppPermissions(bluetooth: .authorized,
            audioCapture: .authorized, loginItem: .notRegistered,
            loginRegister: { callbacks.append($0) })
        permissions.beginLoginEnable { XCTFail("cancelled intent completed") }
        permissions.cancelLoginEnable()
        var newCompletions = 0
        permissions.beginLoginEnable { newCompletions += 1 }
        XCTAssertEqual(callbacks.count, 2)
        callbacks[0](.enabled)
        XCTAssertEqual(newCompletions, 0, "old registration must not satisfy a newer intent")
        XCTAssertTrue(permissions.loginEnablePending)
        callbacks[1](.enabled)
        XCTAssertEqual(newCompletions, 1)
    }

    func testAudioReturnRetainsIntentWhileOldDeniedSnapshotWaitsForCallback() {
        var callbacks: [(Bool) -> Void] = []
        let permissions = AppPermissions(bluetooth: .authorized,
            audioCapture: .denied, loginItem: .notRegistered,
            audioRequest: { callbacks.append($0) },
            refreshStateProvider: { (.authorized, .denied, .notRegistered) })
        var completed = 0
        permissions.beginAudioEnable { completed += 1 }
        permissions.refresh()
        permissions.refresh()
        XCTAssertEqual(callbacks.count, 1)
        XCTAssertTrue(permissions.audioEnablePending)
        XCTAssertEqual(completed, 0)
        callbacks[0](true)
        XCTAssertEqual(completed, 1)
        XCTAssertFalse(permissions.audioEnablePending)
    }

    func testCancellingPreexistingLoginApprovalDoesNotUnregisterIt() {
        var unregisters = 0
        let permissions = AppPermissions(bluetooth: .authorized,
            audioCapture: .authorized, loginItem: .requiresApproval,
            loginUnregister: { completion in
                unregisters += 1
                completion(.notRegistered)
            })
        permissions.beginLoginEnable { XCTFail("cancelled intent completed") }
        permissions.cancelLoginEnable()
        XCTAssertEqual(unregisters, 0)
        XCTAssertFalse(permissions.loginEnablePending)
    }

}
