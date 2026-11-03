import AppKit
import Darwin
import Foundation
import SwiftUI

/// Isolated native QA for the fourth menu-bar download entry. It uses only a
/// fake DownloadServicing implementation: no production manager, no engine
/// network request, no real Downloads/Trash access and no media/calendar work.
enum DownloadMenuVerification {
    @MainActor static func run(output: String, stress: Bool = true) {
        Task { @MainActor in
            do {
                let directory = URL(fileURLWithPath: output, isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                var checks: [[String: Any]] = []
                var rendered: [String] = []

                let fake = FakeDownloadService()
                let controller = DownloadMenuBarController(
                    service: fake, onSettings: {}, onQuit: {}, animates: false)
                controller.start()
                try await Task.sleep(nanoseconds: 250_000_000)
                checks.append([
                    "statusItemCreated": controller.statusItem != nil,
                    "statusImageSize": NSStringFromSize(controller.statusItem?.button?.image?.size ?? .zero),
                    "statusImageIsTemplate": controller.statusItem?.button?.image?.isTemplate ?? false
                ])
                try Self.captureStatus(controller.statusItem, name: "status-downloads",
                                       directory: directory, rendered: &rendered)
                try Self.captureStatusPreview(controller.statusItem?.button?.image,
                                               name: "status-downloads-preview",
                                               directory: directory, rendered: &rendered)

                let menu = controller.makeBasicMenu()
                let titles = menu.items.map(\.title)
                checks.append([
                    "basicMenuTitles": titles,
                    "hasNewDownload": titles.contains("新建下载…"),
                    "hasVersion": titles.contains(where: { $0.hasPrefix("版本") }),
                    "hasSettings": titles.contains(AppMenuCommands.settingsTitle),
                    "hasQuit": titles.contains(AppMenuCommands.quitTitle),
                    "hasMusic": titles.contains("播放") || titles.contains("暂停")
                        || titles.contains("上一首") || titles.contains("下一首"),
                    "hasDisplay": titles.contains("显示器")
                ])

                // Empty state through the real status item/popover.
                fake.setItemsForQA([])
                controller.showPopover()
                try await Task.sleep(nanoseconds: 450_000_000)
                if !controller.isPopoverShown {
                    controller.showPopover()
                    try await Task.sleep(nanoseconds: 250_000_000)
                }
                checks.append(["emptyPopoverShown": controller.isPopoverShown,
                               "emptyPopoverSize": NSStringFromSize(controller.popoverWindow?.contentView?.bounds.size ?? .zero)])
                try Self.captureWindow(controller.popoverWindow, name: "popover-empty",
                                       directory: directory, rendered: &rendered)

                // Multiple states in one stable list, including an unknown
                // size task and a long filename.
                let now = Date()
                let items = [
                    Self.item("active-known.bin", state: .downloading, progress: 0.42,
                              total: 8_388_608, downloaded: 3_520_000, createdAt: now,
                              segments: [.init(start: 0, end: 0.5, filled: 0.7, isActive: true),
                                         .init(start: 0.5, end: 1, filled: 0.14, isActive: true)],
                              layout: "lanes"),
                    Self.item("unknown-size-stream.log", state: .downloading, progress: 0.15,
                              total: 0, downloaded: 1_048_576, createdAt: now.addingTimeInterval(-1),
                              hasUnknown: true),
                    Self.item("paused.zip", state: .paused, progress: 0.61,
                              total: 20_000_000, downloaded: 12_200_000, createdAt: now.addingTimeInterval(-2)),
                    Self.item("failed.bin", state: .failed, progress: 0.2,
                              total: 1_000, downloaded: 200, createdAt: now.addingTimeInterval(-3),
                              error: "连接失败"),
                    Self.item("completed.bin", state: .completed, progress: 1,
                              total: 4_096, downloaded: 4_096, createdAt: now.addingTimeInterval(-4), filePresent: true, fileSize: 4_096),
                    Self.item("a-very-long-file-name-that-must-be-truncated-in-the-middle-while-the-row-stays-readable.bin",
                              state: .waiting, progress: 0, total: 10_000_000, downloaded: 0, createdAt: now.addingTimeInterval(-5)),
                    Self.item("starting.bin", state: .starting, progress: 0.05,
                              total: 5_000_000, downloaded: 250_000, createdAt: now.addingTimeInterval(-6)),
                    Self.item("validating.bin", state: .validating, progress: 0.1,
                              total: 5_000_000, downloaded: 500_000, createdAt: now.addingTimeInterval(-7)),
                    Self.item("expired-link.bin", state: .urlExpired, progress: 0.2,
                              total: 5_000_000, downloaded: 1_000_000, createdAt: now.addingTimeInterval(-8)),
                    Self.item("folder-missing.bin", state: .destinationMissing, progress: 0.2,
                              total: 5_000_000, downloaded: 1_000_000, createdAt: now.addingTimeInterval(-9)),
                    Self.item("needs-input.bin", state: .awaitingDuplicateResolution, progress: 0,
                              total: 5_000_000, downloaded: 0, createdAt: now.addingTimeInterval(-10))
                ]
                fake.setItemsForQA(items)
                controller.model.refresh()
                try await Task.sleep(nanoseconds: 250_000_000)
                checks.append(["items": controller.model.items.count,
                               "stableIDs": controller.model.items.map(\.id.uuidString),
                               "activeRows": controller.model.activeItems.count,
                               "ring": Self.ringDescription(controller.model),
                               "contentWidth": Double(controller.popoverWindow?.contentView?.bounds.width ?? 0)])
                try Self.captureWindow(controller.popoverWindow, name: "popover-multiple",
                                       directory: directory, rendered: &rendered)
                try Self.captureStatusPreview(controller.statusItem?.button?.image,
                                               name: "status-downloads-active",
                                               directory: directory, rendered: &rendered)
                let knownRing = DownloadRingDescriptor.make(items: [items[0]], phase: 0)
                let pausedRing = DownloadRingDescriptor.make(items: [items[2]], phase: 0)
                let failedRing = DownloadRingDescriptor.make(items: [items[3]], phase: 0)
                try Self.captureStatusPreview(DownloadRingIcon.image(for: knownRing),
                                               name: "ring-known", directory: directory, rendered: &rendered)
                try Self.captureStatusPreview(DownloadRingIcon.image(for: pausedRing),
                                               name: "ring-paused", directory: directory, rendered: &rendered)
                try Self.captureStatusPreview(DownloadRingIcon.image(for: failedRing),
                                               name: "ring-failed", directory: directory, rendered: &rendered)
                checks.append(["knownRing": Self.ringDescription(knownRing),
                               "pausedRing": Self.ringDescription(pausedRing),
                               "failedRing": Self.ringDescription(failedRing)])

                fake.storageUnavailableReason = "存储由另一个实例持有"
                controller.model.refresh()
                try await Task.sleep(nanoseconds: 250_000_000)
                checks.append(["storageUnavailableShown": controller.model.storageUnavailableReason != nil])
                try Self.captureWindow(controller.popoverWindow, name: "popover-storage-unavailable",
                                       directory: directory, rendered: &rendered)
                fake.storageUnavailableReason = nil
                controller.model.refresh()

                // New download form: direct native window from the same UI-safe
                // model; no clipboard or network work.
                let newHost = NSHostingController(rootView: DownloadNewView(model: controller.model))
                newHost.sizingOptions = [.preferredContentSize]
                let newWindow = NSWindow(contentViewController: newHost)
                newWindow.title = "新建下载（隔离 QA）"
                newWindow.makeKeyAndOrderFront(nil)
                try await Task.sleep(nanoseconds: 350_000_000)
                try Self.captureWindow(newWindow, name: "new-download",
                                       directory: directory, rendered: &rendered)
                newWindow.close()

                // Conflict sheet, using only a fake conflict snapshot.
                let conflictSnapshot = DownloadConflictSnapshot(
                    id: UUID(), existingID: items[0].id, existingFilename: "active-known.bin",
                    existingState: .downloading, incomingURL: "https://example.invalid/file.bin",
                    suggestedAlternativeName: "active-known (1).bin", canResumeExisting: true)
                let conflictHost = NSHostingController(rootView: DownloadConflictSheet(
                    model: controller.model, conflict: conflictSnapshot))
                conflictHost.sizingOptions = [.preferredContentSize]
                let conflictWindow = NSWindow(contentViewController: conflictHost)
                conflictWindow.makeKeyAndOrderFront(nil)
                try await Task.sleep(nanoseconds: 300_000_000)
                try Self.captureWindow(conflictWindow, name: "duplicate-conflict",
                                       directory: directory, rendered: &rendered)
                conflictWindow.close()

                // Delete confirmation in its default record-only form and with
                // an explicit Trash preview. No file is touched.
                let plan = controller.model.deletionPlan(for: [items[1].id, items[4].id])
                let deleteHost = NSHostingController(rootView: DownloadDeleteConfirmation(
                    request: DownloadDeleteRequest(taskIDs: [items[1].id, items[4].id]),
                    plan: plan, onConfirm: { _, _ in }))
                deleteHost.sizingOptions = [.preferredContentSize]
                let deleteWindow = NSWindow(contentViewController: deleteHost)
                deleteWindow.makeKeyAndOrderFront(nil)
                try await Task.sleep(nanoseconds: 300_000_000)
                try Self.captureWindow(deleteWindow, name: "delete-confirmation",
                                       directory: directory, rendered: &rendered)
                deleteWindow.close()
                checks.append(["deletePlanTrivial": plan.isTriviallyDeletable,
                               "deletePlanTrashable": plan.trashableCount,
                               "deletePlanDiscarding": plan.progressDiscardingCount])

                // End the list controller and use a fresh fake-backed controller
                // for the popover cycle audit. This exercises the same start/stop
                // lifecycle as an app quit/reopen without creating a manager.
                controller.stop()
                checks.append(["mainStatusRemoved": controller.statusItem == nil,
                               "mainServiceShutdown": fake.shutdownCount == 1])

                if stress {
                let cycleFake = FakeDownloadService()
                cycleFake.setItemsForQA(items)
                let cycleController = DownloadMenuBarController(
                    service: cycleFake, onSettings: {}, onQuit: {}, animates: false)
                cycleController.start()
                try await Task.sleep(nanoseconds: 250_000_000)
                let timerBefore = cycleController.model.timerCreateCount
                let identityBefore = String(describing: ObjectIdentifier(cycleController))
                for _ in 0..<60 {
                    cycleController.togglePopover()
                    try? await Task.sleep(nanoseconds: 350_000_000)
                    cycleController.closePopover()
                    try? await Task.sleep(nanoseconds: 350_000_000)
                }
                try? await Task.sleep(nanoseconds: 400_000_000)
                cycleFake.setItemsForQA([])
                cycleController.model.refresh()
                cycleController.closePopover()
                try? await Task.sleep(nanoseconds: 350_000_000)
                checks.append(["cycles": 60,
                               "controllerIdentityStable": identityBefore == String(describing: ObjectIdentifier(cycleController)),
                               "timerCreations": cycleController.model.timerCreateCount - timerBefore,
                               "popoverShows": cycleController.popoverShowCount,
                               "timerStoppedAtIdle": !cycleController.model.needsTick,
                               "cycleServiceShutdownBeforeStop": cycleFake.shutdownCount])
                cycleController.stop()
                checks.append(["statusItemRemoved": cycleController.statusItem == nil,
                               "serviceShutdownAfterStop": cycleFake.shutdownCount == 1,
                               "openedRunCount": cycleFake.openedIDs.count,
                               "revealedRunCount": cycleFake.revealedIDs.count])
                } else {
                    checks.append(["stressCyclesSkippedPerUser": true])
                }

                let result: [String: Any] = [
                    "checks": checks,
                    "rendered": rendered,
                    "fakeServiceOnly": true,
                    "productionManagerCreated": false,
                    "networkRequests": 0,
                    "realDownloadsTouched": false,
                    "realTrashTouched": false,
                    "nativeStatusItem": true,
                    "nativePopover": true
                ]
                try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
                    .write(to: directory.appendingPathComponent("verification.json"))
            } catch {
                fputs("Download menu verification failed: \(error)\n", stderr)
            }
            NSApp.terminate(nil)
        }
    }

    private static func item(_ name: String, state: DownloadItemState, progress: Double,
                             total: Int64, downloaded: Int64, createdAt: Date,
                             segments: [DownloadSegmentSnapshot] = [], layout: String? = nil,
                             hasUnknown: Bool = false, error: String? = nil,
                             filePresent: Bool = false, fileSize: Int64? = nil) -> DownloadItemSnapshot {
        DownloadItemSnapshot(
            id: UUID(), sourceURL: "https://example.invalid/\(name)",
            destinationPath: "/tmp/valora-download-qa/\(name)", filename: name,
            state: state, progress: progress, downloadedBytes: downloaded, totalBytes: total,
            speed: state == .downloading ? 2_000_000 : 0, estimatedTimeRemaining: 12,
            isMerging: false, isFilePresent: filePresent, segmentLayout: layout,
            activeSegments: segments.filter(\.isActive).count, segments: segments,
            errorDescription: error, createdAt: createdAt, completedAt: state == .completed ? createdAt : nil,
            fileSize: fileSize, hasUnknownTotalSize: hasUnknown,
            completedSegments: segments.filter { $0.filled >= 1 }.count, totalSegments: segments.count)
    }

    @MainActor private static func ringDescription(_ descriptor: DownloadRingDescriptor) -> String {
        switch descriptor.kind {
        case .idle: return "idle"
        case .active(let p): return "active:\(p.map { String(format: "%.3f", $0) } ?? "unknown")"
        case .paused(let p): return "paused:\(p.map { String(format: "%.3f", $0) } ?? "unknown")"
        case .failed: return "failed"
        }
    }

    @MainActor private static func ringDescription(_ model: DownloadMenuModel) -> String {
        let descriptor = DownloadRingDescriptor.make(items: model.items, phase: model.phase)
        switch descriptor.kind {
        case .idle: return "idle"
        case .active(let p): return "active:\(p.map { String(format: "%.3f", $0) } ?? "unknown")"
        case .paused(let p): return "paused:\(p.map { String(format: "%.3f", $0) } ?? "unknown")"
        case .failed: return "failed"
        }
    }

    @MainActor private static func captureStatus(_ item: NSStatusItem?, name: String,
                                                 directory: URL, rendered: inout [String]) throws {
        guard let button = item?.button else { return }
        button.layoutSubtreeIfNeeded()
        let view = button.window?.contentView ?? button
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return }
        try png.write(to: directory.appendingPathComponent(name + ".png"))
        rendered.append(name)
    }

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
            background.setFill(); NSRect(x: 0, y: 0, width: width, height: height).fill()
            let tinted: NSImage
            if source.isTemplate {
                tinted = NSImage(size: source.size, flipped: false) { rect in
                    source.draw(in: rect)
                    (suffix == "dark" ? NSColor.white : NSColor.black).setFill()
                    rect.fill(using: .sourceAtop)
                    return true
                }
            } else { tinted = source }
            tinted.draw(in: NSRect(x: 0, y: 0, width: width, height: height))
            context.flushGraphics(); NSGraphicsContext.restoreGraphicsState()
            guard let png = rep.representation(using: .png, properties: [:]) else { continue }
            try png.write(to: directory.appendingPathComponent("\(name)-\(suffix).png"))
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
