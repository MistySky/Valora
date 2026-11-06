import XCTest
import Foundation
@testable import Valora

private actor IndependentCountingDevices: ConnectedAudioSource {
    private(set) var calls = 0
    func snapshot() async -> ConnectedAudioSnapshot {
        calls += 1
        return ConnectedAudioSnapshot(devices: [], output: "fake")
    }
}

@MainActor
private final class IndependentSilentDeviceSound: LowBatterySoundPlaying {
    func playLowBattery() {}
}

@MainActor
final class IndependentConnectivityLifecycleTests: XCTestCase {
    func testEnablingStartsInitialReadWithoutWaitingForPoll() async {
        let suite = "com.wangqing.valora.independent-connect-enable.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = RevivalSettings(defaults: defaults)
        settings.bluetoothEnabled = false
        let model = AppModel(settings: settings)
        let source = IndependentCountingDevices()
        let controller = ConnectivityController(model, source: source,
                                                sound: IndependentSilentDeviceSound())
        controller.start()
        settings.bluetoothEnabled = true
        try? await Task.sleep(nanoseconds: 150_000_000)
        let calls = await source.calls
        XCTAssertEqual(calls, 1, "enabling should schedule its initial baseline read after Published commits")
        controller.stop()
    }

    func testStoppedControllerRejectsRefresh() async {
        let suite = "com.wangqing.valora.independent-connect-stop.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = RevivalSettings(defaults: defaults)
        settings.bluetoothEnabled = true
        let model = AppModel(settings: settings)
        let source = IndependentCountingDevices()
        let controller = ConnectivityController(model, source: source,
                                                sound: IndependentSilentDeviceSound())
        controller.start(polling: false)
        controller.stop()
        controller.refresh()
        try? await Task.sleep(nanoseconds: 150_000_000)
        let calls = await source.calls
        XCTAssertEqual(calls, 0, "stop must close the query lifecycle, including queued refresh callbacks")
    }
}
