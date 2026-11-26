import CoreAudio
import XCTest
@testable import Valora

@MainActor
final class ConnectivitySystemEventsTests: XCTestCase {
    private final class ConnectionToken: BluetoothConnectionNotification {
        private(set) var removals = 0
        func unregister() { removals += 1 }
    }

    func testPartialRegistrationRetriesOnlyMissingListenersAndReleasesEachSuccessOnce() {
        let route = kAudioHardwarePropertyDefaultOutputDevice
        let devices = kAudioHardwarePropertyDevices
        var connectionAttempts = 0
        var tokens: [ConnectionToken] = []
        var attempts: [AudioObjectPropertySelector: Int] = [:]
        var removals: [AudioObjectPropertySelector: Int] = [:]
        let events = ConnectivitySystemEvents(registerConnection: { _, _ in
            connectionAttempts += 1
            guard connectionAttempts >= 3 else { return nil }
            let token = ConnectionToken()
            tokens.append(token)
            return token
        }, observeAudio: { selector, _ in
            attempts[selector, default: 0] += 1
            if selector == devices, attempts[selector, default: 0] < 4 { return nil }
            return { removals[selector, default: 0] += 1 }
        })

        for _ in 0..<5 { events.start() }
        XCTAssertEqual(connectionAttempts, 3)
        XCTAssertEqual(attempts, [route: 1, devices: 4])
        events.stop()
        events.stop()
        XCTAssertEqual(removals, [route: 1, devices: 1])
        XCTAssertEqual(tokens.map(\.removals), [1])

        events.start()
        events.stop()
        XCTAssertEqual(connectionAttempts, 4)
        XCTAssertEqual(attempts, [route: 2, devices: 5])
        XCTAssertEqual(removals, [route: 2, devices: 2])
        XCTAssertEqual(tokens.map(\.removals), [1, 1])
    }

    func testLateAudioCallbackCannotRefreshRestartedSession() async throws {
        var callbacks: [AudioObjectPropertyListenerBlock] = []
        let events = ConnectivitySystemEvents(registerConnection: { _, _ in ConnectionToken() },
                                              observeAudio: { selector, callback in
            if selector == kAudioHardwarePropertyDefaultOutputDevice { callbacks.append(callback) }
            return {}
        })
        var changes = 0
        events.onChange = { changes += 1 }
        events.start()
        events.stop()
        events.start()
        defer { events.stop() }
        XCTAssertEqual(callbacks.count, 2)
        var address = AudioObjectPropertyAddress()
        callbacks[0](1, &address)
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertEqual(changes, 0)
        callbacks[1](1, &address)
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertEqual(changes, 1)
    }
}
