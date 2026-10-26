// Adapted from TheDynamicPunk/Convoy commit 007a20973923fcd69c42a3571fc299f5b8582dc6
// Views/DuplicateDownloadSheet.swift (GPL-3.0; see Resources/Licenses/Convoy-GPL-3.0.txt).
// Four native decisions are retained, while the conflict is represented by an
// immutable snapshot and the engine's continuation is resolved by the adapter.
import SwiftUI

struct DownloadConflictSheet: View {
    @ObservedObject var model: DownloadMenuModel
    let conflict: DownloadConflictSnapshot
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.12)).frame(width: 44, height: 44)
                    Image(systemName: "arrow.down.doc.fill").font(.system(size: 20, weight: .medium)).foregroundStyle(.orange)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("已经在下载列表中").font(.system(size: 14, weight: .semibold))
                    Text(conflict.existingFilename).font(.system(size: 12)).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
            }
            .padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 18)
            Divider()
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("当前下载").font(.system(size: 11, weight: .medium)).foregroundStyle(.tertiary)
                        .textCase(.uppercase).tracking(0.4)
                    Text(conflict.existingFilename).font(.system(size: 12.5))
                        .lineLimit(2).truncationMode(.middle)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("新请求").font(.system(size: 11, weight: .medium)).foregroundStyle(.tertiary)
                        .textCase(.uppercase).tracking(0.4)
                    Text(conflict.incomingURL).font(.system(size: 11.5)).foregroundStyle(.secondary)
                        .lineLimit(2).truncationMode(.middle)
                }
            }
            .padding(.horizontal, 24).padding(.vertical, 18)
            Divider()
            VStack(spacing: 8) {
                if conflict.canResumeExisting {
                    Button { resolve(.resumeExisting) } label: {
                        Label("保留现有下载", systemImage: "play.circle.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button { resolve(.skip) } label: {
                        Label("保留我已有的文件", systemImage: "checkmark.circle.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                }
                Button { resolve(.restart) } label: {
                    Label("重新下载并替换", systemImage: "arrow.clockwise").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered).controlSize(.large)
                Button { resolve(.addSeparate) } label: {
                    Label("另存为“\(conflict.suggestedAlternativeName)”", systemImage: "plus.circle")
                        .frame(maxWidth: .infinity).lineLimit(1).truncationMode(.middle)
                }
                .buttonStyle(.bordered).controlSize(.large)
                if conflict.canResumeExisting {
                    Button("跳过此下载") { resolve(.skip) }
                        .buttonStyle(.plain).font(.system(size: 12.5)).foregroundStyle(.secondary)
                        .keyboardShortcut(.cancelAction).padding(.top, 2)
                }
            }
            .padding(.horizontal, 24).padding(.top, 16).padding(.bottom, 22)
        }
        .frame(width: UIStyle.Metrics.menuBarPopoverWidth)
        .interactiveDismissDisabled()
    }

    private func resolve(_ action: DownloadConflictAction) {
        Task { await model.resolve(action); dismiss() }
    }
}
