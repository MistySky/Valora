import AppKit
import CoreGraphics
import IOKit.pwr_mgt
import notify

@MainActor
final class DisplayPowerMonitor {
    typealias ChangeHint = @MainActor @Sendable () -> Void
    typealias ObserveChanges = @MainActor (@escaping ChangeHint) -> () -> Void

    private(set) var allDisplaysAsleep = false
    var onChange: ((Bool) -> Void)?

    private let readAllDisplaysAsleep: () -> Bool
    private let observeChanges: ObserveChanges
    private var cancelObservation: (() -> Void)?
    private var generation = 0

    init(readAllDisplaysAsleep: @escaping () -> Bool = { readDisplaySleep() },
         observeChanges: @escaping ObserveChanges = observeSystemChanges) {
        self.readAllDisplaysAsleep = readAllDisplaysAsleep
        self.observeChanges = observeChanges
    }

    func start() {
        guard cancelObservation == nil else { return }
        generation += 1
        let current = generation
        cancelObservation = observeChanges { [weak self] in
            guard let self, self.generation == current else { return }
            self.refresh()
        }
        refresh()
    }

    // Also called by the existing media tick: display sleep can occur while
    // the machine stays awake without an AppKit sleep notification.
    func refresh() {
        guard cancelObservation != nil else { return }
        setAsleep(readAllDisplaysAsleep())
    }

    func stop() {
        generation += 1
        cancelObservation?()
        cancelObservation = nil
        setAsleep(false)
    }

    isolated deinit { cancelObservation?() }

    private func setAsleep(_ value: Bool) {
        guard allDisplaysAsleep != value else { return }
        allDisplaysAsleep = value
        onChange?(value)
    }

    static func readDisplaySleep(
        online: (UInt32, UnsafeMutablePointer<CGDirectDisplayID>?, UnsafeMutablePointer<UInt32>?) -> CGError = CGGetOnlineDisplayList,
        isAsleep: (CGDirectDisplayID) -> Bool = { CGDisplayIsAsleep($0) != 0 }
    ) -> Bool {
        var count: UInt32 = 0
        guard online(0, nil, &count) == .success, count > 0, count < UInt32.max else { return false }
        // One spare entry detects hot-plug growth between the count and list
        // calls. An incomplete or empty snapshot must keep rendering enabled.
        let capacity = count + 1
        return withUnsafeTemporaryAllocation(of: CGDirectDisplayID.self, capacity: Int(capacity)) { displays in
            guard online(capacity, displays.baseAddress, &count) == .success,
                  count > 0, count < capacity else { return false }
            return displays.prefix(Int(count)).allSatisfy(isAsleep)
        }
    }

    private static func observeSystemChanges(_ hint: @escaping ChangeHint) -> () -> Void {
        let workspace = NSWorkspace.shared.notificationCenter
        let notifications: [(NotificationCenter, Notification.Name)] = [
            (workspace, NSWorkspace.screensDidSleepNotification),
            (workspace, NSWorkspace.screensDidWakeNotification),
            (workspace, NSWorkspace.didWakeNotification),
            (.default, NSApplication.didChangeScreenParametersNotification),
            (DistributedNotificationCenter.default(), Notification.Name("com.apple.screenIsUnlocked"))
        ]
        let observers = notifications.map { center, name in
            (center, center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { hint() }
            })
        }
        // These process-wide hints can arrive before a display transition
        // finishes. CoreGraphics remains the source of truth for each screen.
        let darwinTokens = [kIOSystemLoadAdvisoryNotifyName, "com.apple.iokit.hid.displayStatus"].compactMap { name -> Int32? in
            var token: Int32 = 0
            let status = notify_register_dispatch(name, &token, .main) { _ in
                MainActor.assumeIsolated { hint() }
            }
            return status == NOTIFY_STATUS_OK ? token : nil
        }
        return {
            for (center, observer) in observers { center.removeObserver(observer) }
            for token in darwinTokens { notify_cancel(token) }
        }
    }
}
