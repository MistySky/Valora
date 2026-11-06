// Two independent Calmon menu-bar modules share one presentation popover:
// system monitor (native CPU/MEM item) and calendar (date item). The
// Outline-v7 application entry remains owned by AppDelegate.
import AppKit
import Observation
import SwiftUI

@MainActor
final class MenuBarModuleController: NSObject, NSPopoverDelegate {
    let monitor: SystemMonitor
    let calendar: CalmonCalendarModel
    /// Read-only Codex quota line in the shared panel. Started/stopped by its
    /// own settings switch; never affects the monitor or calendar samples.
    private(set) var codex: CodexUsageProvider?
    private let onSettings: () -> Void
    private let onQuit: () -> Void

    private let appModel: AppModel?
    private let settings: RevivalSettings?
    private(set) var monitorItem: NSStatusItem?
    private(set) var calendarItem: NSStatusItem?

    /// Exactly one popover is used by both entries. It is re-anchored to the
    /// clicked status item; two panels can never coexist.
    private let sharedPopover = NSPopover()
    private let visibility = MenuBarPanelVisibility()

    private var started = false
    private var samplingEnabled = true
    private var systemMonitorVisible = true
    private var calendarVisible = true
    private var codexUsageVisible = false
    private var monitorObservationActive = false
    private var calendarObservationActive = false
    private var monitorObservationEpoch: UInt64 = 0
    private var calendarObservationEpoch: UInt64 = 0
    private var lastMonitorKey: String?
    private var lastCalendarText: String?
    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private(set) var panelShowCount = 0
    private(set) var panelCloseCount = 0
    private(set) var calendarPopoverCloseCount = 0
    private(set) var monitorPopoverCloseCount = 0
    private(set) var lastCalendarPopoverCloseAt: Date?
    private(set) var lastMonitorPopoverCloseAt: Date?
    private(set) var menuShowCount = 0
    private(set) var lastOpenedModule: MenuBarModule?

    enum MenuBarModule: String, Equatable {
        case systemMonitor
        case calendar
    }

    enum PanelRouteDecision: Equatable {
        case open
        case close
        case switchAnchor
    }

    /// Pure routing policy shared by status-item clicks and panel methods.
    /// It guarantees one popover at a time: same anchor toggles closed, the
    /// other anchor switches in one close/open sequence.
    static func panelRouteDecision(isShown: Bool, lastOpened: MenuBarModule?,
                                   clicked: MenuBarModule) -> PanelRouteDecision {
        guard isShown else { return .open }
        return lastOpened == clicked ? .close : .switchAnchor
    }

    init(monitor: SystemMonitor, calendar: CalmonCalendarModel,
         appModel: AppModel? = nil, settings: RevivalSettings? = nil,
         onSettings: @escaping () -> Void, onQuit: @escaping () -> Void,
         calendarPopoverBehavior: NSPopover.Behavior = .transient) {
        self.monitor = monitor
        self.calendar = calendar
        self.appModel = appModel
        self.settings = settings
        self.onSettings = onSettings
        self.onQuit = onQuit
        super.init()
        sharedPopover.behavior = calendarPopoverBehavior
        sharedPopover.delegate = self
        visibility.monitorVisible = systemMonitorVisible
        visibility.calendarVisible = calendarVisible
    }

    // MARK: - Lifecycle

    func start(startSampling: Bool = true) {
        guard !started else { return }
        started = true
        samplingEnabled = startSampling
        monitorObservationEpoch &+= 1
        calendarObservationEpoch &+= 1
        monitorObservationActive = false
        calendarObservationActive = false
        lastCalendarText = nil
        lastMonitorKey = nil
        if calendarVisible, calendarItem == nil {
            calendarItem = makeStatusItem(autosaveName: "Valora.Calendar")
        }
        if systemMonitorVisible, monitorItem == nil {
            monitorItem = makeStatusItem(autosaveName: "Valora.SystemMonitor")
        }
        if calendarVisible {
            calendar.start()
            calendar.handleWake()
        }
        if startSampling, systemMonitorVisible { monitor.start() }
        updateCalendarImage()
        updateMonitorImage()
        if systemMonitorVisible { observeMonitor() }
        if calendarVisible { observeCalendar() }
        installWakeObservers()
    }

