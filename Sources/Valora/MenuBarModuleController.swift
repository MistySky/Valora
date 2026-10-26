// Routing/popover/status-item structure migrated from MistySky/Calmon commit
// 72235116e1420fa081e8f694991a32809f81498d, CalMon/App/MenuBarController.swift.
// Hot-key panel, Calmon settings and capture/debug hooks are intentionally absent.
// The Outline-v7 application item remains independently owned by AppDelegate.
import AppKit
import Observation
import SwiftUI

/// Owns the two independent Calmon-style status items (system monitor and
/// calendar), their native popovers, and the shared basic right-click menu.
///
/// The Outline-v7 application status item is owned by AppDelegate and remains a
/// separate, always-present music-management entry. This controller never
/// touches it, never registers a notch/music command, and never replaces the
/// single application icon.
@MainActor
final class MenuBarModuleController: NSObject, NSPopoverDelegate {
    let monitor: SystemMonitor
    let calendar: CalmonCalendarModel
    let codexUsage: CodexUsageProvider?
    private let onSettings: () -> Void
    private let onQuit: () -> Void

    /// The monitor and Codex modules share this one status item. Calendar and
    /// the application Outline item remain independent.
    private(set) var combinedItem: NSStatusItem?
    private(set) var calendarItem: NSStatusItem?
    private let combinedPopover = NSPopover()
    private let calendarPopover = NSPopover()

    // Compatibility accessors for diagnostics/tests: they resolve the shared
    // item only when that section is enabled; no second status item exists.
    private var codexActive: Bool { codexVisible && codexUsage != nil }
    struct CombinedSections: Equatable {
        let monitor: Bool
        let codex: Bool
        var isEmpty: Bool { !monitor && !codex }
    }
    var combinedSections: CombinedSections {
        CombinedSections(monitor: systemMonitorVisible, codex: codexActive)
    }
    var monitorItem: NSStatusItem? { systemMonitorVisible ? combinedItem : nil }
    var codexItem: NSStatusItem? { codexActive ? combinedItem : nil }
    private var monitorPopover: NSPopover { combinedPopover }
    private var codexPopover: NSPopover { combinedPopover }
    private let appSearch = AppSearchModel()
    private var started = false
    private var samplingEnabled = true
    private var systemMonitorVisible = true
    private var calendarVisible = true
    private var codexVisible = true
    private var monitorObservationActive = false
    private var calendarObservationActive = false
    private var codexObservationActive = false
    private var monitorObservationEpoch: UInt64 = 0
    private var codexObservationEpoch: UInt64 = 0
    private var lastMonitorKey: String?
    private var lastCalendarText: String?
    private var lastCodexKey: String?
    private var lastCombinedKey: String?
    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private(set) var panelShowCount = 0
    private(set) var panelCloseCount = 0
    private(set) var calendarPopoverCloseCount = 0
    private(set) var monitorPopoverCloseCount = 0
    private(set) var codexPopoverCloseCount = 0
    private(set) var lastCalendarPopoverCloseAt: Date?
    private(set) var lastMonitorPopoverCloseAt: Date?
    private(set) var lastCodexPopoverCloseAt: Date?
    private(set) var menuShowCount = 0
    private(set) var lastOpenedModule: MenuBarModule?

    enum MenuBarModule: String, Equatable {
        case systemMonitor
        case codexUsage
        case calendar
    }

    init(monitor: SystemMonitor, calendar: CalmonCalendarModel,
         codexUsage: CodexUsageProvider? = nil,
         onSettings: @escaping () -> Void, onQuit: @escaping () -> Void,
         calendarPopoverBehavior: NSPopover.Behavior = .transient) {
        self.monitor = monitor
        self.calendar = calendar
        self.codexUsage = codexUsage
        self.onSettings = onSettings
        self.onQuit = onQuit
        super.init()
        // The shared monitor/Codex panel. Calendar remains its own popover.
        combinedPopover.behavior = .transient
        combinedPopover.delegate = self
        // Production uses transient. QA-only fixed-display mode reuses this
        // same popover/view/model with applicationDefined to isolate focus.
        calendarPopover.behavior = calendarPopoverBehavior
        calendarPopover.delegate = self
    }

