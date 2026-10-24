import Foundation

/// Edge-triggered AirPods/Bluetooth battery warning. The first snapshot is
/// learned without replaying a warning; a device alerts once when it crosses
/// the configured threshold and re-arms after recovering above it.
public struct DeviceBatteryAlertState {
    private var previous: [String: Int] = [:]
    private var alerted: Set<String> = []

    public init() {}

    public mutating func update(id: String, battery: Int?, threshold: Int) -> Bool {
        guard let battery else {
            previous[id] = nil
            alerted.remove(id)
            return false
        }
        let old = previous[id]
        previous[id] = battery
        if battery > threshold {
            alerted.remove(id)
            return false
        }
        guard !alerted.contains(id), let old, old > threshold else { return false }
        alerted.insert(id)
        return true
    }

    public mutating func remove(id: String) {
        previous[id] = nil
        alerted.remove(id)
    }
}
