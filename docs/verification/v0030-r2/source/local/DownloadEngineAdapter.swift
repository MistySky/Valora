import Foundation
import DownloadEngine

/// Valora's narrow, immutable download boundary. DownloadEngine remains an
/// adapter detail; the future download UI must use this boundary, not engine
/// types. This file deliberately never touches `DownloadManager.shared` or
/// `AppSettings.shared`.
enum DownloadItemState: String, Sendable, Equatable {
    case waiting
    case starting
    case validating
    case refreshingLink
    case downloading
    case paused
    case completed
    case failed
    case cancelled
    case urlExpired
    case destinationMissing
    case awaitingDuplicateResolution
    case unknown
}

struct DownloadSegmentSnapshot: Sendable, Equatable {
    let start: Double
    let end: Double
    let filled: Double
    let isActive: Bool
}

struct DownloadItemSnapshot: Identifiable, Sendable, Equatable {
    let id: UUID
    let sourceURL: String
    let destinationPath: String
    let filename: String
    let state: DownloadItemState
    let progress: Double
    let downloadedBytes: Int64
    let totalBytes: Int64
    let speed: Int64
    let estimatedTimeRemaining: TimeInterval
    let isMerging: Bool
    let isFilePresent: Bool
    let segmentLayout: String?
    let activeSegments: Int
    let segments: [DownloadSegmentSnapshot]
    let errorDescription: String?
    // Stable list identity/order and row metrics. Defaults keep the existing
    // pure QA fixtures concise; the real adapter supplies task values.
    var createdAt: Date = Date()
    var completedAt: Date? = nil
    var fileSize: Int64? = nil
    var hasUnknownTotalSize: Bool = false
    var completedSegments: Int = 0
    var totalSegments: Int = 0
}

/// The small, UI-safe view of a duplicate request. The engine's conflict
/// object (and its DownloadTask) never crosses this boundary.
struct DownloadConflictSnapshot: Identifiable, Equatable, Sendable {
    let id: UUID
    let existingID: UUID
    let existingFilename: String
    let existingState: DownloadItemState
    let incomingURL: String
    let suggestedAlternativeName: String
    let canResumeExisting: Bool
}

enum DownloadConflictAction: Sendable {
    case resumeExisting
    case restart
    case addSeparate
    case skip
}

enum DownloadDeletionImpact: Equatable, Sendable {
    case finishedFile(bytes: Int64)
    case finishedFileMissing
    case discardsProgress(bytes: Int64)
    case nothingToLose
}

/// Pure DeletionPlan counterpart for the menu-bar UI. It mirrors the fixed
/// Convoy source's classification without exposing DownloadTask/DeletionPlan.
struct DownloadDeletionPlan: Equatable, Sendable {
    struct Item: Identifiable, Equatable, Sendable {
        let id: UUID
        let filename: String
        let impact: DownloadDeletionImpact
        let isFailed: Bool
        let folderName: String?
    }
    let items: [Item]
    var count: Int { items.count }
    var isEmpty: Bool { items.isEmpty }
    var single: Item? { items.count == 1 ? items.first : nil }
    var isTriviallyDeletable: Bool {
        items.allSatisfy {
            switch $0.impact {
            case .nothingToLose, .finishedFileMissing: return true
            case .finishedFile, .discardsProgress: return false
            }
        }
    }
    var trashableCount: Int {
        items.filter { if case .finishedFile = $0.impact { return true }; return false }.count
    }
    var trashableBytes: Int64 {
        items.reduce(0) { if case .finishedFile(let bytes) = $1.impact { return $0 + bytes }; return $0 }
    }
    var progressDiscardingCount: Int {
        items.filter { if case .discardsProgress = $0.impact { return true }; return false }.count
    }
    var progressDiscardingBytes: Int64 {
        items.reduce(0) { if case .discardsProgress(let bytes) = $1.impact { return $0 + bytes }; return $0 }
    }
}