    func stop() {
        guard started else { return }
        started = false
        monitorObservationEpoch &+= 1
        calendarObservationEpoch &+= 1
        monitorObservationActive = false
        calendarObservationActive = false
        closeAllPopovers()
        sharedPopover.contentViewController = nil
        removeStatusItems()
        calendar.stop()
        monitor.stop()
        if let sleepObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver)
            self.sleepObserver = nil
        }
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
    }

    func setSystemMonitorVisible(_ visible: Bool) {
        systemMonitorVisible = visible
        visibility.monitorVisible = visible
        guard started else { return }
        if visible {
            if monitorItem == nil { monitorItem = makeStatusItem(autosaveName: "Valora.SystemMonitor") }
            if samplingEnabled { monitor.start() }
            updateMonitorImage()
            observeMonitor()
            if sharedPopover.isShown, calendarVisible { monitor.setPanelVisible(true) }
        } else {
            monitorObservationEpoch &+= 1
            monitorObservationActive = false
            monitor.setPanelVisible(false)
            monitor.stop()
            removeStatusItem(&monitorItem)
            lastMonitorKey = nil
            if sharedPopover.isShown, !calendarVisible { sharedPopover.performClose(nil) }
        }
    }

    func setCalendarVisible(_ visible: Bool) {
        calendarVisible = visible
        visibility.calendarVisible = visible
        guard started else { return }
        if visible {
            if calendarItem == nil { calendarItem = makeStatusItem(autosaveName: "Valora.Calendar") }
            calendar.start()
            calendar.handleWake()
            updateCalendarImage()
            observeCalendar()
            if sharedPopover.isShown, systemMonitorVisible {
                calendar.setPanelVisibility(panel: true, calendarModule: true)
            }
        } else {
            calendarObservationEpoch &+= 1
            calendarObservationActive = false
            calendar.setPanelVisibility(panel: false, calendarModule: false)
            calendar.stop()
            removeStatusItem(&calendarItem)
            lastCalendarText = nil
            if sharedPopover.isShown, !systemMonitorVisible { sharedPopover.performClose(nil) }
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
        removeStatusItem(&monitorItem)
        removeStatusItem(&calendarItem)
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
    }

    private func handleWake() {
        guard started else { return }
        if calendarVisible { calendar.handleWake() }
        if systemMonitorVisible, samplingEnabled { monitor.start() }
        updateCalendarImage()
        updateMonitorImage()
    }

    // MARK: - Status-item routing

    @objc func statusItemClicked(_ sender: NSStatusBarButton) {
        let right = NSApp.currentEvent?.type == .rightMouseUp
            || NSApp.currentEvent?.modifierFlags.contains(.control) == true
        let item: NSStatusItem?
        let module: MenuBarModule?
        if sender === monitorItem?.button {
            item = monitorItem
            module = .systemMonitor
        } else if sender === calendarItem?.button {
            item = calendarItem
            module = .calendar
        } else {
            item = nil
            module = nil
        }
        guard let item, let module else { return }
        if right {
            showBasicMenu(for: item)
        } else {
            toggle(module)
        }
    }

    private func toggle(_ module: MenuBarModule) {
        switch Self.panelRouteDecision(isShown: sharedPopover.isShown,
                                       lastOpened: lastOpenedModule,
                                       clicked: module) {
        case .close:
            sharedPopover.performClose(nil)
        case .open, .switchAnchor:
            showSharedPanel(module)
        }
    }

    /// Own switch for the Codex usage line. Enabling starts the read-only
    /// refresh; disabling stops its task/timer and removes the row.
    func setCodexUsage(_ provider: CodexUsageProvider?, visible: Bool) {
        codex = provider
        guard codexUsageVisible != visible else {
            visibility.codexUsageVisible = visible
            return
        }
        codexUsageVisible = visible
        visibility.codexUsageVisible = visible
        if visible {
            provider?.start()
        } else {
            provider?.stop()
        }
        if sharedPopover.isShown { sharedPopover.performClose(nil) }
    }

    /// Stops the background read without touching the monitor or calendar.
    func stopCodexUsage() {
        codex?.stop()
        codexUsageVisible = false
        visibility.codexUsageVisible = false
    }

    // MARK: - Shared panel

    func showMonitorPanel() { showSharedPanel(.systemMonitor) }
    func showCalendarPanel() { showSharedPanel(.calendar) }

    private func showSharedPanel(_ module: MenuBarModule) {
        guard started, sharedItem(for: module) != nil else { return }
        switch Self.panelRouteDecision(isShown: sharedPopover.isShown,
                                       lastOpened: lastOpenedModule,
                                       clicked: module) {
        case .close:
            sharedPopover.performClose(nil)
            return
        case .switchAnchor:
            sharedPopover.performClose(nil)
        case .open:
            break
        }
        lastOpenedModule = module
        // Opening the panel may refresh an expired Codex snapshot; the provider
        // throttles and coalesces, so repeated opens cannot stack requests.
        if codexUsageVisible { codex?.refreshOnOpen() }
        guard let item = sharedItem(for: module) else { return }
        let screen = item.button?.window?.screen ?? NSScreen.main
        let maxHeight = (screen?.visibleFrame.height ?? 800) * 0.8
        let host = NSHostingController(rootView: CalendarMonitorSharedView(
            monitor: monitor, calendar: calendar, codex: codex,
            appModel: appModel, settings: settings,
            visibility: visibility,
            maxHeight: maxHeight,
            onClose: { [weak self] in self?.sharedPopover.performClose(nil) }))
        host.sizingOptions = [.preferredContentSize]
        sharedPopover.contentViewController = host
        guard let button = item.button else { return }
        sharedPopover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        sharedPopover.contentViewController?.view.window?.makeKey()
        NSApp.activate(ignoringOtherApps: true)
        panelShowCount += 1
        if systemMonitorVisible { monitor.setPanelVisible(true) }
        if calendarVisible { calendar.setPanelVisibility(panel: true, calendarModule: true) }
    }

    private func sharedItem(for module: MenuBarModule) -> NSStatusItem? {
        switch module {
        case .systemMonitor: return systemMonitorVisible ? monitorItem : nil
        case .calendar: return calendarVisible ? calendarItem : nil
        }
    }

    func closeAllPopovers() {
        sharedPopover.performClose(nil)
    }

    func popoverDidClose(_ notification: Notification) {
        guard notification.object as? NSPopover === sharedPopover else { return }
        if lastOpenedModule == .systemMonitor {
            monitorPopoverCloseCount += 1
            lastMonitorPopoverCloseAt = Date()
        } else if lastOpenedModule == .calendar {
            calendarPopoverCloseCount += 1
            lastCalendarPopoverCloseAt = Date()
        }
        panelCloseCount += 1
        monitor.setPanelVisible(false)
        if calendarVisible {
            calendar.setPanelVisibility(panel: false, calendarModule: true)
        } else {
            calendar.setPanelVisibility(panel: false, calendarModule: false)
        }
    }

    // MARK: - Diagnostics

    var isMonitorPanelShown: Bool { sharedPopover.isShown && systemMonitorVisible }
    var isCalendarPanelShown: Bool { sharedPopover.isShown && calendarVisible }
    var monitorPopoverIdentity: ObjectIdentifier { ObjectIdentifier(sharedPopover) }
    var calendarPopoverIdentity: ObjectIdentifier { ObjectIdentifier(sharedPopover) }
    var calendarPopoverForDiagnostics: NSPopover { sharedPopover }
    var monitorPanelContentSize: NSSize { sharedPopover.contentSize }
    var calendarPanelContentSize: NSSize { sharedPopover.contentSize }
    var monitorPopoverWindow: NSWindow? { sharedPopover.contentViewController?.view.window }
    var calendarPopoverWindow: NSWindow? { sharedPopover.contentViewController?.view.window }
    var monitorStatusButton: NSStatusBarButton? { systemMonitorVisible ? monitorItem?.button : nil }
    var calendarStatusButton: NSStatusBarButton? { calendarVisible ? calendarItem?.button : nil }
    var calendarStatusText: String? {
        guard let value = calendarStatusButton?.accessibilityLabel() else { return nil }
        return value.replacingOccurrences(of: "日期 ", with: "")
    }

    // MARK: - Menu

    func makeBasicMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let version = NSMenuItem(title: AppMenuCommands.versionText, action: nil, keyEquivalent: "")
        version.isEnabled = false
        menu.addItem(version)
        let settings = NSMenuItem(title: AppMenuCommands.settingsTitle,
                                  action: #selector(openSettingsFromMenu), keyEquivalent: AppMenuCommands.settingsKey)
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: AppMenuCommands.quitTitle,
                              action: #selector(quitFromMenu), keyEquivalent: AppMenuCommands.quitKey)
        quit.target = self
        menu.addItem(quit)
        return menu
    }

    private func showBasicMenu(for item: NSStatusItem) {
        closeAllPopovers()
        menuShowCount += 1
        let menu = makeBasicMenu()
        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil
    }

    @objc private func openSettingsFromMenu() { onSettings() }
    @objc private func quitFromMenu() { onQuit() }

    func refreshCalendarHolidays() { calendar.refreshCalendarHolidays() }

    // MARK: - Rendering

    private func updateCalendarImage() {
        guard let item = calendarItem else { return }
        let text = calendar.menuBarText
        guard text != lastCalendarText else { return }
        lastCalendarText = text
        item.button?.image = Self.dateImage(text)
        item.button?.toolTip = text
        item.button?.setAccessibilityLabel("日期 \(text)")
    }

    private func updateMonitorImage() {
        guard let item = monitorItem, systemMonitorVisible else { return }
        let cpu = UIStyle.percentString(monitor.snapshot.cpu.usage)
        let mem = UIStyle.percentString(monitor.snapshot.memory?.usedPercent)
        let key = "\(cpu)|\(mem)"
        guard key != lastMonitorKey else { return }
        lastMonitorKey = key
        item.button?.image = Self.metricImage(cpu: cpu, mem: mem)
        item.button?.toolTip = "CPU \(cpu) · 内存 \(mem)"
        item.button?.setAccessibilityLabel("CPU \(cpu)，内存 \(mem)")
    }

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
        let labelStyle = NSMutableParagraphStyle(); labelStyle.alignment = .left
        let valueStyle = NSMutableParagraphStyle(); valueStyle.alignment = .right
        let valueX = labelWidth + gap
        func draw(_ label: String, _ value: String, slot: Int) {
            let y = height - CGFloat(slot + 1) * lineHeight
            (label as NSString).draw(in: NSRect(x: 0, y: y, width: labelWidth, height: lineHeight),
                                     withAttributes: [.font: font, .paragraphStyle: labelStyle,
                                                      .foregroundColor: NSColor.black])
            (value as NSString).draw(in: NSRect(x: valueX, y: y, width: valueWidth, height: lineHeight),
                                     withAttributes: [.font: font, .paragraphStyle: valueStyle,
                                                      .foregroundColor: NSColor.black])
        }
        draw("CPU", cpu, slot: 0)
        draw("MEM", mem, slot: 1)
        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    static func dateImage(_ text: String) -> NSImage {
        let font = UIStyle.Fonts.menuBarDate
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let textHeight = ceil((text as NSString).size(withAttributes: attributes).height)
        let height = textHeight + 2
        let textWidth = ceil((text as NSString).size(withAttributes: attributes).width)
        let image = NSImage(size: NSSize(width: textWidth, height: height))
        image.lockFocus()
        let style = NSMutableParagraphStyle(); style.alignment = .center
        let y = (height - textHeight) / 2
        (text as NSString).draw(in: NSRect(x: 0, y: y, width: textWidth, height: textHeight),
                                withAttributes: [.font: font, .paragraphStyle: style,
                                                 .foregroundColor: NSColor.black])
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
            _ = monitor.snapshot.memory?.unusedCapacity
            _ = monitor.snapshot.disk?.available
            _ = monitor.snapshot.uptime
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

    private func observeCalendar() {
        guard started, calendarVisible, !calendarObservationActive else { return }
        let epoch = calendarObservationEpoch
        calendarObservationActive = true
        withObservationTracking {
            _ = calendar.menuBarText
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.started, self.calendarVisible,
                      self.calendarObservationEpoch == epoch else { return }
                self.calendarObservationActive = false
                self.updateCalendarImage()
                self.observeCalendar()
            }
        }
    }
}
