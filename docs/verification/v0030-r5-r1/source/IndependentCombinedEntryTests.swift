import XCTest
@testable import Valora

@MainActor
final class IndependentCombinedEntryTests: XCTestCase {
    func testEnablingCodexAfterDisabledStartupUpdatesSharedStatusFromBackground() async throws {
        let provider = CodexUsageProvider(readLimits: {
            CodexRateLimits(fiveHour: CodexQuotaWindow(usedPercent: 21, resetsAt: nil),
                            week: CodexQuotaWindow(usedPercent: 3, resetsAt: nil),
                            resetAvailableCount: 0, resetCredits: [], observedAt: Date())
        })
        let controller = MenuBarModuleController(monitor: SystemMonitor(),
            calendar: CalmonCalendarModel(), codexUsage: provider, onSettings: {}, onQuit: {})
        controller.setSystemMonitorVisible(false)
        controller.setCodexVisible(false)
        controller.setCalendarVisible(false)
        controller.start(startSampling: false)
        defer { controller.stop() }
        XCTAssertNil(controller.combinedItem)
        controller.setCodexVisible(true)
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline, !(controller.combinedItem?.button?.toolTip?.contains("79%") ?? false) {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(provider.snapshot.fiveHourRemainingPercentText, "79%")
        XCTAssertTrue(controller.combinedItem?.button?.toolTip?.contains("79%") ?? false,
                      "background quota completion must update the shared item after enabling from persisted off")
        XCTAssertTrue(controller.combinedItem?.button?.toolTip?.contains("97%") ?? false)
    }
}

@MainActor
extension IndependentCombinedEntryTests {
    func testMonitorEnableOffOnReconnectsAndContinuesSnapshotObservation() async throws {
        let monitor = SystemMonitor()
        let controller = MenuBarModuleController(monitor: monitor,
            calendar: CalmonCalendarModel(), codexUsage: nil, onSettings: {}, onQuit: {})
        controller.setSystemMonitorVisible(false)
        controller.setCodexVisible(false)
        controller.setCalendarVisible(false)
        controller.start(startSampling: false)
        defer { controller.stop() }
        XCTAssertNil(controller.combinedItem)
        controller.setSystemMonitorVisible(true)
        monitor.verificationApply(snapshot: SystemMonitor.Snapshot(
            cpu: .init(usage: 23),
            memory: .init(total: 32 * 1_073_741_824, used: 20 * 1_073_741_824),
            device: .init(chip: "Fixture", osVersion: "macOS 27")))
        let firstDeadline = Date().addingTimeInterval(1)
        while Date() < firstDeadline, !(controller.combinedItem?.button?.toolTip?.contains("23%") ?? false) {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(controller.combinedItem?.button?.toolTip?.contains("23%") ?? false,
                      "enabling monitor after off must attach the shared status observation")
        monitor.verificationApply(snapshot: SystemMonitor.Snapshot(
            cpu: .init(usage: 55),
            memory: .init(total: 32 * 1_073_741_824, used: 20 * 1_073_741_824),
            device: .init(chip: "Fixture", osVersion: "macOS 27")))
        let nextDeadline = Date().addingTimeInterval(1)
        while Date() < nextDeadline, !(controller.combinedItem?.button?.toolTip?.contains("55%") ?? false) {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(controller.combinedItem?.button?.toolTip?.contains("55%") ?? false)
    }

    func testCodexEnableOffOnReconnectsAndNextBackgroundUpdateReachesTooltip() async throws {
        let scheduler = CombinedManualScheduler()
        let calls = CombinedCounter()
        let provider = CodexUsageProvider(readLimits: {
            calls.value += 1
            let used = calls.value == 1 ? 21.0 : 40.0
            return CodexRateLimits(fiveHour: CodexQuotaWindow(usedPercent: used, resetsAt: nil),
                                   week: CodexQuotaWindow(usedPercent: 3, resetsAt: nil),
                                   resetAvailableCount: 0, resetCredits: [], observedAt: Date())
        }, refreshInterval: 180, scheduler: scheduler)
        let controller = MenuBarModuleController(monitor: SystemMonitor(),
            calendar: CalmonCalendarModel(), codexUsage: provider, onSettings: {}, onQuit: {})
        controller.setSystemMonitorVisible(false)
        controller.setCodexVisible(false)
        controller.setCalendarVisible(false)
        controller.start(startSampling: false)
        defer { controller.stop(); provider.stop() }
        controller.setCodexVisible(true)
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline, !(controller.combinedItem?.button?.toolTip?.contains("79%") ?? false) {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(controller.combinedItem?.button?.toolTip?.contains("79%") ?? false)
        scheduler.fireNext()
        let nextDeadline = Date().addingTimeInterval(2)
        while Date() < nextDeadline, !(controller.combinedItem?.button?.toolTip?.contains("60%") ?? false) {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(controller.combinedItem?.button?.toolTip?.contains("60%") ?? false,
                      "the observation must continue to receive subsequent background snapshots")

        controller.setCodexVisible(false)
        XCTAssertNil(controller.combinedItem)
        controller.setCodexVisible(true)
        let reconnected = Date().addingTimeInterval(2)
        while Date() < reconnected, !(controller.combinedItem?.button?.toolTip?.contains("60%") ?? false) {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertNotNil(controller.combinedItem?.button?.image)
        XCTAssertTrue(controller.combinedItem?.button?.toolTip?.contains("60%") ?? false,
                      "off-on must reconnect the shared status observation")
    }
}

private final class CombinedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = 0
    var value: Int {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); stored = newValue; lock.unlock() }
    }
}

@MainActor
private final class CombinedManualScheduler: CodexRefreshScheduling {
    final class Token: CodexScheduledRefresh {
        var action: (@MainActor () -> Void)?
        init(_ action: @escaping @MainActor () -> Void) { self.action = action }
        func cancel() { action = nil }
    }
    private var pending: [Token] = []
    func schedule(after interval: TimeInterval,
                  action: @escaping @MainActor () -> Void) -> any CodexScheduledRefresh {
        let token = Token(action)
        pending.append(token)
        return token
    }
    func fireNext() {
        guard let index = pending.firstIndex(where: { $0.action != nil }) else { return }
        let token = pending.remove(at: index)
        token.action?()
        token.action = nil
    }
}
