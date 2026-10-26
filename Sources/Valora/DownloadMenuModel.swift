// Owns the download popover's UI-safe snapshots. It never constructs a
// second manager, never reads DownloadManager.shared, and uses one bounded
// refresh timer only while something can actually change.
import AppKit
import Combine
import Foundation

@MainActor
final class DownloadMenuModel: ObservableObject {
    let service: DownloadServicing
    @Published private(set) var items: [DownloadItemSnapshot] = []
    @Published private(set) var conflict: DownloadConflictSnapshot?
    @Published private(set) var phase: Double = 0
    @Published private(set) var storageUnavailableReason: String?
    @Published var isNewDownloadPresented = false

    var onChange: (() -> Void)?
    private var timer: Timer?
    private var popoverOpen = false
    private(set) var refreshCount = 0
    private(set) var timerCreateCount = 0

    init(service: DownloadServicing) {
        self.service = service
        refresh()
    }

    var activeItems: [DownloadItemSnapshot] {
        items.filter { [.waiting, .starting, .validating, .refreshingLink, .downloading].contains($0.state) }
    }

    var needsTick: Bool {
        popoverOpen || conflict != nil || items.contains {
            [.waiting, .starting, .validating, .refreshingLink, .downloading].contains($0.state)
        }
    }

    /// Refresh snapshots and the ring descriptor. Stable sort by the task's
    /// creation time (ID tiebreak); status/progress changes never reorder.
    func refresh() {
        refreshCount += 1
        let next = service.items.sorted {
            if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
            return $0.id.uuidString < $1.id.uuidString
        }
        let nextConflict = service.pendingConflict
        let nextStorageReason = service.storageUnavailableReason
        let itemsChanged = next != items
        let conflictChanged = nextConflict?.id != conflict?.id
        let storageChanged = nextStorageReason != storageUnavailableReason
        items = next
        conflict = nextConflict
        storageUnavailableReason = nextStorageReason
        let unknownAnimation: Bool
        if case .active(progress: nil) = DownloadRingDescriptor.make(items: items, phase: phase).kind {
            unknownAnimation = true
            phase += 0.10
            if phase >= 1 { phase -= 1 }
        } else {
            unknownAnimation = false
        }
        if itemsChanged || conflictChanged || storageChanged || unknownAnimation { onChange?() }
        updateTimer()
    }

    func setPopoverOpen(_ open: Bool) {
        popoverOpen = open
        refresh()
    }

    func requestNewDownload() {
        isNewDownloadPresented = true
        refresh()
    }

    func deletionPlan(for ids: Set<UUID>) -> DownloadDeletionPlan {
        service.deletionPlan(for: ids)
    }

    func enqueue(source: URL, destination: URL) async throws {
        try await service.enqueue(source: source, destination: destination)
        refresh()
    }

    func pause(_ id: UUID) async { await service.pause(id: id); refresh() }
    func start(_ id: UUID) async throws { try await service.start(id: id); refresh() }
    func resume(_ id: UUID) async throws { try await service.resume(id: id); refresh() }
    func retry(_ id: UUID, fromScratch: Bool) async throws {
        try await service.retry(id: id, fromScratch: fromScratch); refresh()
    }
    func cancel(_ id: UUID) async { await service.cancel(id: id); refresh() }
    func delete(ids: Set<UUID>, moveFilesToTrash: Bool) async {
        for id in ids { await service.delete(id: id, moveFilesToTrash: moveFilesToTrash) }
        refresh()
    }
    func resolve(_ action: DownloadConflictAction) async {
        await service.resolveConflict(action)
        refresh()
    }
    func open(_ id: UUID) { service.openFile(id: id) }
    func reveal(_ id: UUID) { service.revealInFinder(id: id) }
    func suspendAll() async {
        await service.pauseAllAndSave()
        refresh()
        stopTimer()
    }

    func shutdown() { timer?.invalidate(); timer = nil; service.shutdown() }
    func stopTimer() { timer?.invalidate(); timer = nil }

    private func updateTimer() {
        guard needsTick else { stopTimer(); return }
        guard timer == nil else { return }
        timerCreateCount += 1
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}
