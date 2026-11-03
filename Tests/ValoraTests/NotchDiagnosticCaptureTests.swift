import XCTest
@testable import Valora

final class NotchDiagnosticCaptureTests: XCTestCase {
    func testRecordedFrameBurstCannotConsumeWindowSpaceOrUnlockSlots() throws {
        // Replay the user's own geometry-only trace, not a performance loop.
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let url = root.appendingPathComponent("docs/verification/independent-v0038/live-lock-2026-10-30/own-window-diagnostic.jsonl")
        let lines = try String(contentsOf: url, encoding: .utf8).split(separator: "\n")
        var policy = NotchDiagnosticCapturePolicy()
        for line in lines {
            let event = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
            _ = policy.shouldRecord(kind: event["kind"] as? String ?? "window",
                phase: event["phase"] as? String ?? "hidden", key: String(line),
                now: event["time"] as? Double ?? 0)
        }
        XCTAssertLessThan(policy.totalCount, 40)
        XCTAssertTrue(policy.shouldRecord(kind: "window", phase: "locked", key: "lock-window", now: 2_000_000_000))
        XCTAssertTrue(policy.shouldRecord(kind: "space", phase: "locked", key: "membership", now: 2_000_000_000))
        XCTAssertTrue(policy.shouldRecord(kind: "event", phase: "unlock-request", key: "locked", now: 2_000_000_001))
        XCTAssertTrue(policy.shouldRecord(kind: "window", phase: "unlocking", key: "unlock-window", now: 2_000_000_001))
        XCTAssertTrue(policy.shouldRecord(kind: "space", phase: "restoring", key: "detach", now: 2_000_000_002))
        XCTAssertTrue(policy.shouldRecord(kind: "window", phase: "returned-to-desktop", key: "restored-window", now: 2_000_000_003))
    }

    func testIndependentOverlayTrafficStillLeavesFinalHandoffRecords() {
        var p = NotchDiagnosticCapturePolicy()
        var now: TimeInterval = 0
        // Replay a bounded full lifecycle with the per-lane allowances introduced
        // by V0039. This is policy-only; it never opens or closes a window.
        for phase in ["hidden", "locking", "neutralizing", "locked", "unlocking", "restoring"] {
            for (kind, count) in [("swiftui-layout", 4), ("window", 6), ("space", 4), ("overlay", 8)] {
                for index in 0..<count {
                    now += 1
                    _ = p.shouldRecord(kind: kind, phase: phase, key: "\(index)", now: now)
                }
            }
        }
        XCTAssertTrue(p.shouldRecord(kind: "window", phase: "returned-to-desktop",
            key: "final-primary", now: now + 1), "overlay records must not consume the final primary handoff budget")
        XCTAssertTrue(p.shouldRecord(kind: "event", phase: "unlock-request",
            key: "unlock", now: now + 1))
    }

    func testSamplingIsPerKindAndPerPhase() {
        var p = NotchDiagnosticCapturePolicy()
        XCTAssertTrue(p.shouldRecord(kind: "swiftui-layout", phase: "locked", key: "a", now: 0))
        XCTAssertFalse(p.shouldRecord(kind: "swiftui-layout", phase: "locked", key: "b", now: 0.01))
        XCTAssertTrue(p.shouldRecord(kind: "window", phase: "locked", key: "window", now: 0.01))
        XCTAssertTrue(p.shouldRecord(kind: "swiftui-layout", phase: "unlocking", key: "a", now: 0.02))
        XCTAssertTrue(p.shouldRecord(kind: "swiftui-layout", phase: "locked", key: "b", now: 0.13))
        XCTAssertFalse(p.shouldRecord(kind: "swiftui-layout", phase: "locked", key: "b", now: 0.3))
    }
}
