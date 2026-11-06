import AppKit
import XCTest
@testable import Valora

/// V0098: activation ownership around the lock surface. Fake hooks only —
/// no NSApp activation, no login, no other app is really touched.
@MainActor
final class LockActivationOwnerTests: XCTestCase {
    private final class Fake {
        var policy: NSApplication.ActivationPolicy = .accessory
        var policyWrites: [NSApplication.ActivationPolicy] = []
        var activations = 0
        var frontmost = "com.example.editor"
        var selfIsFrontmost = true
        var locked = false
        var running: Set<String> = ["com.example.editor"]
        var activatedApps: [String] = []

        func hooks() -> LockActivationOwner.Hooks {
            LockActivationOwner.Hooks(
                currentPolicy: { self.policy },
                setPolicy: { self.policy = $0; self.policyWrites.append($0) },
                activateSelf: { self.activations += 1 },
                selfIsFrontmost: { self.selfIsFrontmost },
                sessionLockState: { self.locked },
                frontmostBundleIdentifier: { self.frontmost },
                isRunning: { self.running.contains($0) },
                activateApp: { self.activatedApps.append($0) })
        }
    }

    func testRepeatedAcquireAndReleaseRestoresPolicyOnce() {
        let fake = Fake()
        let owner = LockActivationOwner(hooks: fake.hooks())
        owner.acquire()
        owner.acquire()
        XCTAssertEqual(fake.policyWrites, [.regular])
        XCTAssertEqual(fake.activations, 1, "nested acquire must not re-activate")
        owner.release()
        XCTAssertEqual(fake.policyWrites, [.regular], "still owned: no restore yet")
        owner.release()
        XCTAssertEqual(fake.policyWrites, [.regular, .accessory])
        XCTAssertEqual(fake.activatedApps, ["com.example.editor"])
        XCTAssertEqual(owner.lastReleaseReason, "policy-restored; previous app activated")
    }

    func testReleaseWithoutAcquireNeverTouchesPolicy() {
        let fake = Fake()
        let owner = LockActivationOwner(hooks: fake.hooks())
        owner.release()
        XCTAssertTrue(fake.policyWrites.isEmpty)
        XCTAssertEqual(owner.lastReleaseReason, "not-owned")
    }

    /// The lock card and the preview may overlap: only the owner that changed the
    /// policy may restore it.
    func testOverlappingOwnersOnlyTheChangerRestores() {
        let fake = Fake()
        let first = LockActivationOwner(hooks: fake.hooks())
        let second = LockActivationOwner(hooks: fake.hooks())
        first.acquire()                     // .accessory → .regular
        second.acquire()                    // already .regular: records nothing
        XCTAssertEqual(fake.policyWrites, [.regular])
        second.release()
        XCTAssertEqual(fake.policyWrites, [.regular], "second must not restore")
        FirstRelease: do {
            XCTAssertEqual(second.lastReleaseReason, "policy-unchanged-by-this-owner")
            break FirstRelease
        }
        first.release()
        XCTAssertEqual(fake.policyWrites, [.regular, .accessory])
    }

    func testPolicyIsRestoredButPreviousAppIsNotActivatedWhileLocked() {
        let fake = Fake()
        fake.locked = true
        let owner = LockActivationOwner(hooks: fake.hooks())
        owner.acquire()
        owner.release()
        XCTAssertEqual(fake.policy, .accessory, "policy restore always happens")
        XCTAssertTrue(fake.activatedApps.isEmpty, "must not activate an app over the login window")
        XCTAssertEqual(owner.lastReleaseReason, "policy-restored; previous app not activated (locked)")
    }

    func testNoFocusStealWhenTheUserAlreadyMovedOn() {
        let fake = Fake()
        let owner = LockActivationOwner(hooks: fake.hooks())
        owner.acquire()
        fake.selfIsFrontmost = false        // user switched to another app
        owner.release()
        XCTAssertEqual(fake.policy, .accessory)
        XCTAssertTrue(fake.activatedApps.isEmpty)
        XCTAssertEqual(owner.lastReleaseReason, "policy-restored; previous app not activated (focus moved)")
    }

    func testTerminatedPreviousAppIsNotActivated() {
        let fake = Fake()
        let owner = LockActivationOwner(hooks: fake.hooks())
        owner.acquire()
        fake.running = []
        owner.release()
        XCTAssertTrue(fake.activatedApps.isEmpty)
        XCTAssertEqual(owner.lastReleaseReason, "policy-restored; previous app not activated (gone)")
    }

    func testAcquiringWhenAlreadyRegularDoesNotRecordOrActivate() {
        let fake = Fake()
        fake.policy = .regular
        fake.policyWrites = []
        let owner = LockActivationOwner(hooks: fake.hooks())
        owner.acquire()
        XCTAssertTrue(fake.policyWrites.isEmpty)
        XCTAssertEqual(fake.activations, 0)
        owner.release()
        XCTAssertTrue(fake.policyWrites.isEmpty)
        XCTAssertEqual(owner.lastReleaseReason, "policy-unchanged-by-this-owner")
    }

