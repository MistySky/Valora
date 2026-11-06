import SwiftUI
import ReferenceCore

/// Pure data for the device line inside the monitor summary card. It reads only
/// the controller's current snapshot (`model.devices`), never the connection
/// toast/metadata cache, so a disconnected device cannot keep showing an old
/// battery value.
struct DeviceBatteryRowData: Equatable {
    let deviceID: String
    /// Model name shown first; truncates before the values.
    let name: String
    /// Second column: "全部85%" when both sides equal, "左85% 右78%" otherwise,
    /// "全部85%" for Max; missing sides use "--%".
    let ears: String
    /// Third column: "盒62%" for a real case reading, otherwise "盒--%".
    let caseText: String
    let accessibility: String
}

enum DeviceBatteryRow {
    static func data(devices: [AudioDevice], enabled: Bool) -> DeviceBatteryRowData? {
        guard enabled else { return nil }
        // Reliable headphones only: recognized AirPods. The native source also
        // returns connected non-audio Bluetooth devices; a random battery
        // reading must not promote an MX Master or similar into this row.
        let candidates = devices.filter(isRecognizedAirPods)
        guard let device = candidates.first(where: { $0.active }) ?? candidates.first else {
            return nil
        }
        let isMax = device.airPodsModel == .max || device.airPodsModel == .max2
        let displayName = device.airPodsModel?.displayName ?? device.name
        let caseText: String
        let caseAccessibility: String
        if isMax {
            // Max has no charging case; a single-device reading must never be
            // promoted into the case column.
            caseText = "盒--%"
            caseAccessibility = "无充电盒"
        } else if let caseValue = valid(device.caseBattery) {
            caseText = "盒\(caseValue)%"
            caseAccessibility = "盒电量\(caseValue)%"
        } else {
            caseText = "盒--%"
            caseAccessibility = "盒电量不可用"
        }
        let ears: String
        var accessibleValues: String
        if isMax {
            // AirPods Max gives one whole-device reading.
            let token = valid(device.single).map { "\($0)%" } ?? "--%"
            ears = "全部\(token)"
            accessibleValues = token == "--%" ? "整机电量不可用"
                : "整机电量\(token)（整机共享读数）"
        } else {
            let leftValue = valid(device.left)
            let rightValue = valid(device.right)
            switch (leftValue, rightValue) {
            case let (left?, right?):
                if left == right {
                    ears = "全部\(left)%"
                    accessibleValues = "全部电量\(left)%"
                } else {
                    ears = "左\(left)% 右\(right)%"
                    accessibleValues = "左\(left)%，右\(right)%"
                }
            case let (left?, nil):
                ears = "左\(left)% 右--%"
                accessibleValues = "左\(left)%，右耳电量不可用"
            case let (nil, right?):
                ears = "左--% 右\(right)%"
                accessibleValues = "左耳电量不可用，右\(right)%"
            case (nil, nil):
                ears = "左--% 右--%"
                accessibleValues = "左右耳电量均不可用"
            }
        }
        accessibleValues += "，\(caseAccessibility)"
        return DeviceBatteryRowData(
            deviceID: device.id,
            name: displayName,
            ears: ears,
            caseText: caseText,
            accessibility: "\(displayName)，\(accessibleValues)")
    }

    static func isRecognizedAirPods(_ device: AudioDevice) -> Bool {
        if device.isAirPods { return true }
        return AirPodsModel.identify(modelUID: device.modelUID) != nil
    }

    /// 0 is a real reading; nil/negative/>100 are unavailable.
    static func valid(_ value: Int?) -> Int? {
        guard let value, (0...100).contains(value) else { return nil }
        return value
    }

    /// 0 is a real reading; nil/negative/>100 are unavailable, shown as "-".
    static func percent(_ value: Int?) -> String {
        guard let value, (0...100).contains(value) else { return "-" }
        return "\(value)%"
    }
}
