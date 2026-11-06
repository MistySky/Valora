import AppKit
import SwiftUI
import XCTest
@testable import Valora

@MainActor
final class DeviceBatteryRowTests: XCTestCase {
    private final class SilentSound: LowBatterySoundPlaying {
        func playLowBattery() {}
        func stopLowBattery() {}
    }

    private actor EmptySource: ConnectedAudioSource {
        func snapshot() async -> ConnectedAudioSnapshot {
            ConnectedAudioSnapshot(devices: [], output: "")
        }
    }

    private func device(_ name: String = "AirPods 3",
                        left: Int? = 85, right: Int? = 85, single: Int? = nil,
                        active: Bool = true, isAirPods: Bool = true,
                        modelUID: String = "2013 4c", id: String? = nil,
                        caseBattery: Int? = nil) -> AudioDevice {
        AudioDevice(id: id ?? name, name: name, left: left, right: right, single: single,
                    active: active, isAirPods: isAirPods, modelUID: modelUID,
                    caseBattery: caseBattery)
    }

    func testEqualEarbudsCollapseToOneValue() {
        let row = DeviceBatteryRow.data(devices: [device()], enabled: true)
        XCTAssertEqual(row?.name, "AirPods 3")
        XCTAssertEqual(row?.ears, "全部85%")
        XCTAssertEqual(row?.caseText, "盒--%")
    }

    func testDifferentSidesAreShownSeparately() {
        let row = DeviceBatteryRow.data(devices: [device(left: 85, right: 78)], enabled: true)
        XCTAssertEqual(row?.ears, "左85% 右78%")
        XCTAssertEqual(row?.caseText, "盒--%")
    }

    func testAirPodsMaxUsesSharedSingleReadingInBothColumns() {
        let max = device("AirPods Max", left: 50, right: 60, single: 85,
                         isAirPods: true, modelUID: "200a")
        let row = DeviceBatteryRow.data(devices: [max], enabled: true)
        XCTAssertEqual(row?.ears, "全部85%")
        XCTAssertEqual(row?.caseText, "盒--%")
        XCTAssertTrue(row?.accessibility.contains("整机共享读数") == true)
        let unknown = device("AirPods Max", left: nil, right: nil, single: nil,
                             isAirPods: true, modelUID: "200a")
        XCTAssertEqual(DeviceBatteryRow.data(devices: [unknown], enabled: true)?.ears,
                       "全部--%")
    }

    func testZeroIsValidAndMissingOrOutOfRangeIsDash() {
        XCTAssertEqual(DeviceBatteryRow.data(devices: [device(left: 0, right: 0)], enabled: true)?.ears,
                       "全部0%")
        XCTAssertEqual(DeviceBatteryRow.data(devices: [device(left: nil, right: nil)], enabled: true)?.ears,
                       "左--% 右--%")
        XCTAssertEqual(DeviceBatteryRow.data(devices: [device(left: -1, right: 101)], enabled: true)?.ears,
                       "左--% 右--%")
        XCTAssertEqual(DeviceBatteryRow.data(devices: [device(left: 70, right: 900)], enabled: true)?.ears,
                       "左70% 右--%")
    }

    func testOnlyRecognizedAirPodsQualify() {
        let mxMaster = device("MX Master 3S", left: nil, right: nil, single: 80,
                              active: true, isAirPods: false, modelUID: "", id: "mx")
        XCTAssertNil(DeviceBatteryRow.data(devices: [mxMaster], enabled: true),
                     "a generic battery reading must not be treated as headphones")
        let keyboard = device("Magic Keyboard", left: 80, right: nil, active: true,
                              isAirPods: false, modelUID: "", id: "keyboard")
        XCTAssertNil(DeviceBatteryRow.data(devices: [keyboard], enabled: true))
    }

    func testSelectionPrefersActiveAirPods() {
        let inactive = device("AirPods", left: 40, right: 40, active: false, id: "inactive")
        let active = device("AirPods Pro", left: 85, right: 78, active: true, id: "active")
        XCTAssertEqual(DeviceBatteryRow.data(devices: [inactive, active], enabled: true)?.deviceID,
                       "active")
        XCTAssertEqual(DeviceBatteryRow.data(devices: [inactive], enabled: true)?.deviceID,
                       "inactive")
    }

    func testDisabledSwitchOrEmptyDevicesHidesRow() {
        XCTAssertNil(DeviceBatteryRow.data(devices: [device()], enabled: false))
        XCTAssertNil(DeviceBatteryRow.data(devices: [], enabled: true))
    }

