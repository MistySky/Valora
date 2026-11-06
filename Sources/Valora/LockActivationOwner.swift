import AppKit

/// Shared lifetime for the temporary activation taken while lock surfaces are on
/// screen.
///
/// Why it exists: the current implementation makes the panel key and raises the
/// app so the material renders in its active state (an implementation
/// observation, not a system guarantee). That temporarily changes the app's
/// activation policy and takes focus; this registry keeps the change explicit,
/// bounded and reversible.
///
/// Rules:
/// * Every surface holds a scope; the policy is captured once when the first
///   scope enters and restored only when the last scope leaves, whatever the
///   exit order.
/// * A scope that never changed anything (the app was already regular, i.e.
///   another surface raised it) records nothing and restores nothing.
/// * Re-activating the previously frontmost app is conservative: it needs
///   positive evidence that the session is unlocked, that Valora is *still*
///   frontmost, and that the app is still running.
@MainActor
final class LockActivationRegistry {
    struct Hooks {
        var currentPolicy: () -> NSApplication.ActivationPolicy
        var setPolicy: (NSApplication.ActivationPolicy) -> Void
        /// Raise this app and make the surface key.
        var activateSelf: () -> Void
        /// Whether this app is currently frontmost.
        var selfIsFrontmost: () -> Bool
        /// Session lock state, read **once** per release: `true` locked,
        /// `false` unlocked, `nil` unknown. A second query could disagree with
        /// the first, so callers must never combine two reads.
        var sessionLockState: () -> Bool?
        /// Bundle identifier of the app that was frontmost before acquiring.
        var frontmostBundleIdentifier: () -> String?
        /// Whether that identifier still refers to a running app.
        var isRunning: (String) -> Bool
        /// Bring that app back to the front.
        var activateApp: (String) -> Void
    }

    /// One registry for the whole app: the lock card and the preview must share
    /// it, otherwise whichever leaves first would restore the policy while the
    /// other surface is still up.
    static let shared = LockActivationRegistry(hooks: productionHooks())

    private let hooks: Hooks
    private var depth = 0
    private var savedPolicy: NSApplication.ActivationPolicy?
    private var savedPreviousApp: String?
    /// Last restore outcome, for diagnostics only (no titles/accounts).
    private(set) var lastReleaseReason: String?

    init(hooks: Hooks) {
        self.hooks = hooks
    }

    var activeScopeCount: Int { depth }

    func acquire() {
        depth += 1
        guard depth == 1 else { return }
        let policy = hooks.currentPolicy()
        guard policy != .regular else {
            // Another owner already raised the app: record nothing, so the final
            // release leaves it alone.
            savedPolicy = nil
            savedPreviousApp = nil
            return
        }
        savedPolicy = policy
        savedPreviousApp = hooks.frontmostBundleIdentifier()
        hooks.setPolicy(.regular)
        hooks.activateSelf()
    }

    func release() {
        guard depth > 0 else {
            lastReleaseReason = "not-owned"
            return
        }
        depth -= 1
        guard depth == 0 else {
            lastReleaseReason = "still-owned"
            return
        }
        let policy = savedPolicy
        let previous = savedPreviousApp
        savedPolicy = nil
        savedPreviousApp = nil
        guard let policy else {
            lastReleaseReason = "policy-unchanged-by-this-owner"
            return
        }
        hooks.setPolicy(policy)
        guard let previous, previous != Bundle.main.bundleIdentifier else {
            lastReleaseReason = "policy-restored"
            return
        }
        // One snapshot decides everything: unknown (nil) and locked are treated
        // the same — never pull another app forward over a possible login window.
        switch hooks.sessionLockState() {
        case .none:
            lastReleaseReason = "policy-restored; previous app not activated (lock state unknown)"
            return
        case .some(true):
            lastReleaseReason = "policy-restored; previous app not activated (locked)"
            return
        case .some(false):
            break
        }
        guard hooks.selfIsFrontmost() else {
            lastReleaseReason = "policy-restored; previous app not activated (focus moved)"
            return
        }
        guard hooks.isRunning(previous) else {
            lastReleaseReason = "policy-restored; previous app not activated (gone)"
            return
        }
        hooks.activateApp(previous)
        lastReleaseReason = "policy-restored; previous app activated"
    }

    static func productionHooks() -> Hooks {
        Hooks(
            currentPolicy: { NSApplication.shared.activationPolicy() },
            setPolicy: { _ = NSApplication.shared.setActivationPolicy($0) },
            activateSelf: { NSApplication.shared.activate(ignoringOtherApps: true) },
            selfIsFrontmost: {
                NSWorkspace.shared.frontmostApplication?.processIdentifier
                    == ProcessInfo.processInfo.processIdentifier
            },
            sessionLockState: { productionSessionLocked() },
            frontmostBundleIdentifier: {
                NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            },
            isRunning: { identifier in
                NSRunningApplication.runningApplications(withBundleIdentifier: identifier).isEmpty == false
            },
            activateApp: { identifier in
                NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
                    .first?.activate(options: [])
            })
    }

    /// `nil` means "the session dictionary did not tell us" — not "unlocked".
    nonisolated static func productionSessionLocked() -> Bool? {
        lockState(from: CGSessionCopyCurrentDictionary() as? [String: Any])
    }

    /// Pure reader for the session lock flag. Missing session, missing key or a
    /// non-numeric value all stay `nil` (unknown), which the owner treats as
    /// locked.
    nonisolated static func lockState(from session: [String: Any]?) -> Bool? {
        guard let session else { return nil }
        guard let value = session["CGSSessionScreenIsLocked"] else { return nil }
        if let bool = value as? Bool { return bool }
        if let number = value as? NSNumber { return number.boolValue }
        return nil
    }
}

/// One surface's hold on the shared activation. Own acquire/release flags keep
/// repeated or unbalanced calls from disturbing other surfaces.
@MainActor
final class LockActivationOwner {
    typealias Hooks = LockActivationRegistry.Hooks

    private let registry: LockActivationRegistry
    private var depth = 0
    /// Reason reported for an unbalanced release, when the shared registry was
    /// never touched at all.
    private var localReason: String?

    init(registry: LockActivationRegistry) {
        self.registry = registry
    }

    /// Convenience for a single-surface owner; production shares
    /// `LockActivationRegistry.shared` instead.
    convenience init(hooks: Hooks) {
        self.init(registry: LockActivationRegistry(hooks: hooks))
    }

    var isOwned: Bool { depth > 0 }
    var lastReleaseReason: String? { localReason ?? registry.lastReleaseReason }

    /// Nested acquires within one surface are balanced; only the outermost one
    /// reaches the shared registry, so a repeated acquire cannot double-hold it.
    func acquire() {
        depth += 1
        guard depth == 1 else { return }
        localReason = nil
        registry.acquire()
    }

    func release() {
        guard depth > 0 else {
            localReason = "not-owned"
            return
        }
        depth -= 1
        guard depth == 0 else {
            localReason = "still-owned"
            return
        }
        localReason = nil
        registry.release()
    }
}
