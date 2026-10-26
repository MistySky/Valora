import AppKit
import Foundation

/// One bounded, read-only live probe. It never sends account/read, a thread,
/// turn, model request or reset operation, and writes only redacted field
/// presence/status/timing to disk.
@MainActor
enum CodexUsageLiveProbe {
    @MainActor static func run(output: String) {
        Task { @MainActor in
            let started = Date()
            var fields: [String: Any] = [:]
            var status = "unknown"
            let locator = DefaultCodexEngineLocator()
            let engine = locator.find()
            do {
                guard engine != nil else {
                    status = "missing_engine"
                    fields = ["engineFound": false]
                    try Self.write(output: output, started: started, status: status, fields: fields)
                    NSApp.terminate(nil); return
                }
                let reading = try await CodexAppServerFetch(locator: locator, timeout: 12).fetch()
                status = "ok"
                fields = [
                    "engineFound": true,
                    "fiveHourPresent": reading.fiveHour != nil,
                    "fiveHourPercentPresent": reading.fiveHour?.usedPercent != nil,
                    "fiveHourResetPresent": reading.fiveHour?.resetsAt != nil,
                    "weekPresent": reading.week != nil,
                    "weekPercentPresent": reading.week?.usedPercent != nil,
                    "weekResetPresent": reading.week?.resetsAt != nil,
                    "resetCountPresent": reading.resetAvailableCount != nil,
                    "resetCreditEntries": reading.resetCredits.count,
                    "rawRPCStored": false,
                    "accountRead": false,
                    "accountFieldsStored": false
                ]
            } catch {
                status = Self.statusName(error)
                fields = ["engineFound": engine != nil,
                          "rawRPCStored": false,
                          "accountRead": false,
                          "accountFieldsStored": false]
            }
            try? Self.write(output: output, started: started, status: status, fields: fields)
            fputs("CODEX_USAGE_LIVE status=\(status) duration=\(Date().timeIntervalSince(started))\n", stderr)
            NSApp.terminate(nil)
        }
    }

    private static func statusName(_ error: Error) -> String {
        guard let e = error as? CodexUsageError else { return "error" }
        switch e {
        case .missingEngine: return "missing_engine"
        case .notSignedIn: return "not_signed_in"
        case .timeout: return "timeout"
        case .protocolError: return "protocol_error"
        case .processExited: return "process_exited"
        case .outputLimit: return "output_limit"
        }
    }

    private static func write(output: String, started: Date, status: String, fields: [String: Any]) throws {
        let dir = URL(fileURLWithPath: output, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var body = fields
        body["status"] = status
        body["durationSeconds"] = Date().timeIntervalSince(started)
        body["generatedAt"] = ISO8601DateFormatter().string(from: Date())
        body["readOnlyCommandAllowlist"] = ["initialize", "initialized", "account/rateLimits/read"]
        try JSONSerialization.data(withJSONObject: body, options: [.prettyPrinted, .sortedKeys])
            .write(to: dir.appendingPathComponent("codex-live-probe.json"))
    }
}
