import Foundation
import XCTest
@testable import Valora

@MainActor
final class DownloadMenuModelTests: XCTestCase {
    private func item(_ name: String, state: DownloadItemState = .downloading,
                      progress: Double = 0.4, total: Int64 = 1_000,
                      downloaded: Int64 = 400, created: Date = Date(),
                      unknown: Bool = false, filePresent: Bool = false,
                      fileSize: Int64? = nil) -> DownloadItemSnapshot {
        DownloadItemSnapshot(
            id: UUID(), sourceURL: "https://example.invalid/\(name)",
            destinationPath: "/tmp/valora-menu-qa/\(name)", filename: name,
            state: state, progress: progress, downloadedBytes: downloaded, totalBytes: total,
            speed: 0, estimatedTimeRemaining: 0, isMerging: false,
            isFilePresent: filePresent, segmentLayout: nil, activeSegments: 0,
            segments: [], errorDescription: nil, createdAt: created,
            completedAt: state == .completed ? created : nil, fileSize: fileSize,
            hasUnknownTotalSize: unknown, completedSegments: 0, totalSegments: 0)
    }

    func testListOrderUsesStableCreationTimeAndID() {
        let older = item("older.bin", created: Date(timeIntervalSince1970: 1))
        let newer = item("newer.bin", created: Date(timeIntervalSince1970: 2))
        let fake = FakeDownloadService()
        fake.setItemsForQA([older, newer])
        let model = DownloadMenuModel(service: fake)
        XCTAssertEqual(model.items.map(\.id), [newer.id, older.id])
        let ids = model.items.map(\.id)

        // A progress-only refresh must not reorder or replace stable IDs.
        var updated = newer
        updated = DownloadItemSnapshot(
            id: newer.id, sourceURL: newer.sourceURL, destinationPath: newer.destinationPath,
            filename: newer.filename, state: .downloading, progress: 0.9,
            downloadedBytes: 900, totalBytes: newer.totalBytes, speed: 10,
            estimatedTimeRemaining: 1, isMerging: false, isFilePresent: false,
            segmentLayout: nil, activeSegments: 0, segments: [], errorDescription: nil,
            createdAt: newer.createdAt, completedAt: nil, fileSize: nil,
            hasUnknownTotalSize: false, completedSegments: 0, totalSegments: 0)
        fake.setItemsForQA([older, updated])
        model.refresh()
        XCTAssertEqual(model.items.map(\.id), ids)
        XCTAssertEqual(model.items.first?.progress, 0.9)
        model.stopTimer()
    }

    func testRingStates() {
        XCTAssertEqual(DownloadRingDescriptor.make(items: [], phase: 0).kind, .idle)
        XCTAssertEqual(DownloadRingDescriptor.make(items: [
            item("known", progress: 0.25, total: 1_000, downloaded: 250)
        ], phase: 0).kind, .active(progress: 0.25))
        XCTAssertEqual(DownloadRingDescriptor.make(items: [
            item("unknown", progress: 0.25, total: 0, downloaded: 250, unknown: true)
        ], phase: 0).kind, .active(progress: nil))
        XCTAssertEqual(DownloadRingDescriptor.make(items: [
            item("paused", state: .paused, progress: 0.5, total: 1_000, downloaded: 500)
        ], phase: 0).kind, .paused(progress: 0.5))
        XCTAssertEqual(DownloadRingDescriptor.make(items: [
            item("failed", state: .failed, progress: 0, total: 1_000, downloaded: 0)
        ], phase: 0).kind, .failed)
        let image = DownloadRingIcon.image(for: .init(kind: .active(progress: 0.4)))
        XCTAssertEqual(image.size.width, 18)
        XCTAssertTrue(image.isTemplate)
    }