    func testLateSnapshotWithoutDeviceRemovesRow() {
        let suite = "com.wangqing.valora.device-row.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = RevivalSettings(defaults: defaults)
        settings.bluetoothEnabled = true
        let model = AppModel(settings: settings)
        let controller = ConnectivityController(model, source: EmptySource(), sound: SilentSound())
        controller.verificationApply(ConnectedAudioSnapshot(devices: [device()], output: "AirPods"))
        XCTAssertNotNil(DeviceBatteryRow.data(devices: model.devices, enabled: true))
        controller.verificationApply(ConnectedAudioSnapshot(devices: [], output: ""))
        XCTAssertNil(DeviceBatteryRow.data(devices: model.devices, enabled: true),
                     "a late/empty snapshot must remove the stale battery row")
        controller.stop()
    }

    func testAccessibilityIncludesModelAndValues() {
        let row = DeviceBatteryRow.data(devices: [device()], enabled: true)
        XCTAssertTrue(row?.accessibility.contains("AirPods 3") == true)
        XCTAssertTrue(row?.accessibility.contains("全部电量85%") == true)
        XCTAssertTrue(row?.accessibility.contains("盒电量不可用") == true)
    }
}

@MainActor
final class DeviceBatteryRowLayoutTests: XCTestCase {
    func testSharedPanelWidthAndDeviceRowHeight() {
        let suite = "com.wangqing.valora.device-layout.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = RevivalSettings(defaults: defaults)
        settings.bluetoothEnabled = true
        let model = AppModel(settings: settings)
        model.devices = [AudioDevice(id: "airpods",
                                     name: "AirPods Pro With A Very Long Model Name That Must Truncate",
                                     left: 85, right: 78, single: nil, active: true,
                                     isAirPods: true, modelUID: "2014 4c")]
        let calendar = CalmonCalendarModel(provider: HolidayProvider.nonReading(),
                                           readGate: { true }, preview: true)
        let visibility = MenuBarPanelVisibility()
        let monitor = SystemMonitor()
        monitor.verificationApply(snapshot: SystemMonitor.Snapshot(
            memory: .init(total: 32 * 1_073_741_824, used: 20 * 1_073_741_824),
            uptime: "已运行 2 天"))
        let withDevice = CalendarMonitorSharedView(
            monitor: monitor, calendar: calendar, codex: nil,
            appModel: model, settings: settings, visibility: visibility,
            maxHeight: 700, onClose: {})
        let host = NSHostingView(rootView: withDevice)
        host.layoutSubtreeIfNeeded()
        XCTAssertLessThanOrEqual(host.fittingSize.width, 400.5,
                                 "device line must not widen the 400pt shared panel")

        let emptyModel = AppModel(settings: settings)
        let withoutDevice = CalendarMonitorSharedView(
            monitor: monitor, calendar: calendar, codex: nil,
            appModel: emptyModel, settings: settings, visibility: visibility,
            maxHeight: 700, onClose: {})
        let emptyHost = NSHostingView(rootView: withoutDevice)
        emptyHost.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(host.fittingSize.height, emptyHost.fittingSize.height + 8,
                             "connected AirPods fixture must add the device row")
    }

    func testDeviceLineHiddenWhenConnectivitySwitchIsOff() {
        let suite = "com.wangqing.valora.device-layout-off.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = RevivalSettings(defaults: defaults)
        settings.bluetoothEnabled = false
        let model = AppModel(settings: settings)
        model.devices = [AudioDevice(id: "airpods", name: "AirPods 3", left: 85, right: 85,
                                     single: nil, active: true, isAirPods: true,
                                     modelUID: "2013 4c")]
        let calendar = CalmonCalendarModel(provider: HolidayProvider.nonReading(),
                                           readGate: { true }, preview: true)
        let view = CalendarMonitorSharedView(
            monitor: SystemMonitor(), calendar: calendar, codex: nil,
            appModel: model, settings: settings, visibility: MenuBarPanelVisibility(),
            maxHeight: 700, onClose: {})
        let host = NSHostingView(rootView: view)
        host.layoutSubtreeIfNeeded()
        let withOffModel = AppModel(settings: settings)
        let withoutView = CalendarMonitorSharedView(
            monitor: SystemMonitor(), calendar: calendar, codex: nil,
            appModel: withOffModel, settings: settings, visibility: MenuBarPanelVisibility(),
            maxHeight: 700, onClose: {})
        let emptyHost = NSHostingView(rootView: withoutView)
        emptyHost.layoutSubtreeIfNeeded()
        XCTAssertEqual(host.fittingSize.height, emptyHost.fittingSize.height, accuracy: 1,
                       "connectivity switch off must hide the whole device line")
    }
}

