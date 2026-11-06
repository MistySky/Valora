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
    private let nativeSource: Bool
    private let sound: any LowBatterySoundPlaying
    private let authorizationGate: () -> Bool
    private let systemEvents = ConnectivitySystemEvents()
    private var timer: Timer?
    private var queryTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?
    private var subscriptions = Set<AnyCancellable>()
    private var known = Set<String>()
    // Keep explicit connections until the matching AirPods metadata is ready.
    // A generic early snapshot must not consume the arrival; expire stale intent.
    private var pendingConnections: [String: TimeInterval] = [:]
    /// Last known metadata is keyed by the stable native id. A transient
    /// missing modelUID/name must not turn the existing AirPods toast into a
    /// generic headphone icon, while a different id never inherits it.
    private var metadataCache: [String: (modelUID: String, name: String, isAirPods: Bool,
                                         productID: UInt16?, vendorID: UInt16?)] = [:]
    private var lastActiveAirPodsIDs = Set<String>()
    private var lastActiveAudioID: String?
    private let clock: () -> TimeInterval
    private var didRead = false
    private var queryGeneration: UInt64 = 0
    private var eventRevision: UInt64 = 0
    private var pendingRefresh = false
    private var queryInFlight = false
    private var toastGeneration: UInt64 = 0
    private var batteryAlerts = DeviceBatteryAlertState()
    private var started = false
    private var pollingEnabled = true

    init(_ model: AppModel,
         source: any ConnectedAudioSource = NativeConnectedAudioSource(),
         sound: any LowBatterySoundPlaying = AppKitLowBatterySound(),
         authorizationGate: @escaping () -> Bool = { true },
         clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.model = model
        self.source = source
        self.nativeSource = source is NativeConnectedAudioSource
        self.sound = sound
        self.authorizationGate = authorizationGate
        self.clock = clock
        systemEvents.onConnect = { [weak self] address in
            // Bluetooth may connect before CoreAudio supplies the model UID.
            // Preserve this explicit intent across intermediate snapshots.
            guard let self, self.started, self.model.settings.bluetoothEnabled else { return }
            guard !address.isEmpty else { return }
            let now = self.clock()
            self.pendingConnections = self.pendingConnections.filter { $0.value > now }
            self.pendingConnections[address] = now + 10
            self.noteEvent()
        }
        systemEvents.onChange = { [weak self] in
            guard let self, self.started, self.model.settings.bluetoothEnabled else { return }
            self.noteEvent()
        }
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
        systemEvents.stop()
        queryTask?.cancel()
        queryTask = nil
        queryGeneration &+= 1
        eventRevision &+= 1
        pendingRefresh = false
        toastTask?.cancel()
        toastTask = nil
        toastGeneration &+= 1
        subscriptions.removeAll()
        sound.stopLowBattery()
        known = []
        pendingConnections.removeAll()
        metadataCache.removeAll()
        lastActiveAirPodsIDs.removeAll()
        lastActiveAudioID = nil
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
              !model.previewMode else { return }
        if queryTask != nil || queryInFlight {
            // A normal poll must not queue another read. Event-driven callers
            // set pendingRefresh before calling this; retain that one flag.
            return
        }
        // Register notifications only after the same authorization gate that
        // permits a read. Registration itself does not scan or query devices.
        if nativeSource { systemEvents.start() }
        pendingRefresh = false
        let generation = queryGeneration
        let revision = eventRevision
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
            // A connect/output event invalidates this snapshot even if it
            // arrived while the read was already running. Do not let the old
            // read consume the new device's freshness marker.
            if self.eventRevision == revision {
                self.applySnapshot(snapshot)
            }
            if self.pendingRefresh {
                self.pendingRefresh = false
                self.refresh()
            }
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

    private func noteEvent() {
        guard started, model.settings.bluetoothEnabled, !model.previewMode else { return }
        eventRevision &+= 1
        pendingRefresh = true
        refresh()
    }

    private func setEnabled(_ enabled: Bool, deferInitialRead: Bool = false) {
        guard started else { return }
        timer?.invalidate()
        timer = nil
        queryGeneration &+= 1
        eventRevision &+= 1
        pendingRefresh = false
        queryTask?.cancel()
        queryTask = nil
        toastTask?.cancel()
        toastTask = nil
        toastGeneration &+= 1
        systemEvents.stop()
        sound.stopLowBattery()
        known = []
        pendingConnections.removeAll()
        metadataCache.removeAll()
        lastActiveAirPodsIDs.removeAll()
        lastActiveAudioID = nil
        didRead = false
        batteryAlerts = DeviceBatteryAlertState()
        model.connectionToast = nil
        model.connectionLowBattery = false
        model.connectionArrivalGeneration &+= 1
        if enabled {
            model.devices = []
            if nativeSource, authorizationGate() {
                systemEvents.start()
            }
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

    private func mergeMetadata(_ devices: [AudioDevice]) -> [AudioDevice] {
        var merged: [AudioDevice] = []
        for original in devices {
            var device = original
            if let cached = metadataCache[device.id] {
                if device.modelUID.isEmpty { device.modelUID = cached.modelUID }
                if device.name.isEmpty || device.name == "Bluetooth device" {
                    device.name = cached.name
                }
                if !device.isAirPods && cached.isAirPods { device.isAirPods = true }
                // Model identity only. Battery is never cached: a later snapshot
                // with missing percentages must show "--%" rather than stale data.
                if device.productID == nil { device.productID = cached.productID }
                if device.vendorID == nil { device.vendorID = cached.vendorID }
            }
            if !device.modelUID.isEmpty || device.isAirPods || device.productID != nil {
                metadataCache[device.id] = (device.modelUID, device.name, device.isAirPods,
                                            device.productID, device.vendorID)
            }
            merged.append(device)
        }
        if metadataCache.count > 16 {
            let keep = Set(merged.map(\.id))
            metadataCache = metadataCache.filter { keep.contains($0.key) }
        }
        return merged
    }

    private func applySnapshot(_ snapshot: ConnectedAudioSnapshot) {
        guard model.settings.bluetoothEnabled, !model.previewMode else { return }
        let devices = mergeMetadata(snapshot.devices)
        let ids = Set(devices.map(\.id))
        let now = clock()
        pendingConnections = pendingConnections.filter { $0.value > now }
        // A wearing/route transition is an active AirPods output becoming
        // active after being absent/inactive. A connected-but-not-active
        // earbud is not a wear event and must not consume the arrival.
        // Trigger decisions use the raw snapshot: cached metadata may keep a
        // current toast's artwork stable, but must not make a generic early
        // snapshot look like a recognized AirPods arrival.
        let rawActiveAirPods = snapshot.devices.filter { $0.isAirPods && $0.active }
        let rawActiveAirPodsIDs = Set(rawActiveAirPods.map(\.id))
        let newActiveAirPods = rawActiveAirPodsIDs.subtracting(lastActiveAirPodsIDs)
        let activeAudioID = snapshot.devices.first(where: { $0.active })?.id
        let transitionAirPods = rawActiveAirPods.first { device in
            pendingConnections[device.id] != nil
                || (didRead && newActiveAirPods.contains(device.id)
                    && lastActiveAudioID != device.id)
        }
        lastActiveAirPodsIDs = rawActiveAirPodsIDs
        lastActiveAudioID = activeAudioID
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
        if let transitionAirPods {
            let display = devices.first(where: { $0.id == transitionAirPods.id }) ?? transitionAirPods
            pendingConnections.removeValue(forKey: transitionAirPods.id)
            showConnection(display)
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
