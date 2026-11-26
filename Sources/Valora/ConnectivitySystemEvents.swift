import CoreAudio
import Foundation
import IOBluetooth

protocol BluetoothConnectionNotification: AnyObject {
    func unregister()
}

extension IOBluetoothUserNotification: BluetoothConnectionNotification {}

/// Small event source layered over the existing 3 s fallback poll. It only
/// registers for system CoreAudio/Bluetooth notifications; it never scans,
/// pairs, selects an output, or reads a device by itself.
@MainActor
final class ConnectivitySystemEvents: NSObject {
    typealias RegisterConnection = @MainActor (ConnectivitySystemEvents, Selector) -> (any BluetoothConnectionNotification)?
    typealias ObserveAudio = @MainActor (AudioObjectPropertySelector, @escaping AudioObjectPropertyListenerBlock) -> (() -> Void)?

    var onChange: (() -> Void)?
    var onConnect: ((String) -> Void)?

    private let registerConnection: RegisterConnection
    private let observeAudio: ObserveAudio
    private var connectNotification: (any BluetoothConnectionNotification)?
    private var removeListeners: [AudioObjectPropertySelector: () -> Void] = [:]
    private var generation = 0
    private var debounceTask: Task<Void, Never>?

    init(registerConnection: @escaping RegisterConnection = {
        IOBluetoothDevice.register(forConnectNotifications: $0, selector: $1)
    }, observeAudio: @escaping ObserveAudio = ConnectivitySystemEvents.observeSystemAudio) {
        self.registerConnection = registerConnection
        self.observeAudio = observeAudio
    }

    func start() {
        if connectNotification == nil {
            connectNotification = registerConnection(self, #selector(bluetoothConnected(_:device:)))
        }
        addMissingAudioListener(kAudioHardwarePropertyDefaultOutputDevice)
        addMissingAudioListener(kAudioHardwarePropertyDevices)
    }

    func stop() {
        generation &+= 1
        debounceTask?.cancel()
        debounceTask = nil
        connectNotification?.unregister()
        connectNotification = nil
        for remove in removeListeners.values { remove() }
        removeListeners.removeAll()
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

    private func addMissingAudioListener(_ selector: AudioObjectPropertySelector) {
        guard removeListeners[selector] == nil else { return }
        let registration = generation
        removeListeners[selector] = observeAudio(selector) { [weak self] _, _ in
            DispatchQueue.main.async {
                // CoreAudio may have queued a delivery before removal.
                guard let self, self.generation == registration else { return }
                self.schedule()
            }
        }
    }

    private static func observeSystemAudio(_ selector: AudioObjectPropertySelector,
                                           block: @escaping AudioObjectPropertyListenerBlock) -> (() -> Void)? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, block) == noErr else { return nil }
        return {
            _ = AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, block)
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