@MainActor
final class DeviceBatteryRowCombinationLayoutTests: XCTestCase {
    func testStatsAndCodexCombinationsKeepDeviceRowInside400Points() {
        let row = DeviceBatteryRowData(deviceID: "airpods", name: "AirPods 3",
                                       ears: "全部85%", caseText: "盒--%",
                                       accessibility: "AirPods 3")
        let snapshot = SystemMonitor.Snapshot(
            memory: .init(total: 32 * 1_073_741_824, used: 20 * 1_073_741_824),
            uptime: "已运行 2 天")
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let codex = CodexUsageSnapshot(
            status: .ready,
            fiveHour: CodexQuotaWindow(usedPercent: 21, resetsAt: now.addingTimeInterval(3600)),
            week: CodexQuotaWindow(usedPercent: 3, resetsAt: now.addingTimeInterval(86_400)),
            resetAvailableCount: 2, resetCredits: [], observedAt: now, message: nil)
        for showsStats in [true, false] {
            for codexValue in [nil, codex] as [CodexUsageSnapshot?] {
                let withDevice = MonitorSummaryCard(snapshot: snapshot, codex: codexValue,
                                                    device: row, showsStats: showsStats)
                let host = NSHostingView(rootView: withDevice)
                host.layoutSubtreeIfNeeded()
                XCTAssertLessThanOrEqual(host.fittingSize.width, 400.5,
                                         "stats=\(showsStats) codex=\(codexValue != nil) overflow")

                let withoutDevice = MonitorSummaryCard(snapshot: snapshot, codex: codexValue,
                                                       device: nil, showsStats: showsStats)
                let emptyHost = NSHostingView(rootView: withoutDevice)
                emptyHost.layoutSubtreeIfNeeded()
                XCTAssertGreaterThan(host.fittingSize.height, emptyHost.fittingSize.height + 8,
                                     "device row missing for stats=\(showsStats) codex=\(codexValue != nil)")
            }
        }
    }
}

@MainActor
final class DeviceBatteryCaseAndNameTests: XCTestCase {
    private func device(_ name: String = "AirPods 3",
                        left: Int? = 85, right: Int? = 85, single: Int? = nil,
                        caseBattery: Int? = nil, modelUID: String = "2013 4c",
                        isAirPods: Bool = true) -> AudioDevice {
        AudioDevice(id: name, name: name, left: left, right: right, single: single,
                    active: true, isAirPods: isAirPods, modelUID: modelUID,
                    caseBattery: caseBattery)
    }

    func testCaseBatteryRules() {
        XCTAssertEqual(DeviceBatteryRow.data(devices: [device(caseBattery: 62)], enabled: true)?.caseText,
                       "盒62%")
        XCTAssertEqual(DeviceBatteryRow.data(devices: [device(caseBattery: 0)], enabled: true)?.caseText,
                       "盒0%")
        XCTAssertEqual(DeviceBatteryRow.data(devices: [device(caseBattery: 100)], enabled: true)?.caseText,
                       "盒100%")
        XCTAssertEqual(DeviceBatteryRow.data(devices: [device(caseBattery: 101)], enabled: true)?.caseText,
                       "盒--%")
        XCTAssertEqual(DeviceBatteryRow.data(devices: [device(caseBattery: -1)], enabled: true)?.caseText,
                       "盒--%")
        XCTAssertEqual(DeviceBatteryRow.data(devices: [device()], enabled: true)?.caseText,
                       "盒--%")
    }

    func testMaxNeverPromotesSingleIntoCase() {
        let max = device("AirPods Max", left: nil, right: nil, single: 85,
                         caseBattery: 80, modelUID: "200a")
        let row = DeviceBatteryRow.data(devices: [max], enabled: true)
        XCTAssertEqual(row?.ears, "全部85%")
        XCTAssertEqual(row?.caseText, "盒--%")
    }

    func testGenerationNamesAndRealNameFallback() {
        let cases: [(String, String)] = [
            ("2002 4c", "AirPods"), ("200f 4c", "AirPods 2"),
            ("2013 4c", "AirPods 3"), ("201b 4c", "AirPods 4"),
            ("200e 4c", "AirPods Pro"), ("2014 4c", "AirPods Pro 2"),
            ("2027 4c", "AirPods Pro 3"), ("200a 4c", "AirPods Max"),
            ("201f 4c", "AirPods Max 2")
        ]
        for (modelUID, expected) in cases {
            let row = DeviceBatteryRow.data(devices: [device("Raw Bluetooth Name",
                                                             modelUID: modelUID)], enabled: true)
            XCTAssertEqual(row?.name, expected, modelUID)
        }
        let custom = DeviceBatteryRow.data(devices: [device("My AirPods",
                                                            modelUID: "unknown-token")], enabled: true)
        XCTAssertEqual(custom?.name, "My AirPods", "unknown model keeps the real Bluetooth name")
    }

