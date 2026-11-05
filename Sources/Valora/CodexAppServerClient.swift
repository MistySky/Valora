import Foundation

/// Minimal read-only client for the locally installed Codex engine.
///
/// It speaks the app-server stdio protocol and is deliberately restricted to
/// the three calls needed to read the rate-limit snapshot:
/// `initialize`, `initialized` and `account/rateLimits/read`. It never reads
/// `auth.json`, tokens, sessions, transcripts or account identity, never sends a
/// model request and never consumes a reset credit. The allowlist is a constant
/// in this type, so the restriction is visible and testable.
///
/// Lifecycle: the child process is always reaped (SIGTERM, then SIGKILL after a
/// short grace), stdout is drained through a non-blocking readability handler so
/// an absolute deadline fires even when the engine prints nothing, stderr is
/// drained and discarded, and task cancellation terminates the real child before
/// the call returns `CancellationError`.
final class CodexAppServerClient: @unchecked Sendable {
    /// The complete set of methods this client may send.
    static let allowedMethods = ["initialize", "initialized", "account/rateLimits/read"]

    /// Buffer ceiling for a single response line; beyond it the read fails
    /// instead of growing without bound.
    static let stdoutLimit = 256 * 1024

    let executable: URL
    let timeout: TimeInterval

    init(executable: URL, timeout: TimeInterval = 8) {
        self.executable = executable
        self.timeout = max(0.5, timeout)
        Self.ignoreBrokenPipeOnce
    }

    /// Writing to a child that already exited would otherwise raise SIGPIPE and
    /// kill the app; the client never wants that failure mode.
    private static let ignoreBrokenPipeOnce: Void = {
        signal(SIGPIPE, SIG_IGN)
    }()

