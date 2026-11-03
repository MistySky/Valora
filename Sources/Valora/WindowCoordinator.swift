import AppKit
import SwiftUI
import Combine
import ReferenceCore

/// Display geometry used by the coordinator. Production maps NSScreen; tests
/// inject frames (including negative origins) without a physical display.
struct DisplayDescriptor: Equatable, Sendable {
    let id: String
    let name: String
    let frame: CGRect
    let safeAreaTop: CGFloat
    let auxiliaryLeftWidth: CGFloat?
    let auxiliaryRightWidth: CGFloat?
    let menuBarHeight: CGFloat
    let isBuiltIn: Bool

    init(id: String, name: String, frame: CGRect, safeAreaTop: CGFloat,
         auxiliaryLeftWidth: CGFloat?, auxiliaryRightWidth: CGFloat?,
         menuBarHeight: CGFloat, isBuiltIn: Bool = false) {
        self.id = id; self.name = name; self.frame = frame
        self.safeAreaTop = safeAreaTop
        self.auxiliaryLeftWidth = auxiliaryLeftWidth
        self.auxiliaryRightWidth = auxiliaryRightWidth
        self.menuBarHeight = menuBarHeight
        self.isBuiltIn = isBuiltIn
    }

    init(screen: NSScreen) {
        let number = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        id = number.map(String.init) ?? screen.localizedName + "|" + NSStringFromRect(screen.frame)
        name = screen.localizedName
        frame = screen.frame
        safeAreaTop = screen.safeAreaInsets.top
        auxiliaryLeftWidth = screen.auxiliaryTopLeftArea?.width
        auxiliaryRightWidth = screen.auxiliaryTopRightArea?.width
        menuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
        isBuiltIn = number.map { CGDisplayIsBuiltin($0) != 0 } ?? false
    }
}

final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// The notch is an edge-anchored, programmatically positioned panel. AppKit
    /// may otherwise constrain a window to the visible frame/menu-bar area
    /// during screen/Space transitions, producing a short down-shifted notch.
    /// This does not add an offset; it preserves the caller's full-screen top
    /// coordinate. Normal user-driven window movement never applies here.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}
final class EdgeHostingView: NSHostingView<NotchView> {
    override var safeAreaInsets: NSEdgeInsets { NSEdgeInsetsZero }
}

/// One NSPanel per enabled display. Media content is shared; geometry, pointer,
/// hover and panel ownership are per screen. Only the active screen renders the
/// dynamic player surface; passive screens stay compact but remain interactive.
@MainActor
final class WindowCoordinator {
    private final class ScreenPanel {
        let id: String
        var display: DisplayDescriptor
        let panel: NotchPanel
        var geometry: NotchGeometry
        var pointerInside = false
        var pendingHover: DispatchWorkItem?
        var hoverGeneration = 0
        var moveObserver: NSObjectProtocol?
        init(display: DisplayDescriptor, panel: NotchPanel, geometry: NotchGeometry) {
            self.id = display.id; self.display = display; self.panel = panel; self.geometry = geometry
        }
    }

    unowned let model: AppModel
    private let displayProvider: () -> [DisplayDescriptor]
    private(set) var panel: NotchPanel!
    private var panels: [ScreenPanel] = []
    private var active: ScreenPanel!
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var applicationObserver: NSObjectProtocol?
    private var screenObserver: NSObjectProtocol?
    private var subscriptions = Set<AnyCancellable>()
    private var screenStateMonitor: ScreenStateMonitor?
    /// Current active notch panel number is published for the lock coordinator;
    /// screen reconciliation/activation can replace the panel after startup.
    let activeNotchWindowNumber = CurrentValueSubject<Int?, Never>(nil)

    init(_ model: AppModel, displayProvider: (() -> [DisplayDescriptor])? = nil) {
        self.model = model
        self.displayProvider = displayProvider ?? { NSScreen.screens.map(DisplayDescriptor.init(screen:)) }
    }

