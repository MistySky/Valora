import AppKit
import Darwin
import Foundation
import SwiftUI

/// Explicit QA-only fixed presentation. It reuses the production
/// `CalmonCalendarView` and `CalmonCalendarModel` in a plain NSWindow instead of
/// an NSPopover. It is not production interaction and cannot establish transient
/// popover behavior; it exists only to obtain a valid long-open view-tree/memory
/// baseline when the host focus cannot keep an NSPopover visible.
@MainActor
enum CalendarFixedWindowAudit {
    @MainActor static func run(output: String) {
        Task { @MainActor in
            let startedAt = Date()
            do {
                let directory = URL(fileURLWithPath: output, isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let calendar = CalmonCalendarModel(
                    calendar: .current, now: Date.init,
                    eventProvider: PreviewCalendarEvents(),
                    readGate: { true }, preview: true)
                calendar.start()
                calendar.setPanelVisibility(panel: true, calendarModule: true)

                let screenHeight = NSScreen.main?.visibleFrame.height ?? 800
                let host = NSHostingController(rootView: CalmonCalendarView(
                    model: calendar, maxHeight: screenHeight * 0.8, onClose: {}))
                host.sizingOptions = [.preferredContentSize]
                let window = NSWindow(contentViewController: host)
                window.styleMask = [.borderless]
                window.isReleasedWhenClosed = false
                // QA-only fixed display: keep the production view tree above
                // other windows while this focused audit is running, so a
                // terminal/app activation cannot occlude the measured surface.
                window.level = .floating
                window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
                window.hidesOnDeactivate = false
                window.setContentSize(host.view.fittingSize)
                window.center()
                NSApp.activate(ignoringOtherApps: true)
                window.orderFrontRegardless()
                window.makeKeyAndOrderFront(nil)
                try? await Task.sleep(for: .milliseconds(500))

                var tracker = ContinuousVisibilityTracker(expectedSeconds: 180, expectedSamples: 37)
                var samples: [[String: Any]] = []
                @MainActor func capture(_ label: String) {
                    let memory = Self.memorySnapshot()
                    let visible = window.isVisible && window.occlusionState.contains(.visible)
                    let sample: [String: Any] = [
                        "label": label,
                        "seconds": Date().timeIntervalSince(startedAt),
                        "windowVisible": window.isVisible,
                        "windowKey": window.isKeyWindow,
                        "windowOccluded": !window.occlusionState.contains(.visible),
                        "appActive": NSApp.isActive,
                        "physicalFootprint": memory.physical,
                        "residentBytes": memory.resident,
                        "calendarEventStarts": calendar.eventReadStartCount,
                        "calendarEventCompletions": calendar.eventReadCompletionCount,
                        "calendarEvents": calendar.events.count,
                        "visible": visible
                    ]
                    samples.append(sample)
                    tracker.record(visible: visible, elapsed: Date().timeIntervalSince(startedAt))
                }
                capture("start")
                for index in 1...36 {
                    try? await Task.sleep(for: .seconds(5))
                    capture("\(index * 5)s")
                    if !window.isVisible || !window.occlusionState.contains(.visible) { break }
                }
                let status = tracker.status
                window.close()
                try? await Task.sleep(for: .milliseconds(500))
                calendar.stop()
                let result: [String: Any] = [
                    "schema": 1,
                    "mode": "fixed-qa-window",
                    "productionTransient": false,
                    "note": "Same production CalmonCalendarView and CalmonCalendarModel; plain QA NSWindow, not a production NSPopover.",
                    "status": status.rawValue,
                    "validLongOpen": status == .completed,
                    "visibleSamples": tracker.visibleSamples,
                    "totalSamples": tracker.totalSamples,
                    "visibleSeconds": tracker.visibleSeconds,
                    "firstInvisibleAt": tracker.firstInvisibleAt ?? -1,
                    "startedAt": ISO8601DateFormatter().string(from: startedAt),
                    "durationSeconds": Date().timeIntervalSince(startedAt),
                    "samples": samples,
                    "personalEventsRead": false,
                    "mediaCommandsSent": false,
                    "permissionsRequested": false
                ]
                try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
                    .write(to: directory.appendingPathComponent("calendar-fixed-window-audit.json"))
                fputs("CALENDAR_FIXED_WINDOW status=\(status.rawValue) visible=\(tracker.visibleSamples)/\(tracker.totalSamples)\n", stderr)
            } catch {
                fputs("Calendar fixed-window audit failed: \(error)\n", stderr)
            }
            NSApp.terminate(nil)
        }
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