    func testNativeSourceParsesCaseFieldAndRejectsInvalidValues() {
        func row(caseValue: Any?) -> [String: Any] {
            var row: [String: Any] = ["id": "fixture", "name": "AirPods 3",
                                      "left": 85, "right": 78, "single": -1,
                                      "active": true, "airpods": true, "modelUID": "2013 4c"]
            if let caseValue { row["case"] = caseValue }
            return row
        }
        XCTAssertEqual(NativeConnectedAudioSource.device(from: row(caseValue: 62))?.caseBattery, 62)
        XCTAssertEqual(NativeConnectedAudioSource.device(from: row(caseValue: 0))?.caseBattery, 0)
        XCTAssertEqual(NativeConnectedAudioSource.device(from: row(caseValue: 100))?.caseBattery, 100)
        XCTAssertNil(NativeConnectedAudioSource.device(from: row(caseValue: 101))?.caseBattery)
        XCTAssertNil(NativeConnectedAudioSource.device(from: row(caseValue: -1))?.caseBattery)
        XCTAssertNil(NativeConnectedAudioSource.device(from: row(caseValue: 255))?.caseBattery)
        XCTAssertNil(NativeConnectedAudioSource.device(from: row(caseValue: nil))?.caseBattery)
    }

    func testCaseDisappearsWithDisconnectedSnapshot() {
        let suite = "com.wangqing.valora.device-case.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = RevivalSettings(defaults: defaults)
        settings.bluetoothEnabled = true
        let model = AppModel(settings: settings)
        final class Silent: LowBatterySoundPlaying { func playLowBattery() {} }
        final class Empty: ConnectedAudioSource {
            func snapshot() async -> ConnectedAudioSnapshot {
                ConnectedAudioSnapshot(devices: [], output: "")
            }
        }
        let controller = ConnectivityController(model, source: Empty(), sound: Silent())
        controller.verificationApply(ConnectedAudioSnapshot(
            devices: [device(caseBattery: 62)], output: "AirPods"))
        XCTAssertEqual(DeviceBatteryRow.data(devices: model.devices, enabled: true)?.caseText, "盒62%")
        controller.verificationApply(ConnectedAudioSnapshot(devices: [], output: ""))
        XCTAssertNil(DeviceBatteryRow.data(devices: model.devices, enabled: true))
        controller.stop()
    }
}

@MainActor
final class DeviceBatteryProductIDTests: XCTestCase {
    private func row(_ values: [String: Any]) -> [String: Any] {
        var base: [String: Any] = ["id": "fixture", "name": "Custom AirPods",
                                   "active": true, "airpods": false, "modelUID": ""]
        values.forEach { base[$0.key] = $0.value }
        return base
    }

    func testPnPProductIDIdentifiesAirPods3WhenCoreAudioOutputIsSpeaker() {
        let parsed = NativeConnectedAudioSource.device(from: row([
            "productID": 0x2013, "vendorID": 0x004C, "modelUID": "Speaker",
            "name": "Custom AirPods", "left": 85, "right": 78, "case": 62
        ]))
        XCTAssertEqual(parsed?.airPodsModel, .airPods3)
        XCTAssertTrue(parsed?.isAirPods == true)
        let display = parsed.flatMap { DeviceBatteryRow.data(devices: [$0], enabled: true) }
        XCTAssertEqual(display?.name, "AirPods 3")
        XCTAssertEqual(display?.ears, "左85% 右78%")
        XCTAssertEqual(display?.caseText, "盒62%")
    }

    func testSpecificProductIDBeatsGenericCoreAudio2002() {
        let parsed = NativeConnectedAudioSource.device(from: row([
            "productID": 0x2013, "vendorID": 0x004C, "modelUID": "2002 4c"
        ]))
        XCTAssertEqual(parsed?.airPodsModel, .airPods3,
                       "a generic 2002 CoreAudio token must not override the real product ID")
    }