    func testDeletionPlanTrivialAndExplicitTrash() {
        let completed = item("done.bin", state: .completed, total: 4_096,
                             downloaded: 4_096, filePresent: true, fileSize: 4_096)
        let missing = item("missing.bin", state: .completed, total: 4_096,
                           downloaded: 4_096, filePresent: false)
        let partial = item("partial.bin", state: .paused, total: 1_000, downloaded: 300)
        let noBytes = item("queued.bin", state: .waiting, total: 0, downloaded: 0)
        let all = [completed, missing, partial, noBytes]
        let trivial = DownloadEngineCompatibility.deletionPlan(for: [missing, noBytes], ids: Set([missing.id, noBytes.id]))
        XCTAssertTrue(trivial.isTriviallyDeletable)
        let full = DownloadEngineCompatibility.deletionPlan(for: all, ids: Set(all.map(\.id)))
        XCTAssertFalse(full.isTriviallyDeletable)
        XCTAssertEqual(full.trashableCount, 1)
        XCTAssertEqual(full.trashableBytes, 4_096)
        XCTAssertEqual(full.progressDiscardingCount, 1)
        XCTAssertEqual(full.progressDiscardingBytes, 300)
        XCTAssertEqual(full.single, nil)
    }

    func testControllerMenuLifecycleAndReopenReuseOneService() {
        let fake = FakeDownloadService()
        let controller = DownloadMenuBarController(service: fake, onSettings: {}, onQuit: {},
                                                   animates: false)
        controller.start()
        XCTAssertNotNil(controller.statusItem)
        XCTAssertTrue(controller.statusItem?.button?.target === controller)
        XCTAssertEqual(controller.statusItem?.button?.action,
                       NSSelectorFromString("statusItemClicked:"))
        XCTAssertEqual(controller.makeBasicMenu().items.map(\.title),
                       ["新建下载…", "", AppMenuCommands.versionText,
                        AppMenuCommands.settingsTitle, "", AppMenuCommands.quitTitle])
        let titles = controller.makeBasicMenu().items.map(\.title)
        XCTAssertFalse(titles.contains("播放"))
        XCTAssertFalse(titles.contains("显示器"))
        controller.showNewDownload()
        XCTAssertTrue(controller.model.isNewDownloadPresented)
        controller.model.isNewDownloadPresented = false
        controller.closePopover()
        controller.stop()
        XCTAssertNil(controller.statusItem)
        XCTAssertEqual(fake.shutdownCount, 1, "stop must save through the one service")
        controller.start()
        XCTAssertNotNil(controller.statusItem)
        XCTAssertEqual(fake.shutdownCount, 1, "reopen must not create or shut down a manager")
        controller.stop()
        XCTAssertEqual(fake.shutdownCount, 2)
    }

    func testFakeDeleteSpyKeepsFileAndTrashSemanticsInjected() async {
        let fake = FakeDownloadService()
        fake.setItemsForQA([item("delete.bin", state: .completed, total: 10,
                                 downloaded: 10, filePresent: true, fileSize: 10)])
        let model = DownloadMenuModel(service: fake)
        let id = model.items[0].id
        await model.delete(ids: [id], moveFilesToTrash: false)
        XCTAssertEqual(fake.deletedIDs, [id])
        XCTAssertEqual(fake.deleteTrashFlags, [false])
        XCTAssertTrue(model.items.isEmpty)
        model.stopTimer()
    }

    func testFakeServiceActionsAreObservableWithoutEngine() async throws {
        let fake = FakeDownloadService()
        fake.setItemsForQA([item("action.bin", state: .paused)])
        let model = DownloadMenuModel(service: fake)
        let id = try XCTUnwrap(model.items.first?.id)
        await model.pause(id)
        try await model.resume(id)
        try await model.retry(id, fromScratch: true)
        model.open(id); model.reveal(id)
        XCTAssertEqual(fake.openedIDs, [id])
        XCTAssertEqual(fake.revealedIDs, [id])
        XCTAssertEqual(fake.retriedIDs, [id])
        let conflict = DownloadConflictSnapshot(
            id: UUID(), existingID: id, existingFilename: "action.bin",
            existingState: .paused, incomingURL: "https://example.invalid/action.bin",
            suggestedAlternativeName: "action (1).bin", canResumeExisting: true)
        fake.setConflictForQA(conflict)
        model.refresh()
        XCTAssertEqual(model.conflict?.id, conflict.id)
        await model.resolve(.addSeparate)
        XCTAssertEqual(fake.lastConflictAction, .addSeparate)
        XCTAssertNil(model.conflict)
        model.stopTimer()
    }
}
