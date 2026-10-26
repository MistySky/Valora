import Foundation
import XCTest
@testable import Valora

final class CodexUsageTransportTests: XCTestCase {
    private func temporaryScript(_ body: String) throws -> (URL, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("valora-codex-transport-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let script = root.appendingPathComponent("fake-codex")
        let data = Data(("#!/bin/sh\n" + body).utf8)
        try data.write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return (root, script)
    }

    private func client(_ script: URL, timeout: TimeInterval = 1) -> CodexAppServerClient {
        CodexAppServerClient(executable: script,
                             dataDirectory: script.deletingLastPathComponent(),
                             timeout: timeout)
    }

    func testFakeChildNormalProtocolRecordsExactlyThreeMethods() async throws {
        let (root, script) = try temporaryScript("""
        log="$1"
        read one; echo "$one" >> "$log"
        printf '{"id":1,"result":{}}\\n'
        read two; echo "$two" >> "$log"
        read three; echo "$three" >> "$log"
        printf '{"id":2,"result":{"rateLimitsByLimitId":{"codex":{"primary":{"usedPercent":12,"windowDurationMins":300},"secondary":{"usedPercent":34,"windowDurationMins":10080}}},"rateLimitResetCredits":{"availableCount":1,"credits":[]}}}\\n'
        sleep 0.4
        """)
        defer { try? FileManager.default.removeItem(at: root) }
        let log = root.appendingPathComponent("commands.log")
        // The production client launches `script app-server --listen stdio://`;
        // the fake records these exact stdin commands in a side file.
        let executable = root.appendingPathComponent("record-codex")
        try Data("""
        #!/bin/sh
        log="\(log.path)"
        exec "\(script.path)" "$log"
        """.utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        let reading = try await client(executable, timeout: 4).fetch()
        XCTAssertEqual(reading.fiveHour?.usedPercent, 12)
        XCTAssertEqual(reading.week?.usedPercent, 34)
        let commands = try String(contentsOf: log, encoding: .utf8)
            .split(separator: "\n").compactMap {
                (try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any])?["method"] as? String
            }
        XCTAssertEqual(commands, ["initialize", "initialized", "account/rateLimits/read"])
    }

    func testHardDeadlineExpiresUnderContinuousNotifications() async throws {
        let (root, script) = try temporaryScript("""
        while true; do printf '{"method":"notification"}\\n'; sleep 0.01; done
        """)
        defer { try? FileManager.default.removeItem(at: root) }
        let started = Date()
        do {
            _ = try await client(script, timeout: 0.25).fetch()
            XCTFail("continuous notifications must not bypass the hard deadline")
        } catch {
            XCTAssertEqual(error as? CodexUsageError, .timeout)
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 2.5)
    }

    func testOutputLimitStopsOversizedChild() async throws {
        let (root, script) = try temporaryScript("""
        head -c 1100000 /dev/zero | tr '\\0' x
        printf '\\n'
        sleep 0.2
        """)
        defer { try? FileManager.default.removeItem(at: root) }
        do {
            _ = try await client(script, timeout: 1).fetch()
            XCTFail("oversized output must fail")
        } catch {
            XCTAssertEqual(error as? CodexUsageError, .outputLimit)
        }
    }

    func testCancellationTerminatesFakeChild() async throws {
        let (root, script) = try temporaryScript("""
        echo $$ > "$1"
        sleep 60
        """)
        defer { try? FileManager.default.removeItem(at: root) }
        let pidFile = root.appendingPathComponent("child.pid")
        let executable = root.appendingPathComponent("pid-codex")
        try Data("""
        #!/bin/sh
        exec "\(script.path)" "\(pidFile.path)"
        """.utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let cancellableClient = client(executable, timeout: 60)
        let task = Task { try await cancellableClient.fetch() }
        let deadline = Date().addingTimeInterval(6)
        while !FileManager.default.fileExists(atPath: pidFile.path), Date() < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        guard FileManager.default.fileExists(atPath: pidFile.path) else {
            task.cancel()
            _ = await task.result
            return XCTFail("fake child did not start")
        }
        let pidText = try String(contentsOf: pidFile, encoding: .utf8)
        guard let pid = pid_t(pidText.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            task.cancel(); _ = await task.result; return XCTFail("invalid fake child pid")
        }
        task.cancel()
        _ = await task.result
        let stopped = Date().addingTimeInterval(4)
        while Date() < stopped {
            if kill(pid, 0) != 0 { break }
            try? await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertNotEqual(kill(pid, 0), 0, "cancelled child must be terminated, not left alive")
    }
}
