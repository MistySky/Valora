import AppKit
import NativeBridge
import ReferenceCore

@MainActor
protocol AudioWriteTask: AnyObject {
    func cancel()
}

@MainActor
protocol AudioWriteScheduling: AnyObject {
    func schedule(after seconds: TimeInterval, _ action: @escaping @MainActor () -> Void) -> AudioWriteTask
}

@MainActor
private final class DispatchAudioWriteTask: AudioWriteTask {
    private let item: DispatchWorkItem
    init(_ item: DispatchWorkItem) { self.item = item }
    func cancel() { item.cancel() }
}

@MainActor
private final class DispatchAudioWriteScheduler: AudioWriteScheduling {
    func schedule(after seconds: TimeInterval, _ action: @escaping @MainActor () -> Void) -> AudioWriteTask {
        let item = DispatchWorkItem {
            MainActor.assumeIsolated { action() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, seconds), execute: item)
        return DispatchAudioWriteTask(item)
    }
}

struct AudioOutputState: Equatable {
    var uid = "", name = "", modelUID = "", kind = "", port = ""
    var volume = 0.0
    var muted = false, canMute = false, canSetVolume = false
    var effectivelyMuted: Bool { muted || volume <= 0 }
    var volumeButtonSymbol: String { effectivelyMuted ? "speaker.slash.fill" : "speaker.wave.1.fill" }
    var symbol: String {
        if let model = AirPodsModel.identify(modelUID: modelUID) {
            if NSImage(systemSymbolName: model.symbol, accessibilityDescription: nil) != nil { return model.symbol }
            return model.fallbackSymbol ?? "airpods"
        }
        let text = (name + " " + port).lowercased()
        if text.contains("airpods max") { return "airpodsmax" }
        if text.contains("airpods pro") { return "airpods.pro" }
        if text.contains("airpods") { return "airpods" }
        if text.contains("headphone") || text.contains("耳机") || kind == "bluetooth" { return "headphones" }
        return kind == "builtIn" ? (ARComputerIsPortable() ? "laptopcomputer" : "desktopcomputer") : "hifispeaker"
    }
}

@MainActor
final class AudioOutputController {
    unowned let model: AppModel
    private var timer: Timer?
    private var lastAudible: [String: Double] = [:]
    private var pendingWrite: AudioWriteTask?
    private var pendingRefresh: AudioWriteTask?
    private var localTarget: Double?
    private var suppressionUntil: TimeInterval = 0
    private let volumeWriter: (String, Double) -> Bool
    private let muteWriter: (String, Bool) -> Bool
    private let scheduler: AudioWriteScheduling
    init(_ model: AppModel,
         volumeWriter: @escaping (String, Double) -> Bool = { ARSetOutputVolume($0, $1) },
         muteWriter: @escaping (String, Bool) -> Bool = { ARSetOutputMuted($0, $1) },
         scheduler: AudioWriteScheduling? = nil) {
        self.model = model
        self.volumeWriter = volumeWriter
        self.muteWriter = muteWriter
        self.scheduler = scheduler ?? DispatchAudioWriteScheduler()
    }
    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }
    func stop() {
        timer?.invalidate(); timer = nil
        pendingWrite?.cancel(); pendingWrite = nil
        pendingRefresh?.cancel(); pendingRefresh = nil
    }
    func refresh() {
        guard !model.previewMode else { return }
        let d = ARAudioOutputSnapshot()
        var state = AudioOutputState(uid: d["uid"] as? String ?? "", name: d["name"] as? String ?? "",
            modelUID: d["modelUID"] as? String ?? "", kind: d["kind"] as? String ?? "", port: d["port"] as? String ?? "",
            volume: (d["volume"] as? NSNumber)?.doubleValue ?? 0, muted: d["muted"] as? Bool ?? false,
            canMute: d["canMute"] as? Bool ?? false, canSetVolume: d["canSetVolume"] as? Bool ?? false)
        if ProcessInfo.processInfo.systemUptime < suppressionUntil, let localTarget {
            state.volume = localTarget
            if localTarget > 0 { state.muted = false }
        }
        if state.volume > 0 { lastAudible[state.uid] = state.volume }
        if model.output != state { model.output = state; model.audioOutput = state.name }
    }
    func stepVolume(_ action: VolumeKeyAction, fine: Bool) {
        guard model.output.canSetVolume else { return }
        let current = model.output.muted ? 0 : model.output.volume
        setVolume(VolumeStep.target(current: current, action: action, fine: fine), expectedUID: model.output.uid)
    }
    func setVolume(_ value: Double, expectedUID: String) {
        guard value.isFinite, model.output.uid == expectedUID else { refresh(); return }
        let target = min(1, max(0, value))
        let speed = model.settings.volumePreferences.speed
        // 1.7.9 VolumeManager: coalesce writes and keep the local target while
        // the CoreAudio callback still reports the previous value. The selected
        // speed changes the actual write/refresh timing, not just the HUD.
        localTarget = target
        suppressionUntil = ProcessInfo.processInfo.systemUptime + speed.callbackSuppression
        model.output.volume = target
        if target > 0 { model.output.muted = false }
        if target > 0 { lastAudible[expectedUID] = target }
        pendingWrite?.cancel(); pendingWrite = nil
        pendingRefresh?.cancel(); pendingRefresh = nil
        let work = scheduler.schedule(after: speed.writeDelay) { [weak self] in
            guard let self, self.model.output.uid == expectedUID, self.localTarget == target else { return }
            self.pendingWrite = nil
            let ok = self.volumeWriter(expectedUID, target)
            if ok, target > 0, self.model.output.muted { _ = self.muteWriter(expectedUID, false) }
            self.pendingRefresh = self.scheduler.schedule(after: speed.refreshDelay) { [weak self] in
                guard let self, self.model.output.uid == expectedUID, self.localTarget == target else { return }
                self.pendingRefresh = nil
                self.localTarget = nil
                self.suppressionUntil = 0
                self.refresh()
            }
        }
        pendingWrite = work
    }
    func toggleMute() {
        let output = model.output
        if output.effectivelyMuted {
            // A zero-volume slider can have its native mute bit unset. Restore
            // the last audible level as well as clearing mute in that case.
            if output.volume <= 0, output.canSetVolume {
                guard volumeWriter(output.uid, lastAudible[output.uid] ?? 0.25) else { refresh(); return }
            }
            if output.canMute { _ = muteWriter(output.uid, false) }
        } else if output.canMute { _ = muteWriter(output.uid, true) }
        else if output.canSetVolume { _ = volumeWriter(output.uid, 0) }
        refresh()
    }
}
