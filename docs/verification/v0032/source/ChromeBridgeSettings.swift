import AppKit
import ChromeBridgeKit
import Foundation
import OSLog
import SwiftUI

/// Settings-side state for the Chrome-only bridge. It reads the real
/// Chrome native-messaging manifest when refreshed, but writes it only from
/// the explicit install action below.
@MainActor
final class ChromeBridgeSettingsModel: ObservableObject {
    let registration: ChromeBridgeRegistration
    @Published private(set) var status: ChromeBridgeRegistration.Status = .notSetUp
    @Published private(set) var isBridgeListening = false
    @Published private(set) var lastHandshakeAt: Date?
    @Published private(set) var message: String?

    private let bridgeListening: () -> Bool
    private let lastHandshake: () -> Date?
    private let logger = Logger(subsystem: "com.wangqing.valora", category: "ChromeBridgeSettings")

    init(registration: ChromeBridgeRegistration,
         bridgeListening: @escaping () -> Bool = { false },
         lastHandshake: @escaping () -> Date? = { nil }) {
        self.registration = registration
        self.bridgeListening = bridgeListening
        self.lastHandshake = lastHandshake
        refresh()
    }

    var extensionAvailable: Bool {
        FileManager.default.fileExists(
            atPath: registration.extensionDirectory.appendingPathComponent("manifest.json").path)
    }

    var extensionStatusText: String {
        extensionAvailable ? "待安装" : "不可用"
    }

    var bridgeStatusText: String {
        switch status {
        case .notSetUp:
            return "未设置"
        case .needsRepair:
            return "需修复"
        case .ready:
            if !isBridgeListening { return "未监听" }
            return lastHandshakeAt == nil ? "已设置" : "已就绪"
        }
    }

    var bridgeActionTitle: String {
        status == .notSetUp ? "启用" : "修复"
    }

    func refresh() {
        status = registration.status()
        isBridgeListening = bridgeListening()
        lastHandshakeAt = lastHandshake()
        message = nil
    }

    func installBridge() {
        do {
            try registration.register()
            refresh()
            message = "桥接已设置。"
        } catch {
            logger.error("Chrome bridge registration failed: \(error.localizedDescription, privacy: .public)")
            message = shortError(error)
            refresh()
        }
    }

    func openChromeExtensions() {
        guard let chrome = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome") else {
            message = "未找到 Google Chrome。"
            return
        }
        let url = URL(string: "chrome://extensions")!
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open([url], withApplicationAt: chrome, configuration: configuration) { [weak self] _, error in
            Task { @MainActor in
                if let error {
                    self?.logger.error("Could not open Chrome extensions: \(error.localizedDescription, privacy: .public)")
                    self?.message = "无法打开 Chrome 扩展页。"
                }
            }
        }
    }

    func openExtensionFolder() {
        let url = registration.extensionDirectory
        guard FileManager.default.fileExists(atPath: url.path) else {
            message = "随包扩展不可用。"
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func shortError(_ error: Error) -> String {
        guard let error = error as? ChromeBridgeRegistration.RegistrationError else {
            return "桥接设置失败。"
        }
        switch error {
        case .unstableLocation:
            return "请先将 Valora 移到固定位置。"
        case .invalidHost:
            return "本地桥接程序不可用。"
        case .invalidExtension:
            return "随包扩展不完整。"
        case .writeFailed:
            return "无法写入 Chrome 注册文件。"
        }
    }
}

struct ChromeBridgeSettingsCard: View {
    @ObservedObject var model: ChromeBridgeSettingsModel
    @State private var showInstallHelp = false

    var body: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Text("Chrome 扩展").font(.system(size: 13.5))
                    Spacer(minLength: 8)
                    Text(model.extensionStatusText)
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    Button("安装…") { showInstallHelp.toggle() }
                        .font(.system(size: 12.5))
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                        .disabled(!model.extensionAvailable)
                }
                .padding(.horizontal, 12).frame(height: 41)

                SettingsRule()

                HStack(spacing: 8) {
                    Text("本地桥接").font(.system(size: 13.5))
                    Spacer(minLength: 8)
                    Text(model.bridgeStatusText)
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    Button(model.bridgeActionTitle) { model.installBridge() }
                        .font(.system(size: 12.5))
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                }
                .padding(.horizontal, 12).frame(height: 41)

                if showInstallHelp {
                    SettingsRule()
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Chrome 开发者模式 → 加载已解压的扩展程序")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 14) {
                            Button("打开扩展页") { model.openChromeExtensions() }
                            Button("打开扩展目录") { model.openExtensionFolder() }
                            Spacer(minLength: 0)
                        }
                        .font(.system(size: 12.5))
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 9)
                }

                if let message = model.message {
                    SettingsRule()
                    Text(message)
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                        .lineLimit(1)
                        .padding(.horizontal, 12).frame(height: 32)
                }
            }
        }
    }
}
