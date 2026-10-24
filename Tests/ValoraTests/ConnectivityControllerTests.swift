import XCTest
@testable import Valora
@testable import ReferenceCore

@MainActor
private final class TestSound: LowBatterySoundPlaying {
    var plays = 0
    var stops = 0
    func playLowBattery() { plays += 1 }
    func stopLowBattery() { stops += 1 }
}

private actor DelayedSource: ConnectedAudioSource {
    private(set) var calls = 0
    private let snapshots: [[AudioDevice]]
    private let delay: UInt64
    init(devices: [AudioDevice], delay: UInt64 = 200_000_000) {
        snapshots = [devices]
        self.delay = delay
    }
    init(snapshots: [[AudioDevice]], delay: UInt64 = 200_000_000) {
        self.snapshots = snapshots
        self.delay = delay
    }
    func snapshot() async -> ConnectedAudioSnapshot {
        calls += 1
        let index = min(calls - 1, snapshots.count - 1)
        try? await Task.sleep(nanoseconds: delay)
        return ConnectedAudioSnapshot(devices: snapshots[index], output: "QA output")
    }
    func callCount() -> Int { calls }
}

@MainActor
final class ConnectivityControllerTests: XCTestCase {
    private func model() -> AppModel {
        let defaults = UserDefaults(suiteName: "com.wangqing.valora.connectivity.\(UUID().uuidString)")!
        let settings = RevivalSettings(defaults: defaults)
        settings.bluetoothEnabled = true
        let model = AppModel(settings: settings)
        return model
    }

    private func device(_ id: String, battery: Int? = 80,
                        modelUID: String = "2014 4c") -> AudioDevice {
        AudioDevice(id: id, name: "AirPods \(id)", left: battery, right: battery,
                    single: nil, active: true, isAirPods: true, modelUID: modelUID)
    }

    func testFirstSnapshotIsBaselineAndNewConnectionArrivesOnce() {
        let model = model()
        let sound = TestSound()
        let controller = ConnectivityController(model, source: EmptyConnectivitySource(), sound: sound)
        controller.start(polling: false)
        let first = device("first")
        controller.verificationApply(ConnectedAudioSnapshot(devices: [first], output: "out"))
        XCTAssertNil(model.connectionToast, "existing device must not become a new arrival")
        let second = device("second")
        controller.verificationApply(ConnectedAudioSnapshot(devices: [first, second], output: "out"))
        XCTAssertEqual(model.connectionToast?.id, "second")
        let generation = model.connectionArrivalGeneration
        controller.verificationApply(ConnectedAudioSnapshot(devices: [first, second], output: "out"))
        XCTAssertEqual(model.connectionArrivalGeneration, generation)
        controller.stop()
    }

    func testLateMetadataUpdatesToastWithoutReplay() {
        let model = model()
        let controller = ConnectivityController(model, source: EmptyConnectivitySource(), sound: TestSound())
        controller.start(polling: false)
        let base = device("base")
        controller.verificationApply(ConnectedAudioSnapshot(devices: [base], output: "out"))
        var second = device("second")
        second.modelUID = "2014 4c"
        controller.verificationApply(ConnectedAudioSnapshot(devices: [base, second], output: "out"))
        XCTAssertEqual(model.connectionToast?.id, "second")
        let arrival = model.connectionArrivalGeneration
        second.modelUID = "2013 4c"
        second.left = 70
        controller.verificationApply(ConnectedAudioSnapshot(devices: [base, second], output: "out"))
        XCTAssertEqual(model.connectionToast?.movie, "airpods-3")
        XCTAssertEqual(model.connectionArrivalGeneration, arrival)
        controller.stop()
    }

    func testFirstLowSnapshotDoesNotAlertOrSound() {
        let model = model()
        let sound = TestSound()
        let controller = ConnectivityController(model, source: EmptyConnectivitySource(), sound: sound)
        controller.start(polling: false)
        let low = device("first-low", battery: 10)
        controller.verificationApply(ConnectedAudioSnapshot(devices: [low], output: "out"))
        XCTAssertNil(model.connectionToast)
        XCTAssertEqual(sound.plays, 0)
        controller.stop()
    }

    func testLowBatteryEdgeAndZeroVersusNil() {
        let model = model()
        let sound = TestSound()
        let controller = ConnectivityController(model, source: EmptyConnectivitySource(), sound: sound)
        controller.start(polling: false)
        let high = device("low", battery: 50, modelUID: "2013 4c")
        controller.verificationApply(ConnectedAudioSnapshot(devices: [high], output: "out"))
        XCTAssertEqual(sound.plays, 0)
        let low = device("low", battery: 20, modelUID: "2013 4c")
        controller.verificationApply(ConnectedAudioSnapshot(devices: [low], output: "out"))
        XCTAssertTrue(model.connectionLowBattery)
        XCTAssertEqual(sound.plays, 1)
        let zero = device("low", battery: 0, modelUID: "2013 4c")
        XCTAssertEqual(zero.battery, 0)
        let missing = AudioDevice(id: "missing", name: "AirPods", left: nil, right: nil,
                                  single: nil, active: false, isAirPods: true)
        XCTAssertNil(missing.battery)
        controller.verificationApply(ConnectedAudioSnapshot(devices: [zero], output: "out"))
        XCTAssertEqual(sound.plays, 1, "0 is below threshold but must not repeat the edge alert")
        controller.stop()
        XCTAssertGreaterThanOrEqual(sound.stops, 1, "controller stop must stop an active alert sound")
    }

