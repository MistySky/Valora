import Foundation
import CoreBluetooth
import NativeBridge
import ReferenceCore

/// Sendable snapshot crossing from the bounded native query queue to the
/// MainActor controller. No AppKit objects are stored in AudioDevice.
struct ConnectedAudioSnapshot: Sendable {
    var devices: [AudioDevice]
    var output: String
}

protocol ConnectedAudioSource: Sendable {
    func snapshot() async -> ConnectedAudioSnapshot
}

/// IOBluetooth can block while initializing its service. The synchronous
/// IOBluetooth/CoreAudio read runs on one utility queue; the controller keeps
/// at most one such request in flight and ignores expired generations.
final class NativeConnectedAudioSource: ConnectedAudioSource, @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.wangqing.valora.connectivity.devices",
                                      qos: .utility)

    // Only an explicitly marked local acceptance bundle may write up to
    // three sanitized readings. All state is confined to the utility queue.
    private var acceptanceSamples: [[String: Int]] = []
    private var acceptanceStartedAt: TimeInterval?

    func snapshot() async -> ConnectedAudioSnapshot {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: self.read())
            }
        }
    }

    private func read() -> ConnectedAudioSnapshot {
        let raw = ARConnectedAudioDevices() as? [[String: Any]] ?? []
        func validBattery(_ value: Any?) -> Int? {
            guard let number = value as? NSNumber else { return nil }
            let battery = number.intValue
            return (0...100).contains(battery) ? battery : nil
        }
        func validString(_ value: Any?) -> String {
            (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        var devices: [AudioDevice] = []
        for row in raw {
            let name = validString(row["name"])
            let modelUID = validString(row["modelUID"])
            let id = validString(row["id"]).isEmpty
                ? "\(name)\u{0}\(modelUID)" : validString(row["id"])
            guard !id.isEmpty else { continue }
            let isAirPods = (row["airpods"] as? Bool ?? false)
                || AirPodsModel.identify(modelUID: modelUID) != nil
            devices.append(AudioDevice(
                id: id, name: name.isEmpty ? "Bluetooth device" : name,
                left: validBattery(row["left"]), right: validBattery(row["right"]),
                single: validBattery(row["single"]),
                active: row["active"] as? Bool ?? false,
                isAirPods: isAirPods, modelUID: modelUID,
                rawColorID: (row["colorID"] as? NSNumber)?.intValue))
        }
        recordAcceptanceSample(devices)
        return ConnectedAudioSnapshot(devices: devices, output: ARDefaultAudioOutputName())
    }
    private func recordAcceptanceSample(_ devices: [AudioDevice]) {
        guard Bundle.main.object(forInfoDictionaryKey: "ValoraDeviceAcceptanceSample") as? Bool == true,
              CBManager.authorization == .allowedAlways,
              acceptanceSamples.count < 3 else { return }
        guard let device = devices.first(where: { $0.active && $0.isAirPods }) else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if acceptanceStartedAt == nil { acceptanceStartedAt = now }
        guard now - (acceptanceStartedAt ?? now) < 10 else { return }
        // Deliberately excludes name, address, persistent ID and other devices.
        var sample = ["activeAirPods": 1,
                      "elapsedMilliseconds": Int((now - (acceptanceStartedAt ?? now)) * 1000)]
        sample["modelGeneration"] = device.airPodsModel?.rawValue
        sample["left"] = device.left
        sample["right"] = device.right
        sample["single"] = device.single
        sample["displayBattery"] = device.battery
        acceptanceSamples.append(sample)
        let directory = URL(fileURLWithPath: "/private/tmp/valora-v0035-device-acceptance", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
            let data = try JSONSerialization.data(withJSONObject: acceptanceSamples, options: [.prettyPrinted, .sortedKeys])
            let file = directory.appendingPathComponent("readings.json")
            try data.write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        } catch { /* Diagnostics cannot affect normal recognition or playback. */ }
    }

}
