import AppKit
import CoreGraphics
import Darwin
import ReferenceCore

/// Detects the three General hide conditions.
///
/// 1.7.9 evidence:
/// - GameManager fields: trackedGameBundleIdentifiers / trackedGamePathFragments;
///   the binary contains the four League/Riot bundle IDs.
/// - MissionControlManager.isMissionControlActive: in Mission Control the
///   com.apple.WindowManager process owns full-screen layer>=10 windows.
/// - ScreenManager.isFullscreen: a normal layer-0 window covering the selected
///   display (active fullscreen display detection, changelog 1.6.5).
///
/// The detectors are local reconstructions; they are not claimed to match every
/// private WindowServer branch of 1.7.9.
@MainActor
final class ScreenStateMonitor {
    private let screens: () -> [NSScreen]
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var suppressUntil = Date()
    private(set) var isFullscreen = false
    private(set) var isMissionControl = false
    private(set) var isGaming = false
    var onStateChange: (() -> Void)?

    private typealias CGSConnection = Int32
    private typealias MainFn = @convention(c) () -> CGSConnection
    private typealias CopyFn = @convention(c) (CGSConnection, Int32, CFArray) -> CFArray?
    private typealias TypeFn = @convention(c) (CGSConnection, UInt64) -> Int32
    private static let skyLight: (main: MainFn?, copy: CopyFn?, type: TypeFn?) = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY | RTLD_LOCAL) else {
            return (nil, nil, nil)
        }
        return (unsafeBitCast(dlsym(handle, "CGSMainConnectionID"), to: MainFn.self),
                unsafeBitCast(dlsym(handle, "CGSCopySpacesForWindows"), to: CopyFn.self),
                unsafeBitCast(dlsym(handle, "CGSSpaceGetType"), to: TypeFn.self))
    }()

    private static func spaceTypes(for windowID: Int) -> [Int32] {
        guard let main = skyLight.main, let copy = skyLight.copy, let type = skyLight.type else { return [] }
        let connection = main()
        let windows = [NSNumber(value: windowID)] as CFArray
        guard let spaces = copy(connection, 0x7, windows) as? [NSNumber] else { return [] }
        return spaces.map { type(connection, $0.uint64Value) }
    }

    init(screens: @escaping () -> [NSScreen]) {
        self.screens = screens
    }

    func start() {
        stop()
        for name in [NSWorkspace.didActivateApplicationNotification,
                     NSWorkspace.activeSpaceDidChangeNotification,
                     NSApplication.didChangeScreenParametersNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                // ScreenManager.hasRecentlySleptOrWoke: suppress false positives
                // while the desktop/space state settles after wake.
                self?.suppressUntil = Date().addingTimeInterval(2)
                self?.refresh()
            }
        })
        let timer = Timer(timeInterval: 0.75, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        refresh()
    }

    func stop() {
        timer?.invalidate(); timer = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
    }

    isolated deinit { stop() }

    func refresh() {
        guard Date() >= suppressUntil else { return }
        let windows = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]) ?? []
        let screenList = screens().isEmpty ? Array(NSScreen.screens.prefix(1)) : screens()
        let displayBounds = screenList.compactMap { screen -> CGRect? in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            return CGDisplayBounds(number.uint32Value)
        }
        let ourPID = Int(ProcessInfo.processInfo.processIdentifier)
        let dockPID = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first.map { Int($0.processIdentifier) }
        let windowManagerPID = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.WindowManager").first.map { Int($0.processIdentifier) }

        func bounds(_ window: [String: Any]) -> CGRect? {
            guard let dictionary = window[kCGWindowBounds as String] as? [String: Any] else { return nil }
            return CGRect(dictionaryRepresentation: dictionary as CFDictionary)
        }
        func coversDisplay(_ window: [String: Any], tolerance: CGFloat = 2) -> Bool {
            guard let rect = bounds(window) else { return false }
            return displayBounds.contains { display in
                abs(rect.width - display.width) <= tolerance && abs(rect.height - display.height) <= tolerance
            }
        }

        let fullscreen = windows.contains { window in
            guard (window[kCGWindowLayer as String] as? Int ?? 0) == 0,
                  let pid = window[kCGWindowOwnerPID as String] as? Int,
                  let number = window[kCGWindowNumber as String] as? Int,
                  let rect = bounds(window) else { return false }
            if pid == ourPID || pid == dockPID || pid == windowManagerPID { return false }
            let owner = window[kCGWindowOwnerName as String] as? String ?? ""
            if owner == "Window Server" || owner == "WindowManager" { return false }
            let intersects = displayBounds.contains { display in
                let intersection = rect.intersection(display)
                return !intersection.isNull && intersection.width >= display.width * 0.9 && intersection.height >= display.height * 0.8
            }
            guard intersects else { return false }
            let types = Self.spaceTypes(for: number)
            if types.contains(4) { return true }
            // Fallback if SkyLight changes: an exactly display-sized window.
            return types.isEmpty && displayBounds.contains { abs(rect.width - $0.width) <= 2 && abs(rect.height - $0.height) <= 2 }
        }
        let missionControl = windows.contains { window in
            guard let wm = windowManagerPID,
                  (window[kCGWindowOwnerPID as String] as? Int) == wm,
                  (window[kCGWindowLayer as String] as? Int ?? 0) >= 10 else { return false }
            return coversDisplay(window)
        }
        let gaming = gameApplication()

        if fullscreen != isFullscreen || missionControl != isMissionControl || gaming != isGaming {
            isFullscreen = fullscreen; isMissionControl = missionControl; isGaming = gaming
            onStateChange?()
        }
    }

    private func gameApplication() -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication else { return false }
        let bundle = app.bundleURL.flatMap { Bundle(url: $0) }
        let category = bundle?.infoDictionary?["LSApplicationCategoryType"] as? String
        return GameMatcher.matches(bundleIdentifier: app.bundleIdentifier,
                                   path: app.bundleURL?.path,
                                   category: category)
    }
}