    func testSwitchOffClearsToastAndRejectsLateSnapshot() async {
        let model = model()
        let controller = ConnectivityController(model, source: EmptyConnectivitySource(), sound: TestSound())
        controller.start(polling: false)
        let base = device("base")
        controller.verificationApply(ConnectedAudioSnapshot(devices: [base], output: "out"))
        let new = device("new")
        controller.verificationApply(ConnectedAudioSnapshot(devices: [base, new], output: "out"))
        XCTAssertEqual(model.connectionToast?.id, "new")
        model.settings.bluetoothEnabled = false
        try? await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertNil(model.connectionToast)
        XCTAssertTrue(model.devices.isEmpty)
        controller.verificationApply(ConnectedAudioSnapshot(devices: [new], output: "out"))
        XCTAssertNil(model.connectionToast, "late result after switch-off must be ignored")
        controller.stop()
    }

    func testSwitchOffStopsSoundAndPreventsFurtherPlayback() async {
        let model = model()
        let sound = TestSound()
        let controller = ConnectivityController(model, source: EmptyConnectivitySource(), sound: sound)
        controller.start(polling: false)
        let base = device("base", battery: 50)
        controller.verificationApply(ConnectedAudioSnapshot(devices: [base], output: "out"))
        let low = device("base", battery: 20)
        controller.verificationApply(ConnectedAudioSnapshot(devices: [low], output: "out"))
        XCTAssertEqual(sound.plays, 1)
        model.settings.bluetoothEnabled = false
        try? await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertGreaterThanOrEqual(sound.stops, 1)
        controller.verificationApply(ConnectedAudioSnapshot(devices: [low], output: "out"))
        XCTAssertEqual(sound.plays, 1)
        controller.stop()
    }

    func testStopRemovesSettingSubscriptionAndQueuedEnable() async {
        let model = model()
        let source = DelayedSource(devices: [device("never")], delay: 10_000_000)
        let controller = ConnectivityController(model, source: source, sound: TestSound())
        controller.start(polling: false)
        controller.stop()
        model.settings.bluetoothEnabled = false
        model.settings.bluetoothEnabled = true
        try? await Task.sleep(nanoseconds: 200_000_000)
        let calls = await source.callCount()
        XCTAssertEqual(calls, 0, "a stopped controller must not restart from queued setting events")
    }

    func testLateSourceAcrossStopStartCannotReopenOldToast() async {
        let model = model()
        let source = DelayedSource(devices: [device("stale")], delay: 150_000_000)
        let controller = ConnectivityController(model, source: source, sound: TestSound())
        controller.start(polling: false)
        controller.refresh()
        try? await Task.sleep(nanoseconds: 30_000_000)
        controller.stop()
        controller.start(polling: false)
        try? await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertNil(model.connectionToast, "a source result from the previous generation must not show")
        controller.stop()
    }

    func testStopThenStartReestablishesBaselineWithoutToast() {
        let model = model()
        let source = EmptyConnectivitySource()
        let controller = ConnectivityController(model, source: source, sound: TestSound())
        controller.start(polling: false)
        controller.stop()
        controller.start(polling: false)
        let base = device("base")
        controller.verificationApply(ConnectedAudioSnapshot(devices: [base], output: "out"))
        XCTAssertNil(model.connectionToast)
        let fresh = device("fresh")
        controller.verificationApply(ConnectedAudioSnapshot(devices: [base, fresh], output: "out"))
        XCTAssertEqual(model.connectionToast?.id, "fresh")
        controller.stop()
    }

    func testLateSourceResultAfterSwitchOffIsIgnored() async {
        let model = model()
        let source = DelayedSource(devices: [device("late")], delay: 250_000_000)
        let controller = ConnectivityController(model, source: source, sound: TestSound())
        controller.start(polling: false)
        controller.refresh()
        try? await Task.sleep(nanoseconds: 40_000_000)
        model.settings.bluetoothEnabled = false
        try? await Task.sleep(nanoseconds: 350_000_000)
        XCTAssertNil(model.connectionToast)
        XCTAssertTrue(model.devices.isEmpty)
        controller.stop()
    }

    func testQueryIsBoundedToOneAndStaleResultIsIgnored() async {
        let model = model()
        let base = device("base")
        let source = DelayedSource(snapshots: [
            [base],
            [base, device("delayed")]
        ])
        let controller = ConnectivityController(model, source: source, sound: TestSound())
        controller.start(polling: false)
        controller.refresh()
        controller.refresh()
        try? await Task.sleep(nanoseconds: 50_000_000)
        let firstCallCount = await source.callCount()
        XCTAssertEqual(firstCallCount, 1, "a second poll must not start a concurrent query")
        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(model.connectionToast, nil, "the first source read is still baseline")
        controller.refresh()
        try? await Task.sleep(nanoseconds: 300_000_000)
        let secondCallCount = await source.callCount()
        XCTAssertEqual(secondCallCount, 2)
        XCTAssertEqual(model.connectionToast?.id, "delayed")
        controller.stop()
    }
}