    // MARK: - Lifecycle

    /// `startSampling == false` is for injected QA only: status-item routing and
    /// native popovers are still real, but no system monitor timer is started.
    func start(startSampling: Bool = true) {
        guard !started else { return }
        started = true
        samplingEnabled = startSampling
        monitorObservationEpoch &+= 1
        codexObservationEpoch &+= 1
        monitorObservationActive = false
        codexObservationActive = false
        lastCalendarText = nil
        lastMonitorKey = nil
        lastCodexKey = nil
        lastCombinedKey = nil
        // NSStatusBar inserts newer items to the left. Calendar is created first
        // so the initial left-to-right module order is monitor → calendar, while
        // the application Outline item remains independently present.
        if calendarVisible, calendarItem == nil {
            calendarItem = makeStatusItem(autosaveName: "Valora.Calendar")
        }
        if (systemMonitorVisible || codexActive), combinedItem == nil {
            combinedItem = makeStatusItem(autosaveName: "Valora.MonitorCodex")
        }
        if calendarVisible {
            calendar.start()
            calendar.handleWake()
        }
        if codexVisible {
            codexUsage?.start()
        }
        if startSampling, systemMonitorVisible {
            monitor.start()
        }
        updateCalendarImage()
        updateCombinedImage()
        if systemMonitorVisible { observeMonitor() }
        if calendarVisible { observeCalendar() }
        if codexVisible { observeCodex() }
        installWakeObservers()
    }

