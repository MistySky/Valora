import AppKit
import SwiftUI
import Combine
import CoreImage
import NativeBridge
import ReferenceCore
import OSLog

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let runtimeDefaults: UserDefaults
    let runtimeSuiteName: String
    let startupMode: AppRuntimeDefaults.StartupMode
    let settings: RevivalSettings
    private var modelWasLoaded = false
    lazy var model: AppModel = {
        let model = AppModel(settings: settings)
        model.openMediaSourceAction = { bundleIdentifier in
            let logger = Logger(subsystem: "com.wangqing.valora", category: "MediaSourceActivation")
            guard let application = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
                .first(where: { !$0.isTerminated }), let url = application.bundleURL else { return }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            configuration.createsNewApplicationInstance = false
            logger.notice("Opening running media source: \(bundleIdentifier, privacy: .public)")
            NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
                if let error {
                    logger.error("Media source activation failed: \(error.localizedDescription, privacy: .public)")
                } else {
                    logger.notice("Media source open request completed")
                }
            }
        }
        modelWasLoaded = true
        return model
    }()
    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    private var bluetoothAuthorizationRequester: BluetoothAuthorizationRequester?
    private var menuBarModules: MenuBarModuleController?
    private var coordinator: WindowCoordinator!
    private var lockMusic: LockMusicCoordinator?
    private var lockCardPreview: LockCardPreviewController?
    private var settingsWindow: NSWindow?
    private let settingsNavigation = SettingsNavigation()
    lazy var settingsDraft = SettingsDraft(defaults: runtimeDefaults)
    private var subscriptions = Set<AnyCancellable>()
    private lazy var appPermissions = AppPermissions(
        bluetoothRequest: { [weak self] in self?.requestBluetoothAuthorization() },
        openBluetoothSettings: { AppPermissions.openBluetoothPrivacySettings() },
        loginRegister: { completion in
            do {
                try LoginItem.set(true)
                completion(AppPermissions.loginAccess(from: LoginItem.status))
            } catch {
                completion(.unknown)
            }
        },
        loginUnregister: { completion in
            do {
                try LoginItem.set(false)
                completion(AppPermissions.loginAccess(from: LoginItem.status))
            } catch {
                completion(.unknown)
            }
        },
        openLoginSettings: { AppPermissions.openLoginItemSettings() },
        openCalendarSettings: { AppPermissions.openCalendarPrivacySettings() })

    init(arguments: [String] = CommandLine.arguments) {
        let resolved = AppRuntimeDefaults.resolve(arguments: arguments)
        runtimeDefaults = resolved.defaults
        runtimeSuiteName = resolved.suiteName
        startupMode = AppRuntimeDefaults.startupMode(arguments: arguments)
        settings = RevivalSettings(defaults: resolved.defaults)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        settings.$hideFromScreenCapture.removeDuplicates().sink { [weak self] hidden in
            MainActor.assumeIsolated { self?.settingsWindow?.sharingType = hidden ? .none : .readOnly }
        }.store(in: &subscriptions)
        NSApp.setActivationPolicy(.accessory)
        model.showSettingsAction = { [weak self] in self?.showSettings() }
        model.quitAction = { [weak self] in self?.quit() }

        if startupMode == .verifyCalendarParity {
            guard let output = AppRuntimeDefaults.value(after: "--verify-calendar-parity",
                                                        arguments: CommandLine.arguments) else {
                fputs("--verify-calendar-parity requires an output directory\n", stderr)
                NSApp.terminate(nil); return
            }
            CalendarParityVerification.run(output: output)
            return
        }
        if startupMode == .previewMenuBarModules {
            // Isolated native preview of the two Calmon modules. No media,
            // Bluetooth, EventKit authorization or real calendar query.
            setupMenu()
            return
        }
        if startupMode == .auditMenuBarMemory {
            guard let output = AppRuntimeDefaults.value(after: "--audit-menubar-memory",
                                                        arguments: CommandLine.arguments) else {
                fputs("--audit-menubar-memory requires an output directory\n", stderr)
                NSApp.terminate(nil); return
            }
            MenuBarMemoryAudit.run(output: output)
            return
        }
        if startupMode == .auditCalendarFixedWindow {
            guard let output = AppRuntimeDefaults.value(after: "--audit-calendar-fixed-window",
                                                        arguments: CommandLine.arguments) else {
                fputs("--audit-calendar-fixed-window requires an output directory\n", stderr)
                NSApp.terminate(nil); return
            }
            CalendarFixedWindowAudit.run(output: output)
            return
        }
        if startupMode == .auditCalendarPopover || startupMode == .auditCalendarPopoverFixed {
            let fixed = startupMode == .auditCalendarPopoverFixed
            let flag = fixed ? "--audit-calendar-popover-fixed" : "--audit-calendar-popover"
            guard let output = AppRuntimeDefaults.value(after: flag,
                                                        arguments: CommandLine.arguments) else {
                fputs("\(flag) requires an output directory\n", stderr)
                NSApp.terminate(nil); return
            }
            CalendarPopoverAudit.run(output: output, fixedDisplay: fixed)
            return
        }

        // Construct the controllers for every mode; only production starts them.
        model.media = MediaController(model)
        model.audio = AudioOutputController(model)
        model.bluetooth = ConnectivityController(model, authorizationGate: {
            AppPermissions.currentBluetooth == .authorized
        })

        if startupMode == .verifyMenuBar {
            guard let output = AppRuntimeDefaults.value(after: "--verify-menubar", arguments: CommandLine.arguments) else {
                fputs("--verify-menubar requires an output directory\n", stderr); NSApp.terminate(nil); return
            }
            setupMenu()
            guard let statusItem else {
                fputs("--verify-menubar requires the application status item\n", stderr)
                NSApp.terminate(nil); return
            }
            MenuBarIconVerification.run(statusItem: statusItem, output: output)
            return
        }

        if startupMode == .verifySettings {
            guard let output = AppRuntimeDefaults.value(after: "--verify-settings", arguments: CommandLine.arguments) else {
                fputs("--verify-settings requires an output directory\n", stderr); NSApp.terminate(nil); return
            }
            SettingsVerification.run(model: model, output: output)
            return
        }
        if startupMode == .previewSettings {
            showSettings(); return
        }

        if startupMode == .verifySystemMedia {
            guard let output = AppRuntimeDefaults.value(after: "--verify-system-media", arguments: CommandLine.arguments) else {
                fputs("--verify-system-media requires an output directory\n", stderr); NSApp.terminate(nil); return
            }
            SystemMediaVerification.run(output: output)
            return
        }

        if startupMode == .verifyMultiDisplay {
            guard let output = AppRuntimeDefaults.value(after: "--verify-multidisplay", arguments: CommandLine.arguments) else {
                fputs("--verify-multidisplay requires an output directory\n", stderr); NSApp.terminate(nil); return
            }
            settingsDraft.binding("showOnDisplay", "Main display").wrappedValue = "All displays"
            settings.reloadPreferences()
            settings.showNotch = true
            settings.forceSimulatedNotch = false
            settings.hoverEnabled = false
            settings.autoCollapse = false
            model.title = "多屏音乐面板预览"
            model.artist = "活动屏与被动屏独立呈现"
            model.source = "系统"
            model.playing = true
            model.duration = 236
            model.elapsed = 74
            let builtIn = DisplayDescriptor(id: "builtin", name: "Built-in display",
                frame: CGRect(x: 0, y: 0, width: 1728, height: 1117), safeAreaTop: 32,
                auxiliaryLeftWidth: 771.5, auxiliaryRightWidth: 771.5, menuBarHeight: 32, isBuiltIn: true)
            let external = DisplayDescriptor(id: "external", name: "External display",
                frame: CGRect(x: -1920, y: -200, width: 1920, height: 1080), safeAreaTop: 0,
                auxiliaryLeftWidth: nil, auxiliaryRightWidth: nil, menuBarHeight: 24)
            coordinator = WindowCoordinator(model, displayProvider: { [builtIn, external] })
            coordinator.start(trackPointer: false)
            MultiDisplayVerification.run(model: model, coordinator: coordinator, output: output)
            return
        }

        if startupMode == .verifyLyrics {
            guard let output = AppRuntimeDefaults.value(after: "--verify-lyrics", arguments: CommandLine.arguments) else {
                fputs("--verify-lyrics requires an output directory\n", stderr); NSApp.terminate(nil); return
            }
            settingsDraft.binding("showOnDisplay", "Main display").wrappedValue = "All displays"
            settingsDraft.binding("showLyrics", false).wrappedValue = true
            settings.reloadPreferences()
            settings.showNotch = true
            settings.forceSimulatedNotch = true
            settings.hoverEnabled = false
            settings.autoCollapse = false
            settings.nowPlayingEnabled = true
            settings.hideWhenIdle = false
            model.playing = true
            model.elapsed = 1
            model.title = "晴天"
            model.artist = "周杰伦"
            model.album = "叶惠美"
            model.duration = 269
            model.source = "预览"
            let art = NSImage(size: NSSize(width: 64, height: 64))
            art.lockFocus()
            NSColor(calibratedRed: 0.16, green: 0.62, blue: 0.55, alpha: 1).setFill()
            NSBezierPath(rect: NSRect(x: 0, y: 0, width: 64, height: 64)).fill()
            NSColor(calibratedRed: 0.86, green: 0.48, blue: 0.22, alpha: 1).setFill()
            NSBezierPath(rect: NSRect(x: 0, y: 0, width: 32, height: 64)).fill()
            art.unlockFocus()
            model.artwork = art
            let lines = [
                LyricLine(start: 1, text: "短句歌词", words: [
                    LyricWord(text: "短句", start: 1, duration: 0.5),
                    LyricWord(text: "歌词", start: 1.5, duration: 0.5)
                ]),
                LyricLine(start: 5, text: "这是一句很长的歌词，需要在紧凑区域中慢速从左向右跟随当前字，同时保持当前唱到的部分可见", words: [
                    LyricWord(text: "这是一句很长的歌词，", start: 5, duration: 0.5),
                    LyricWord(text: "需要在紧凑区域中", start: 5.5, duration: 0.5),
                    LyricWord(text: "慢速从左向右跟随当前字，", start: 6.0, duration: 0.5),
                    LyricWord(text: "同时保持当前唱到的部分可见", start: 6.5, duration: 0.4)
                ]),
                LyricLine(start: 7, text: ""),
                LyricLine(start: 9, text: "第二句", words: [
                    LyricWord(text: "第二句", start: 9, duration: 1)
                ]),
                LyricLine(start: 12, text: "这是一句没有逐字时间的长歌词，只有LRC整行时间，需要按行时间平滑滚动显示后半句，不能平均分字伪造成逐字同步"),
                LyricLine(start: 20, text: "第三句")
            ]
            model.lyricsController = LyricsController(model: model,
                provider: StaticLyricsProvider(result: .timed(LyricTimeline(lines: lines))))
            let builtIn = DisplayDescriptor(id: "builtin", name: "Built-in display",
                frame: CGRect(x: 0, y: 0, width: 1728, height: 1117), safeAreaTop: 32,
                auxiliaryLeftWidth: 771.5, auxiliaryRightWidth: 771.5, menuBarHeight: 32, isBuiltIn: true)
            let external = DisplayDescriptor(id: "external", name: "External display",
                frame: CGRect(x: -1920, y: -200, width: 1920, height: 1080), safeAreaTop: 0,
                auxiliaryLeftWidth: nil, auxiliaryRightWidth: nil, menuBarHeight: 24)
            coordinator = WindowCoordinator(model, displayProvider: { [builtIn, external] })
            coordinator.start(trackPointer: false)
            model.lyricsController?.start()
            LyricsVerification.run(model: model, coordinator: coordinator, output: output)
            return
        }

        if startupMode == .auditFluidity {
            guard let output = AppRuntimeDefaults.value(after: "--audit-fluidity", arguments: CommandLine.arguments) else {
                fputs("--audit-fluidity requires an output directory\n", stderr); NSApp.terminate(nil); return
            }
            settingsDraft.binding("showOnDisplay", "Main display").wrappedValue = "All displays"
            settingsDraft.binding("showLyrics", false).wrappedValue = true
            settings.reloadPreferences()
            settings.showNotch = true
            settings.forceSimulatedNotch = true
            settings.hoverEnabled = false
            settings.autoCollapse = false
            settings.nowPlayingEnabled = true
            settings.hideWhenIdle = false
            model.playing = true
            model.elapsed = 0.5
            model.title = "audit-track"
            model.artist = "audit-artist"
            model.album = "audit-album"
            model.duration = 120
            model.source = "预览"
            let provider = AuditLyricsProvider(result: .wordTimed(FluidityFixtures.timeline()))
            model.lyricsController = LyricsController(model: model, provider: provider)
            let builtIn = DisplayDescriptor(id: "builtin", name: "Built-in display",
                frame: CGRect(x: 0, y: 0, width: 1728, height: 1117), safeAreaTop: 32,
                auxiliaryLeftWidth: 771.5, auxiliaryRightWidth: 771.5, menuBarHeight: 32, isBuiltIn: true)
            let external = DisplayDescriptor(id: "external", name: "External display",
                frame: CGRect(x: -1920, y: -200, width: 1920, height: 1080), safeAreaTop: 0,
                auxiliaryLeftWidth: nil, auxiliaryRightWidth: nil, menuBarHeight: 24)
            coordinator = WindowCoordinator(model, displayProvider: { [builtIn, external] })
            coordinator.start(trackPointer: false)
            model.lyricsController?.start()
            FluidityAudit.run(model: model, coordinator: coordinator, provider: provider,
                              settings: settings, defaults: runtimeDefaults, output: output)
            return
        }

        if startupMode == .verifyConnectivity {
            guard let output = AppRuntimeDefaults.value(after: "--verify-connectivity", arguments: CommandLine.arguments) else {
                fputs("--verify-connectivity requires an output directory\n", stderr); NSApp.terminate(nil); return
            }
            settingsDraft.binding("showOnDisplay", "Main display").wrappedValue = "All displays"
            settingsDraft.binding("showLyrics", false).wrappedValue = true
            settings.reloadPreferences()
            settings.showNotch = true
            settings.forceSimulatedNotch = true
            settings.hoverEnabled = false
            settings.autoCollapse = false
            settings.nowPlayingEnabled = true
            settings.hideWhenIdle = false
            settings.bluetoothEnabled = true
            model.playing = true
            model.elapsed = 0.5
            model.title = "晴天"
            model.artist = "周杰伦"
            model.album = "叶惠美"
            model.duration = 269
            model.source = "预览"
            let art = NSImage(size: NSSize(width: 64, height: 64))
            art.lockFocus()
            NSColor(calibratedRed: 0.16, green: 0.62, blue: 0.55, alpha: 1).setFill()
            NSBezierPath(rect: NSRect(x: 0, y: 0, width: 64, height: 64)).fill()
            NSColor(calibratedRed: 0.86, green: 0.48, blue: 0.22, alpha: 1).setFill()
            NSBezierPath(rect: NSRect(x: 0, y: 0, width: 32, height: 64)).fill()
            art.unlockFocus()
            model.artwork = art
            model.lyrics = LyricsDisplayState(status: .ready,
                timeline: LyricTimeline(lines: [
                    LyricLine(start: 0, text: "连接提示结束后的歌词", words: [
                        LyricWord(text: "连接提示", start: 0, duration: 1),
                        LyricWord(text: "结束后的歌词", start: 1, duration: 1)
                    ])
                ]), identity: LyricsTrackIdentity(title: model.title, artist: model.artist,
                                                  album: model.album, duration: model.duration))
            let sound = ConnectivitySoundSpy()
            let controller = ConnectivityController(model, source: EmptyConnectivitySource(),
                                                    sound: sound)
            model.bluetooth = controller
            let builtIn = DisplayDescriptor(id: "builtin", name: "Built-in display",
                frame: CGRect(x: 0, y: 0, width: 1728, height: 1117), safeAreaTop: 32,
                auxiliaryLeftWidth: 771.5, auxiliaryRightWidth: 771.5, menuBarHeight: 32, isBuiltIn: true)
            let external = DisplayDescriptor(id: "external", name: "External display",
                frame: CGRect(x: -1920, y: -200, width: 1920, height: 1080), safeAreaTop: 0,
                auxiliaryLeftWidth: nil, auxiliaryRightWidth: nil, menuBarHeight: 24)
            coordinator = WindowCoordinator(model, displayProvider: { [builtIn, external] })
            coordinator.start(trackPointer: false)
            ConnectivityVerification.run(model: model, coordinator: coordinator,
                                          controller: controller, sound: sound, output: output)
            return
        }

        let lyricsProvider: any LyricsProviding = startupMode == .production
            ? QQMusicLyricsService() : NoLyricsProvider()
        model.lyricsController = LyricsController(model: model, provider: lyricsProvider)
        model.lyricsController?.start()

        coordinator = WindowCoordinator(model)
        coordinator.start(trackPointer: startupMode == .production)

        if startupMode == .verifyMusic {
            guard let output = AppRuntimeDefaults.value(after: "--verify-music", arguments: CommandLine.arguments) else {
                fputs("--verify-music requires an output directory\n", stderr); NSApp.terminate(nil); return
            }
            // Existing fake-media/coordinator verification exercises the
            // independent Calmon status items alongside the notch coordinator.
            // Calendar data is injected; no production media, Bluetooth,
            // permission request or EventKit query is started by this QA mode.
            setupMenu()
            MusicPresentationVerification.run(model: model, coordinator: coordinator, output: output)
            return
        }
        if startupMode == .previewMusic {
            // Synthetic preview never starts production media or audio polling.
            settings.autoCollapse = false
            settings.hoverEnabled = false
            setupMenu()
            previewMusic()
            if CommandLine.arguments.contains("--preview-long-title") {
                model.title = "长标题滚动检查 · 原生文字图层与两端渐隐效果"
                model.artist = "歌手名称滚动检查 · 与标题共享循环周期"
            }
            return
        }

        let actualLogin = LoginItem.isEnabled
        settingsDraft.binding("launchAtLogin", actualLogin).wrappedValue = actualLogin
        setupMenu()
        lockMusic = LockMusicCoordinator(
            model,
            notchWindowProvider: { [weak coordinator] in coordinator?.panel },
            notchWindowUpdates: coordinator.activeNotchWindowNumber.eraseToAnyPublisher(),
            overlayFrameProvider: { [weak coordinator] in coordinator?.currentNotchDisplayFrame })
        lockMusic?.setEnabled(settings.lockPreferences.enabled)
        model.settings.$lockPreferences.map(\.enabled).removeDuplicates().dropFirst().sink { [weak self] enabled in
            DispatchQueue.main.async { self?.lockMusic?.setEnabled(enabled) }
        }.store(in: &subscriptions)
        model.media.start()
        model.audio.start()
        model.bluetooth.start()
        if CommandLine.arguments.contains("--lock-card-preview") {
            lockCardPreview = LockCardPreviewController(model)
            lockCardPreview?.start()
        }
        if CommandLine.arguments.contains("--expand-media") {
            // QA-only: wait for the first system media snapshot, then expand.
            model.pinned = true
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 900_000_000)
                self?.coordinator.expand()
            }
        }
        if !CommandLine.arguments.contains("--no-settings"),
           runtimeDefaults.object(forKey: "didLaunchValora") == nil || CommandLine.arguments.contains("--settings") {
            runtimeDefaults.set(true, forKey: "didLaunchValora")
            showSettings()
        }
        if let output = AppRuntimeDefaults.value(after: "--diagnostic", arguments: CommandLine.arguments) {
            writeLiveDiagnostic(to: output)
        }
    }

    /// Read-only production diagnostic. Records flags only; never song text,
    /// artist, album, artwork bytes, player bundle IDs or output device names.
    private func writeLiveDiagnostic(to path: String) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard let self else { return }
            let model = self.model
            let info: [String: Any] = [
                "trackPresent": model.hasTrack,
                "playing": model.playing,
                "canSeek": model.mediaCanSeek,
                "canSkip": model.mediaCanSkip,
                "canControl": model.mediaCanControl,
                "durationValid": MediaProgressState.validDuration(model.duration),
                "elapsedWithinDuration": model.elapsed <= model.duration + 0.001,
                "artworkPresent": model.artwork != nil,
                "musicActivityVisible": model.showsMusicActivity,
                "expanded": model.expanded,
                "presentationPhase": model.presentation.phase.rawValue,
                "hasPhysicalNotch": model.notchGeometry.hasPhysicalNotch,
                "visibleSize": NSStringFromSize(model.visibleSize),
                "nativeNotchSize": NSStringFromSize(model.nativeNotchSize),
                "panelVisible": self.coordinator.panel.isVisible,
                "panelSharingType": self.coordinator.panel.sharingType.rawValue,
                "outputKind": model.output.kind,
                "outputNamePresent": !model.output.name.isEmpty,
                "canSetVolume": model.output.canSetVolume,
                "canMute": model.output.canMute,
                "sourceIsSystem": model.source == "系统",
                "mediaErrorPresent": model.mediaError != nil,
                "playerCommandSent": false,
                "privateMetadataRecorded": false
            ]
            let directory = URL(fileURLWithPath: path, isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if let data = try? JSONSerialization.data(withJSONObject: info, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: directory.appendingPathComponent("live-diagnostic.json"))
            }
            NSApp.terminate(nil)
        }
    }

    private func installApplicationStatusItemIfNeeded() {
        if let statusItem {
            statusItem.isVisible = true
            return
        }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = statusBarImage()
        item.button?.imageScaling = .scaleProportionallyDown
        item.button?.imagePosition = .imageOnly
        item.button?.setAccessibilityLabel("Valora")
        let menu = NSMenu()
        menu.delegate = self
        statusMenu = menu
        rebuildStatusMenu(menu)
        item.menu = menu
        statusItem = item
    }

    /// The explicit General "show menu bar icon" switch controls only the
    /// Outline-v7 application entry. Hiding it leaves the notch, music and
    /// every module intact; showing it reuses the same item/menu route.
    private func setApplicationStatusItemVisible(_ visible: Bool) {
        if visible { installApplicationStatusItemIfNeeded() }
        else { statusItem?.isVisible = false }
    }

    private func applyFeatureSettings() {
        guard menuBarModules != nil else { return }
        menuBarModules?.setSystemMonitorVisible(settingsDraft.value("enableSystemMonitor", true))
        menuBarModules?.setCalendarVisible(true)
        setApplicationStatusItemVisible(settingsDraft.value("showApplicationMenuBarIcon", true))
    }

    private func refreshCalendarEventsAfterSettings() {
        menuBarModules?.refreshCalendarEvents()
    }

    /// Borderless ribbon V alpha mask; macOS supplies the menu-bar tint.
    private func statusBarImage() -> NSImage {
        let size = NSSize(width: 20, height: 20)
        let image = NSImage(size: size)
        guard let resources = Bundle.main.resourceURL else { return image }
        for name in ["MenuBarIcon.png", "MenuBarIcon@2x.png", "MenuBarIcon@3x.png"] {
            guard let data = try? Data(contentsOf: resources.appendingPathComponent(name)),
                  let rep = NSBitmapImageRep(data: data) else {
                fputs("Valora: missing menu-bar image representation\n", stderr)
                continue
            }
            rep.size = size
            image.addRepresentation(rep)
        }
        image.isTemplate = true
        return image
    }

    private func setupMenu() {
        guard menuBarModules == nil else { return }
        if settingsDraft.value("showApplicationMenuBarIcon", true) {
            installApplicationStatusItemIfNeeded()
        }

        let previewData = startupMode == .previewMenuBarModules
            || startupMode == .previewMusic
            || startupMode == .verifyMusic
        let calendar: CalmonCalendarModel
        if previewData || startupMode != .production {
            calendar = CalmonCalendarModel(
                provider: HolidayProvider(authorizationCheck: { false }),
                eventProvider: PreviewCalendarEvents(),
                readGate: { true }, preview: true)
        } else {
            let holidayProvider = HolidayProvider(
                authorizationCheck: { [weak self] in
                    guard let self else { return false }
                    return self.settingsDraft.value("enableCalendar", false)
                        && self.appPermissions.calendar == .fullAccess
                },
                transportFactory: { EventKitHolidayTransport() })
            calendar = CalmonCalendarModel(
                provider: holidayProvider,
                eventProvider: EventKitCalendarEventProvider(),
                readGate: { [weak self] in
                    guard let self else { return false }
                    return self.settingsDraft.value("enableCalendar", false)
                        && self.appPermissions.calendar == .fullAccess
                })
        }
        let monitor = SystemMonitor()
        menuBarModules = MenuBarModuleController(
            monitor: monitor, calendar: calendar,
            onSettings: { [weak self] in self?.showSettings() },
            onQuit: { [weak self] in self?.quit() })
        menuBarModules?.setSystemMonitorVisible(settingsDraft.value("enableSystemMonitor", true))
        menuBarModules?.setCalendarVisible(true)
        menuBarModules?.start()
        setApplicationStatusItemVisible(settingsDraft.value("showApplicationMenuBarIcon", true))
        if startupMode == .production {
            CalendarAuthorizationRefresh.subscribe(appPermissions) { [weak self] in
                self?.refreshCalendarEventsAfterSettings()
            }.store(in: &subscriptions)
            NotificationCenter.default.publisher(for: Notification.Name("ValoraSettingsDraftChanged"))
                .sink { [weak self] _ in
                    MainActor.assumeIsolated { self?.refreshCalendarEventsAfterSettings() }
                }
                .store(in: &subscriptions)
            NotificationCenter.default.publisher(for: Notification.Name("ValoraSettingsDraftChanged"))
                .sink { [weak self] _ in
                    Task { @MainActor in self?.applyFeatureSettings() }
                }
                .store(in: &subscriptions)
        }

        let main = NSMenu()
        let applicationItem = NSMenuItem(title: "Valora", action: nil, keyEquivalent: "")
        let applicationMenu = NSMenu()
        applicationMenu.addItem(NSMenuItem(title: "关于 Valora", action: #selector(showAbout), keyEquivalent: ""))
        applicationMenu.addItem(NSMenuItem(title: AppMenuCommands.settingsTitle, action: #selector(showSettings), keyEquivalent: AppMenuCommands.settingsKey))
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(NSMenuItem(title: "隐藏 Valora", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(NSMenuItem(title: AppMenuCommands.quitTitle, action: #selector(quit), keyEquivalent: AppMenuCommands.quitKey))
        for item in applicationMenu.items where item.action != #selector(NSApplication.hide(_:)) { item.target = self }
        applicationItem.submenu = applicationMenu
        main.addItem(applicationItem)
        NSApp.mainMenu = main
    }

    /// Native feature-switch QA entry. It reuses the real status-item/menu
    /// construction but never starts production media services.
    func setupMenuForVerification() { setupMenu() }
    func applyFeatureSettingsForVerification() { applyFeatureSettings() }
    var applicationStatusItemForVerification: NSStatusItem? { statusItem }
    var menuBarModulesForVerification: MenuBarModuleController? { menuBarModules }

    func removeApplicationStatusItemForVerification() {
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        statusItem = nil
        statusMenu = nil
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === statusMenu { rebuildStatusMenu(menu) }
    }

    /// QA entry that reuses the exact production application-menu builder.
    /// It does not start media, configure a status item, or dispatch any menu
    /// action; the caller must supply the model fixture.
    @MainActor
    func applicationStatusMenuForVerification() -> NSMenu {
        let menu = NSMenu()
        rebuildStatusMenu(menu)
        return menu
    }

    private func rebuildStatusMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        if model.hasTrack, settings.nowPlayingEnabled {
            let controls: [(String, String, Selector, Bool)] = [
                (model.playing ? "暂停" : "播放", model.playing ? "pause.fill" : "play.fill", #selector(playPause), model.mediaCanControl),
                ("上一首", "backward.end.fill", #selector(previous), model.mediaCanSkip),
                ("下一首", "forward.end.fill", #selector(next), model.mediaCanSkip)
            ]
            for (title, symbol, action, enabled) in controls {
                let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
                item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
                item.isEnabled = enabled
                menu.addItem(item)
            }
            menu.addItem(.separator())
        }
        menu.autoenablesItems = false
        let displayItem = NSMenuItem(title: "显示器", action: nil, keyEquivalent: "")
        let displayMenu = NSMenu()
        let selected = settingsDraft.value("showOnDisplay", "Main display")
        for option in SettingsDisplayCatalog.options {
            if option == NSScreen.screens.first?.localizedName { displayMenu.addItem(.separator()) }
            let item = NSMenuItem(title: SettingsText.localized(option), action: #selector(selectDisplay(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = option; item.state = option == selected ? .on : .off
            item.image = NSImage(systemSymbolName: SettingsDisplayCatalog.symbol(for: option), accessibilityDescription: nil)
            displayMenu.addItem(item)
        }
        displayItem.submenu = displayMenu
        menu.addItem(displayItem)
        menu.addItem(.separator())
        let versionItem = NSMenuItem(title: AppMenuCommands.versionText, action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)
        menu.addItem(NSMenuItem(title: AppMenuCommands.settingsTitle, action: #selector(showSettings), keyEquivalent: AppMenuCommands.settingsKey))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: AppMenuCommands.quitTitle, action: #selector(quit), keyEquivalent: AppMenuCommands.quitKey))
        for item in menu.items { item.target = self }
    }

    @objc private func selectDisplay(_ sender: NSMenuItem) {
        guard let selection = sender.representedObject as? String else { return }
        settingsDraft.binding("showOnDisplay", "Main display").wrappedValue = selection
    }
    @objc private func showAbout() {
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Valora",
            .applicationVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.2.0",
            .version: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        ])
    }
    @objc private func playPause() { model.media.command(2) }
    @objc private func next() { model.media.command(4) }
    @objc private func previous() { model.media.command(5) }
    @objc private func quit() { NSApp.terminate(nil) }


    /// Explicit user gesture from the Connectivity switch. This is the only
    /// path that asks CoreBluetooth for Bluetooth authorization. It never
    /// scans or reads a device; AppPermissions refreshes on completion.
    private func requestBluetoothAuthorization() {
        guard bluetoothAuthorizationRequester == nil else { return }
        let requester = BluetoothAuthorizationRequester()
        bluetoothAuthorizationRequester = requester
        requester.request { [weak self] in
            guard let self else { return }
            self.bluetoothAuthorizationRequester = nil
            self.appPermissions.refresh()
        }
    }

    @objc func showSettings() {
        if settingsWindow == nil {
            let view = SettingsView(model:model,settings:settings,navigation:settingsNavigation,
                                    draft:settingsDraft,permissions:appPermissions)
            let (window, _) = SettingsWindowFactory.make(rootView: view)
            window.center()
            settingsWindow = window
            window.sharingType = settings.hideFromScreenCapture ? .none : .readOnly
            settingsNavigation.$page.sink { [weak window] page in
                MainActor.assumeIsolated { window?.title = page.displayTitle }
            }.store(in: &subscriptions)
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func previewMusic() {
        model.media?.invalidate()
        model.previewMode = true
        model.title = "音乐面板预览"
        model.artist = "界面与动画检查 · 非真实播放"
        model.source = "预览"
        model.playing = true
        model.duration = 236
        model.elapsed = 74
        model.artwork = nil
        model.pinned = true
        settings.showNotch = true
        coordinator.expand()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Do not touch the lazy model here when no controller was constructed;
        // termination must not create an AppModel/ConnectivityController and
        // accidentally start its lifecycle.
        if modelWasLoaded {
            lockMusic?.stop()
            lockMusic = nil
            lockCardPreview?.stop()
            lockCardPreview = nil
            model.lyricsController?.cancel()
            model.media?.stop()
            model.audio?.stop()
            model.bluetooth?.stop()
        }
        menuBarModules?.stop()
        menuBarModules = nil
        coordinator?.cancelPendingHover()
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
