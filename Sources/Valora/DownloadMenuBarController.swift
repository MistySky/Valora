// Independent fourth menu-bar entry for the migrated Convoy download list.
// It owns one status item and one popover, never constructs a DownloadManager
// on open, and never reads DownloadManager.shared.
import AppKit
import SwiftUI

@MainActor
final class DownloadMenuBarController: NSObject, NSPopoverDelegate {
    let model: DownloadMenuModel
    private let onSettings: () -> Void
    private let onQuit: () -> Void
    private(set) var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var started = false
    private var lastIconKey: String?
    private(set) var popoverShowCount = 0
    private(set) var menuShowCount = 0

    init(service: DownloadServicing, onSettings: @escaping () -> Void, onQuit: @escaping () -> Void,
         animates: Bool = true) {
        self.model = DownloadMenuModel(service: service)
        self.onSettings = onSettings
        self.onQuit = onQuit
        super.init()
        popover.behavior = .transient
        popover.animates = animates
        popover.delegate = self
        model.onChange = { [weak self] in self?.updateIcon() }
    }

    func start() {
        guard !started else { return }
        started = true
        model.service.activate()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = "Valora.Downloads"
        item.button?.imagePosition = .imageOnly
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked(_:))
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item
        model.refresh()
        updateIcon()
    }

    func stop() {
        guard started else { return }
        started = false
        popover.close()
        popover.contentViewController = nil
        if let statusItem {
            statusItem.button?.target = nil
            statusItem.button?.action = nil
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItem = nil
        model.shutdown()
        lastIconKey = nil
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let right = NSApp.currentEvent?.type == .rightMouseUp
            || NSApp.currentEvent?.modifierFlags.contains(.control) == true
        if right { showBasicMenu() } else { togglePopover() }
    }

    func togglePopover() {
        guard started, statusItem != nil else { return }
        if popover.isShown { popover.close() }
        else { showPopover() }
    }

    func showPopover() {
        guard started, let button = statusItem?.button else { return }
        if popover.isShown { return }
        let screen = button.window?.screen ?? NSScreen.main
        let maxHeight = (screen?.visibleFrame.height ?? 800) * 0.7
        model.setPopoverOpen(true)
        let host = NSHostingController(rootView: DownloadPopoverView(
            model: model, maxHeight: maxHeight,
            onClose: { [weak self] in self?.popover.performClose(nil) }))
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        NSApp.activate(ignoringOtherApps: true)
        popoverShowCount += 1
    }

    func showNewDownload() {
        guard started else { return }
        if !popover.isShown { showPopover() }
        model.requestNewDownload()
    }

    /// Feature-off path: pause every active task, save records/partials and
    /// then hide the entry. It does not delete tasks or files; re-start reuses
    /// the same service and leaves paused tasks for an explicit user resume.
    func suspendAndStop() async {
        closePopover()
        await model.suspendAll()
        stop()
    }

    func closePopover() {
        // A sheet/temporary child can make performClose refuse; close() is the
        // AppKit force-close path and also releases the hosting tree.
        popover.close()
        popover.contentViewController = nil
    }

    func popoverDidClose(_ notification: Notification) {
        guard notification.object as? NSPopover === popover else { return }
        model.setPopoverOpen(false)
        popover.contentViewController = nil
    }

    var isPopoverShown: Bool { popover.isShown }
    var popoverIdentity: ObjectIdentifier { ObjectIdentifier(popover) }
    var popoverWindow: NSWindow? { popover.contentViewController?.view.window }

    /// Right click: new-download is the one module action; the rest is the
    /// same disabled version/settings/separator/quit menu used by the other
    /// independent modules.
    func makeBasicMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let newDownload = NSMenuItem(title: "新建下载…", action: #selector(newDownloadFromMenu),
                                     keyEquivalent: "")
        newDownload.target = self
        menu.addItem(newDownload)
        menu.addItem(.separator())
        let version = NSMenuItem(title: AppMenuCommands.versionText, action: nil, keyEquivalent: "")
        version.isEnabled = false
        menu.addItem(version)
        let settings = NSMenuItem(title: AppMenuCommands.settingsTitle,
                                  action: #selector(openSettings), keyEquivalent: AppMenuCommands.settingsKey)
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: AppMenuCommands.quitTitle,
                              action: #selector(quit), keyEquivalent: AppMenuCommands.quitKey)
        quit.target = self
        menu.addItem(quit)
        return menu
    }

    private func showBasicMenu() {
        guard let item = statusItem else { return }
        closePopover()
        menuShowCount += 1
        let menu = makeBasicMenu()
        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil
    }

    @objc private func newDownloadFromMenu() { showNewDownload() }
    @objc private func openSettings() { onSettings() }
    @objc private func quit() { onQuit() }

    private func updateIcon() {
        guard let button = statusItem?.button else { return }
        let descriptor = DownloadRingDescriptor.make(items: model.items, phase: model.phase)
        let key: String
        switch descriptor.kind {
        case .active(let p): key = "active-\(p.map { String(format: "%.4f", $0) } ?? "unknown")-\(String(format: "%.2f", model.phase))"
        case .paused(let p): key = "paused-\(p.map { String(format: "%.4f", $0) } ?? "unknown")"
        case .idle: key = "idle"
        case .failed: key = "failed"
        }
        guard key != lastIconKey else { return }
        lastIconKey = key
        button.image = DownloadRingIcon.image(for: descriptor)
        button.imageScaling = .scaleProportionallyDown
        button.toolTip = tooltip(descriptor)
        button.setAccessibilityLabel("下载")
    }

    private func tooltip(_ descriptor: DownloadRingDescriptor) -> String {
        switch descriptor.kind {
        case .idle: return "下载"
        case .active(let progress):
            return progress.map { "下载 \(Int($0 * 100))%" } ?? "下载中"
        case .paused(let progress):
            return progress.map { "已暂停 \(Int($0 * 100))%" } ?? "已暂停"
        case .failed: return "下载失败"
        }
    }
}