    func testGenericProductID2002RemainsAirPodsWhenItIsTheRealProduct() {
        let parsed = NativeConnectedAudioSource.device(from: row([
            "productID": 0x2002, "vendorID": 0x004C, "modelUID": "2013 4c"
        ]))
        XCTAssertEqual(parsed?.airPodsModel, .airPods)
        XCTAssertEqual(parsed.flatMap { DeviceBatteryRow.data(devices: [$0], enabled: true) }?.name,
                       "AirPods")
    }

    func testNonAppleVendorDoesNotMapProductID() {
        let parsed = NativeConnectedAudioSource.device(from: row([
            "productID": 0x2013, "vendorID": 0x1234, "modelUID": "", "airpods": true
        ]))
        XCTAssertNil(parsed?.airPodsModel)
        let display = parsed.flatMap { DeviceBatteryRow.data(devices: [$0], enabled: true) }
        XCTAssertEqual(display?.name, "Custom AirPods", "unknown model keeps the real Bluetooth name")
    }

    func testInactiveAirPodsIsSelectedWhileSpeakerIsCurrentOutput() {
        let speaker = AudioDevice(id: "speaker", name: "MacBook Speakers", left: nil, right: nil,
                                  single: nil, active: true, isAirPods: false, modelUID: "Speaker")
        let airpods = AudioDevice(id: "airpods", name: "Custom AirPods", left: 85, right: 78,
                                  single: nil, active: false, isAirPods: true,
                                  modelUID: "", caseBattery: 62,
                                  productID: 0x2013, vendorID: 0x004C)
        let display = DeviceBatteryRow.data(devices: [speaker, airpods], enabled: true)
        XCTAssertEqual(display?.deviceID, "airpods")
        XCTAssertEqual(display?.name, "AirPods 3")
    }

    func testUnknownProductIDFallsBackToRealDeviceName() {
        let parsed = NativeConnectedAudioSource.device(from: row([
            "productID": 0x9999, "vendorID": 0x004C, "modelUID": "", "airpods": true,
            "name": "My AirPods"
        ]))
        XCTAssertNil(parsed?.airPodsModel)
        XCTAssertEqual(parsed.flatMap { DeviceBatteryRow.data(devices: [$0], enabled: true) }?.name,
                       "My AirPods")
    }
}

@MainActor
final class DeviceBatteryMetadataCacheTests: XCTestCase {
    private final class Silent: LowBatterySoundPlaying { func playLowBattery() {} }
    private final class Empty: ConnectedAudioSource {
        func snapshot() async -> ConnectedAudioSnapshot {
            ConnectedAudioSnapshot(devices: [], output: "")
        }
    }

    func testTransientMissingProductIDKeepsModelButNotBattery() {
        let suite = "com.wangqing.valora.device-model-cache.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = RevivalSettings(defaults: defaults)
        settings.bluetoothEnabled = true
        let model = AppModel(settings: settings)
        let controller = ConnectivityController(model, source: Empty(), sound: Silent())

        let confirmed = AudioDevice(id: "same", name: "Custom AirPods",
                                    left: 85, right: 78, single: nil,
                                    active: false, isAirPods: true, modelUID: "",
                                    caseBattery: 62, productID: 0x2013, vendorID: 0x004C)
        controller.verificationApply(ConnectedAudioSnapshot(devices: [confirmed], output: "Speaker"))
        XCTAssertEqual(model.devices.first?.airPodsModel, .airPods3)
        XCTAssertEqual(DeviceBatteryRow.data(devices: model.devices, enabled: true)?.name, "AirPods 3")

        // Same stable id, metadata temporarily missing (not worn / intermediate
        // snapshot). The model may be retained by the existing cache; battery
        // must not be.
        let transient = AudioDevice(id: "same", name: "Custom AirPods",
                                    left: nil, right: nil, single: nil,
                                    active: false, isAirPods: true, modelUID: "",
                                    caseBattery: nil, productID: nil, vendorID: nil)
        controller.verificationApply(ConnectedAudioSnapshot(devices: [transient], output: "Speaker"))
        let row = DeviceBatteryRow.data(devices: model.devices, enabled: true)
        XCTAssertEqual(row?.name, "AirPods 3", "confirmed model survives a transient metadata gap")
        XCTAssertEqual(row?.ears, "左--% 右--%", "battery must not be cached")
        XCTAssertEqual(row?.caseText, "盒--%", "case battery must not be cached")

        controller.verificationApply(ConnectedAudioSnapshot(devices: [], output: ""))
        XCTAssertNil(DeviceBatteryRow.data(devices: model.devices, enabled: true),
                     "disconnect hides the row even though model metadata may remain cached")
        controller.stop()
    }
}
