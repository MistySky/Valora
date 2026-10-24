import AppKit
import Combine
import Foundation
import ReferenceCore
import SwiftUI
import ReferenceCore

@MainActor
protocol LowBatterySoundPlaying: AnyObject {
    func playLowBattery()
    func stopLowBattery()
}

extension LowBatterySoundPlaying {
    /// Existing test doubles may not need a stop hook; production overrides it.
    func stopLowBattery() {}
}

@MainActor
final class AppKitLowBatterySound: NSObject, NSSoundDelegate, LowBatterySoundPlaying {
    private var sound: NSSound?

    func playLowBattery() {
        stopLowBattery()
        guard let url = Bundle.main.url(forResource: "low-battery", withExtension: "caf",
                                        subdirectory: "Sounds"),
              let sound = NSSound(contentsOf: url, byReference: true) else { return }
        self.sound = sound
        sound.delegate = self
        sound.play()
    }

    func stopLowBattery() {
        sound?.stop()
        sound = nil
    }

    func sound(_ sound: NSSound, didFinishPlaying flag: Bool) {
        if self.sound === sound { self.sound = nil }
    }
}

/// Read-only AirPods connection/battery notification controller.
///
/// The source query runs off-main and at most one query is in flight. Turning
/// the switch off, stopping, or changing generations invalidates late results;
/// those results cannot reopen the toast. The 3s poll is the recovered feature
/// clock; it is not the removed automation/heartbeat timer.
@MainActor
final class ConnectivityController {
    unowned let model: AppModel
    private let source: any ConnectedAudioSource
    private let sound: any LowBatterySoundPlaying
    private let authorizationGate: () -> Bool
    private var timer: Timer?
    private var queryTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?
    private var subscriptions = Set<AnyCancellable>()
    private var known = Set<String>()
    private var didRead = false
    private var queryGeneration: UInt64 = 0
    private var queryInFlight = false
    private var toastGeneration: UInt64 = 0
    private var batteryAlerts = DeviceBatteryAlertState()
    private var started = false
    private var pollingEnabled = true

    init(_ model: AppModel,
         source: any ConnectedAudioSource = NativeConnectedAudioSource(),
         sound: any LowBatterySoundPlaying = AppKitLowBatterySound(),
         authorizationGate: @escaping () -> Bool = { true }) {
        self.model = model
        self.source = source
        self.sound = sound
        self.authorizationGate = authorizationGate
    }

    func start(polling: Bool = true) {
        guard !started else { return }
        started = true
        pollingEnabled = polling
        model.settings.$bluetoothEnabled
            .removeDuplicates()
            .dropFirst()
            // @Published emits in willSet. Defer the work until the stored
            // property commits, otherwise an initial query reads the old value.
            .sink { [weak self] enabled in
                MainActor.assumeIsolated { self?.setEnabled(enabled, deferInitialRead: true) }
            }
            .store(in: &subscriptions)
        setEnabled(model.settings.bluetoothEnabled)
    }

    func stop() {
        guard started else { return }
        started = false
        pollingEnabled = false
        timer?.invalidate()
        timer = nil
        queryTask?.cancel()
        queryTask = nil
        queryGeneration &+= 1
        toastTask?.cancel()
        toastTask = nil
        toastGeneration &+= 1
        subscriptions.removeAll()
        sound.stopLowBattery()
        known = []
        didRead = false
        batteryAlerts = DeviceBatteryAlertState()
        model.devices = []
        model.connectionToast = nil
        model.connectionLowBattery = false
        model.connectionArrivalGeneration &+= 1
    }

