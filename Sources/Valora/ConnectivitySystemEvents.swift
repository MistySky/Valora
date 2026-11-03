import CoreAudio
import Foundation
import IOBluetooth

/// Small event source layered over the existing 3 s fallback poll. It only
/// registers for system CoreAudio/Bluetooth notifications; it never scans,
/// pairs, selects an output, or reads a device by itself.
@MainActor
final class ConnectivitySystemEvents: NSObject {
    var onChange: (() -> Void)?
    var onConnect: ((String) -> Void)?

    private var connectNotification: IOBluetoothUserNotification?
    private var listeners: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    private var debounceTask: Task<Void, Never>?

    func start() {
        guard connectNotification == nil else { return }
        connectNotification = IOBluetoothDevice.register(
            forConnectNotifications: self,
            selector: #selector(bluetoothConnected(_:device:)))
        addAudioListener(kAudioHardwarePropertyDefaultOutputDevice)
        addAudioListener(kAudioHardwarePropertyDevices)
    }

    func stop() {
        debounceTask?.cancel()
        debounceTask = nil
        connectNotification?.unregister()
        connectNotification = nil
        for (address, block) in listeners {
            var mutable = address
            _ = AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &mutable, DispatchQueue.main, block)
        }
        listeners.removeAll()
    }

    // IOBluetooth invokes this Objective-C selector on its coordinator queue,
    // NOT the main actor. Copy only Sendable values before hopping to MainActor.
    @objc nonisolated private func bluetoothConnected(_ notification: IOBluetoothUserNotification,
                                                      device: IOBluetoothDevice) {
        let address = (device.addressString ?? "")
            .lowercased()
            .components(separatedBy: CharacterSet(charactersIn: "-: "))
            .joined()
        let identity = ObjectIdentifier(notification)
        Task { @MainActor [weak self] in
            guard let self, let current = self.connectNotification,
                  ObjectIdentifier(current) == identity else { return }
            if !address.isEmpty { self.onConnect?(address) }
            self.schedule()
        }
    }

    private func addAudioListener(_ selector: AudioObjectPropertySelector) {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.schedule() }
            }
        }
        if AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, block) == noErr {
            listeners.append((address, block))
        }
    }

    private func schedule() {
        debounceTask?.cancel()
        debounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard let self, !Task.isCancelled else { return }
            self.onChange?()
        }
    }

    isolated deinit {
        stop()
    }
}
