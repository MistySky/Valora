// Adapted from TheDynamicPunk/Convoy commit 007a20973923fcd69c42a3571fc299f5b8582dc6
// Views/NewDownloadView.swift (GPL-3.0; see Resources/Licenses/Convoy-GPL-3.0.txt).
// The URL/card/footer presentation and explicit-submit behavior are retained.
// YouTube/helper/clipboard paths are intentionally absent: V0030 is HTTP(S)-only
// and helpers remain disabled by the accepted DownloadEnvironment.
import AppKit
import SwiftUI

struct DownloadNewView: View {
    @ObservedObject var model: DownloadMenuModel
    @Environment(\.dismiss) private var dismiss
    @State private var inputText = ""
    @State private var destination: URL?
    @State private var errorMessage = ""
    @State private var isLoading = false
    @FocusState private var isURLFieldFocused: Bool

    private var urls: [URL] {
        inputText.split(whereSeparator: \.isNewline).compactMap { line in
            let value = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, let url = URL(string: value),
                  let scheme = url.scheme?.lowercased(),
                  ["http", "https"].contains(scheme), url.host != nil else { return nil }
            return url
        }
    }

    private var folder: URL {
        destination ?? model.service.defaultDownloadDirectory
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(Color.blue.opacity(0.12)).frame(width: 44, height: 44)
                    Image(systemName: "arrow.down.doc.fill").font(.system(size: 20, weight: .medium)).foregroundStyle(.blue)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("新建下载").font(.system(size: 14, weight: .semibold))
                    Text("粘贴或输入一个或多个 HTTP(S) 链接").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 18)

            Divider()

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 6) {
                    Image(systemName: "link").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                    Text("URL(s)").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                }
                TextField(text: $inputText, prompt: Text(verbatim: "https://example.com/file.zip"), axis: .vertical) {
                    Text("URLs")
                }
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: inputText.isEmpty ? .default : .monospaced))
                .lineLimit(2...5)
                .focused($isURLFieldFocused)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(Color(nsColor: .quaternarySystemFill), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.accentColor, lineWidth: 1.5)
                    .opacity(isURLFieldFocused ? 1 : 0))

                HStack(spacing: 6) {
                    if urls.isEmpty {
                        Image(systemName: "exclamationmark.circle").foregroundStyle(.orange)
                        Text(inputText.isEmpty ? "输入有效的 HTTP(S) 链接" : "没有有效的 HTTP(S) 链接")
                    } else {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        Text(urls.count == 1 ? "1 个链接" : "\(urls.count) 个链接")
                    }
                    Spacer(minLength: 0)
                }
                .font(.system(size: 11)).foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Text("保存到").font(.system(size: 12)).foregroundStyle(.secondary)
                    Text(folder.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        .font(.system(size: 11.5)).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 8)
                    Button("选择…") { chooseFolder() }.controlSize(.small)
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(Color(nsColor: .quaternarySystemFill), in: RoundedRectangle(cornerRadius: 10))

                if !errorMessage.isEmpty {
                    Text(errorMessage).font(.system(size: 11)).foregroundStyle(.red)
                }
            }
            .padding(.horizontal, 24).padding(.vertical, 18)

            Divider()

            HStack {
                Button("取消") { dismiss() }.keyboardShortcut(.escape)
                Spacer()
                Button(action: start) {
                    if isLoading { ProgressView().controlSize(.small) }
                    else { Text(urls.count > 1 ? "开始 \(urls.count) 个下载" : "开始下载") }
                }
                .buttonStyle(.borderedProminent)
                .disabled(urls.isEmpty || isLoading)
                .keyboardShortcut(.return)
            }
            .padding(24)
        }
        .frame(width: UIStyle.Metrics.menuBarPopoverWidth)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "选择"
        if panel.runModal() == .OK { destination = panel.url }
    }

    private func start() {
        guard !urls.isEmpty else { return }
        isLoading = true
        errorMessage = ""
        Task { @MainActor in
            do {
                for url in urls {
                    let name = url.lastPathComponent.isEmpty ? "download" : url.lastPathComponent
                    try await model.enqueue(source: url, destination: folder.appendingPathComponent(name))
                }
                dismiss()
            } catch DownloadServiceError.conflict {
                // The engine queued its native duplicate decision; this form
                // gets out of the way and the conflict sheet owns the next step.
                model.refresh()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }
}