    /// Manual/poll query entry. One in-flight query is a hard bound; a hung
    /// synchronous IOBluetooth read cannot create a second concurrent query.
    func refresh() {
        guard started, authorizationGate(), model.settings.bluetoothEnabled,
              !model.previewMode, queryTask == nil, !queryInFlight else { return }
        let generation = queryGeneration
        queryInFlight = true
        queryTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let snapshot = await self.source.snapshot()
            let stillCurrent = !Task.isCancelled
                && self.queryGeneration == generation
                && self.model.settings.bluetoothEnabled
                && !self.model.previewMode
            self.queryInFlight = false
            if stillCurrent { self.queryTask = nil }
            guard stillCurrent else {
                // A stop/restart may have happened while a non-cooperative
                // native read was outstanding. Only after it returns may the
                // new generation start its one allowed query.
                if self.started, self.model.settings.bluetoothEnabled, self.pollingEnabled {
                    self.refresh()
                }
                return
            }
            self.applySnapshot(snapshot)
        }
    }

    /// Explicit user hand action: run one read even while the total switch is
    /// off or authorization is unknown. This is the only path that can cause
    /// the native API to surface its system authorization UI. Its result is
    /// intentionally not applied as a device/toast snapshot.
    func requestAccessProbe() {
        guard started, !model.previewMode, queryTask == nil, !queryInFlight else { return }
        let generation = queryGeneration
        queryInFlight = true
        queryTask = Task { @MainActor [weak self] in
            guard let self else { return }
            _ = await self.source.snapshot()
            self.queryInFlight = false
            if self.queryGeneration == generation { self.queryTask = nil }
        }
    }

    /// QA seam: applies a synthetic read-only snapshot without touching the
    /// native source. Still honors the total-switch gate.
    func verificationApply(_ snapshot: ConnectedAudioSnapshot) {
        guard model.settings.bluetoothEnabled else { return }
        applySnapshot(snapshot)
    }

    var verificationKnownIDs: Set<String> { known }

    private func setEnabled(_ enabled: Bool, deferInitialRead: Bool = false) {
        guard started else { return }
        timer?.invalidate()
        timer = nil
        queryGeneration &+= 1
        queryTask?.cancel()
        queryTask = nil
        toastTask?.cancel()
        toastTask = nil
        toastGeneration &+= 1
        sound.stopLowBattery()
        known = []
        didRead = false
        batteryAlerts = DeviceBatteryAlertState()
        model.connectionToast = nil
        model.connectionLowBattery = false
        model.connectionArrivalGeneration &+= 1
        if enabled {
            model.devices = []
            if pollingEnabled {
                if deferInitialRead {
                    // @Published emits in willSet; defer only the initial read
                    // until the stored value is committed, matching the
                    // mature controller's timing.
                    DispatchQueue.main.async { [weak self] in
                        MainActor.assumeIsolated {
                            guard let self, self.started,
                                  self.model.settings.bluetoothEnabled else { return }
                            self.refresh()
                        }
                    }
                } else {
                    refresh()
                }
                timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated { self?.refresh() }
                }
            }
        } else {
            model.devices = []
            model.connectionToast = nil
            model.connectionLowBattery = false
        }
    }

    private func applySnapshot(_ snapshot: ConnectedAudioSnapshot) {
        guard model.settings.bluetoothEnabled, !model.previewMode else { return }
        let devices = snapshot.devices
        let ids = Set(devices.map(\.id))
        let fresh = devices.first { !known.contains($0.id) && $0.isAirPods }
        model.devices = devices
        model.audioOutput = snapshot.output
        let preferences = model.settings.connectivityPreferences

        var lowDevice: AudioDevice?
        for device in devices {
            let alert = batteryAlerts.update(id: device.id, battery: device.battery,
                                             threshold: preferences.lowBatteryThreshold)
            if alert, lowDevice == nil { lowDevice = device }
        }
        for id in known.subtracting(ids) { batteryAlerts.remove(id: id) }

        if let lowDevice, preferences.warnOnLowBattery {
            showLowBattery(lowDevice)
        }

        if let current = model.connectionToast {
            if let latest = devices.first(where: { $0.id == current.id }) {
                // Metadata/battery arriving later updates the current asset
                // without replaying arrival or extending the fixed duration.
                if latest != current { model.connectionToast = latest }
            } else {
                toastGeneration &+= 1
                toastTask?.cancel(); toastTask = nil
                withAnimation(.spring(duration: 0.4, bounce: 0)) {
                    model.connectionToast = nil
                    model.connectionLowBattery = false
                }
            }
        }
        if let fresh, didRead {
            showConnection(fresh)
        }
        known = ids
        didRead = true
    }

    private func showConnection(_ device: AudioDevice) {
        model.presenter.cancelPeek()
        toastTask?.cancel()
        toastGeneration &+= 1
        let generation = toastGeneration
        model.connectionArrivalGeneration &+= 1
        model.connectionLowBattery = false
        withAnimation(.spring(duration: 0.45, bounce: 0.1)) {
            model.connectionToast = device
        }
        toastTask = scheduleDismiss(generation: generation,
                                    duration: model.settings.connectivityPreferences.duration)
    }

    private func showLowBattery(_ device: AudioDevice) {
        model.presenter.cancelPeek()
        toastTask?.cancel()
        toastGeneration &+= 1
        let generation = toastGeneration
        model.connectionArrivalGeneration &+= 1
        if model.settings.connectivityPreferences.playSoundOnLowBattery {
            sound.playLowBattery()
        }
        withAnimation(.spring(duration: 0.45, bounce: 0.1)) {
            model.connectionToast = device
            model.connectionLowBattery = true
        }
        toastTask = scheduleDismiss(generation: generation,
                                    duration: model.settings.connectivityPreferences.duration)
    }

    private func scheduleDismiss(generation: UInt64, duration: Double) -> Task<Void, Never> {
        Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(max(0, duration) * 1_000_000_000))
            } catch { return }
            guard let self, !Task.isCancelled, self.toastGeneration == generation else { return }
            withAnimation(.spring(duration: 0.4, bounce: 0)) {
                self.model.connectionToast = nil
                self.model.connectionLowBattery = false
            }
        }
    }

    isolated deinit {
        timer?.invalidate()
        queryTask?.cancel()
        toastTask?.cancel()
        sound.stopLowBattery()
    }
}