enum DownloadServiceError: Error, LocalizedError {
    case conflict
    case storageUnavailable
    case featureSuspended
    case unsupported
    var errorDescription: String? {
        switch self {
        case .conflict: return "另有一个下载正在等待你的处理"
        case .storageUnavailable: return "下载存储正被其他实例使用"
        case .featureSuspended: return "下载功能当前已关闭"
        case .unsupported: return "当前下载类型不受支持"
        }
    }
}

@MainActor
protocol DownloadServicing: AnyObject {
    var items: [DownloadItemSnapshot] { get }
    func enqueue(source: URL, destination: URL) async throws
    func pause(id: UUID) async
    func resume(id: UUID) async throws
    func cancel(id: UUID) async
    func delete(id: UUID, moveFilesToTrash: Bool) async
    var hasPendingConflict: Bool { get }
    var pendingConflict: DownloadConflictSnapshot? { get }
    func start(id: UUID) async throws
    func retry(id: UUID, fromScratch: Bool) async throws
    func resolveConflict(_ action: DownloadConflictAction) async
    func openFile(id: UUID)
    func revealInFinder(id: UUID)
    var defaultDownloadDirectory: URL { get }
    var storageUnavailableReason: String? { get }
    func activate()
    func pauseAllAndSave() async
    func deletionPlan(for ids: Set<UUID>) -> DownloadDeletionPlan
    func shutdown()
}

/// Pure mapping and linkage proof for the pinned DownloadEngine product.
/// No engine singleton, settings singleton, task start, file write, network
/// request or temporary-directory scan occurs here.
@MainActor
enum DownloadEngineCompatibility {
    static var isLinked: Bool {
        TemporaryStorageNotice.defaultThresholdGB > 0
    }

    static func state(_ status: DownloadStatus) -> DownloadItemState {
        switch status {
        case .waiting: return .waiting
        case .starting: return .starting
        case .validating: return .validating
        case .refreshingLink: return .refreshingLink
        case .downloading: return .downloading
        case .paused: return .paused
        case .completed: return .completed
        case .failed: return .failed
        case .cancelled: return .cancelled
        case .urlExpired: return .urlExpired
        case .destinationMissing: return .destinationMissing
        case .awaitingDuplicateResolution: return .awaitingDuplicateResolution
        }
    }

    static func segments(_ map: SegmentMap?) -> [DownloadSegmentSnapshot] {
        guard let map else { return [] }
        return map.spans.map {
            DownloadSegmentSnapshot(start: $0.start, end: $0.end,
                                    filled: $0.filled, isActive: $0.isActive)
        }
    }

    /// QA fixture that exercises the public DownloadTask initializer and pure
    /// mapping without manager/settings/file/network access.
    static func verificationSnapshot() -> DownloadItemSnapshot {
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("fixture.bin")
        let task = DownloadTask(
            url: URL(string: "https://example.invalid/fixture.bin")!,
            destinationURL: destination,
            originalName: "fixture.bin",
            segmentCount: 4,
            initialStatus: .paused,
            totalBytes: 1_000,
            downloadedBytes: 250)
        return snapshot(of: task)
    }

    static func deletionPlan(for items: [DownloadItemSnapshot], ids: Set<UUID>) -> DownloadDeletionPlan {
        let selected = items.filter { ids.contains($0.id) }
        return DownloadDeletionPlan(items: selected.map { item in
            let impact: DownloadDeletionImpact
            let folderName: String?
            if item.state == .completed {
                if let size = item.fileSize, item.isFilePresent {
                    impact = .finishedFile(bytes: size)
                    folderName = URL(fileURLWithPath: item.destinationPath).deletingLastPathComponent().lastPathComponent
                } else {
                    impact = .finishedFileMissing
                    folderName = nil
                }
            } else if item.downloadedBytes > 0 {
                impact = .discardsProgress(bytes: item.downloadedBytes)
                folderName = nil
            } else {
                impact = .nothingToLose
                folderName = nil
            }
            return DownloadDeletionPlan.Item(
                id: item.id, filename: item.filename, impact: impact,
                isFailed: item.state == .failed, folderName: folderName)
        })
    }

