import Foundation
import XCTest
@testable import Valora

/// A local, silent executable only. Never invokes Codex or reads account data.
@MainActor
final class IndependentCodexTransportTests: XCTestCase {
    func testAlreadyCancelledReadFinishesWithoutLaunchingAnEngine() async throws {
        // A missing executable is intentional: cancellation must win before
        // launch, without leaving the checked continuation suspended forever.
        let client = CodexAppServerClient(executable: URL(fileURLWithPath: "/private/tmp/valora-no-such-codex-engine"))
        var completed = false
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try await client.readRateLimits()
                XCTFail("already cancelled read succeeded")
            } catch {
                XCTAssertTrue(error is CancellationError, "cancellation must win over launch: \(error)")
            }
            completed = true
        }
        defer { task.cancel() }
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertTrue(completed, "cancellation before start stranded its continuation")
    }

    private func silentEngine(seconds: Double) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("valora-codex-transport-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("engine")
        try "#!/bin/sh\nIFS= read -r a\nIFS= read -r b\nIFS= read -r c\nexec /bin/sleep \(seconds)\n"
            .write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
        return file
    }

    func testCancellingReadTerminatesTheActualSilentChild() async throws {
        let client = CodexAppServerClient(executable: try silentEngine(seconds: 1.5))
        let task = Task { try await client.readRateLimits() }
        try await Task.sleep(for: .milliseconds(80))
        let cancelledAt = Date()
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("cancelled read returned quota")
        } catch {
            XCTAssertTrue(error is CancellationError, "expected cancellation, got \(error)")
        }
        XCTAssertLessThan(Date().timeIntervalSince(cancelledAt), 0.6,
                          "off must stop the actual child, not wait for it to exit")
    }

    func testSilentStdoutCannotBypassTheReadDeadline() async throws {
        let client = CodexAppServerClient(executable: try silentEngine(seconds: 3.2), timeout: 2)
        let start = Date()
        do {
            _ = try await client.readRateLimits()
            XCTFail("silent engine returned quota")
        } catch {
            XCTAssertEqual(error as? CodexUsageError, .timeout)
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 2.7,
                          "blocking availableData must not prevent the deadline from firing")
    }

    /// The engine ignores SIGTERM on purpose. A cancelled read must not leave a
    /// live child behind, and the next read must kill it before spawning its own,
    /// so the provider can never own two engines at once.
    func testRestartKillsPreviousTerIgnoringChild() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("valora-codex-reap-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let pidFile = root.appendingPathComponent("pid")
        let engine = root.appendingPathComponent("engine")
        try """
        #!/bin/sh
        echo $$ > "\(pidFile.path)"
        trap '' TERM
        IFS= read -r a
        IFS= read -r b
        IFS= read -r c
        exec /bin/sleep 5
        """.write(to: engine, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: engine.path)

        let client = CodexAppServerClient(executable: engine, timeout: 5)
        let task = Task { try await client.readRateLimits() }
        // Wait for the child to publish its PID, then cancel it.
        var pidText: String?
        for _ in 0..<50 where pidText == nil {
            try? await Task.sleep(for: .milliseconds(20))
            pidText = try? String(contentsOf: pidFile, encoding: .utf8)
        }
        let pid = pid_t(pidText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
        XCTAssertNotNil(pid, "engine did not start")
        task.cancel()
        _ = try? await task.value

        // A second read must reap the TERM-ignoring child before it starts.
        let second = Task { try? await CodexAppServerClient(executable: engine, timeout: 1).readRateLimits() }
        try? await Task.sleep(for: .milliseconds(400))
        if let pid {
            XCTAssertEqual(kill(pid, 0), -1, "previous child \(pid) is still alive")
        }
        second.cancel()
        _ = await second.value
    }
}
