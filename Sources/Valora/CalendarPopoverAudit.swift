import AppKit
import Darwin
import Foundation

/// Calendar-only lifecycle/memory audit.
///
/// Transient mode uses the production `NSPopover.behavior = .transient`.
/// Fixed mode is explicitly QA-only: it sets `.applicationDefined` on the same
/// popover/view/model to isolate host focus. Fixed-mode memory is never labeled
/// as production transient interaction.
@MainActor
enum CalendarPopoverAudit {
    private struct Sample {
        let label: String
        let seconds: Double
        let shown: Bool
        let appActive: Bool
        let windowKey: Bool
        let windowVisible: Bool
        let physical: UInt64
        let resident: UInt64
        let eventStarts: Int
        let eventCompletions: Int
        let eventDiscards: Int
        let closeCount: Int
        let cacheEntries: Int
    }

    @MainActor static func run(output: String, fixedDisplay: Bool) {
        Task { @MainActor in
            let startedAt = Date()
            let mode = fixedDisplay ? "fixed-qa-applicationDefined" : "production-transient"
            do {
                let directory = URL(fileURLWithPath: output, isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

                let monitor = SystemMonitor()
                monitor.verificationApply(snapshot: SystemMonitor.Snapshot(
                    cpu: .init(usage: 23),
                    memory: .init(total: 32 * 1_073_741_824, used: 20 * 1_073_741_824),
                    disk: .init(volumePath: "/", volumeIdentifier: "preview",
                                total: 500_000_000_000, available: 200_000_000_000,
                                used: 300_000_000_000),
                    device: .init(chip: "Preview chip", osVersion: "macOS 27"),
                    uptime: "已运行 1 天"))
                let calendar = CalmonCalendarModel(
                    calendar: .current, now: Date.init,
                    eventProvider: PreviewCalendarEvents(),
                    readGate: { true }, preview: true)
                let appItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
                appItem.button?.setAccessibilityLabel("Valora calendar audit")
                let appMenu = NSMenu()
                let version = NSMenuItem(title: AppMenuCommands.versionText, action: nil, keyEquivalent: "")
                version.isEnabled = false
                appMenu.addItem(version)
                appMenu.addItem(.separator())
                appMenu.addItem(NSMenuItem(title: AppMenuCommands.settingsTitle, action: nil, keyEquivalent: ""))
                appMenu.addItem(.separator())
                appMenu.addItem(NSMenuItem(title: AppMenuCommands.quitTitle, action: nil, keyEquivalent: ""))
                appItem.menu = appMenu

                let controller = MenuBarModuleController(
                    monitor: monitor, calendar: calendar,
                    onSettings: {}, onQuit: {},
                    calendarPopoverBehavior: fixedDisplay ? .applicationDefined : .transient)
                controller.start(startSampling: false)
                try? await Task.sleep(for: .milliseconds(500))

                let diagnostics = CalendarAuditDiagnostics()
                let popover = controller.calendarPopoverForDiagnostics
                let closeToken = NotificationCenter.default.addObserver(
                    forName: NSPopover.didCloseNotification, object: popover, queue: .main
                ) { _ in
                    Task { @MainActor in
                        diagnostics.recordClose(startedAt: startedAt, controller: controller)
                    }
                }
                let appResignToken = NotificationCenter.default.addObserver(
                    forName: NSApplication.didResignActiveNotification, object: NSApp, queue: .main
                ) { _ in
                    Task { @MainActor in
                        diagnostics.recordAppResign(startedAt: startedAt, controller: controller)
                    }
                }

                NSApp.activate(ignoringOtherApps: true)
                controller.showCalendarPanel()
                try? await Task.sleep(for: .milliseconds(500))
                let window = controller.calendarPopoverWindow
                var resignKeyToken: NSObjectProtocol?
                if let window {
                    resignKeyToken = NotificationCenter.default.addObserver(
                        forName: NSWindow.didResignKeyNotification, object: window, queue: .main
                    ) { _ in
                        Task { @MainActor in
                            diagnostics.recordWindowResign(startedAt: startedAt, controller: controller)
                        }
                    }
                }

                var tracker = ContinuousVisibilityTracker(expectedSeconds: 180, expectedSamples: 37)
                var samples: [Sample] = []
                let first = Self.sample(label: "start", startedAt: startedAt, controller: controller, calendar: calendar, monitor: monitor)
                samples.append(first)
                tracker.record(visible: first.shown, elapsed: first.seconds)

                if first.shown {
                    for index in 1...36 {
                        try? await Task.sleep(for: .seconds(5))
                        let value = Self.sample(label: "\(index * 5)s", startedAt: startedAt,
                                                controller: controller, calendar: calendar, monitor: monitor)
                        samples.append(value)
                        tracker.record(visible: value.shown, elapsed: value.seconds)
                        if !value.shown { break }
                    }
                }

                let status = tracker.status
                let closeCount = controller.calendarPopoverCloseCount
                let wasShownAtEnd = controller.isCalendarPanelShown
                controller.closeAllPopovers()
                try? await Task.sleep(for: .milliseconds(700))
                let windowStillKey = window?.isKeyWindow ?? false
                if let resignKeyToken { NotificationCenter.default.removeObserver(resignKeyToken) }
                NotificationCenter.default.removeObserver(closeToken)
                NotificationCenter.default.removeObserver(appResignToken)
                controller.stop()
                NSStatusBar.system.removeStatusItem(appItem)

                let result: [String: Any] = [
                    "schema": 1,
                    "mode": mode,
                    "productionTransient": !fixedDisplay,
                    "requestedSeconds": 180,
                    "startedAt": ISO8601DateFormatter().string(from: startedAt),
                    "finishedAt": ISO8601DateFormatter().string(from: Date()),
                    "durationSeconds": Date().timeIntervalSince(startedAt),
                    "status": status.rawValue,
                    "validLongOpen": status == .completed,
                    "visibleSamples": tracker.visibleSamples,
                    "totalSamples": tracker.totalSamples,
                    "visibleSeconds": tracker.visibleSeconds,
                    "firstInvisibleAt": tracker.firstInvisibleAt ?? -1,
                    "wasShownAtEnd": wasShownAtEnd,
                    "windowWasKeyAfterClose": windowStillKey,
                    "calendarPopoverCloseCount": closeCount,
                    "closeEvents": diagnostics.closeEvents,
                    "windowResignKeyEvents": diagnostics.windowResignKeyEvents,
                    "appResignActiveEvents": diagnostics.appResignActiveEvents,
                    "applicationActiveAtFinish": NSApp.isActive,
                    "samples": samples.map { Self.encode($0) },
                    "diagnosticsOnly": true,
                    "personalEventsRead": false,
                    "mediaCommandsSent": false,
                    "permissionsRequested": false
                ]
                try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
                    .write(to: directory.appendingPathComponent("calendar-audit.json"))
                fputs("CALENDAR_AUDIT mode=\(mode) status=\(status.rawValue) visible=\(tracker.visibleSamples)/\(tracker.totalSamples) closes=\(closeCount)\n", stderr)
            } catch {
                fputs("Calendar audit failed: \(error)\n", stderr)
            }
            NSApp.terminate(nil)
        }
    }

    @MainActor private static func sample(label: String, startedAt: Date,
                                           controller: MenuBarModuleController,
                                           calendar: CalmonCalendarModel,
                                           monitor: SystemMonitor) -> Sample {
        let memory = Self.memorySnapshot()
        let window = controller.calendarPopoverWindow
        return Sample(label: label, seconds: Date().timeIntervalSince(startedAt),
                      shown: controller.isCalendarPanelShown,
                      appActive: NSApp.isActive,
                      windowKey: window?.isKeyWindow ?? false,
                      windowVisible: window?.isVisible ?? false,
                      physical: memory.physical, resident: memory.resident,
                      eventStarts: calendar.eventReadStartCount,
                      eventCompletions: calendar.eventReadCompletionCount,
                      eventDiscards: calendar.eventReadDiscardCount,
                      closeCount: controller.calendarPopoverCloseCount,
                      cacheEntries: 0)
    }

    private static func encode(_ sample: Sample) -> [String: Any] {
        ["label": sample.label, "seconds": sample.seconds, "shown": sample.shown,
         "appActive": sample.appActive, "windowKey": sample.windowKey,
         "windowVisible": sample.windowVisible,
         "physicalFootprint": sample.physical, "residentBytes": sample.resident,
         "calendarEventStarts": sample.eventStarts,
         "calendarEventCompletions": sample.eventCompletions,
         "calendarEventDiscards": sample.eventDiscards,
         "calendarPopoverCloseCount": sample.closeCount,
         "cacheEntries": sample.cacheEntries]
    }

    @MainActor static func diagnosticEvent(label: String, startedAt: Date,
                                                   controller: MenuBarModuleController,
                                                   window: NSWindow?) -> [String: Any] {
        let memory = Self.memorySnapshot()
        return ["event": label,
                "seconds": Date().timeIntervalSince(startedAt),
                "appActive": NSApp.isActive,
                "windowKey": window?.isKeyWindow ?? false,
                "windowVisible": window?.isVisible ?? false,
                "shown": controller.isCalendarPanelShown,
                "closeCount": controller.calendarPopoverCloseCount,
                "physicalFootprint": memory.physical,
                "residentBytes": memory.resident]
    }

    private static func memorySnapshot() -> (physical: UInt64, resident: UInt64) {
        var info = rusage_info_v4()
        let physicalResult: Int32 = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { pointer in
                proc_pid_rusage(getpid(), RUSAGE_INFO_V4, pointer)
            }
        }
        let physical = physicalResult == 0 ? info.ri_phys_footprint : 0
        var basic = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let residentResult: Int32 = withUnsafeMutablePointer(to: &basic) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        let resident = residentResult == KERN_SUCCESS ? UInt64(basic.resident_size) : 0
        return (physical, resident)
    }
}


@MainActor
private final class CalendarAuditDiagnostics {
    var closeEvents: [[String: Any]] = []
    var windowResignKeyEvents: [[String: Any]] = []
    var appResignActiveEvents: [[String: Any]] = []

    func recordClose(startedAt: Date, controller: MenuBarModuleController) {
        closeEvents.append(CalendarPopoverAudit.diagnosticEvent(
            label: "popoverDidClose", startedAt: startedAt, controller: controller,
            window: controller.calendarPopoverWindow))
    }

    func recordWindowResign(startedAt: Date, controller: MenuBarModuleController) {
        windowResignKeyEvents.append(CalendarPopoverAudit.diagnosticEvent(
            label: "windowDidResignKey", startedAt: startedAt, controller: controller,
            window: controller.calendarPopoverWindow))
    }

    func recordAppResign(startedAt: Date, controller: MenuBarModuleController) {
        appResignActiveEvents.append(CalendarPopoverAudit.diagnosticEvent(
            label: "appDidResignActive", startedAt: startedAt, controller: controller,
            window: controller.calendarPopoverWindow))
    }
}