    static func snapshot(of task: DownloadTask) -> DownloadItemSnapshot {
        DownloadItemSnapshot(
            id: task.id,
            sourceURL: task.url.absoluteString,
            destinationPath: task.destinationURL.path,
            filename: task.filename,
            state: state(task.status),
            progress: min(1, max(0, task.progress)),
            downloadedBytes: task.downloadedBytes,
            totalBytes: task.totalBytes,
            speed: task.speed,
            estimatedTimeRemaining: task.estimatedTimeRemaining,
            isMerging: task.isMerging,
            isFilePresent: FileManager.default.fileExists(atPath: task.destinationURL.path),
            segmentLayout: task.segmentMap.map { $0.layout == .lanes ? "lanes" : "pieces" },
            activeSegments: task.segmentMap?.activeCount ?? 0,
            segments: segments(task.segmentMap),
            errorDescription: task.error?.localizedDescription,
            createdAt: task.createdAt,
            completedAt: task.endTime,
            fileSize: (try? task.destinationURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init),
            hasUnknownTotalSize: task.hasUnknownTotalSize,
            completedSegments: task.segmentProgress?.completed ?? 0,
            totalSegments: task.segmentProgress?.total ?? 0)
    }
}

/// Real thin adapter. It is only constructed by a future download UI after an
/// explicit environment exists; AppDelegate never creates it at launch.
@MainActor
final class DownloadEngineService: DownloadServicing {
    let manager: DownloadManager
    let defaultDownloadDirectory: URL
    private var suspended = false
    private var actionGeneration: UInt64 = 0
    private var actionTasks: [UUID: Task<Void, Never>] = [:]

    init(environment: DownloadEnvironment) {
        self.manager = DownloadManager(environment: environment)
        self.defaultDownloadDirectory = environment.defaultDownloadDirectory
            ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
    }

    func activate() {
        suspended = false
        actionGeneration &+= 1
        manager.resumeActions()
    }

    var items: [DownloadItemSnapshot] {
        (manager.tasks + manager.completedTasks).map(DownloadEngineCompatibility.snapshot)
    }

    func enqueue(source: URL, destination: URL) async throws {
        guard !suspended else { throw DownloadServiceError.featureSuspended }
        do {
            _ = try await manager.addDownload(url: source, destination: destination)
        } catch is DownloadConflictError {
            throw DownloadServiceError.conflict
        } catch {
            // Storage ownership remains the engine's explicit
            // DownloadError.storageUnavailable; the UI only reads its
            // localizedDescription and never imports engine types.
            throw error
        }
    }

    func pause(id: UUID) async {
        guard let task = (manager.tasks + manager.completedTasks).first(where: { $0.id == id }) else { return }
        await manager.pauseDownload(task)
    }