    func testRapidAcquireReleaseCyclesStayBalanced() {
        let fake = Fake()
        let owner = LockActivationOwner(hooks: fake.hooks())
        for _ in 0..<5 {
            owner.acquire()
            owner.release()
        }
        XCTAssertEqual(fake.policyWrites.filter { $0 == .regular }.count, 5)
        XCTAssertEqual(fake.policyWrites.filter { $0 == .accessory }.count, 5)
        XCTAssertEqual(fake.policy, .accessory)
    }

    // MARK: - Shared lifetime across surfaces (V0098-R1)

    private func shared(_ fake: Fake) -> (LockActivationRegistry,
                                          (LockActivationOwner, LockActivationOwner)) {
        let registry = LockActivationRegistry(hooks: fake.hooks())
        return (registry,
                (LockActivationOwner(registry: registry), LockActivationOwner(registry: registry)))
    }

    func testCardLeavesFirstThenPreviewRestoresOnce() {
        let fake = Fake()
        let (_, owners) = shared(fake)
        let (card, preview) = owners
        card.acquire(); preview.acquire()
        card.release()
        XCTAssertEqual(fake.policy, .regular, "preview still holds activation")
        XCTAssertTrue(fake.activatedApps.isEmpty)
        preview.release()
        XCTAssertEqual(fake.policy, .accessory)
        XCTAssertEqual(fake.policyWrites, [.regular, .accessory])
        XCTAssertEqual(fake.activatedApps, ["com.example.editor"])
    }

    func testPreviewLeavesFirstThenCardRestoresOnce() {
        let fake = Fake()
        let (_, owners) = shared(fake)
        let (card, preview) = owners
        card.acquire(); preview.acquire()
        preview.release()
        XCTAssertEqual(fake.policy, .regular)
        card.release()
        XCTAssertEqual(fake.policy, .accessory)
        XCTAssertEqual(fake.policyWrites, [.regular, .accessory])
    }

    func testRepeatedReleaseIsIgnoredAndNewCycleRecaptures() {
        let fake = Fake()
        let registry = LockActivationRegistry(hooks: fake.hooks())
        let owner = LockActivationOwner(registry: registry)
        owner.acquire(); owner.release(); owner.release()
        XCTAssertEqual(fake.policyWrites, [.regular, .accessory])
        mock: do {
            XCTAssertEqual(owner.lastReleaseReason, "not-owned")
        }
        fake.policyWrites = []
        fake.policy = .accessory
        owner.acquire()
        XCTAssertEqual(fake.policyWrites, [.regular], "a new cycle captures again")
        owner.release()
        XCTAssertEqual(fake.policyWrites, [.regular, .accessory])
    }

    func testNestedAcquireWithinOneOwnerIsBalanced() {
        let fake = Fake()
        let registry = LockActivationRegistry(hooks: fake.hooks())
        let owner = LockActivationOwner(registry: registry)
        owner.acquire(); owner.acquire()
        XCTAssertEqual(registry.activeScopeCount, 1)
        owner.release()
        XCTAssertEqual(fake.policy, .regular, "one nested release still holds")
        owner.release()
        XCTAssertEqual(fake.policy, .accessory)
    }

    // MARK: - Unknown lock state

    func testLockStateReaderTreatsMissingOrOddValuesAsUnknown() {
        XCTAssertNil(LockActivationRegistry.lockState(from: nil))
        XCTAssertNil(LockActivationRegistry.lockState(from: [:]))
        XCTAssertNil(LockActivationRegistry.lockState(from: ["CGSSessionScreenIsLocked": "yes"]))
        XCTAssertEqual(LockActivationRegistry.lockState(from: ["CGSSessionScreenIsLocked": true]), true)
        XCTAssertEqual(LockActivationRegistry.lockState(from: ["CGSSessionScreenIsLocked": false]), false)
        XCTAssertEqual(LockActivationRegistry.lockState(from: ["CGSSessionScreenIsLocked": NSNumber(value: 1)]), true)
    }

    func testUnknownLockStateNeverActivatesThePreviousApp() {
        let fake = Fake()
        let registry = LockActivationRegistry(hooks: LockActivationOwner.Hooks(
            currentPolicy: { fake.policy },
            setPolicy: { fake.policy = $0; fake.policyWrites.append($0) },
            activateSelf: { fake.activations += 1 },
            selfIsFrontmost: { true },
            sessionLockState: { nil },
            frontmostBundleIdentifier: { "com.example.editor" },
            isRunning: { _ in true },
            activateApp: { fake.activatedApps.append($0) }))
        let owner = LockActivationOwner(registry: registry)
        owner.acquire(); owner.release()
        XCTAssertEqual(fake.policy, .accessory)
        XCTAssertTrue(fake.activatedApps.isEmpty, "unknown lock state must not pull an app forward")
        XCTAssertEqual(owner.lastReleaseReason,
                       "policy-restored; previous app not activated (lock state unknown)")
    }
}
