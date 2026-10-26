import AppKit
import Darwin
import Foundation

/// Bounded native memory/CPU audit for the download popover. It uses only the
/// fake service and never starts the engine, network, media or permissions.
enum DownloadMenuMemoryAudit {
    @MainActor static func run(output: String) {
        Task { @MainActor in
            do {
                let directory = URL(fileURLWithPath: output, isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let fake = FakeDownloadService()
                let now = Date()
                let items = (0..<4).map { index in
                    Self.auditItem(index: index, now: now)
                }
                fake.setItemsForQA(items)
                let controller = DownloadMenuBarController(
                    service: fake, onSettings: {}, onQuit: {}, animates: false)
                controller.start()
                try await Task.sleep(nanoseconds: 300_000_000)

                // 60 open/close cycles before the long-open warm-up.
                for _ in 0..<60 {
                    controller.togglePopover()
                    try? await Task.sleep(nanoseconds: 45_000_000)
                    controller.closePopover()
                    try? await Task.sleep(nanoseconds: 45_000_000)
                }
                try? await Task.sleep(nanoseconds: 500_000_000)
                let timerAfterCycles = controller.model.timerCreateCount
                let statusItemAfterCycles = controller.statusItem.map { String(describing: ObjectIdentifier($0)) }

                // Keep the popover open with an unknown-size active task: this
                // is the animated case, but still only the model's one timer.
                controller.showPopover()
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                let warmMemory = Self.memory()
                let warmCPU = Self.cpuSeconds()
                var samples: [[String: Any]] = []
                let start = Date()
                var peak = warmMemory
                var minPhysical = warmMemory.physical
                while Date().timeIntervalSince(start) < 180 {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    let memory = Self.memory()
                    peak = memory
                    minPhysical = min(minPhysical, memory.physical)
                    samples.append([
                        "t": Int(Date().timeIntervalSince(start)),
                        "physical": memory.physical,
                        "resident": memory.resident,
                        "visible": controller.isPopoverShown
                    ])
                }
                let endCPU = Self.cpuSeconds()
                let endMemory = Self.memory()
                let timerAfterLong = controller.model.timerCreateCount
                let identityAfterLong = controller.statusItem.map { String(describing: ObjectIdentifier($0)) }
                controller.closePopover()
                try? await Task.sleep(nanoseconds: 700_000_000)
                fake.setItemsForQA([])
                controller.model.refresh()
                try? await Task.sleep(nanoseconds: 500_000_000)
                let pausedMemory = Self.memory()
                let idleTimerStopped = !controller.model.needsTick
                let releasedWindow = controller.popoverWindow == nil
                let timerAfterIdle = controller.model.timerCreateCount
                controller.stop()
                let shutdown = fake.shutdownCount
                let result: [String: Any] = [
                    "cycles": 60,
                    "statusItemStable": statusItemAfterCycles == identityAfterLong,
                    "timerCreateAfterCycles": timerAfterCycles,
                    "timerCreateAfterLongOpen": timerAfterLong,
                    "timerCreateAfterIdle": timerAfterIdle,
                    "longOpenSamples": samples.count,
                    "longOpenSeconds": 180,
                    "physicalWarm": warmMemory.physical,
                    "physicalEnd": endMemory.physical,
                    "physicalMin": minPhysical,
                    "physicalPeak": peak.physical,
                    "residentWarm": warmMemory.resident,
                    "residentEnd": endMemory.resident,
                    "cpuSeconds": endCPU - warmCPU,
                    "idleTimerStopped": idleTimerStopped,
                    "popoverWindowReleased": releasedWindow,
                    "physicalAfterIdle": pausedMemory.physical,
                    "serviceShutdownCount": shutdown,
                    "fakeServiceOnly": true,
                    "productionManagerCreated": false,
                    "networkRequests": 0,
                    "samples": samples
                ]
                try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
                    .write(to: directory.appendingPathComponent("audit.json"))
            } catch {
                fputs("Download menu memory audit failed: \(error)\n", stderr)
            }
            NSApp.terminate(nil)
        }
    }

    @MainActor private static func auditItem(index: Int, now: Date) -> DownloadItemSnapshot {
        let segments: [DownloadSegmentSnapshot] = index == 0
            ? [.init(start: 0, end: 0.5, filled: 0.7, isActive: true),
               .init(start: 0.5, end: 1, filled: 0.0, isActive: true)]
            : []
        return DownloadItemSnapshot(
            id: UUID(), sourceURL: "https://example.invalid/audit-\(index)",
            destinationPath: "/tmp/valora-download-audit/audit-\(index).bin",
            filename: "audit-\(index).bin", state: .downloading,
            progress: 0.35, downloadedBytes: 3_500_000, totalBytes: 10_000_000,
            speed: 2_000_000, estimatedTimeRemaining: 4, isMerging: false,
            isFilePresent: false, segmentLayout: index == 0 ? "lanes" : nil,
            activeSegments: index == 0 ? 2 : 0, segments: segments,
            errorDescription: nil, createdAt: now.addingTimeInterval(-Double(index)),
            completedAt: nil, fileSize: nil,
            hasUnknownTotalSize: index == 1, completedSegments: 0, totalSegments: 0)
    }

    private static func memory() -> (physical: UInt64, resident: UInt64) {
        var info = rusage_info_v4()
        let physicalResult: Int32 = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(getpid(), RUSAGE_INFO_V4, $0)
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
        return (physical, residentResult == KERN_SUCCESS ? UInt64(basic.resident_size) : 0)
    }

    private static func cpuSeconds() -> Double {
        var info = rusage_info_v4()
        let result: Int32 = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(getpid(), RUSAGE_INFO_V4, $0)
            }
        }
        guard result == 0 else { return 0 }
        return Double(info.ri_user_time + info.ri_system_time) / 1_000_000_000
    }
}