    func resume(id: UUID) async throws {
        guard !suspended else { throw DownloadServiceError.featureSuspended }
        guard let task = (manager.tasks + manager.completedTasks).first(where: { $0.id == id }) else { return }
        // Match the engine's UI contract (action returns while the task runs),
        // but keep an owned action task so a feature-off barrier can invalidate
        // it and wait for its cancellation before saving.
        let actionID = UUID()
        let requestGeneration = actionGeneration
        let action = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.actionTasks.removeValue(forKey: actionID) }
            guard !self.suspended, requestGeneration == self.actionGeneration else { return }
            try? await self.manager.resumeDownload(task)
        }
        actionTasks[actionID] = action
    }

    func cancel(id: UUID) async {
        guard let task = (manager.tasks + manager.completedTasks).first(where: { $0.id == id }) else { return }
        await manager.cancelDownload(task)
    }

    func delete(id: UUID, moveFilesToTrash: Bool) async {
        _ = await manager.delete(taskIDs: [id], moveFilesToTrash: moveFilesToTrash)
    }

    var hasPendingConflict: Bool { manager.pendingConflict != nil }

    var pendingConflict: DownloadConflictSnapshot? {
        guard let conflict = manager.pendingConflict else { return nil }
        let existing = DownloadEngineCompatibility.snapshot(of: conflict.existingTask)
        let canResume: Bool
        switch existing.state {
        case .completed, .cancelled: canResume = false
        default: canResume = true
        }
        return DownloadConflictSnapshot(
            id: conflict.id,
            existingID: existing.id,
            existingFilename: existing.filename,
            existingState: existing.state,
            incomingURL: conflict.incomingURL.absoluteString,
            suggestedAlternativeName: conflict.suggestedAlternativeName,
            canResumeExisting: canResume)
    }

    func start(id: UUID) async throws {
        guard !suspended else { throw DownloadServiceError.featureSuspended }
        guard let task = (manager.tasks + manager.completedTasks).first(where: { $0.id == id }) else { return }
        try await manager.startDownload(task)
    }

    func retry(id: UUID, fromScratch: Bool) async throws {
        guard !suspended else { throw DownloadServiceError.featureSuspended }
        guard let task = (manager.tasks + manager.completedTasks).first(where: { $0.id == id }) else { return }
        try await manager.retryFailed(task, fromScratch: fromScratch)
    }

    func resolveConflict(_ action: DownloadConflictAction) async {
        guard !suspended, let conflict = manager.pendingConflict else { return }
        let resolution: ConflictResolution
        switch action {
        case .resumeExisting: resolution = .resumeExisting
        case .restart: resolution = .restart
        case .addSeparate: resolution = .addSeparate
        case .skip: resolution = .skip
        }
        await manager.resolveConflict(conflict, resolution: resolution)
    }

    func openFile(id: UUID) {
        (manager.tasks + manager.completedTasks).first(where: { $0.id == id })?.openFile()
    }

    func revealInFinder(id: UUID) {
        (manager.tasks + manager.completedTasks).first(where: { $0.id == id })?.showInFinder()
    }

    func deletionPlan(for ids: Set<UUID>) -> DownloadDeletionPlan {
        DownloadEngineCompatibility.deletionPlan(for: items, ids: ids)
    }

    var storageUnavailableReason: String? { manager.downloadListUnavailableReason }

    func pauseAllAndSave() async {
        // Barrier first: any queued resume/start Task sees suspended or a new
        // generation and cannot begin network work after this returns.
        suspended = true
        actionGeneration &+= 1
        manager.suspendActions()
        let actions = Array(actionTasks.values)
        for action in actions { action.cancel() }
        // Pause the real tasks so an in-flight action can unwind, then wait for
        // every owned action before saving the final state.
        await manager.pauseAll()
        for action in actions { await action.value }
        actionTasks.removeAll()
        manager.saveBeforeTermination()
    }

    func shutdown() {
        manager.saveBeforeTermination()
    }
}

/// Explicit roots for Valora. This function is not called by AppDelegate.
@MainActor
enum ValoraDownloadEnvironment {
    static func production() -> DownloadEnvironment {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Valora/Downloads", isDirectory: true)
        let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Valora/Downloads", isDirectory: true)
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        let defaults = UserDefaults(suiteName: "com.wangqing.valora.downloads")!
        return DownloadEnvironment(
            persistenceURL: support.appendingPathComponent("downloads.json"),
            scratchContainer: cache,
            defaults: defaults,
            defaultDownloadDirectory: downloads,
            allowExternalHelpers: false,
            measureTemporaryStorageAtLaunch: false)
    }