    /// Locates a trusted local Codex engine. No network, no shell expansion.
    static func locate() -> URL? {
        let candidates = [
            "/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            NSHomeDirectory() + "/.local/bin/codex",
            NSHomeDirectory() + "/.codex/bin/codex"
        ]
        let manager = FileManager.default
        for path in candidates where manager.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    /// One bounded, cancellable read. Never blocks the caller's executor.
    func readRateLimits() async throws -> CodexRateLimits {
        let run = Run(executable: executable, timeout: timeout)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                run.start(continuation)
            }
        } onCancel: {
            run.abort(CancellationError())
        }
    }

    /// One process, one continuation, one terminal outcome.
    private final class Run: @unchecked Sendable {
        private let executable: URL
        private let timeout: TimeInterval
        private let lock = NSLock()
        private var continuation: CheckedContinuation<CodexRateLimits, Error>?
        private var finished = false
        private var pendingError: Error?
        private var process: Process?
        private var stdoutHandle: FileHandle?
        private var stderrHandle: FileHandle?
        private var stdoutBuffer = Data()
        private var deadline: DispatchWorkItem?
        private var killDeadline: DispatchWorkItem?

        init(executable: URL, timeout: TimeInterval) {
            self.executable = executable
            self.timeout = timeout
        }

        func start(_ continuation: CheckedContinuation<CodexRateLimits, Error>) {
            let process = Process()
            process.executableURL = executable
            process.arguments = ["app-server"]
            let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
            process.standardInput = stdin
            process.standardOutput = stdout
            process.standardError = stderr

            lock.lock()
            if finished {
                // Cancelled before the engine existed: finish without spawning.
                let error = pendingError ?? CancellationError()
                self.continuation = continuation
                lock.unlock()
                continuation.resume(throwing: error)
                return
            }
            self.continuation = continuation
            self.process = process
            stdoutHandle = stdout.fileHandleForReading
            stderrHandle = stderr.fileHandleForReading
            lock.unlock()

            Self.reapPreviousChildren()
            do {
                try process.run()
            } catch {
                finish(.failure(CodexUsageError.missingEngine))
                return
            }

            // Non-blocking drains: the deadline no longer depends on output.
            stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
                self?.consume(handle.availableData)
            }
            stderr.fileHandleForReading.readabilityHandler = { handle in
                // Drain and discard; engine diagnostics are not persisted or
                // surfaced, and the buffer is dropped immediately.
                _ = handle.availableData
            }

            // Writes happen off the caller's actor; failures are terminal.
            let payload = [
                #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"clientInfo":{"name":"valora","version":"0"}}}"#,
                #"{"jsonrpc":"2.0","method":"initialized","params":{}}"#,
                #"{"jsonrpc":"2.0","id":2,"method":"account/rateLimits/read","params":{}}"#
            ]
            DispatchQueue.global(qos: .utility).async { [weak self, weak stdin] in
                guard let self, let stdin else { return }
                guard self.isActive else { return }
                for line in payload {
                    stdin.fileHandleForWriting.write(Data((line + "\n").utf8))
                }
            }

            let work = DispatchWorkItem { [weak self] in
                self?.finish(.failure(CodexUsageError.timeout))
            }
            lock.lock()
            deadline = work
            lock.unlock()
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: work)
        }

        private var isActive: Bool {
            lock.lock(); defer { lock.unlock() }
            return !finished
        }

        private func consume(_ data: Data) {
            guard !data.isEmpty else { return }
            lock.lock()
            guard !finished else { lock.unlock(); return }
            stdoutBuffer.append(data)
            if stdoutBuffer.count > CodexAppServerClient.stdoutLimit {
                lock.unlock()
                finish(.failure(CodexUsageError.outputLimit))
                return
            }
            var complete: [Data] = []
            while let newline = stdoutBuffer.firstIndex(of: 0x0A) {
                complete.append(Data(stdoutBuffer[stdoutBuffer.startIndex..<newline]))
                stdoutBuffer.removeSubrange(stdoutBuffer.startIndex...newline)
            }
            lock.unlock()

            for line in complete {
                guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                      (object["id"] as? NSNumber)?.intValue == 2 else { continue }
                if object["error"] != nil {
                    finish(.failure(CodexUsageError.protocolError("额度接口暂不兼容")))
                    return
                }
                guard let result = object["result"] else {
                    finish(.failure(CodexUsageError.protocolError("额度接口暂不兼容")))
                    return
                }
                do {
                    finish(.success(try CodexRateLimitsParser.parse(object: result)))
                } catch {
                    finish(.failure(CodexUsageError.protocolError("额度接口暂不兼容")))
                }
                return
            }
        }

        // MARK: - Guaranteed child reaping
        //
        // A cancelled read returns to the caller before the child is necessarily
        // gone (TERM is asynchronous and an engine may ignore it). The registry
        // makes the *next* read kill that child before spawning its own, so the
        // provider can never end up with two live engines.

        private static let childLock = NSLock()
        /// Guarded by `childLock`; `nonisolated(unsafe)` is the narrow escape hatch
        /// for this process registry, matching the lock discipline above.
        nonisolated(unsafe) private static var registrations: [Process] = []

        private static func registerChild(_ process: Process) {
            childLock.lock()
            registrations.removeAll { !$0.isRunning }
            registrations.append(process)
            childLock.unlock()
        }

        private static func reapPreviousChildren() {
            childLock.lock()
            let live = registrations.filter { $0.isRunning }
            registrations.removeAll { !$0.isRunning }
            childLock.unlock()
            guard !live.isEmpty else { return }
            for process in live { kill(process.processIdentifier, SIGKILL) }
            // Bounded wait so ownership is unambiguous before a new child starts.
            let deadline = Date().addingTimeInterval(0.25)
            while Date() < deadline, live.contains(where: { $0.isRunning }) {
                usleep(10_000)
            }
        }

        /// Cancellation path: terminate the real child immediately and resume
        /// the caller with `CancellationError`.
        func abort(_ error: Error) {
            finish(.failure(error))
        }

        private func finish(_ result: Result<CodexRateLimits, Error>) {
            lock.lock()
            if finished {
                lock.unlock()
                return
            }
            finished = true
            let continuation = self.continuation
            self.continuation = nil
            if continuation == nil, case .failure(let error) = result {
                // Cancelled (or failed) before the caller registered its
                // continuation: remember it so `start` can finish immediately
                // instead of hanging forever.
                pendingError = error
            }
            let work = deadline
            deadline = nil
            let process = self.process
            self.process = nil
            let out = stdoutHandle
            let err = stderrHandle
            stdoutHandle = nil
            stderrHandle = nil
            lock.unlock()

            work?.cancel()
            out?.readabilityHandler = nil
            err?.readabilityHandler = nil
            try? out?.close()
            try? err?.close()

            if let process, process.isRunning {
                Self.registerChild(process)
                process.terminate()
                // Bounded grace, then SIGKILL on a background queue. The caller
                // is not blocked on the child exiting.
                let killWork = DispatchWorkItem {
                    if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                }
                let previous = killDeadline
                killDeadline = killWork
                previous?.cancel()
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.5, execute: killWork)
            }

            switch result {
            case .success(let limits):
                continuation?.resume(returning: limits)
            case .failure(let error):
                continuation?.resume(throwing: error)
            }
        }
    }
}
