import Foundation
import XCTest
@testable import Valora

/// A local, silent executable only. Never invokes Codex or reads account data.
@MainActor
final class IndependentCodexTransportTests: XCTestCase {
    // MARK: - Readiness helpers

    /// The fake engine publishes its pid with a shell redirect. `echo $$ > file`
    /// is not atomic: another process can open the created-but-empty file and
    /// read `""` for a moment. An empty, partial or non-numeric read is
    /// therefore "not ready yet", never a completed wait. The real process test
    /// publishes atomically, but the parser still tolerates a transient empty
    /// file so the wait can never mistake it for a finished setup.
    enum TransportEngineReadiness {
        static func readyPID(from text: String?) -> pid_t? {
            guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !trimmed.isEmpty,
                  let raw = pid_t(trimmed),
                  raw > 0 else { return nil }
            return raw
        }

        /// Bounded wait. Returns nil only when `deadline` expires without ever
        /// observing a valid positive pid. `read` is injected so the
        /// empty-then-ready race can be tested without a real process.
        @MainActor
        static func waitForPID(deadline: TimeInterval,
                               read: @MainActor () -> String?) async -> pid_t? {
            let started = Date()
            while Date().timeIntervalSince(started) < deadline {
                if let pid = readyPID(from: read()) { return pid }
                try? await Task.sleep(for: .milliseconds(10))
            }
            // One last look at the deadline edge; still only a valid pid counts.
            return readyPID(from: read())
        }
    }

    /// Reports the child task's own failure so a setup miss can be diagnosed
    /// instead of silently failing on `XCTAssertNotNil`.
    @MainActor
    final class TaskOutcome {
        var finished = false
        var error: Error?
    }

    /// Deterministic sequence reader for readiness tests.
    final class SequencedReads {
        private var values: [String?]
        private(set) var count = 0
        init(_ values: [String?]) { self.values = values }
        func next() -> String? {
            defer { count += 1 }
            guard !values.isEmpty else { return values.last ?? nil }
            return values.removeFirst()
        }
    }

    // MARK: - Readiness contract

    func testReadyPIDRejectsEmptyPartialAndPlaceholderValues() {
        XCTAssertNil(TransportEngineReadiness.readyPID(from: nil))
        XCTAssertNil(TransportEngineReadiness.readyPID(from: ""))
        XCTAssertNil(TransportEngineReadiness.readyPID(from: "  \n"))
        XCTAssertNil(TransportEngineReadiness.readyPID(from: "not-a-pid"))
        XCTAssertNil(TransportEngineReadiness.readyPID(from: "0"))
        XCTAssertNil(TransportEngineReadiness.readyPID(from: "-7"))
        XCTAssertEqual(TransportEngineReadiness.readyPID(from: " 4242\n"), 4242)
    }

    func testTransientEmptyFileBecomesReadyWhenAValidPIDArrives() async {
        let reads = SequencedReads(["", "  \n", "not-a-pid", "0", "-12", "4242"])
        let pid = await TransportEngineReadiness.waitForPID(deadline: 1) { reads.next() }
        XCTAssertEqual(pid, 4242, "an empty first read must not end the wait")
        XCTAssertGreaterThanOrEqual(reads.count, 6)
    }

    func testNoValidPIDEverFailsWithinTheBoundedDeadline() async {
        let reads = SequencedReads(["", "oops", "0"])
        let started = Date()
        let pid = await TransportEngineReadiness.waitForPID(deadline: 0.15) { reads.next() }
        XCTAssertNil(pid)
        XCTAssertLessThan(Date().timeIntervalSince(started), 1.0,
                          "readiness must fail bounded, not wait forever")
        XCTAssertGreaterThan(reads.count, 1,
                             "polling must continue past an empty/partial file")
    }

    // MARK: - Transport

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
        // Publish the pid atomically (temp + rename) so a reader never depends on
        // catching the shell's redirect mid-write; the readiness parser still
        // tolerates a transient empty file from other fixtures.
        try """
        #!/bin/sh
        trap '' TERM
        printf '%s\\n' $$ > "\(pidFile.path).tmp"
        mv "\(pidFile.path).tmp" "\(pidFile.path)"
        IFS= read -r a
        IFS= read -r b
        IFS= read -r c
        exec /bin/sleep 5
        """.write(to: engine, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: engine.path)

        let client = CodexAppServerClient(executable: engine, timeout: 5)
        let outcome = TaskOutcome()
        let task = Task {
            do {
                _ = try await client.readRateLimits()
            } catch {
                outcome.error = error
            }
            outcome.finished = true
        }

        var lastText: String?
        let pid = await TransportEngineReadiness.waitForPID(deadline: 3) {
            let text = try? String(contentsOf: pidFile, encoding: .utf8)
            lastText = text
            return text
        }
        guard let pid else {
            // Give an early exit/crash of the fake engine a moment to publish its
            // own error before failing, so the diagnostic is not just "nil".
            try? await Task.sleep(for: .milliseconds(150))
            XCTFail("engine did not publish a valid pid within 3s: "
                    + "file=\(lastText.map { $0.debugDescription } ?? "missing"), "
                    + "taskFinished=\(outcome.finished), "
                    + "taskError=\(String(describing: outcome.error))")
            task.cancel()
            _ = try? await task.value
            return
        }
        task.cancel()
        _ = try? await task.value

        // A second read must reap the TERM-ignoring child before it starts.
        let second = Task { try? await CodexAppServerClient(executable: engine, timeout: 1).readRateLimits() }
        try? await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(kill(pid, 0), -1, "previous child \(pid) is still alive")
        second.cancel()
        _ = await second.value
    }
}
