#if VALORA_DEVELOPMENT
import AppKit
import Darwin
import Foundation

/// Isolated lifecycle/memory audit for the two Calmon menu-bar modules.
///
/// The audit intentionally uses fake calendar events and a fake application
/// reader so no personal events or application metadata are collected. It does
/// read the process's own resident/phys-footprint values and runs the real
/// SystemMonitor CPU/MEM scheduler (public system counters) while panels open.
/// It is a QA command only, never started by the production app.
@MainActor
enum MenuBarMemoryAudit {
    private struct Point {
        let label: String
        let seconds: Double
        let physicalFootprint: UInt64
        let residentBytes: UInt64
        let monitorRunning: Bool
        let monitorSampling: Bool
        let sampleStarts: Int
        let sampleCompletions: Int
        let staleSamples: Int
        let calendarPanelVisible: Bool
        let monitorPanelVisible: Bool
        let readerCacheEntries: Int
        let readerCacheEvictions: Int
        let monitorItemIdentity: String?
        let calendarItemIdentity: String?
        let popoverIdentity: String?
    }

    @MainActor static func run(output: String) {
        Task { @MainActor in
            do {
                let directory = URL(fileURLWithPath: output, isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let startedAt = Date()
                var reader: AuditAppMemoryReader? = AuditAppMemoryReader()
                var monitor: SystemMonitor? = SystemMonitor(reader: reader!)
                let now = Date()
                var calendar: CalmonCalendarModel? = CalmonCalendarModel(
                    calendar: .current, now: { now },
                    readGate: { true }, preview: true)

                let appItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
                appItem.button?.setAccessibilityLabel("Valora audit")
                let appMenu = NSMenu()
                let version = NSMenuItem(title: AppMenuCommands.versionText, action: nil, keyEquivalent: "")
                version.isEnabled = false
                appMenu.addItem(version)
                appMenu.addItem(.separator())
                appMenu.addItem(NSMenuItem(title: AppMenuCommands.settingsTitle, action: nil, keyEquivalent: ""))
                appMenu.addItem(.separator())
                appMenu.addItem(NSMenuItem(title: AppMenuCommands.quitTitle, action: nil, keyEquivalent: ""))
                appItem.menu = appMenu

                var controller: MenuBarModuleController? = MenuBarModuleController(
                    monitor: monitor!, calendar: calendar!,
                    onSettings: {}, onQuit: {})
                var points: [Point] = []
                @MainActor func point(_ label: String) {
                    guard let controller else { return }
                    points.append(Self.point(label: label, startedAt: startedAt, monitor: monitor!,
                                             calendar: calendar!, reader: reader!,
                                             controller: controller))
                }

                var controllerRef: MenuBarModuleController? = controller
                point("cold-process-baseline")
                controllerRef!.start(startSampling: true)
                try? await Task.sleep(for: .milliseconds(900))
                let monitorItemID = controllerRef!.monitorItem.map { String(describing: ObjectIdentifier($0)) }
                let calendarItemID = controllerRef!.calendarItem.map { String(describing: ObjectIdentifier($0)) }
                let monitorPopoverID = String(describing: controllerRef!.monitorPopoverIdentity)
                let calendarPopoverID = String(describing: controllerRef!.calendarPopoverIdentity)
                point("first-start-warmup")

                @MainActor func open(_ module: MenuBarModuleController.MenuBarModule) {
                    if module == .calendar { controllerRef!.showCalendarPanel() }
                    else { controllerRef!.showMonitorPanel() }
                }
                @MainActor func closeAll() { controllerRef!.closeAllPopovers() }
                @MainActor func waitUntilClosed(_ module: MenuBarModuleController.MenuBarModule) async {
                    for _ in 0..<20 {
                        let shown = module == .calendar
                            ? controllerRef!.isCalendarPanelShown
                            : controllerRef!.isMonitorPanelShown
                        if !shown { return }
                        try? await Task.sleep(for: .milliseconds(50))
                    }
                }

                // First open/close is the view/font/icon warmup, kept separate
                // from the 30-cycle steady-state sequence.
                open(.calendar)
                try? await Task.sleep(for: .milliseconds(250))
                point("calendar-first-open")
                closeAll()
                await waitUntilClosed(.calendar)
                try? await Task.sleep(for: .milliseconds(650))
                point("calendar-first-close-settle")

                open(.systemMonitor)
                try? await Task.sleep(for: .milliseconds(250))
                point("monitor-first-open")
                closeAll()
                await waitUntilClosed(.systemMonitor)
                try? await Task.sleep(for: .milliseconds(650))
                point("monitor-first-close-settle")

                // 30 calendar open/close cycles and 30 monitor cycles, each
                // isolated to the same status-item/popover identities.
                for index in 1...30 {
                    open(.calendar)
                    try? await Task.sleep(for: .milliseconds(260))
                    closeAll()
                    await waitUntilClosed(.calendar)
                    try? await Task.sleep(for: .milliseconds(300))
                    points.append(Self.point(label: "calendar-cycle-\(index)", startedAt: startedAt,
                                             monitor: monitor!, calendar: calendar!, reader: reader!,
                                             controller: controllerRef!))
                }
                try? await Task.sleep(for: .seconds(1))
                point("calendar-30cycles-settle")

                for index in 1...30 {
                    open(.systemMonitor)
                    try? await Task.sleep(for: .milliseconds(260))
                    closeAll()
                    await waitUntilClosed(.systemMonitor)
                    try? await Task.sleep(for: .milliseconds(300))
                    points.append(Self.point(label: "monitor-cycle-\(index)", startedAt: startedAt,
                                             monitor: monitor!, calendar: calendar!, reader: reader!,
                                             controller: controllerRef!))
                }
                try? await Task.sleep(for: .seconds(1))
                point("monitor-30cycles-settle")

                // At least three continuous minutes for each module. A hidden
                // sample ends the run; it is never reported as a long-open pass
                // and is never reopened/stitched into a synthetic segment.
                var continuousResults: [String: Any] = [:]
                var calendarTracker = ContinuousVisibilityTracker(expectedSeconds: 180, expectedSamples: 37)
                open(.calendar)
                try? await Task.sleep(for: .milliseconds(300))
                let calendarStart = Self.point(label: "calendar-continuous-start", startedAt: startedAt,
                                               monitor: monitor!, calendar: calendar!, reader: reader!,
                                               controller: controllerRef!)
                points.append(calendarStart)
                calendarTracker.record(visible: calendarStart.calendarPanelVisible,
                                       elapsed: calendarStart.seconds)
                if calendarStart.calendarPanelVisible {
                    for index in 1...36 {
                        try? await Task.sleep(for: .seconds(5))
                        let q = Self.point(label: "calendar-continuous-\(index * 5)s", startedAt: startedAt,
                                           monitor: monitor!, calendar: calendar!, reader: reader!,
                                           controller: controllerRef!)
                        points.append(q)
                        calendarTracker.record(visible: q.calendarPanelVisible, elapsed: q.seconds)
                        if !q.calendarPanelVisible { break }
                    }
                }
                var calendarSummary = calendarTracker.summary
                calendarSummary["popoverCloseCountAtEnd"] = controllerRef!.calendarPopoverCloseCount
                calendarSummary["lastPopoverCloseAt"] = controllerRef!.lastCalendarPopoverCloseAt.map {
                    ISO8601DateFormatter().string(from: $0)
                } ?? "nil"
                continuousResults["calendar"] = calendarSummary
                closeAll()
                await waitUntilClosed(.calendar)
                try? await Task.sleep(for: .milliseconds(800))
                point("calendar-continuous-close-settle")

                var monitorTracker = ContinuousVisibilityTracker(expectedSeconds: 180, expectedSamples: 37)
                open(.systemMonitor)
                try? await Task.sleep(for: .milliseconds(300))
                let monitorStart = Self.point(label: "monitor-continuous-start", startedAt: startedAt,
                                              monitor: monitor!, calendar: calendar!, reader: reader!,
                                              controller: controllerRef!)
                points.append(monitorStart)
                monitorTracker.record(visible: monitorStart.monitorPanelVisible, elapsed: monitorStart.seconds)
                if monitorStart.monitorPanelVisible {
                    for index in 1...36 {
                        try? await Task.sleep(for: .seconds(5))
                        let q = Self.point(label: "monitor-continuous-\(index * 5)s", startedAt: startedAt,
                                           monitor: monitor!, calendar: calendar!, reader: reader!,
                                           controller: controllerRef!)
                        points.append(q)
                        monitorTracker.record(visible: q.monitorPanelVisible, elapsed: q.seconds)
                        if !q.monitorPanelVisible { break }
                    }
                }
                var monitorSummary = monitorTracker.summary
                monitorSummary["popoverCloseCountAtEnd"] = controllerRef!.monitorPopoverCloseCount
                monitorSummary["lastPopoverCloseAt"] = controllerRef!.lastMonitorPopoverCloseAt.map {
                    ISO8601DateFormatter().string(from: $0)
                } ?? "nil"
                continuousResults["monitor"] = monitorSummary
                closeAll()
                await waitUntilClosed(.systemMonitor)
                try? await Task.sleep(for: .milliseconds(800))
                point("monitor-continuous-close-settle")

                // Prove the controller/model/provider surfaces are not retained
                // after an explicit stop and nil-out.
                let weakController = WeakBox(controller!)
                let weakMonitor = WeakBox(monitor!)
                let weakCalendar = WeakBox(calendar!)
                let weakReader = WeakBox(reader!)
                controller?.stop()
                try? await Task.sleep(for: .milliseconds(900))
                controller = nil
                controllerRef = nil
                monitor = nil
                calendar = nil
                reader = nil
                try? await Task.sleep(for: .milliseconds(900))
                let deallocated = [
                    "controller": weakController.value == nil,
                    "monitor": weakMonitor.value == nil,
                    "calendar": weakCalendar.value == nil,
                    "reader": weakReader.value == nil
                ]
                NSStatusBar.system.removeStatusItem(appItem)

                let result: [String: Any] = [
                    "schema": 1,
                    "startedAt": ISO8601DateFormatter().string(from: startedAt),
                    "finishedAt": ISO8601DateFormatter().string(from: Date()),
                    "durationSeconds": Date().timeIntervalSince(startedAt),
                    "environment": [
                        "bundledFakeCalendar": true,
                        "fakeApplicationReader": true,
                        "publicCPUAndMemoryScheduler": true,
                        "realPersonalEventsRead": false,
                        "mediaCommandsSent": false,
                        "distOverwritten": false
                    ],
                    "continuousResults": continuousResults,
                    "statusItemIdentities": [
                        "monitor": monitorItemID ?? "nil",
                        "calendar": calendarItemID ?? "nil",
                        "monitorPopover": monitorPopoverID,
                        "calendarPopover": calendarPopoverID
                    ],
                    "deallocatedAfterStop": deallocated,
                    "points": points.map(Self.encode)
                ]
                try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
                    .write(to: directory.appendingPathComponent("memory-audit.json"))
                fputs("MENUBAR_MEMORY_AUDIT points=\(points.count) deallocated=\(deallocated)\n", stderr)
            } catch {
                fputs("Menu-bar memory audit failed: \(error)\n", stderr)
            }
            NSApp.terminate(nil)
        }
    }

    @MainActor private static func point(label: String, startedAt: Date,
                                         monitor: SystemMonitor, calendar: CalmonCalendarModel,
                                         reader: any AppMemoryReading,
                                         controller: MenuBarModuleController) -> Point {
        let memory = Self.memorySnapshot()
        return Point(
            label: label,
            seconds: Date().timeIntervalSince(startedAt),
            physicalFootprint: memory.physical,
            residentBytes: memory.resident,
            monitorRunning: monitor.isRunning,
            monitorSampling: monitor.isSampling,
            sampleStarts: monitor.sampleStartCount,
            sampleCompletions: monitor.sampleCompletionCount,
            staleSamples: monitor.staleSampleDiscardCount,
            calendarPanelVisible: controller.isCalendarPanelShown,
            monitorPanelVisible: controller.isMonitorPanelShown,
            readerCacheEntries: reader.iconCacheCount,
            readerCacheEvictions: reader.iconCacheEvictionCount,
            monitorItemIdentity: controller.monitorItem.map { String(describing: ObjectIdentifier($0)) },
            calendarItemIdentity: controller.calendarItem.map { String(describing: ObjectIdentifier($0)) },
            popoverIdentity: String(describing: controller.monitorPopoverIdentity))
    }

    private static func encode(_ point: Point) -> [String: Any] {
        ["label": point.label, "seconds": point.seconds,
         "physicalFootprint": point.physicalFootprint, "residentBytes": point.residentBytes,
         "monitorRunning": point.monitorRunning, "monitorSampling": point.monitorSampling,
         "sampleStarts": point.sampleStarts, "sampleCompletions": point.sampleCompletions,
         "staleSamples": point.staleSamples,
         "calendarPanelVisible": point.calendarPanelVisible,
         "monitorPanelVisible": point.monitorPanelVisible,
         "readerCacheEntries": point.readerCacheEntries,
         "readerCacheEvictions": point.readerCacheEvictions,
         "monitorItemIdentity": point.monitorItemIdentity ?? "nil",
         "calendarItemIdentity": point.calendarItemIdentity ?? "nil",
         "popoverIdentity": point.popoverIdentity]
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

private final class WeakBox {
    weak var value: AnyObject?
    init(_ value: AnyObject) { self.value = value }
}

/// Fake application reader for the audit. It returns a few stable descriptors
/// and deterministic memory rows; it never enumerates the user's processes.
private final class AuditAppMemoryReader: AppMemoryReading {
    private let descriptors = [
        AppMemoryReader.AppDescriptor(bundleIdentifier: "audit.one", name: "Audit One",
                                      bundlePath: "/tmp/AuditOne.app", rootPath: "/tmp/AuditOne.app", icon: nil),
        AppMemoryReader.AppDescriptor(bundleIdentifier: "audit.two", name: "Audit Two",
                                      bundlePath: "/tmp/AuditTwo.app", rootPath: "/tmp/AuditTwo.app", icon: nil)
    ]

    func runningApplications() -> [AppMemoryReader.AppDescriptor] { descriptors }

    func sample(applications: [AppMemoryReader.AppDescriptor]) -> AppMemoryReader.SampleResult {
        let rows = applications.map {
            AppMemoryReader.AppUsage(id: $0.bundleIdentifier, name: $0.name, icon: nil,
                                     bytes: 24_000_000, processCount: 1, readableCount: 1, status: .ok)
        }
        return AppMemoryReader.SampleResult(rows: rows, state: .ready)
    }

    var iconCacheCount: Int { 0 }
    var iconCacheEvictionCount: Int { 0 }
    func purge() {}
    func trimCache() {}
}
#endif
