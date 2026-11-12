#if VALORA_LYRICS_EXPERIMENT
import AppKit
import Foundation

/// Opt-in, bounded diagnostics for the experimental native lyric renderer.
/// There is no timer, file handle or output path unless the explicit
/// VALORA_LYRICS_DIAGNOSTICS_DIR environment variable is a /private/tmp child
/// directory. The registry holds weak view references only.
@MainActor
final class LyricsDiagnostics {
    static let shared = LyricsDiagnostics()
    static let environmentKey = "VALORA_LYRICS_DIAGNOSTICS_DIR"
    static let maxDuration: TimeInterval = 12 * 60
    static let maxBytes = 512 * 1024

    private struct Entry {
        weak var view: NativeLyricsRowView?
        var role: String
        let id: Int
    }

    private weak var model: AppModel?
    private var entries: [Entry] = []
    private var ids: [ObjectIdentifier: Int] = [:]
    private var nextID = 1
    private var fallbackState: [String: Bool] = [:]
    private var timer: Timer?
    private var file: FileHandle?
    private var startedAt = ProcessInfo.processInfo.systemUptime
    private var bytesWritten = 0
    private var stopped = false

    let outputURL: URL?

    var isEnabled: Bool { outputURL != nil && !stopped }
    var entryCount: Int { entries.count }
    var fallbackCount: Int { fallbackState.values.filter { $0 }.count }
    var isTimerRunning: Bool { timer != nil }

    init(directory: URL? = nil, startTimer: Bool = true) {
        let directory = directory ?? Self.environmentDirectory()
        guard let directory else {
            outputURL = nil
            return
        }
        do {
            try FileManager.default.createDirectory(at: directory,
                                                    withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("lyrics-diagnostics.jsonl")
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            guard FileManager.default.createFile(atPath: url.path, contents: nil),
                  let handle = try? FileHandle(forWritingTo: url) else {
                outputURL = nil
                return
            }
            outputURL = url
            file = handle
            startedAt = ProcessInfo.processInfo.systemUptime
            if startTimer { start() }
        } catch {
            outputURL = nil
        }
    }

    private static func environmentDirectory() -> URL? {
        guard let raw = ProcessInfo.processInfo.environment[environmentKey],
              !raw.isEmpty else { return nil }
        let url = URL(fileURLWithPath: raw).standardizedFileURL
        let prefix = URL(fileURLWithPath: "/private/tmp/").standardizedFileURL.path
        guard url.path.hasPrefix(prefix), url.path != prefix else { return nil }
        return url
    }

    func bind(model: AppModel) {
        self.model = model
        startIfNeeded()
    }

    func register(view: NativeLyricsRowView, role: String) {
        startIfNeeded()
        prune()
        view.diagnosticRole = role
        let objectID = ObjectIdentifier(view)
        if let index = entries.firstIndex(where: { $0.view === view }) {
            entries[index].role = role
            return
        }
        let id = ids[objectID] ?? nextID
        if ids[objectID] == nil { nextID += 1 }
        ids[objectID] = id
        entries.append(Entry(view: view, role: role, id: id))
    }

    func unregister(view: NativeLyricsRowView) {
        let objectID = ObjectIdentifier(view)
        entries.removeAll { $0.view === view || $0.view == nil }
        ids.removeValue(forKey: objectID)
    }

    func setFallback(role: String, active: Bool) {
        startIfNeeded()
        if fallbackState[role] != active { fallbackState[role] = active }
    }

    func stop() {
        guard !stopped else { return }
        stopped = true
        timer?.invalidate(); timer = nil
        try? file?.close(); file = nil
    }

    private func startIfNeeded() {
        guard outputURL != nil, !stopped, timer == nil else { return }
        start()
    }

    private func start() {
        guard outputURL != nil, !stopped, timer == nil else { return }
        let next = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.emit() }
        }
        next.tolerance = 0.2
        RunLoop.main.add(next, forMode: .common)
        timer = next
        emit()
    }

    private func prune() {
        entries.removeAll { $0.view == nil }
        let live = entries.compactMap { $0.view }
        let liveIDs = Set(live.map(ObjectIdentifier.init))
        ids = ids.filter { liveIDs.contains($0.key) }
    }

    /// Test seam: write one snapshot without waiting for the timer.
    func emitForTesting() { emit() }

    private func emit() {
        guard !stopped, let file else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if now - startedAt >= Self.maxDuration {
            stop(); return
        }
        prune()
        let model = model
        let systemLocked = (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Bool
        var fallback: [String: Int] = [:]
        for (role, active) in fallbackState where active { fallback[role, default: 0] += 1 }
        let instances = entries.compactMap { entry -> [String: Any]? in
            guard let view = entry.view else { return nil }
            return [
                "id": entry.id,
                "role": entry.role,
                "hasWindow": view.window != nil,
                "windowVisible": view.window?.isVisible == true,
                "active": view.diagnosticActive,
                "stopped": view.diagnosticStopped,
                "playing": view.diagnosticPlaying,
                "rate": view.diagnosticRate,
                "backend": String(describing: view.debugBackend),
                "imageFailed": view.debugImageRenderFailed,
                "clockRegistered": view.debugIsClockRunning,
                "boundaryWake": view.debugHasBoundaryWake,
                "boundaryDelay": view.debugBoundaryDelay ?? -1,
                "apply": view.applyCount,
                "applyRequests": view.applyRequestCount,
                "applySkipped": view.applySkippedCount,
                "clockTick": view.clockTickCount,
                "frameTicks": view.frameTicks,
                "maskUpdates": view.maskUpdates,
                "offsetChanges": view.offsetChangeCount,
                "caBriefs": view.caTransactionAttempts,
                "caCommits": view.caTransactionCommits,
                "textBuilds": view.textBuilds,
                "imageBuilds": view.imageBuilds,
                "layoutPasses": view.layoutPasses,
                "hostingLayouts": view.hostingLayouts,
                "rootViewUpdates": view.rootViewUpdates,
                "switches": view.switchCount,
                "stops": view.stopCount,
                "resumes": view.resumeCount,
                "captureWindows": view.captureWindowCreations,
                "captureCloses": view.captureWindowCloses
            ]
        }
        let object: [String: Any] = [
            "utc": ISO8601DateFormatter().string(from: Date()),
            "monotonic": now,
            "systemLocked": systemLocked ?? false,
            "modelSessionLocked": model?.isSessionLocked ?? false,
            "lyricsSwitch": model?.settings.musicPreferences.showLyrics ?? false,
            "nativeLive": entries.count,
            "nativeActive": instances.filter { $0["active"] as? Bool == true }.count,
            "clockRegistered": instances.filter { $0["clockRegistered"] as? Bool == true }.count,
            "fallback": fallback,
            "fallbackCount": fallback.values.reduce(0, +),
            "instances": instances
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              bytesWritten + data.count + 1 <= Self.maxBytes else {
            stop(); return
        }
        file.write(data)
        file.write(Data([0x0A]))
        bytesWritten += data.count + 1
    }
}
#endif
