import Foundation

enum CodexUsageError: Error, Equatable, LocalizedError {
    case missingEngine
    case notSignedIn
    case timeout
    case protocolError(String)
    case processExited
    case outputLimit

    var errorDescription: String? {
        switch self {
        case .missingEngine: return "未找到本机 Codex 引擎"
        case .notSignedIn: return "Codex 未登录或登录已失效"
        case .timeout: return "额度读取超时"
        case .protocolError(let message): return "额度接口错误：\(message)"
        case .processExited: return "Codex 引擎提前退出"
        case .outputLimit: return "Codex 输出超过上限"
        }
    }
}

/// Finds an installed Codex engine without reading auth.json or any account
/// file. The engine itself owns sign-in state.
protocol CodexEngineLocating: Sendable {
    func find() -> URL?
    func dataDirectory() -> URL
}

struct DefaultCodexEngineLocator: CodexEngineLocating {
    var home: URL = FileManager.default.homeDirectoryForCurrentUser
    var applications: URL = URL(fileURLWithPath: "/Applications")
    var environment: [String: String] = ProcessInfo.processInfo.environment
    var path: String = ProcessInfo.processInfo.environment["PATH"] ?? ""

    func dataDirectory() -> URL {
        if let configured = environment["CODEX_HOME"], !configured.isEmpty {
            return URL(fileURLWithPath: configured, isDirectory: true)
        }
        return home.appendingPathComponent(".codex", isDirectory: true)
    }

    func find() -> URL? {
        candidates().first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    private func candidates() -> [URL] {
        var result: [URL] = []
        for root in [applications, home.appendingPathComponent("Applications")] {
            for app in ["Codex.app", "ChatGPT.app"] {
                let base = root.appendingPathComponent(app)
                result.append(base.appendingPathComponent("Contents/Resources/codex-cli/bin/codex"))
                result.append(base.appendingPathComponent("Contents/Resources/codex"))
            }
        }
        for path in [home.appendingPathComponent(".bun/bin/codex"),
                     home.appendingPathComponent(".local/bin/codex"),
                     URL(fileURLWithPath: "/opt/homebrew/bin/codex"),
                     URL(fileURLWithPath: "/usr/local/bin/codex")]
        { result.append(path) }
        result.append(contentsOf: Self.pathCandidates(path: path))
        return result
    }

    private static func pathCandidates(path: String) -> [URL] {
        guard !path.isEmpty else { return [] }
        return path.split(separator: ":").map {
            URL(fileURLWithPath: String($0)).appendingPathComponent("codex")
        }
    }
}

struct CodexAppServerFetch {
    let locator: any CodexEngineLocating
    let timeout: TimeInterval

    init(locator: any CodexEngineLocating = DefaultCodexEngineLocator(), timeout: TimeInterval = 10) {
        self.locator = locator
        self.timeout = timeout
    }

    func fetch() async throws -> CodexRateLimits {
        guard let executable = locator.find() else { throw CodexUsageError.missingEngine }
        return try await CodexAppServerClient(
            executable: executable,
            dataDirectory: locator.dataDirectory(),
            timeout: timeout).fetch()
    }
}

/// One short-lived Codex app-server connection. The allowlist is intentionally
/// closed: initialize, initialized, account/rateLimits/read. No account/read,
/// thread, turn, model request, login or reset operation exists here.
struct CodexAppServerClient: Sendable {
    static let allowedMethods: Set<String> = [
        "initialize", "initialized", "account/rateLimits/read"
    ]

    let executable: URL
    let dataDirectory: URL
    let timeout: TimeInterval

    init(executable: URL, dataDirectory: URL, timeout: TimeInterval = 10) {
        self.executable = executable
        self.dataDirectory = dataDirectory
        self.timeout = timeout
    }

    func fetch() async throws -> CodexRateLimits {
        var environment = ProcessInfo.processInfo.environment
        environment["CODEX_HOME"] = dataDirectory.path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        environment["PATH"] = "\(home)/.bun/bin:\(home)/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (environment["PATH"] ?? "")

        let server: CodexChildProcess
        do {
            server = try CodexChildProcess(
                executable, ["app-server", "--listen", "stdio://"],
                environment: environment,
                directory: FileManager.default.temporaryDirectory,
                input: true, stdoutLimit: 1_048_576)
        } catch {
            throw CodexUsageError.notSignedIn
        }

        do {
            let reading = try await runExchange(server)
            await stopAndWait(server)
            return reading
        } catch {
            await stopAndWait(server)
            throw error
        }
    }

    private func runExchange(_ server: CodexChildProcess) async throws -> CodexRateLimits {
        func send(_ message: [String: Any]) throws {
            guard let method = message["method"] as? String else { throw CodexUsageError.protocolError("missing method") }
            guard Self.allowedMethods.contains(method) else {
                throw CodexUsageError.protocolError("method not allowed: \(method)")
            }
            var bytes = try JSONSerialization.data(withJSONObject: message)
            bytes.append(0x0A)
            try server.write(bytes)
        }

        do {
            try send([
                "id": 1,
                "method": "initialize",
                "params": ["clientInfo": ["name": "valora", "title": "Valora", "version": "0.1.0"]]
            ])
        } catch {
            throw CodexUsageError.protocolError("initialize write failed")
        }

        let deadline = Date().addingTimeInterval(timeout)
        while true {
            // The hard deadline applies even while notifications keep arriving.
            if Date() >= deadline { throw CodexUsageError.timeout }
            if server.output.truncated { throw CodexUsageError.outputLimit }
            guard let line = try await server.line(before: deadline) else { break }
            if server.output.truncated { throw CodexUsageError.outputLimit }
            guard let data = line.data(using: .utf8),
                  let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = message["id"] as? Int else { continue }
            if let error = message["error"] as? [String: Any] {
                let text = error["message"] as? String ?? "app-server error"
                if id == 1 || id == 2 { throw CodexUsageError.protocolError(text) }
                continue
            }
            guard let result = message["result"] else { continue }
            switch id {
            case 1:
                do {
                    try send(["method": "initialized"])
                    try send(["id": 2, "method": "account/rateLimits/read"])
                } catch {
                    throw CodexUsageError.protocolError("limits request write failed")
                }
            case 2:
                let resultData = try JSONSerialization.data(withJSONObject: result)
                do {
                    return try CodexRateLimitsParser.parse(data: resultData)
                } catch {
                    throw CodexUsageError.protocolError("invalid limits result")
                }
            default:
                continue
            }
        }
        if server.output.truncated { throw CodexUsageError.outputLimit }
        if server.output.status != nil { throw CodexUsageError.processExited }
        throw CodexUsageError.timeout
    }

    /// Include the asynchronous SIGTERM/SIGKILL grace in the actual request
    /// lifecycle. The detached waiter survives Swift-task cancellation.
    private func stopAndWait(_ server: CodexChildProcess) async {
        server.stop()
        let waiter = Task.detached {
            var deadline = Date().addingTimeInterval(CodexChildProcess.grace + 1)
            try? await server.waitForExit(before: deadline)
            if server.output.status == nil {
                deadline = Date().addingTimeInterval(0.25)
                try? await server.waitForExit(before: deadline)
            }
        }
        _ = await waiter.value
    }
}