    func start(trackPointer: Bool = true) {
        model.trackChangedHandler = { [weak self] identity in
            self?.handleTrackChanged(identity)
        }
        let monitor = ScreenStateMonitor(screens: { [weak self] in
            guard let self else { return [] }
            return SettingsDisplayCatalog.selectedScreens(self.model.settings.selectedDisplay)
        })
        monitor.onStateChange = { [weak self] in self?.applyScreenState() }
        monitor.start()
        screenStateMonitor = monitor

        place()
        updateVisibility()
        if trackPointer {
            model.frontmostBundleIdentifier = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
            applicationObserver = NSWorkspace.shared.notificationCenter.addObserver(forName:NSWorkspace.didActivateApplicationNotification,object:nil,queue:.main) { [weak self] event in
                let bundle = (event.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier ?? ""
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.model.frontmostBundleIdentifier = bundle
                    self.musicVisibilityChanged()
                }
            }
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching:[.mouseMoved,.leftMouseDragged]) { [weak self] _ in
                MainActor.assumeIsolated { self?.trackMouse() }
            }
            localMonitor = NSEvent.addLocalMonitorForEvents(matching:[.mouseMoved,.leftMouseDragged]) { [weak self] event in
                MainActor.assumeIsolated { self?.trackMouse() }
                return event
            }
        }
        screenObserver = NotificationCenter.default.addObserver(forName:NSApplication.didChangeScreenParametersNotification,object:nil,queue:.main) { [weak self] _ in
            MainActor.assumeIsolated { self?.place() }
        }
        Publishers.MergeMany(
            model.$playing.map { _ in () }.eraseToAnyPublisher(),
            model.$title.map { _ in () }.eraseToAnyPublisher(),
            model.$artist.map { _ in () }.eraseToAnyPublisher(),
            model.$album.map { _ in () }.eraseToAnyPublisher()
        ).sink { [weak self] _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.model.presenter.mediaStateChanged() }
            }
        }.store(in: &subscriptions)
        model.$mediaIdle.removeDuplicates().sink { [weak self] _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.updateVisibility() }
            }
        }.store(in: &subscriptions)
        model.$connectionToast.removeDuplicates().sink { [weak self] _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.updateVisibility() }
            }
        }.store(in: &subscriptions)
        model.settings.$musicPreferences.removeDuplicates().sink { [weak self] _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.musicVisibilityChanged() }
            }
        }.store(in: &subscriptions)
        model.settings.$nowPlayingEnabled.removeDuplicates().sink { [weak self] _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.musicVisibilityChanged() }
            }
        }.store(in: &subscriptions)
        model.$frontmostBundleIdentifier.combineLatest(model.$mediaBundleIdentifier).sink { [weak self] _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.musicVisibilityChanged() }
            }
        }.store(in: &subscriptions)
        model.settings.$showNotch.sink { [weak self] _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.updateVisibility() }
            }
        }.store(in: &subscriptions)
        model.settings.$forceSimulatedNotch.removeDuplicates().sink { [weak self] _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.place() }
            }
        }.store(in: &subscriptions)
        model.settings.$hideWhenIdle.sink { [weak self] _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.updateVisibility() }
            }
        }.store(in: &subscriptions)
        model.settings.$hideFromScreenCapture.removeDuplicates().sink { [weak self] hidden in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    for record in self.panels {
                        record.panel.sharingType = hidden ? .none : .readOnly
                    }
                    self.updateVisibility()
                }
            }
        }.store(in: &subscriptions)
        model.settings.$selectedDisplay.removeDuplicates().sink { [weak self] _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.place() }
            }
        }.store(in: &subscriptions)
        Publishers.MergeMany(
            model.settings.$hideWhileInFullscreen.map { _ in () }.eraseToAnyPublisher(),
            model.settings.$hideWhileInMissionControl.map { _ in () }.eraseToAnyPublisher(),
            model.settings.$hideWhileGaming.map { _ in () }.eraseToAnyPublisher()
        ).sink { [weak self] _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.screenStateMonitor?.refresh()
                    self.applyScreenState()
                }
            }
        }.store(in: &subscriptions)
        Publishers.MergeMany(
            model.settings.$hoverEnabled.map { _ in () }.eraseToAnyPublisher(),
            model.settings.$hoverDelay.map { _ in () }.eraseToAnyPublisher()
        ).sink { [weak self] _ in
            MainActor.assumeIsolated { self?.cancelPendingHover() }
        }.store(in: &subscriptions)
        model.$presentation.sink { [weak self] _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.updateVisibility() }
            }
        }.store(in: &subscriptions)
        model.$title.sink { [weak self] _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.updateVisibility() }
            }
        }.store(in: &subscriptions)
        Publishers.MergeMany(
            model.$isSessionLocked.map { _ in () }.eraseToAnyPublisher(),
            model.$lockIndicator.map { _ in () }.eraseToAnyPublisher(),
            model.$lockNotchMounted.map { _ in () }.eraseToAnyPublisher(),
            model.$lockOverlayReady.map { _ in () }.eraseToAnyPublisher(),
            model.$previewLockPresentationActive.map { _ in () }.eraseToAnyPublisher(),
            model.$previewLockIndicator.map { _ in () }.eraseToAnyPublisher()
        ).sink { [weak self] _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.updateVisibility() }
            }
        }.store(in: &subscriptions)
    }

    private func musicVisibilityChanged() {
        model.presenter.musicVisibilityChanged()
        if !model.settings.nowPlayingEnabled {
            model.presenter.resetForScreenChange()
        }
        updateVisibility()
    }

    private func applyScreenState() {
        guard let monitor = screenStateMonitor else { return }
        let hidden = (monitor.isFullscreen && model.settings.hideWhileInFullscreen)
            || (monitor.isMissionControl && model.settings.hideWhileInMissionControl)
            || (monitor.isGaming && model.settings.hideWhileGaming)
        let wasHidden = model.screenHidden
        if hidden != model.screenHidden { model.screenHidden = hidden }
        if hidden && !wasHidden {
            cancelPendingHover()
            model.presenter.resetForScreenChange()
        }
        updateVisibility()
    }

    // MARK: - Panels and screens

    private func geometry(for display: DisplayDescriptor) -> NotchGeometry {
        .calculate(screenWidth:display.frame.width, safeAreaTop:display.safeAreaTop,
                   auxiliaryLeftWidth:display.auxiliaryLeftWidth,
                   auxiliaryRightWidth:display.auxiliaryRightWidth,
                   menuBarHeight:display.menuBarHeight,
                   simulated:model.settings.forceSimulatedNotch)
    }

    private func makeScreenPanel(_ display: DisplayDescriptor) -> ScreenPanel {
        let target = NSRect(x:display.frame.midX-312, y:display.frame.maxY-320, width:624, height:320)
        let window = NotchPanel(contentRect:target, styleMask:[.borderless,.nonactivatingPanel], backing:.buffered, defer:false)
        window.isOpaque = false; window.backgroundColor = .clear; window.hasShadow = false; window.isMovable = false
        window.isReleasedWhenClosed = false; window.hidesOnDeactivate = false; window.canBecomeVisibleWithoutLogin = true
        window.collectionBehavior = [.canJoinAllSpaces,.stationary,.ignoresCycle,.fullScreenAuxiliary]
        window.level = NSWindow.Level(rawValue:Int(CGShieldingWindowLevel())+1)
        window.ignoresMouseEvents = true; window.acceptsMouseMovedEvents = true; window.animationBehavior = .none
        window.sharingType = model.settings.hideFromScreenCapture ? .none : .readOnly
        window.identifier = NSUserInterfaceItemIdentifier(display.id)
        let geom = geometry(for:display)
        let host = EdgeHostingView(rootView: NotchView(model:model, settings:model.settings,
                                                       compactOnly:true, geometryOverride:geom,
                                                       allowsDynamic:false))
        host.sizingOptions = []
        window.contentView = host
        let record = ScreenPanel(display: display, panel: window, geometry: geom)
        record.moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: window, queue: .main) { [weak self, weak window] _ in
                guard let self, let window,
                      let record = self.panels.first(where: { $0.panel === window }) else { return }
                MainActor.assumeIsolated { self.anchorPanelTop(record) }
            }
        return record
    }

    /// The notch uses the same compact edge panel in normal/lock states. Lock
    /// is a content/activity swap inside that panel, not a separate full-screen
    /// window or a lower bar. The frame stays screen-top anchored.
    private func panelFrame(for record: ScreenPanel) -> NSRect {
        NSRect(x: record.display.frame.midX - 312,
               y: record.display.frame.maxY - 320,
               width: 624, height: 320)
    }

    /// Reassert the panel's screen-top edge after ordering, when WindowServer
    /// may have applied a menu-bar/safe-area constraint during a login Space
    /// handoff. This is event-driven, not a repeating order-front timer.
    private func anchorPanelTop(_ record: ScreenPanel) {
        let before = record.panel.frame
        let target = panelFrame(for: record)
        if record.panel.frame != target {
            record.panel.setFrame(target, display: false)
        }
        recordDiagnostic(record, reason: "anchor", panelBefore: before)
    }

    private func recordDiagnostic(_ record: ScreenPanel, reason: String, panelBefore: CGRect? = nil) {
        guard NotchWindowDiagnostic.shared.isEnabled else { return }
        let host = record.panel.contentView
        host?.layoutSubtreeIfNeeded()
        let hostFrame = host?.frame ?? .zero
        let hostBounds = host?.bounds ?? .zero
        let hostSafeArea = host?.safeAreaInsets ?? NSEdgeInsetsZero
        let hostTop = NotchDiagnosticCoordinate.hostTop(bounds: hostBounds,
                                                        isFlipped: host?.isFlipped ?? false)
        let contentTopScreen: CGPoint? = {
            guard let host, let window = record.panel as NSWindow? else { return nil }
            let point = host.convert(NSPoint(x: host.bounds.midX, y: hostTop), to: nil)
            return window.convertPoint(toScreen: point)
        }()
        let phase = model.lockIndicator.phase
        NotchWindowDiagnostic.shared.record(
            role: "primary",
            reason: reason,
            phase: String(describing: phase),
            displayID: record.id,
            screenFrame: record.display.frame,
            safeAreaTop: record.display.safeAreaTop,
            menuBarHeight: record.display.menuBarHeight,
            auxLeftWidth: record.display.auxiliaryLeftWidth,
            auxRightWidth: record.display.auxiliaryRightWidth,
            forceSimulated: model.settings.forceSimulatedNotch,
            hasPhysicalNotch: model.notchGeometry.hasPhysicalNotch,
            compact: model.notchGeometry.compact,
            visibleSize: model.visibleSize,
            contourTopInset: model.contour.topInset,
            panelBefore: panelBefore ?? record.panel.frame,
            panelAfter: record.panel.frame,
            hostFrame: hostFrame,
            hostBounds: hostBounds,
            hostSafeArea: hostSafeArea,
            hostTop: hostTop,
            contentTopScreen: contentTopScreen,
            visible: record.panel.isVisible,
            sessionLocked: model.isSessionLocked,
            notchMounted: model.lockNotchMounted,
            windowNumber: record.panel.windowNumber)
    }

    private func selectedDisplays() -> [DisplayDescriptor] {
        let all = displayProvider()
        guard !all.isEmpty else { return [] }
        switch model.settings.selectedDisplay {
        case "All displays": return all
        case "Built-in display": return all.filter(\.isBuiltIn)
        case "Main display": return Array(all.prefix(1))
        default:
            let named = all.filter { $0.name == model.settings.selectedDisplay }
            return named.isEmpty ? Array(all.prefix(1)) : named
        }
    }

    private func place() {
        let selectedRaw = selectedDisplays()
        let selected = selectedRaw.isEmpty ? Array(displayProvider().prefix(1)) : selectedRaw
        let wanted = Set(selected.map(\.id))
        var kept: [ScreenPanel] = []
        for record in panels {
            if wanted.contains(record.id) {
                kept.append(record)
            } else {
                record.pendingHover?.cancel()
                if let observer = record.moveObserver {
                    NotificationCenter.default.removeObserver(observer)
                    record.moveObserver = nil
                }
                record.panel.orderOut(nil)
                record.panel.contentView = nil
                record.panel.close()
            }
        }
        panels = kept
        for display in selected {
            let id = display.id
            let geom = geometry(for:display)
            if let record = panels.first(where: { $0.id == id }) {
                record.display = display
                record.geometry = geom
                record.panel.identifier = NSUserInterfaceItemIdentifier(id)
                record.panel.setFrame(panelFrame(for: record), display:true)
            } else {
                panels.append(makeScreenPanel(display))
            }
        }
        model.allowsMultiDisplayDynamic = model.settings.selectedDisplay == "All displays" && panels.count > 1
        if panels.isEmpty {
            active = nil
            panel = nil
            activeNotchWindowNumber.send(nil)
            return
        }
        let previousID = active?.id
        active = panels.first(where: { $0.id == previousID }) ?? panels.first
        model.notchGeometry = active.geometry
        panel = active.panel
        activeNotchWindowNumber.send(panel.windowNumber)
        cancelPendingHover()
        for record in panels {
            record.pointerInside = false
        }
        model.presenter.resetForScreenChange()
        renderPanels()
        updateVisibility()
    }

    private func renderPanels() {
        guard let active else { return }
        model.notchGeometry = active.geometry
        panel = active.panel
        activeNotchWindowNumber.send(panel.windowNumber)
        for record in panels {
            let isActive = record === active
            let root = NotchView(model:model, settings:model.settings,
                                 compactOnly:!isActive,
                                 geometryOverride:isActive ? nil : record.geometry,
                                 allowsDynamic:isActive,
                                 onActivate: isActive ? nil : { [weak self, weak record] in
                                     guard let self, let record else { return }
                                     self.activate(record)
                                 })
            (record.panel.contentView as? EdgeHostingView)?.rootView = root
        }
    }

    private func activate(_ record: ScreenPanel) {
        guard record !== active, !model.pointerInteractionActive else { return }
        cancelPendingHover()
        if let old = active {
            old.pointerInside = false
            old.pendingHover?.cancel(); old.pendingHover = nil
        }
        if model.expanded || model.presentation.phase != .collapsed {
            model.presenter.collapse()
        }
        model.presenter.cancelPeek()
        active = record
        model.notchGeometry = record.geometry
        panel = record.panel
        activeNotchWindowNumber.send(panel.windowNumber)
        renderPanels()
        updateVisibility()
        if record.pointerInside, model.settings.hoverEnabled, !model.expanded {
            scheduleHover(record)
        }
    }

    private func updateVisibility() {
        guard !panels.isEmpty else { return }
        let lockVisible = model.showsLockActivity
        // During the lock-collapse stage the ordinary surface remains visible
        // while it animates closed. Hiding here would make the notch disappear
        // and reappear, which is the observed "pull down then return" defect.
        let visible = !model.screenHidden && model.settings.showNotch
            && (!model.isSessionLocked || lockVisible || model.isLockTransitioning
                || model.isLockNeutralGeometry)
            && (!model.settings.hideWhenIdle || model.showsMusicActivity
                || model.expanded || model.connectionToast != nil || lockVisible
                || model.isLockTransitioning || model.isLockNeutralGeometry)
        for record in panels {
            record.panel.sharingType = model.settings.hideFromScreenCapture ? .none : .readOnly
            // The dedicated lock overlay owns the top surface while the real
            // session is locked. The ordinary desktop panel stays ordered out
            // until the overlay's neutral completion hands back.
            if model.lockOverlayReady && model.isSessionLocked {
                record.pendingHover?.cancel(); record.pendingHover = nil
                record.pointerInside = false
                record.panel.orderOut(nil)
                record.panel.ignoresMouseEvents = true
                continue
            }
            if visible {
                record.panel.ignoresMouseEvents = model.isSessionLocked || model.isLockPreviewActive
                record.panel.orderFrontRegardless()
                anchorPanelTop(record)
                if record === active { recordDiagnostic(record, reason: "visibility") }
            } else {
                record.pendingHover?.cancel(); record.pendingHover = nil
                record.pointerInside = false
                record.panel.orderOut(nil)
                record.panel.ignoresMouseEvents = true
            }
        }
        if !visible || model.isSessionLocked || model.isLockPreviewActive {
            model.presenter.pointerEntered(false)
        }
    }

    // MARK: - Pointer / hover

    private func containsMouse(_ record: ScreenPanel, point: NSPoint) -> Bool {
        guard record.panel.isVisible else { return false }
        let size: CGSize
        let contour: NotchContour
        let scale: CGSize
        if record === active {
            size = model.visibleSize
            contour = model.contour
            scale = model.hoverScale
        } else {
            size = PresentationMetrics.stationarySize(geometry:record.geometry,
                simulated:model.settings.forceSimulatedNotch, expanded:.none, hasOutput:false,
                notification:.none, liveActivity:model.showsMusicActivity ? .playing : .none,
                quickPeek:.none, tuning:.zero)
            contour = .stationary(geometry:record.geometry, simulated:model.settings.forceSimulatedNotch,
                expanded:false, expandedCorners:false, active:model.showsMusicActivity,
                visibleHeight:size.height)
            scale = CGSize(width:1,height:1)
        }
        return Self.containsMouse(point:point, panelFrame:record.panel.frame,
                                  size:size, contour:contour, scale:scale)
    }

    static func containsMouse(point: CGPoint, panelFrame: CGRect, size: CGSize,
                              contour: NotchContour, scale: CGSize) -> Bool {
        let local = NotchHoverMetrics.localPoint(
            centeredX:point.x-panelFrame.midX,
            topY:panelFrame.maxY-point.y-contour.topInset,
            size:size,scale:scale)
        return NotchShape(topRadius: contour.topRadius, bottomRadius: contour.bottomRadius, style: contour.style)
            .path(in: CGRect(origin: .zero, size: size)).contains(local)
    }

    static func containsMouse(localPoint: CGPoint, size: CGSize, contour: NotchContour) -> Bool {
        NotchShape(topRadius: contour.topRadius, bottomRadius: contour.bottomRadius, style: contour.style)
            .path(in: CGRect(origin: .zero, size: size)).contains(localPoint)
    }

    private func trackMouse() { trackMouse(at: NSEvent.mouseLocation) }

    private func trackMouse(at point: NSPoint) {
        guard !model.pointerInteractionActive else { return }
        if model.isSessionLocked || model.isLockPreviewActive {
            for record in panels {
                record.panel.ignoresMouseEvents = true
                record.pointerInside = false
                cancelPendingHover(record)
            }
            model.presenter.pointerEntered(false)
            return
        }
        for record in panels {
            let inside = containsMouse(record, point: point)
            record.panel.ignoresMouseEvents = !inside
            if inside {
                if record !== active { activate(record) }
                if !record.pointerInside {
                    record.pointerInside = true
                    if record === active { model.presenter.pointerEntered(true) }
                    scheduleHover(record)
                }
            } else if record.pointerInside {
                record.pointerInside = false
                cancelPendingHover(record)
                if record === active {
                    model.presenter.pointerEntered(false)
                    if model.expanded, model.settings.autoCollapse, !model.pinned {
                        model.presenter.collapse()
                        updateVisibility()
                    }
                }
            }
        }
    }

    private func scheduleHover(_ record: ScreenPanel) {
        cancelPendingHover(record)
        // Keep the generation counter and increment on every scheduled hover;
        // pending work is invalidated by cancelPendingHover above.
        record.hoverGeneration += 1
        let work = DispatchWorkItem { [weak self, weak record] in
            MainActor.assumeIsolated {
                guard let self, let record, record === self.active,
                      record.pointerInside, self.model.settings.hoverEnabled,
                      !self.model.expanded, !self.model.pointerInteractionActive,
                      !self.model.isSessionLocked, !self.model.isLockPreviewActive else { return }
                record.pendingHover = nil
                self.model.presenter.expand()
                self.updateVisibility()
            }
        }
        record.pendingHover = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, model.settings.hoverDelay), execute: work)
    }

    private func cancelPendingHover(_ record: ScreenPanel) {
        record.pendingHover?.cancel()
        record.pendingHover = nil
    }

    func cancelPendingHover() {
        panels.forEach { cancelPendingHover($0) }
    }

    /// Test/verification entry for the active interaction screen.
    func pointerChanged(_ inside: Bool) {
        guard let active, !model.isSessionLocked, !model.isLockPreviewActive else { return }
        if inside == active.pointerInside { return }
        active.pointerInside = inside
        if inside {
            model.presenter.pointerEntered(true)
            scheduleHover(active)
        } else {
            cancelPendingHover(active)
            model.presenter.pointerEntered(false)
            if model.expanded, model.settings.autoCollapse, !model.pinned {
                model.presenter.collapse()
                updateVisibility()
            }
        }
    }

    var verificationSecondaryPanels: [(view: NSView?, frame: NSRect, visible: Bool, identifier: String)] {
        panels.filter { $0 !== active }.map { ($0.panel.contentView, $0.panel.frame, $0.panel.isVisible, $0.id) }
    }

    var verificationPanelCount: Int { panels.count }
    var verificationActiveScreenID: String? { active?.id }
    var currentNotchDisplayFrame: CGRect? { active?.display.frame }
    var verificationScreenIDs: [String] { panels.map(\.id) }
    func verificationActivateScreen(_ id: String) {
        guard let record = panels.first(where: { $0.id == id }) else { return }
        activate(record)
    }
    func verificationSetPointer(screenID: String, inside: Bool) {
        guard let record = panels.first(where: { $0.id == screenID }) else { return }
        if inside, record !== active { activate(record) }
        record.pointerInside = inside
        if record === active {
            model.presenter.pointerEntered(inside)
            if inside { scheduleHover(record) } else {
                cancelPendingHover(record)
                if model.expanded, model.settings.autoCollapse, !model.pinned {
                    model.presenter.collapse()
                    updateVisibility()
                }
            }
        }
    }
    func verificationTrackChanged(identity: String?) { handleTrackChanged(identity) }
    func verificationTrackMouse(at point: CGPoint) { trackMouse(at: point) }
    func verificationPanelIsActive(_ id: String) -> Bool { active?.id == id }
    func verificationContains(screenID: String, point: CGPoint) -> Bool {
        guard let record = panels.first(where: { $0.id == screenID }) else { return false }
        return containsMouse(record, point: point)
    }

    func expand() {
        cancelPendingHover()
        model.presenter.expand()
        updateVisibility()
    }
    func collapse() {
        cancelPendingHover()
        model.presenter.collapse()
        updateVisibility()
    }

    // MARK: - Track-change target

    private func handleTrackChanged(_ identity: String?) {
        guard !panels.isEmpty else { return }
        if model.expanded || model.presentation.phase != .collapsed {
            model.presenter.trackChanged(identity: identity)
            return
        }
        let target = peekTarget()
        if target !== active { activate(target) }
        model.presenter.trackChanged(identity: identity)
    }

    private func peekTarget() -> ScreenPanel {
        if let active, model.pointerInteractionActive || active.pointerInside { return active }
        if let inside = panels.first(where: { $0.pointerInside }) { return inside }
        let point = NSEvent.mouseLocation
        if let display = displayProvider().first(where: { $0.frame.contains(point) }),
           let record = panels.first(where: { $0.display.id == display.id }) {
            return record
        }
        return active ?? panels[0]
    }

    isolated deinit {
        model.trackChangedHandler = nil
        for record in panels {
            record.pendingHover?.cancel()
            if let observer = record.moveObserver {
                NotificationCenter.default.removeObserver(observer)
                record.moveObserver = nil
            }
            record.panel.orderOut(nil)
            record.panel.contentView = nil
            record.panel.close()
        }
        if let applicationObserver { NSWorkspace.shared.notificationCenter.removeObserver(applicationObserver) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenStateMonitor?.stop()
    }
}
