import Foundation
import ReferenceCore

/// Runs the bundled, source-built Perl + MediaRemote adapter. It reads the
/// system Now Playing session, not an app UI. The helper is scoped to this
/// application lifetime; no daemon or launch agent is installed.
///
/// Swift 6 note: this type crosses main-thread and pipe-reader/command-queue
/// boundaries, so it is explicitly `@unchecked Sendable`. Invariants:
/// - `process` is only mutated on the main actor (`start`, `stop`, and main-hop
///   callbacks), and is read read-only by `deinit`.
/// - `epoch` is lock-guarded and is the only cross-thread cancellation token.
/// - The pipe reader only touches its local `task`, `output` and `buffer`.
/// - `run(_:)` creates its own Process per invocation on the command queue.
/// Callbacks are delivered on the main actor.
final class SystemMediaSource: @unchecked Sendable {
    var onSnapshot: (@MainActor (SystemMediaSnapshot?) -> Void)?
    var onError: (@MainActor (String) -> Void)?

    private var process: Process?
    private let epochLock = NSLock()
    private var epoch = UUID()
    private let reader = DispatchQueue(label: "valora.system-media.stream")
    private let commands = DispatchQueue(label: "valora.system-media.commands")

    private var script: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("MediaRemote/mediaremote-adapter.pl")
    }
    private var framework: URL? {
        Bundle.main.privateFrameworksURL?.appendingPathComponent("MediaRemoteAdapter.framework")
    }

    private func currentEpoch() -> UUID {
        epochLock.lock(); defer { epochLock.unlock() }
        return epoch
    }
    private func beginEpoch() -> UUID {
        let value = UUID()
        epochLock.lock(); epoch = value; epochLock.unlock()
        return value
    }
    private func isCurrent(_ token: UUID) -> Bool {
        epochLock.lock(); defer { epochLock.unlock() }
        return epoch == token
    }

    private func makeProcess(_ arguments: [String]) throws -> Process {
        guard let script, let framework,
              FileManager.default.fileExists(atPath: script.path),
              FileManager.default.fileExists(atPath: framework.path) else {
            throw NSError(domain: "SystemMedia", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "应用内缺少系统媒体适配组件，请重新构建应用。"])
        }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        task.arguments = [script.path, framework.path] + arguments
        task.standardInput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        return task
    }

    @MainActor
    func start() {
        guard process == nil else { return }
        let token = beginEpoch()
        do {
            let task = try makeProcess(["stream", "--no-diff", "--micros", "--debounce=50"])
            let output = Pipe()
            task.standardOutput = output
            process = task
            try task.run()
            reader.async { [weak self] in
                guard let self else { return }
                var buffer = Data()
                while true {
                    let chunk = output.fileHandleForReading.availableData
                    if chunk.isEmpty { break }
                    buffer.append(chunk)
                    if buffer.count > 16_000_000 { task.terminate(); break }
                    while let newline = buffer.firstIndex(of: 10) {
                        let line = Data(buffer[..<newline])
                        buffer.removeSubrange(...newline)
                        guard let event = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                              event["type"] as? String == "data", event["diff"] as? Bool == false,
                              let payload = event["payload"] as? [String: Any] else { continue }
                        let snapshot = SystemMediaSnapshot(payload)
                        DispatchQueue.main.async { [weak self] in
                            MainActor.assumeIsolated {
                                guard let self, self.isCurrent(token) else { return }
                                self.onSnapshot?(snapshot)
                            }
                        }
                    }
                }
                task.waitUntilExit()
                DispatchQueue.main.async { [weak self] in
                    MainActor.assumeIsolated {
                        guard let self, self.isCurrent(token) else { return }
                        self.process = nil
                        self.onError?("系统媒体连接已结束，请切换播放来源后重试。")
                    }
                }
            }
        } catch {
            process = nil
            MainActor.assumeIsolated { onError?(error.localizedDescription) }
        }
    }

    @MainActor
    func stop() {
        _ = beginEpoch()
        if let process, process.isRunning { process.terminate() }
        process = nil
    }

    deinit {
        if let process, process.isRunning { process.terminate() }
    }

    // Validate the current system source immediately before dispatch. A source
    // change must not send an old panel's seek request to a different player.
    func perform(_ arguments: [String], expected: SystemMediaSnapshot, requireSameTrack: Bool,
                 completion: @escaping @MainActor (Bool) -> Void) {
        let token = currentEpoch()
        commands.async { [weak self] in
            guard let self, self.isCurrent(token) else { return }
            var success = false
            do {
                let data = try self.run(["get", "--micros", "--no-artwork"])
                if let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let current = SystemMediaSnapshot(payload),
                   current.bundleIdentifier == expected.bundleIdentifier,
                   !requireSameTrack || current.identity == expected.identity {
                    guard self.isCurrent(token) else { return }
                    let command = arguments == ["send", "2"] ? ["send", current.playing ? "1" : "0"] : arguments
                    _ = try self.run(command)
                    success = true
                }
            } catch {
                success = false
            }
            let result = success
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.isCurrent(token) else { return }
                    completion(result)
                }
            }
        }
    }

    /// Box the Process so the timeout closure can terminate it. NSTask's
    /// `terminate()` is documented as safe to call; the box only provides the
    /// Sendable boundary required by Swift 6 for `DispatchWorkItem`.
    private final class ProcessBox: @unchecked Sendable {
        let process: Process
        init(_ process: Process) { self.process = process }
    }

    private func run(_ arguments: [String]) throws -> Data {
        let task = try makeProcess(arguments)
        let pipe = Pipe()
        task.standardOutput = pipe
        try task.run()
        let box = ProcessBox(task)
        let timeout = DispatchWorkItem { if box.process.isRunning { box.process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 4, execute: timeout)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        timeout.cancel()
        guard task.terminationStatus == 0 else {
            throw NSError(domain: "SystemMedia", code: Int(task.terminationStatus))
        }
        return data
    }
}
