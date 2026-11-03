// Menu-bar container around the migrated Convoy row/segment views. It keeps
// the list bounded and scrollable, exposes no category sidebar or top "+",
// and owns selection/delete/keyboard routing locally.
import AppKit
import SwiftUI

private enum DownloadPopoverSheet: Identifiable {
    case conflict(DownloadConflictSnapshot)
    case delete(DownloadDeleteRequest, DownloadDeletionPlan)
    case newDownload

    var id: String {
        switch self {
        case .conflict(let value): return "conflict-\(value.id)"
        case .delete(let request, _): return "delete-\(request.id)"
        case .newDownload: return "new-download"
        }
    }
}

struct DownloadPopoverView: View {
    @ObservedObject var model: DownloadMenuModel
    let maxHeight: CGFloat
    var onClose: () -> Void = {}

    @State private var selectedIDs: Set<UUID> = []
    @State private var selectionAnchor: UUID?
    @State private var focusedID: UUID?
    @State private var pendingDelete: DownloadDeleteRequest?
    @FocusState private var listFocused: Bool

    private var items: [DownloadItemSnapshot] { model.items }
    private var activeSheet: DownloadPopoverSheet? {
        if let conflict = model.conflict { return .conflict(conflict) }
        if let pendingDelete {
            return .delete(pendingDelete, model.deletionPlan(for: pendingDelete.taskIDs))
        }
        if model.isNewDownloadPresented { return .newDownload }
        return nil
    }

    private var sheetBinding: Binding<DownloadPopoverSheet?> {
        Binding(get: { activeSheet }, set: { value in
            guard value == nil else { return }
            pendingDelete = nil
            model.isNewDownloadPresented = false
            // A conflict is resolved through its actions; never silently
            // discard the engine's waiting continuation via a stray dismissal.
        })
    }

    private var contentHeight: CGFloat {
        let rows = CGFloat(max(items.count, 1))
        return min(maxHeight, max(170, 68 + rows * 92))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("下载").font(.system(size: 13, weight: .semibold))
                Text("\(items.count)").font(.system(size: 11).monospacedDigit()).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 16).padding(.top, 13).padding(.bottom, 10)

