import Foundation
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

    func snapshot() async -> ConnectedAudioSnapshot {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: Self.read())
            }
        }
    }

    private static func read() -> ConnectedAudioSnapshot {
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
        return ConnectedAudioSnapshot(devices: devices, output: ARDefaultAudioOutputName())
    }
}
