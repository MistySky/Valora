// Adapted from TheDynamicPunk/Convoy commit 007a20973923fcd69c42a3571fc299f5b8582dc6
// Views/DeleteConfirmationSheet.swift (GPL-3.0; see Resources/Licenses/Convoy-GPL-3.0.txt).
// The one confirmation decision is retained: record-only by default, explicit
// Trash opt-in, unfinished partial data discarded. File/Trash work is injected
// through onConfirm so QA can spy without touching a real file.
import SwiftUI

struct DownloadDeleteRequest: Identifiable {
    let id = UUID()
    let taskIDs: Set<UUID>
    let preCheckTrash: Bool
    init(taskIDs: Set<UUID>, preCheckTrash: Bool = false) {
        self.taskIDs = taskIDs
        self.preCheckTrash = preCheckTrash
    }
}

struct DownloadDeleteConfirmation: View {
    let request: DownloadDeleteRequest
    let plan: DownloadDeletionPlan
    let onConfirm: (Set<UUID>, Bool) async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var moveFilesToTrash: Bool
    @State private var isDeleting = false

    init(request: DownloadDeleteRequest, plan: DownloadDeletionPlan,
         onConfirm: @escaping (Set<UUID>, Bool) async -> Void) {
        self.request = request
        self.plan = plan
        self.onConfirm = onConfirm
        _moveFilesToTrash = State(initialValue: request.preCheckTrash)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(Color.red.opacity(0.12)).frame(width: 44, height: 44)
                    Image(systemName: "trash").font(.system(size: 19, weight: .medium)).foregroundStyle(.red)
                }
                Text(title).font(.system(size: 14, weight: .semibold))
                    .lineLimit(2).truncationMode(.middle)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 18)
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(messageLines.enumerated()), id: \.offset) { _, line in
                    Text(line).font(.system(size: 12.5)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if plan.trashableCount > 0 {
                    Toggle(isOn: $moveFilesToTrash) {
                        Text(trashToggleLabel).font(.system(size: 12.5))
                    }
                    .toggleStyle(.checkbox).padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24).padding(.vertical, 18)
            Divider()
            HStack(spacing: 12) {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction).frame(minWidth: 76)
                Button(confirmLabel) {
                    guard !isDeleting else { return }
                    isDeleting = true
                    let ids = request.taskIDs, trash = moveFilesToTrash
                    Task { await onConfirm(ids, trash); dismiss() }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(isDeleting).frame(minWidth: 76)
            }
            .padding(.horizontal, 24).padding(.top, 14).padding(.bottom, 20)
        }
        .frame(width: UIStyle.Metrics.menuBarPopoverWidth)
    }

    private var title: String {
        if let single = plan.single { return "删除“\(single.filename)”？" }
        return "删除 \(plan.count) 个下载？"
    }
    private var confirmLabel: String { plan.count > 1 ? "删除 \(plan.count)" : "删除" }
    private var messageLines: [String] {
        if let single = plan.single {
            switch single.impact {
            case .finishedFile: return ["从下载列表移除？文件会保留在原位置。"]
            case .finishedFileMissing: return ["从下载列表移除。文件已经不在保存位置。"]
            case .discardsProgress(let bytes):
                return [single.isFailed
                    ? "删除此下载并丢弃已下载的 \(formatBytes(bytes))？"
                    : "此下载尚未完成，进度将被丢弃。"]
            case .nothingToLose: return ["从下载列表移除。"]
            }
        }
        var lines: [String] = []
        if plan.progressDiscardingCount > 0 {
            lines.append("将丢弃 \(plan.progressDiscardingCount) 个未完成下载中已下载的 \(formatBytes(plan.progressDiscardingBytes))。")
        }
        if lines.isEmpty { lines.append("从下载列表移除。") }
        return lines
    }
    private var trashToggleLabel: String {
        let bytes = formatBytes(plan.trashableBytes)
        if plan.single != nil { return "将文件移到废纸篓（\(bytes)）" }
        return "将 \(plan.trashableCount) 个完成文件移到废纸篓（\(bytes)）"
    }
    private func formatBytes(_ bytes: Int64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var size = Double(max(0, bytes)); var unit = 0
        while size >= 1024 && unit < units.count - 1 { size /= 1024; unit += 1 }
        return String(format: "%.1f %@", size, units[unit])
    }
}