    static func qa(root: URL, suite: String) -> DownloadEnvironment {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let scratch = root.appendingPathComponent("scratch", isDirectory: true)
        let downloads = root.appendingPathComponent("downloads", isDirectory: true)
        let trash = root.appendingPathComponent("trash", isDirectory: true)
        return DownloadEnvironment(
            persistenceURL: root.appendingPathComponent("persistence/downloads.json"),
            scratchContainer: scratch,
            defaults: defaults,
            defaultDownloadDirectory: downloads,
            allowExternalHelpers: false,
            measureTemporaryStorageAtLaunch: false,
            trashItem: { url in
                try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
                let destination = trash.appendingPathComponent(url.lastPathComponent)
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.moveItem(at: url, to: destination)
            })
    }
}

/// A fake implementation for the future UI/adaptation tests. It owns no engine
/// process, manager, settings or filesystem root.
@MainActor
final class FakeDownloadService: DownloadServicing {
    private(set) var items: [DownloadItemSnapshot] = []
    var fakeConflict: DownloadConflictSnapshot?
    var lastConflictAction: DownloadConflictAction?
    private(set) var openedIDs: [UUID] = []
    private(set) var revealedIDs: [UUID] = []
    private(set) var startedIDs: [UUID] = []
    private(set) var retriedIDs: [UUID] = []
    private(set) var deletedIDs: [UUID] = []
    private(set) var deleteTrashFlags: [Bool] = []
    private(set) var pauseAllCount = 0
    private var suspended = false
    private(set) var shutdownCount = 0
    var defaultDownloadDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("valora-fake-downloads", isDirectory: true)
    var storageUnavailableReason: String?

    func activate() { suspended = false }

    func enqueue(source: URL, destination: URL) async throws {
        guard !suspended else { throw DownloadServiceError.featureSuspended }
        items.append(DownloadItemSnapshot(
            id: UUID(), sourceURL: source.absoluteString,
            destinationPath: destination.path,
            filename: destination.lastPathComponent,
            state: .waiting, progress: 0, downloadedBytes: 0, totalBytes: 0,
            speed: 0, estimatedTimeRemaining: 0, isMerging: false,
            isFilePresent: false, segmentLayout: nil, activeSegments: 0,
            segments: [], errorDescription: nil))
    }

    func pause(id: UUID) async {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let old = items[index]
        items[index] = DownloadItemSnapshot(id: old.id, sourceURL: old.sourceURL,
            destinationPath: old.destinationPath, filename: old.filename,
            state: .paused, progress: old.progress,
            downloadedBytes: old.downloadedBytes, totalBytes: old.totalBytes,
            speed: old.speed, estimatedTimeRemaining: old.estimatedTimeRemaining,
            isMerging: old.isMerging, isFilePresent: old.isFilePresent,
            segmentLayout: old.segmentLayout, activeSegments: old.activeSegments,
            segments: old.segments, errorDescription: old.errorDescription)
    }

    func resume(id: UUID) async throws {
        guard !suspended else { throw DownloadServiceError.featureSuspended }
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let old = items[index]
        items[index] = DownloadItemSnapshot(id: old.id, sourceURL: old.sourceURL,
            destinationPath: old.destinationPath, filename: old.filename,
            state: .downloading, progress: old.progress,
            downloadedBytes: old.downloadedBytes, totalBytes: old.totalBytes,
            speed: old.speed, estimatedTimeRemaining: old.estimatedTimeRemaining,
            isMerging: old.isMerging, isFilePresent: old.isFilePresent,
            segmentLayout: old.segmentLayout, activeSegments: old.activeSegments,
            segments: old.segments, errorDescription: old.errorDescription)
    }

    func cancel(id: UUID) async {
        items.removeAll { $0.id == id }
    }

    func delete(id: UUID, moveFilesToTrash: Bool) async {
        deletedIDs.append(id)
        deleteTrashFlags.append(moveFilesToTrash)
        items.removeAll { $0.id == id }
    }

