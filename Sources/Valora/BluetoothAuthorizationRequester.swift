import CoreBluetooth
import Foundation

/// Public CoreBluetooth authorization entry used only after the user clicks
/// the Connectivity switch. Creating a central manager is what lets macOS
/// present its Bluetooth privacy prompt; no scan, connect or device read is
/// started. IOBluetooth reads happen only after this requester reports a
/// resolved authorization and the settings gate is on.
@MainActor
final class BluetoothAuthorizationRequester: NSObject, CBCentralManagerDelegate {
    private var manager: CBCentralManager?
    private var completion: (() -> Void)?

    func request(completion: @escaping () -> Void) {
        guard manager == nil else { return }
        self.completion = completion
        manager = CBCentralManager(
            delegate: self,
            queue: .main,
            options: [CBCentralManagerOptionShowPowerAlertKey: false])
    }

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        // CoreBluetooth can deliver delegate callbacks outside the main actor.
        guard CBManager.authorization != .notDetermined else { return }
        Task { @MainActor [weak self] in self?.finish() }
    }

    private func finish() {
        manager?.delegate = nil
        manager = nil
        let callback = completion
        completion = nil
        callback?()
    }
}