            if let reason = model.storageUnavailableReason {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(.orange)
                    Text("下载存储不可用：\(reason)").font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16).padding(.bottom, 8)
            }

            if items.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 24, weight: .light)).foregroundStyle(.tertiary)
                    Text("没有下载").font(.system(size: 12)).foregroundStyle(.secondary)
                    Text("右键下载图标可新建下载").font(.system(size: 11)).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            DownloadRowView(
                                item: item,
                                isSelected: selectedIDs.contains(item.id),
                                isEmphasized: listFocused,
                                isSelectionModeActive: !selectedIDs.isEmpty,
                                onSelect: { shift, command in
                                    select(item, shift: shift, command: command)
                                },
                                actions: rowActions,
                                onRequestDelete: { requestDelete([item.id]) })
                            if index < items.count - 1 {
                                Divider().padding(.leading, DownloadRowView.textLeading)
                            }
                        }
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .frame(width: UIStyle.Metrics.menuBarPopoverWidth, height: contentHeight)
        // Native NSPopover already supplies the Calmon material. A second
        // .regularMaterial here made this popover heavier than calendar/monitor.
        .focusable()
        .focused($listFocused)
        .onAppear { model.setPopoverOpen(true) }
        .onDisappear { model.setPopoverOpen(false) }
        .background(DownloadKeyboardMonitor(
            onDelete: { requestDelete(selectedIDs) },
            onSelectAll: { selectedIDs = Set(items.map(\.id)); selectionAnchor = items.last?.id; focusedID = items.last?.id },
            onArrow: { direction, shift in handleArrow(direction, shift: shift) }))
        .sheet(item: sheetBinding) { sheet in
            switch sheet {
            case .conflict(let conflict):
                DownloadConflictSheet(model: model, conflict: conflict)
            case .delete(let request, let plan):
                DownloadDeleteConfirmation(request: request, plan: plan) { ids, trash in
                    await model.delete(ids: ids, moveFilesToTrash: trash)
                    selectedIDs.removeAll(); selectionAnchor = nil; focusedID = nil
                }
            case .newDownload:
                DownloadNewView(model: model)
            }
        }
    }

    private var rowActions: DownloadRowActions {
        DownloadRowActions(
            pause: { id in Task { await model.pause(id) } },
            start: { id in Task { try? await model.start(id) } },
            resume: { id in Task { try? await model.resume(id) } },
            retry: { id in Task { try? await model.retry(id, fromScratch: false) } },
            restart: { id in Task { try? await model.retry(id, fromScratch: true) } },
            open: { id in model.open(id) },
            reveal: { id in model.reveal(id) },
            requestDelete: { id in requestDelete([id]) })
    }

    private func select(_ item: DownloadItemSnapshot, shift: Bool, command: Bool) {
        if shift, let anchor = selectionAnchor,
           let a = items.firstIndex(where: { $0.id == anchor }),
           let b = items.firstIndex(where: { $0.id == item.id }) {
            selectedIDs = Set(items[min(a, b)...max(a, b)].map(\.id))
            focusedID = item.id
            return
        }
        if selectedIDs.contains(item.id) { selectedIDs.remove(item.id) }
        else { selectedIDs.insert(item.id) }
        _ = command
        selectionAnchor = item.id
        focusedID = item.id
    }

    private func handleArrow(_ direction: Int, shift: Bool) {
        guard !items.isEmpty else { return }
        let current = focusedID.flatMap { id in items.firstIndex { $0.id == id } }
            ?? (direction > 0 ? -1 : items.count)
        let next = max(0, min(items.count - 1, current + direction))
        let item = items[next]
        focusedID = item.id
        if shift, let anchor = selectionAnchor,
           let a = items.firstIndex(where: { $0.id == anchor }) {
            selectedIDs = Set(items[min(a, next)...max(a, next)].map(\.id))
        } else {
            selectedIDs = [item.id]
            selectionAnchor = item.id
        }
    }

    private func requestDelete(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        let plan = model.deletionPlan(for: ids)
        if plan.isTriviallyDeletable {
            Task { await model.delete(ids: ids, moveFilesToTrash: false)
                selectedIDs.removeAll(); selectionAnchor = nil; focusedID = nil }
        } else {
            pendingDelete = DownloadDeleteRequest(
                taskIDs: ids, preCheckTrash: NSEvent.modifierFlags.contains(.shift))
        }
    }
}

/// Local key monitor, replacing Convoy's ListKeyResponder for a menu-bar
/// popover. It is one event monitor for the lifetime of the view, not a timer
/// or one monitor per row, and leaves text-field editing untouched.
private struct DownloadKeyboardMonitor: NSViewRepresentable {
    var onDelete: () -> Void
    var onSelectAll: () -> Void
    var onArrow: (Int, Bool) -> Void

    final class Coordinator {
        var monitor: Any?
        var onDelete: () -> Void = {}
        var onSelectAll: () -> Void = {}
        var onArrow: (Int, Bool) -> Void = { _, _ in }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.onDelete = onDelete
        context.coordinator.onSelectAll = onSelectAll
        context.coordinator.onArrow = onArrow
        context.coordinator.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak view] event in
            guard let view, let window = view.window, window.isKeyWindow,
                  !(window.firstResponder is NSTextView) else { return event }
            if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "a" {
                context.coordinator.onSelectAll(); return nil
            }
            switch event.keyCode {
            case 51, 117: context.coordinator.onDelete(); return nil
            case 125: context.coordinator.onArrow(1, event.modifierFlags.contains(.shift)); return nil
            case 126: context.coordinator.onArrow(-1, event.modifierFlags.contains(.shift)); return nil
            default: return event
            }
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onDelete = onDelete
        context.coordinator.onSelectAll = onSelectAll
        context.coordinator.onArrow = onArrow
    }
    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        if let monitor = coordinator.monitor { NSEvent.removeMonitor(monitor) }
        coordinator.monitor = nil
    }
}
