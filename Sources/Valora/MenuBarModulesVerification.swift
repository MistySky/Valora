import AppKit
import Darwin
import Foundation
import SwiftUI

/// Native, isolated QA for the two independent Calmon menu-bar modules.
///
/// This mode never starts media/Bluetooth, never requests authorization and
/// never queries EventKit. It injects a clearly-labelled calendar sample and a
/// fixed monitoring snapshot, but creates real NSStatusItems and NSPopover
/// windows so the layout, material and status-item identities can be inspected.
enum MenuBarModulesVerification {
    @MainActor static func run(output: String, stress: Bool = true) {
        Task { @MainActor in
            do {
                let directory = URL(fileURLWithPath: output, isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                var checks: [[String: Any]] = []
                var rendered: [String] = []

                let monitor = SystemMonitor()
                monitor.verificationApply(
                    snapshot: SystemMonitor.Snapshot(
                        cpu: .init(usage: 23, userUsage: 15, systemUsage: 8),
                        memory: .init(total: 32 * 1_073_741_824, used: 20 * 1_073_741_824),
                        disk: .init(volumePath: "/", volumeIdentifier: "preview",
                                    total: 500_000_000_000, available: 200_000_000_000,
                                    used: 300_000_000_000),
                        device: .init(chip: "Preview chip", osVersion: "macOS 27"),
                        uptime: "已运行 1 天"),
                    applications: [
                        Self.app("Finder", 120_000_000, "com.apple.finder"),
                        Self.app("Safari", 480_000_000, "com.apple.Safari"),
                        Self.app("Valora Preview", 96_000_000, "com.wangqing.valora.preview"),
                        Self.app("A very long application name for truncation", 44_000_000, "preview.long")
                    ],
                    applicationState: .ready)

                let now = Date()
                let calendar = CalmonCalendarModel(
                    calendar: .current,
                    now: { now },
                    eventProvider: PreviewCalendarEvents(),
                    readGate: { true },
                    preview: true)

                // The application Outline item is created first and remains a
                // separate entry; module items are created by the controller.
                let appItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
                if let url = Bundle.main.resourceURL?.appendingPathComponent("MenuBarIcon.png"),
                   let data = try? Data(contentsOf: url), let image = NSImage(data: data) {
                    appItem.button?.image = image
                    appItem.button?.imageScaling = .scaleProportionallyDown
                }
                appItem.button?.setAccessibilityLabel("Valora")

                // Build the application menu through the same AppDelegate
                // production path used by the real Outline-v7 status item. The
                // model is a fixture; no media controller is started.
                let appDelegate = AppDelegate(arguments: ["Valora", "--verify-menu-modules"])
                appDelegate.model.title = "Application menu fixture"
                appDelegate.model.artist = "Fixture artist"
                appDelegate.model.album = "Fixture album"
                appDelegate.model.duration = 180
                appDelegate.model.playing = true
                appDelegate.model.mediaCanControl = true
                appDelegate.model.mediaCanSkip = true
                appDelegate.settings.nowPlayingEnabled = true
                let appMenu = appDelegate.applicationStatusMenuForVerification()
                appItem.menu = appMenu
                let appMenuTitles = appMenu.items.map(\.title)

                let codexUsage = PreviewCodexUsage.provider()
                let controller = MenuBarModuleController(
                    monitor: monitor, calendar: calendar, codexUsage: codexUsage,
                    onSettings: {}, onQuit: {})
                controller.start(startSampling: false)
                try? await Task.sleep(nanoseconds: 450_000_000)

                let independent = controller.monitorItem != nil
                    && controller.calendarItem != nil
                    && controller.monitorItem !== controller.calendarItem
                checks.append(["independentStatusItems": independent,
                               "appIconIdentity": String(describing: ObjectIdentifier(appItem)),
                               "monitorIdentity": controller.monitorItem.map { String(describing: ObjectIdentifier($0)) } ?? "nil",
                               "calendarIdentity": controller.calendarItem.map { String(describing: ObjectIdentifier($0)) } ?? "nil",
                               "identitiesDistinct": appItem !== controller.monitorItem
                                   && appItem !== controller.calendarItem
                                   && controller.monitorItem !== controller.calendarItem])
                checks.append(["calendarMenuText": controller.calendarStatusText ?? "nil",
                               "calendarStatusLength": Double(controller.calendarItem?.length ?? 0),
                               "monitorStatusLength": Double(controller.monitorItem?.length ?? 0),
                               "codexStatusText": controller.codexStatusText ?? "nil",
                               "codexStatusImageSize": controller.codexItem?.button?.image.map { NSStringFromSize($0.size) } ?? "nil",
                               "codexSnapshotStatus": String(describing: codexUsage.snapshot.status),
                               "codexFivePercent": codexUsage.snapshot.fiveHourRemainingPercentText,
                               "codexWeekPercent": codexUsage.snapshot.weekRemainingPercentText,
                               "codexFiveUsedPercent": codexUsage.snapshot.fiveHourPercentText,
                               "codexWeekUsedPercent": codexUsage.snapshot.weekPercentText])
                let basicTitles = controller.makeBasicMenu().items.map(\.title)
                checks.append(["applicationMenuTitles": appMenuTitles,
                               "applicationMenuHasMusic": appMenuTitles.contains("播放")
                                   || appMenuTitles.contains("暂停")
                                   || appMenuTitles.contains("上一首")
                                   || appMenuTitles.contains("下一首"),
                               "applicationMenuHasDisplay": appMenuTitles.contains("显示器")])
                checks.append(["basicMenuTitles": basicTitles,
                               "basicMenuHasMusic": basicTitles.contains("播放") || basicTitles.contains("暂停")
                                   || basicTitles.contains("上一首") || basicTitles.contains("下一首"),
                               "basicMenuHasDisplay": basicTitles.contains("显示器")])
                try Self.captureStatusItem(appItem, name: "status-app-outline", directory: directory, rendered: &rendered)
                if let item = controller.monitorItem {
                    try Self.captureStatusItem(item, name: "status-monitor", directory: directory, rendered: &rendered)
                }
                if let item = controller.calendarItem {
                    try Self.captureStatusItem(item, name: "status-calendar", directory: directory, rendered: &rendered)
                }
                if let item = controller.codexItem {
                    try Self.captureStatusItem(item, name: "status-codex", directory: directory, rendered: &rendered)
                    try Self.captureStatusPreview(item.button?.image, name: "status-codex-preview", directory: directory, rendered: &rendered)
                }
                try Self.captureStatusPreview(controller.monitorItem?.button?.image, name: "status-monitor-preview", directory: directory, rendered: &rendered)
                try Self.captureStatusPreview(controller.calendarItem?.button?.image, name: "status-calendar-preview", directory: directory, rendered: &rendered)

                controller.showCalendarPanel()
                try? await Task.sleep(nanoseconds: 350_000_000)
                checks.append(["calendarPanelShown": controller.isCalendarPanelShown,
                               "calendarPanelSize": NSStringFromSize(controller.calendarPanelContentSize),
                               "calendarContentWidth": Double(controller.calendarPopoverWindow?.contentView?.bounds.width ?? 0),
                               "calendarEventState": String(describing: calendar.eventState),
                               "calendarEvents": calendar.events.count])
                try Self.captureWindow(controller.calendarPopoverWindow, name: "calendar-popover",
                                       directory: directory, rendered: &rendered)
                controller.closeAllPopovers()
                try? await Task.sleep(nanoseconds: 700_000_000)
                checks.append(["calendarClosed": !controller.isCalendarPanelShown])

                controller.showCodexPanel()
                try? await Task.sleep(nanoseconds: 350_000_000)
                checks.append(["codexPanelShown": controller.isCodexPanelShown,
                               "codexPanelSize": NSStringFromSize(controller.codexPopoverWindow?.contentView?.bounds.size ?? .zero),
                               "codexContentWidth": Double(controller.codexPopoverWindow?.contentView?.bounds.width ?? 0),
                               "codexResetCount": codexUsage.snapshot.resetAvailableCount ?? -1])
                try Self.captureWindow(controller.codexPopoverWindow, name: "codex-popover",
                                       directory: directory, rendered: &rendered)
                controller.closeAllPopovers()
                try? await Task.sleep(nanoseconds: 700_000_000)
                checks.append(["codexClosed": !controller.isCodexPanelShown])

                // Optional stress loop; disabled by --verify-menu-layout.
                if stress {
                let codexMemoryBefore = Self.processMemory()
                let codexRequestsBefore = codexUsage.requestCount
                let codexCompletionsBefore = codexUsage.completionCount
                let codexIdentityBefore = controller.codexItem.map { String(describing: ObjectIdentifier($0)) }
                for _ in 0..<30 {
                    controller.showCodexPanel()
                    try? await Task.sleep(nanoseconds: 160_000_000)
                    controller.closeAllPopovers()
                    for _ in 0..<20 where controller.isCodexPanelShown {
                        try? await Task.sleep(nanoseconds: 50_000_000)
                    }
                    try? await Task.sleep(nanoseconds: 260_000_000)
                }
                try? await Task.sleep(nanoseconds: 800_000_000)
                let codexMemoryAfter = Self.processMemory()
                let codexIdentityAfter = controller.codexItem.map { String(describing: ObjectIdentifier($0)) }
                checks.append(["codexCycles": 30,
                               "codexStatusItemStable": codexIdentityBefore == codexIdentityAfter,
                               "codexRequestDelta": codexUsage.requestCount - codexRequestsBefore,
                               "codexCompletionDelta": codexUsage.completionCount - codexCompletionsBefore,
                               "codexPhysicalBefore": codexMemoryBefore.physical,
                               "codexPhysicalAfter": codexMemoryAfter.physical,
                               "codexResidentBefore": codexMemoryBefore.resident,
                               "codexResidentAfter": codexMemoryAfter.resident,
                               "codexPreviewSubprocessesLaunched": 0])
                } else {
                    checks.append(["stressCyclesSkippedPerUser": true])
                }

                controller.showMonitorPanel()
                try? await Task.sleep(nanoseconds: 350_000_000)
                checks.append(["monitorPanelShown": controller.isMonitorPanelShown,
                               "monitorPanelSize": NSStringFromSize(controller.monitorPanelContentSize),
                               "monitorContentWidth": Double(controller.monitorPopoverWindow?.contentView?.bounds.width ?? 0),
                               "monitorApplications": monitor.applications.count])
                try Self.captureWindow(controller.monitorPopoverWindow, name: "monitor-popover",
                                       directory: directory, rendered: &rendered)
                controller.closeAllPopovers()
                try? await Task.sleep(nanoseconds: 700_000_000)
                checks.append(["monitorClosed": !controller.isMonitorPanelShown])

                controller.stop()
                NSStatusBar.system.removeStatusItem(appItem)

                let result: [String: Any] = [
                    "checks": checks,
                    "rendered": rendered,
                    "nativeStatusItems": true,
                    "nativePopovers": true,
                    "calendarSampleOnly": true,
                    "monitorSnapshotInjected": true,
                    "providersStarted": false,
                    "eventKitQueried": false,
                    "mediaCommandsSent": false,
                    "permissionsRequested": false,
                    "applicationIconSeparate": true
                ]
                try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
                    .write(to: directory.appendingPathComponent("verification.json"))
            } catch {
                fputs("Menu-bar modules verification failed: \(error)\n", stderr)
            }
            NSApp.terminate(nil)
        }
    }

    @MainActor private static func processMemory() -> (physical: UInt64, resident: UInt64) {
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

    private static func app(_ name: String, _ bytes: UInt64, _ id: String) -> AppMemoryReader.AppUsage {
        AppMemoryReader.AppUsage(id: id, name: name, icon: nil, bytes: bytes,
                                 processCount: 1, readableCount: 1, status: .ok)
    }

    @MainActor private static func captureStatusItem(_ item: NSStatusItem, name: String,
                                                      directory: URL, rendered: inout [String]) throws {
        guard let button = item.button else { return }
        button.layoutSubtreeIfNeeded()
        let view = button.window?.contentView ?? button
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return }
        try png.write(to: directory.appendingPathComponent(name + ".png"))
        rendered.append(name)
    }

    /// Render the actual status-item image on a fixed light/dark strip so the
    /// template pixels are visible in evidence. The status-item identity and
    /// button still come from the real NSStatusItem above.
    @MainActor private static func captureStatusPreview(_ source: NSImage?, name: String,
                                                         directory: URL, rendered: inout [String]) throws {
        guard let source else { return }
        for (suffix, background) in [("light", NSColor(srgbRed: 0.867, green: 0.898, blue: 0.925, alpha: 1)),
                                     ("dark", NSColor(srgbRed: 0.110, green: 0.110, blue: 0.118, alpha: 1))] {
            let scale: CGFloat = 2
            let width = max(24, source.size.width * scale)
            let height = max(24, source.size.height * scale)
            guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width), pixelsHigh: Int(height),
                                             bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                             colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
                  let context = NSGraphicsContext(bitmapImageRep: rep) else { continue }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            background.setFill()
            NSRect(x: 0, y: 0, width: width, height: height).fill()
            let tinted: NSImage
            if source.isTemplate {
                tinted = NSImage(size: source.size, flipped: false) { rect in
                    source.draw(in: rect)
                    (suffix == "dark" ? NSColor.white : NSColor.black).setFill()
                    rect.fill(using: .sourceAtop)
                    return true
                }
            } else {
                tinted = source
            }
            tinted.draw(in: NSRect(x: 0, y: 0, width: width, height: height))
            context.flushGraphics()
            NSGraphicsContext.restoreGraphicsState()
            guard let png = rep.representation(using: .png, properties: [:]) else { continue }
            let filename = "\(name)-\(suffix).png"
            try png.write(to: directory.appendingPathComponent(filename))
            rendered.append("\(name)-\(suffix)")
        }
    }

    @MainActor private static func captureWindow(_ window: NSWindow?, name: String,
                                                 directory: URL, rendered: inout [String]) throws {
        guard let view = window?.contentView else { return }
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return }
        try png.write(to: directory.appendingPathComponent(name + ".png"))
        rendered.append(name)
    }
}