    var hasPendingConflict: Bool { fakeConflict != nil }
    var pendingConflict: DownloadConflictSnapshot? { fakeConflict }
    func setItemsForQA(_ values: [DownloadItemSnapshot]) { items = values }
    func setConflictForQA(_ value: DownloadConflictSnapshot?) { fakeConflict = value }

    func start(id: UUID) async throws {
        guard !suspended else { throw DownloadServiceError.featureSuspended }
        startedIDs.append(id)
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let old = items[index]
        items[index] = DownloadItemSnapshot(id: old.id, sourceURL: old.sourceURL,
            destinationPath: old.destinationPath, filename: old.filename,
            state: .downloading, progress: old.progress,
            downloadedBytes: old.downloadedBytes, totalBytes: old.totalBytes,
            speed: old.speed, estimatedTimeRemaining: old.estimatedTimeRemaining,
            isMerging: old.isMerging, isFilePresent: old.isFilePresent,
            segmentLayout: old.segmentLayout, activeSegments: old.activeSegments,
            segments: old.segments, errorDescription: old.errorDescription,
            createdAt: old.createdAt, completedAt: old.completedAt, fileSize: old.fileSize,
            hasUnknownTotalSize: old.hasUnknownTotalSize,
            completedSegments: old.completedSegments, totalSegments: old.totalSegments)
    }

    func retry(id: UUID, fromScratch: Bool) async throws {
        guard !suspended else { throw DownloadServiceError.featureSuspended }
        retriedIDs.append(id)
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let old = items[index]
        items[index] = DownloadItemSnapshot(id: old.id, sourceURL: old.sourceURL,
            destinationPath: old.destinationPath, filename: old.filename,
            state: .downloading, progress: old.progress,
            downloadedBytes: old.downloadedBytes, totalBytes: old.totalBytes,
            speed: old.speed, estimatedTimeRemaining: old.estimatedTimeRemaining,
            isMerging: old.isMerging, isFilePresent: old.isFilePresent,
            segmentLayout: old.segmentLayout, activeSegments: old.activeSegments,
            segments: old.segments, errorDescription: old.errorDescription,
            createdAt: old.createdAt, completedAt: old.completedAt, fileSize: old.fileSize,
            hasUnknownTotalSize: old.hasUnknownTotalSize,
            completedSegments: old.completedSegments, totalSegments: old.totalSegments)
    }

    func resolveConflict(_ action: DownloadConflictAction) async {
        lastConflictAction = action
        fakeConflict = nil
    }

    func openFile(id: UUID) { openedIDs.append(id) }
    func revealInFinder(id: UUID) { revealedIDs.append(id) }

    func deletionPlan(for ids: Set<UUID>) -> DownloadDeletionPlan {
        DownloadEngineCompatibility.deletionPlan(for: items, ids: ids)
    }

    func pauseAllAndSave() async {
        suspended = true
        pauseAllCount += 1
        for index in items.indices where [.waiting, .starting, .validating, .refreshingLink, .downloading].contains(items[index].state) {
            let old = items[index]
            items[index] = DownloadItemSnapshot(id: old.id, sourceURL: old.sourceURL,
                destinationPath: old.destinationPath, filename: old.filename,
                state: .paused, progress: old.progress,
                downloadedBytes: old.downloadedBytes, totalBytes: old.totalBytes,
                speed: 0, estimatedTimeRemaining: old.estimatedTimeRemaining,
                isMerging: old.isMerging, isFilePresent: old.isFilePresent,
                segmentLayout: old.segmentLayout, activeSegments: 0,
                segments: old.segments, errorDescription: old.errorDescription,
                createdAt: old.createdAt, completedAt: old.completedAt, fileSize: old.fileSize,
                hasUnknownTotalSize: old.hasUnknownTotalSize,
                completedSegments: old.completedSegments, totalSegments: old.totalSegments)
        }
    }

    func shutdown() { shutdownCount += 1 }
}
