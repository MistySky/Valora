import AppKit
import XCTest
@testable import Valora

@MainActor
final class IndependentLockActivationLifetimeTests: XCTestCase {
    func testFirstOwnerLeavingMustNotRestorePolicyWhileSecondOwnerRemains() {
        var policy: NSApplication.ActivationPolicy = .accessory
        var writes: [NSApplication.ActivationPolicy] = []
        var restoredApps: [String] = []
        let hooks = LockActivationOwner.Hooks(
            currentPolicy: { policy },
            setPolicy: { policy = $0; writes.append($0) },
            activateSelf: {},
            selfIsFrontmost: { true },
            sessionLockState: { false },
            frontmostBundleIdentifier: { "com.example.editor" },
            isRunning: { _ in true },
            activateApp: { restoredApps.append($0) })
        // The two surfaces must share one activation lifetime (V0098-R1).
        let registry = LockActivationRegistry(hooks: hooks)
        let card = LockActivationOwner(registry: registry)
        let preview = LockActivationOwner(registry: registry)
        card.acquire()
        preview.acquire()
        card.release()
        XCTAssertEqual(policy, .regular,
                       "card must not restore while preview still owns activation")
        XCTAssertTrue(restoredApps.isEmpty,
                      "must not reactivate previous app while another surface remains")
        preview.release()
        XCTAssertEqual(policy, .accessory)
        XCTAssertEqual(writes, [.regular, .accessory], "restore only after final owner exits")
        XCTAssertEqual(restoredApps, ["com.example.editor"])
    }

    /// V0098-R2: the lock state is read once and used as one snapshot. This
    /// reader says "unlocked" on the first call and would say "unknown" on any
    /// second call, so a re-query or a combined read would be visible here.
    func testLockStateIsReadOnceAndNeverRecombined() {
        var policy: NSApplication.ActivationPolicy = .accessory
        var reads = 0
        var activations: [String] = []
        let hooks = LockActivationRegistry.Hooks(
            currentPolicy: { policy }, setPolicy: { policy = $0 },
            activateSelf: {}, selfIsFrontmost: { true },
            sessionLockState: {
                reads += 1
                return reads == 1 ? false : nil
            },
            frontmostBundleIdentifier: { "com.example.editor" },
            isRunning: { _ in true }, activateApp: { activations.append($0) })
        let owner = LockActivationOwner(registry: LockActivationRegistry(hooks: hooks))
        owner.acquire(); owner.release()
        XCTAssertEqual(reads, 1, "release must read the lock state exactly once")
        XCTAssertEqual(activations, ["com.example.editor"],
                       "a single confirmed-unlocked snapshot allows the guarded restore")
    }

    /// nil (unknown) and true (locked) both keep the previous app down; only an
    /// explicit false continues (other guards still apply).
    func testUnknownOrLockedSnapshotNeverActivates() {
        for state in [nil, true] as [Bool?] {
            var policy: NSApplication.ActivationPolicy = .accessory
            var activations: [String] = []
            let hooks = LockActivationRegistry.Hooks(
                currentPolicy: { policy }, setPolicy: { policy = $0 },
                activateSelf: {}, selfIsFrontmost: { true },
                sessionLockState: { state },
                frontmostBundleIdentifier: { "com.example.editor" },
                isRunning: { _ in true }, activateApp: { activations.append($0) })
            let owner = LockActivationOwner(registry: LockActivationRegistry(hooks: hooks))
            owner.acquire(); owner.release()
            XCTAssertEqual(policy, .accessory)
            XCTAssertTrue(activations.isEmpty, "state \(String(describing: state)) must not activate")
        }
    }
}