    func stop() {
        guard started else { return }
        started = false
        monitorObservationEpoch &+= 1
        codexObservationEpoch &+= 1
        monitorObservationActive = false
        codexObservationActive = false
        closeAllPopovers()
        // Release the SwiftUI trees even if a close animation callback is
        // delayed; stop is the explicit end of this status-item session.
        combinedPopover.contentViewController = nil
        calendarPopover.contentViewController = nil
        removeStatusItems()
        calendar.stop()
        monitor.stop()
        codexUsage?.stop()
        if let sleepObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver)
            self.sleepObserver = nil
        }
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
        monitorObservationActive = false
        calendarObservationActive = false
        codexObservationActive = false
    }

    func setSystemMonitorVisible(_ visible: Bool) {
        systemMonitorVisible = visible
        guard started else { return }
        if visible {
            ensureCombinedStatusItem()
            if samplingEnabled { monitor.start() }
            updateCombinedImage()
            observeMonitor()
        } else {
            monitorObservationEpoch &+= 1
            monitorObservationActive = false
            monitor.stop()
        }
        refreshCombinedPresentation()
    }

    func setCodexVisible(_ visible: Bool) {
        codexVisible = visible
        guard started, codexUsage != nil else { return }
        if visible {
            ensureCombinedStatusItem()
            codexUsage?.start()
            updateCombinedImage()
            observeCodex()
        } else {
            codexObservationEpoch &+= 1
            codexObservationActive = false
            codexUsage?.stop()
        }
        refreshCombinedPresentation()
    }

    func setCalendarVisible(_ visible: Bool) {
        calendarVisible = visible
        guard started else { return }
        if visible {
            if calendarItem == nil { calendarItem = makeStatusItem(autosaveName: "Valora.Calendar") }
            calendar.start()
            calendar.handleWake()
            updateCalendarImage()
        } else {
            calendarPopover.performClose(nil)
            calendar.setPanelVisibility(panel: false, calendarModule: false)
            calendar.stop()
            removeStatusItem(&calendarItem)
            // Do not let a recreated date button inherit the previous item's
            // "already rendered" cache key. The restored item must draw even if
            // the calendar date text is unchanged.
            lastCalendarText = nil
        }
    }

    private func makeStatusItem(autosaveName: String) -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = autosaveName
        item.button?.imagePosition = .imageOnly
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked(_:))
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        return item
    }

    private func removeStatusItems() {
        removeStatusItem(&combinedItem)
        removeStatusItem(&calendarItem)
    }

    private func ensureCombinedStatusItem() {
        guard systemMonitorVisible || codexActive else { return }
        if combinedItem == nil {
            combinedItem = makeStatusItem(autosaveName: "Valora.MonitorCodex")
            lastCombinedKey = nil
        }
    }

    private func refreshCombinedPresentation() {
        guard started else { return }
        guard systemMonitorVisible || codexActive else {
            combinedPopover.performClose(nil)
            removeStatusItem(&combinedItem)
            lastCombinedKey = nil
            return
        }
        ensureCombinedStatusItem()
        updateCombinedImage()
        if combinedPopover.isShown {
            if let host = makeCombinedHost(), let item = combinedItem {
                present(combinedPopover, content: host, item: item)
                if systemMonitorVisible { monitor.setPanelVisible(true) }
            }
        }
    }

    private func removeStatusItem(_ item: inout NSStatusItem?) {
        guard let value = item else { return }
        value.button?.target = nil
        value.button?.action = nil
        NSStatusBar.system.removeStatusItem(value)
        item = nil
    }

    private func installWakeObservers() {
        let center = NSWorkspace.shared.notificationCenter
        sleepObserver = center.addObserver(forName: NSWorkspace.willSleepNotification,
                                           object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.handleSleep() }
        }
        wakeObserver = center.addObserver(forName: NSWorkspace.didWakeNotification,
                                          object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.handleWake() }
        }
    }

    private func handleSleep() {
        guard started else { return }
        closeAllPopovers()
        if systemMonitorVisible { monitor.stop() }
        if codexVisible { codexUsage?.stop() }
    }

    private func handleWake() {
        guard started else { return }
        if calendarVisible { calendar.handleWake() }
        if systemMonitorVisible, samplingEnabled { monitor.start() }
        if codexVisible { codexUsage?.start() }
    }

    // MARK: - Status-item routing

    @objc func statusItemClicked(_ sender: NSStatusBarButton) {
        let right = NSApp.currentEvent?.type == .rightMouseUp
            || NSApp.currentEvent?.modifierFlags.contains(.control) == true
        let item: NSStatusItem?
        let module: MenuBarModule?
        if sender === calendarItem?.button {
            item = calendarItem
            module = .calendar
        } else if sender === combinedItem?.button {
            item = combinedItem
            module = systemMonitorVisible ? .systemMonitor : .codexUsage
        } else {
            item = nil
            module = nil
        }
        guard let item, let module else { return }
        if right {
            showBasicMenu(for: item, module: module)
        } else {
            toggle(module)
        }
    }

    private func toggle(_ module: MenuBarModule) {
        switch module {
        case .calendar:
            if calendarPopover.isShown { calendarPopover.performClose(nil) }
            else { showCalendarPanel() }
        case .codexUsage, .systemMonitor:
            if combinedPopover.isShown { combinedPopover.performClose(nil) }
            else { showCombinedPanel() }
        }
    }

    // MARK: - Popovers

    func showCalendarPanel() {
        guard started, calendarVisible, calendarItem != nil else { return }
        if calendarPopover.isShown {
            calendarPopover.performClose(nil)
            return
        }
        combinedPopover.performClose(nil)
        lastOpenedModule = .calendar
        let screen = calendarItem?.button?.window?.screen ?? NSScreen.main
        let maxHeight = (screen?.visibleFrame.height ?? 800) * 0.8
        let host = NSHostingController(rootView: CalmonCalendarView(
            model: calendar, maxHeight: maxHeight,
            onClose: { [weak self] in self?.calendarPopover.performClose(nil) }))
        host.sizingOptions = [.preferredContentSize]
        if present(calendarPopover, content: host, item: calendarItem) {
            // Start authorized reads only after the native panel is actually on
            // screen, not merely because a click was attempted.
            calendar.setPanelVisibility(panel: true, calendarModule: true)
        }
    }

    func showCodexPanel() { showCombinedPanel(lastOpened: .codexUsage) }
    func showMonitorPanel() { showCombinedPanel(lastOpened: .systemMonitor) }

    private func makeCombinedHost() -> NSHostingController<MonitorCodexCombinedView>? {
        guard systemMonitorVisible || codexVisible else { return nil }
        let screen = combinedItem?.button?.window?.screen ?? NSScreen.main
        let maxHeight = (screen?.visibleFrame.height ?? 800) * 0.8
        let sections = combinedSections
        let root = MonitorCodexCombinedView(
            monitor: monitor, codex: sections.codex ? codexUsage : nil,
            maxHeight: maxHeight, search: appSearch,
            showMonitor: sections.monitor, showCodex: sections.codex,
            onClose: { [weak self] in self?.combinedPopover.performClose(nil) })
        let host = NSHostingController(rootView: root)
        host.sizingOptions = [.preferredContentSize]
        // Prime the first preferred-size measurement before NSPopover shows.
        // Without this, the hosting controller can present a provisional
        // scrollbar while SwiftUI's first layout pass is still settling. This
        // is not a fixed height: subsequent content changes still resize and
        // overflow remains scrollable.
        host.view.layoutSubtreeIfNeeded()
        let measured = host.view.fittingSize
        if measured.width > 0, measured.height > 0, measured.height < maxHeight {
            host.preferredContentSize = NSSize(
                width: UIStyle.Metrics.menuBarPopoverWidth, height: measured.height)
        }
        return host
    }

    func showCombinedPanel(lastOpened: MenuBarModule = .systemMonitor) {
        guard started, combinedItem != nil, systemMonitorVisible || codexActive else { return }
        if combinedPopover.isShown {
            combinedPopover.performClose(nil)
            return
        }
        calendarPopover.performClose(nil)
        lastOpenedModule = lastOpened
        if systemMonitorVisible { appSearch.beginPresentation() }
        if codexActive { codexUsage?.refreshOnOpen() }
        guard let host = makeCombinedHost() else { return }
        if present(combinedPopover, content: host, item: combinedItem) {
            if systemMonitorVisible { monitor.setPanelVisible(true) }
        }
    }

    /// Presentation order follows Calmon: show, make the popover window key,
    /// then activate. Activating first can move the popover to another display.
    @discardableResult
    private func present(_ popover: NSPopover, content: NSViewController, item: NSStatusItem?) -> Bool {
        popover.contentViewController = content
        guard let button = item?.button else { return false }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        NSApp.activate(ignoringOtherApps: true)
        panelShowCount += 1
        return popover.isShown
    }

    func closeAllPopovers() {
        combinedPopover.performClose(nil)
        calendarPopover.performClose(nil)
    }

    func popoverDidClose(_ notification: Notification) {
        guard let popover = notification.object as? NSPopover else { return }
        if popover === combinedPopover {
            monitorPopoverCloseCount &+= 1
            codexPopoverCloseCount &+= 1
            lastMonitorPopoverCloseAt = Date()
            lastCodexPopoverCloseAt = Date()
            monitor.setPanelVisible(false)
            appSearch.beginPresentation()
        } else if popover === calendarPopover {
            calendarPopoverCloseCount &+= 1
            lastCalendarPopoverCloseAt = Date()
            calendar.setPanelVisibility(panel: false, calendarModule: true)
        }
        popover.contentViewController = nil
        panelCloseCount += 1
    }

    var isMonitorPanelShown: Bool { combinedPopover.isShown && systemMonitorVisible }
    var isCalendarPanelShown: Bool { calendarPopover.isShown }
    var isCodexPanelShown: Bool { combinedPopover.isShown && codexActive }
    var monitorPopoverIdentity: ObjectIdentifier { ObjectIdentifier(combinedPopover) }
    var calendarPopoverIdentity: ObjectIdentifier { ObjectIdentifier(calendarPopover) }
    var codexPopoverIdentity: ObjectIdentifier { ObjectIdentifier(combinedPopover) }
    var monitorPanelContentSize: NSSize { combinedPopover.contentSize }
    var codexPanelContentSize: NSSize { combinedPopover.contentSize }
    var calendarPanelContentSize: NSSize { calendarPopover.contentSize }
    var monitorPopoverWindow: NSWindow? { combinedPopover.contentViewController?.view.window }
    var codexPopoverWindow: NSWindow? { combinedPopover.contentViewController?.view.window }
    var calendarPopoverWindow: NSWindow? { calendarPopover.contentViewController?.view.window }
    var combinedStatusButton: NSStatusBarButton? { combinedItem?.button }
    var calendarPopoverForDiagnostics: NSPopover { calendarPopover }
    var monitorStatusButton: NSStatusBarButton? { systemMonitorVisible ? combinedItem?.button : nil }
    var calendarStatusButton: NSStatusBarButton? { calendarItem?.button }
    var codexStatusButton: NSStatusBarButton? { codexActive ? combinedItem?.button : nil }
    var codexStatusText: String? {
        guard codexActive, let value = combinedItem?.button?.accessibilityLabel() else { return nil }
        let values = value.components(separatedBy: "，").filter { $0.contains("5H 剩余") || $0.contains("WEEK 剩余") }
        return values.isEmpty ? nil : "Codex " + values.joined(separator: "，")
    }
    var calendarStatusText: String? {
        guard let value = calendarStatusButton?.accessibilityLabel() else { return nil }
        return value.replacingOccurrences(of: "日期 ", with: "")
    }

    // MARK: - Basic right-click menu

    /// Shared with the notch: disabled version, Settings…, separator, Quit.
    /// Deliberately contains no music, display or notch actions.
    func makeBasicMenu() -> NSMenu {
        let menu = NSMenu()
        let version = NSMenuItem(title: AppMenuCommands.versionText, action: nil, keyEquivalent: "")
        version.isEnabled = false
        menu.addItem(version)
        let settings = NSMenuItem(title: AppMenuCommands.settingsTitle,
                                  action: #selector(openSettingsFromMenu),
                                  keyEquivalent: AppMenuCommands.settingsKey)
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: AppMenuCommands.quitTitle,
                              action: #selector(quitFromMenu),
                              keyEquivalent: AppMenuCommands.quitKey)
        quit.target = self
        menu.addItem(quit)
        return menu
    }

    private func showBasicMenu(for item: NSStatusItem, module: MenuBarModule) {
        closeAllPopovers()
        menuShowCount += 1
        let menu = makeBasicMenu()
        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil
        _ = module
    }

    @objc private func openSettingsFromMenu() { onSettings() }
    @objc private func quitFromMenu() { onQuit() }

    func refreshCalendarEvents() { calendar.refreshEvents() }

    // MARK: - Menu-bar rendering

    private func updateCalendarImage() {
        guard let item = calendarItem else { return }
        let text = calendar.menuBarText
        guard text != lastCalendarText else { return }
        lastCalendarText = text
        item.button?.image = Self.dateImage(text)
        item.button?.toolTip = text
        item.button?.setAccessibilityLabel("日期 \(text)")
    }

    private func updateMonitorImage() { updateCombinedImage() }
    private func updateCodexImage() { updateCombinedImage() }

    private func updateCombinedImage() {
        guard let item = combinedItem, systemMonitorVisible || codexActive else { return }
        let cpu = UIStyle.percentString(monitor.snapshot.cpu.usage)
        let mem = UIStyle.percentString(monitor.snapshot.memory?.usedPercent)
        let five = codexUsage?.snapshot.fiveHourRemainingPercentText ?? "--%"
        let week = codexUsage?.snapshot.weekRemainingPercentText ?? "--%"
        let failure = codexUsage?.snapshot.refreshErrorMessage ?? ""
        let key = "\(systemMonitorVisible)|\(codexVisible)|\(cpu)|\(mem)|\(five)|\(week)|\(failure)"
        guard key != lastCombinedKey else { return }
        lastCombinedKey = key
        item.button?.image = Self.combinedMetricImage(
            cpu: cpu, mem: mem, five: five, week: week,
            showMonitor: systemMonitorVisible,
            showCodex: codexActive)
        var parts: [String] = []
        if systemMonitorVisible { parts.append("CPU \(cpu)，内存 \(mem)") }
        if codexActive { parts.append("5H 剩余 \(five)，WEEK 剩余 \(week)") }
        if !failure.isEmpty { parts.append("Codex 更新失败") }
        item.button?.toolTip = parts.joined(separator: " · ")
        item.button?.setAccessibilityLabel(parts.joined(separator: "，"))
    }

    /// CPU/MEM and 5H/WEEK side by side in one status-item image.
    static func combinedMetricImage(cpu: String, mem: String,
                                    five: String, week: String,
                                    showMonitor: Bool, showCodex: Bool) -> NSImage? {
        let monitorImage = showMonitor ? metricImage(cpu: cpu, mem: mem) : nil
        let codexImage = showCodex ? codexMetricImage(five: five, week: week) : nil
        let gap: CGFloat = 10
        guard monitorImage != nil || codexImage != nil else { return nil }
        if let only = codexImage, monitorImage == nil { return only }
        if let only = monitorImage, codexImage == nil { return only }
        let left = monitorImage!, right = codexImage!
        let height = max(left.size.height, right.size.height)
        let width = left.size.width + gap + right.size.width
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        left.draw(in: NSRect(x: 0, y: (height - left.size.height) / 2,
                             width: left.size.width, height: left.size.height))
        right.draw(in: NSRect(x: left.size.width + gap,
                              y: (height - right.size.height) / 2,
                              width: right.size.width, height: right.size.height))
        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    /// Fixed-width 5H/WEEK image, matching the CPU/MEM menu-bar rhythm.
    static func codexMetricImage(five: String, week: String) -> NSImage {
        let font = UIStyle.Fonts.menuBarMetric
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let labelWidth = max(("5H" as NSString).size(withAttributes: attributes).width,
                             ("WEEK" as NSString).size(withAttributes: attributes).width)
        let valueWidth = max(("100%" as NSString).size(withAttributes: attributes).width,
                             ("--%" as NSString).size(withAttributes: attributes).width)
        let lineHeight = ceil(("5H" as NSString).size(withAttributes: attributes).height)
        let gap: CGFloat = 3
        let height = lineHeight * 2
        let width = ceil(labelWidth + gap + valueWidth)
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        let labelStyle = NSMutableParagraphStyle(); labelStyle.alignment = .left
        let valueStyle = NSMutableParagraphStyle(); valueStyle.alignment = .right
        let valueX = labelWidth + gap
        func draw(_ label: String, _ value: String, slot: Int) {
            let y = height - CGFloat(slot + 1) * lineHeight
            (label as NSString).draw(in: NSRect(x: 0, y: y, width: labelWidth, height: lineHeight),
                                     withAttributes: [.font: font, .paragraphStyle: labelStyle, .foregroundColor: NSColor.black])
            (value as NSString).draw(in: NSRect(x: valueX, y: y, width: valueWidth, height: lineHeight),
                                     withAttributes: [.font: font, .paragraphStyle: valueStyle, .foregroundColor: NSColor.black])
        }
        draw("5H", five, slot: 0)
        draw("WEEK", week, slot: 1)
        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    /// Two-line CPU/MEM label with fixed column width. Directly follows
    /// Calmon's MenuBarController rendering.
    static func metricImage(cpu: String, mem: String) -> NSImage {
        let font = UIStyle.Fonts.menuBarMetric
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let labelWidth = max(("CPU" as NSString).size(withAttributes: attributes).width,
                             ("MEM" as NSString).size(withAttributes: attributes).width)
        let valueWidth = max(("100%" as NSString).size(withAttributes: attributes).width,
                             ("--%" as NSString).size(withAttributes: attributes).width)
        let lineHeight = ceil(("CPU" as NSString).size(withAttributes: attributes).height)
        let gap: CGFloat = 3
        let height = lineHeight * 2
        let width = ceil(labelWidth + gap + valueWidth)
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        NSColor.black.set()
        let labelStyle = NSMutableParagraphStyle()
        labelStyle.alignment = .left
        let valueStyle = NSMutableParagraphStyle()
        valueStyle.alignment = .right
        let valueX = labelWidth + gap
        func draw(_ label: String, _ value: String, slot: Int) {
            let y = height - CGFloat(slot + 1) * lineHeight
            (label as NSString).draw(in: NSRect(x: 0, y: y, width: labelWidth, height: lineHeight),
                                     withAttributes: [.font: font, .paragraphStyle: labelStyle, .foregroundColor: NSColor.black])
            (value as NSString).draw(in: NSRect(x: valueX, y: y, width: valueWidth, height: lineHeight),
                                     withAttributes: [.font: font, .paragraphStyle: valueStyle, .foregroundColor: NSColor.black])
        }
        draw("CPU", cpu, slot: 0)
        draw("MEM", mem, slot: 1)
        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    /// Calmon menu-bar date typography: monospaced digits at 13 pt, template.
    static func dateImage(_ text: String) -> NSImage {
        let font = UIStyle.Fonts.menuBarDate
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let textHeight = ceil((text as NSString).size(withAttributes: attributes).height)
        let height = textHeight + 2
        let textWidth = ceil((text as NSString).size(withAttributes: attributes).width)
        let image = NSImage(size: NSSize(width: textWidth, height: height))
        image.lockFocus()
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let y = (height - textHeight) / 2
        (text as NSString).draw(in: NSRect(x: 0, y: y, width: textWidth, height: textHeight),
                                withAttributes: [.font: font, .paragraphStyle: style, .foregroundColor: NSColor.black])
        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    // MARK: - Observation

    private func observeMonitor() {
        guard started, systemMonitorVisible, !monitorObservationActive else { return }
        let epoch = monitorObservationEpoch
        monitorObservationActive = true
        withObservationTracking {
            _ = monitor.snapshot.timestamp
            _ = monitor.snapshot.cpu.usage
            _ = monitor.snapshot.memory?.usedPercent
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.started, self.systemMonitorVisible,
                      self.monitorObservationEpoch == epoch else { return }
                self.monitorObservationActive = false
                self.updateMonitorImage()
                self.observeMonitor()
            }
        }
    }

    private func observeCodex() {
        guard started, codexActive, !codexObservationActive else { return }
        let epoch = codexObservationEpoch
        codexObservationActive = true
        withObservationTracking {
            _ = codexUsage?.snapshot
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.started, self.codexActive,
                      self.codexObservationEpoch == epoch else { return }
                self.codexObservationActive = false
                self.updateCodexImage()
                self.observeCodex()
            }
        }
    }

    private func observeCalendar() {
        guard started, !calendarObservationActive else { return }
        calendarObservationActive = true
        withObservationTracking {
            _ = calendar.menuBarText
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.started else { return }
                self.calendarObservationActive = false
                self.updateCalendarImage()
                self.observeCalendar()
            }
        }
    }
}
