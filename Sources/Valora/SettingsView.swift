import SwiftUI
import AppKit
import ReferenceCore

/// Layout baseline: reference-ui/*.png at 2×; control order from settings-ax.json.
/// This candidate keeps exactly the General and Now Playing pages. The visible
/// controls are the user-confirmed subset; fixed policies live in
/// RevivalSettings and have no gray placeholder rows.
struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: RevivalSettings
    @ObservedObject var navigation: SettingsNavigation
    @ObservedObject var draft: SettingsDraft
    @ObservedObject var permissions: AppPermissions
    @Environment(\.controlActiveState) private var active
    @Environment(\.colorScheme) private var colorScheme
    @State private var notice: String? = nil
    private var page: SettingsPage { navigation.page }

    init(model: AppModel, settings: RevivalSettings, navigation: SettingsNavigation,
         draft: SettingsDraft, permissions: AppPermissions = AppPermissions()) {
        self.model = model
        self.settings = settings
        self.navigation = navigation
        self.draft = draft
        self.permissions = permissions
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 224.5)
                .background(SettingsPalette.windowBackground(colorScheme))
            Rectangle().fill(Color.primary.opacity(0.09)).frame(width: 0.5)
            ZStack(alignment: .top) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            pageContent
                            Color.clear.frame(height: 0).id("settings-bottom")
                        }
                        .padding(.leading, 16).padding(.trailing, page.scrolls ? 18 : 16)
                        // The 1.7.9 scroll view runs under the title area and fades
                        // the last ~22 pt into the window background (S013).
                        .padding(.top, 53).padding(.bottom, 16)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }.background(SettingsScrollBackground())
                        .background(SettingsPalette.contentBackground(colorScheme))
                        .id(page).scrollIndicators(page.scrolls ? .visible : .hidden)
                        .mask(alignment: .top) {
                            VStack(spacing: 0) {
                                LinearGradient(stops: [
                                    .init(color: .clear, location: 0),
                                    .init(color: .clear, location: 0.53),
                                    .init(color: .black, location: 0.94),
                                    .init(color: .black, location: 1)
                                ], startPoint: .top, endPoint: .bottom).frame(height: 53)
                                Color.black
                            }
                        }
                        .onChange(of: navigation.revealBottom) { _, bottom in
                            if bottom { proxy.scrollTo("settings-bottom", anchor: .bottom) }
                        }
                }
                Color(SettingsPalette.windowBackground(colorScheme))
                    .frame(height: 53).frame(maxWidth: .infinity, alignment: .top).allowsHitTesting(false)
                HStack(spacing: 8) {
                    SettingsIcon(page: page).opacity(active == .inactive ? 0.5 : 1)
                    Text(page.displayTitle).font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.primary.opacity(active == .inactive ? 0.47 : 1))
                    Spacer()
                }.offset(y: -1.5).padding(.horizontal, 16).frame(height: 53).frame(maxWidth: .infinity, alignment: .leading)
                    .allowsHitTesting(false)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(SettingsPalette.contentBackground(colorScheme))
        }.frame(width: 620, height: 687).background(SettingsPalette.windowBackground(colorScheme))
            .tint(SettingsPalette.accent).accentColor(SettingsPalette.accent)
            .onChange(of: draft.value("enableNowPlaying", true)) { _, enabled in settings.nowPlayingEnabled = enabled }
            .onChange(of: settings.musicPreferences.useLiveWaveform) { _, enabled in
                if enabled {
                    LiveAudioTap.shared.startAsync { status in
                        if status != noErr { draft.binding("useLiveWaveform", false).wrappedValue = false }
                    }
                } else {
                    LiveAudioTap.shared.stopAsync()
                }
            }
            .onChange(of: draft.value("launchAtLogin", false)) { _, enabled in
                guard enabled != LoginItem.isEnabled else { return }
                do {
                    try LoginItem.set(enabled)
                    let status = LoginItem.status
                    permissions.refresh()
                    FileHandle.standardError.write(Data("login-item set \(enabled) status=\(status.rawValue)\n".utf8))
                    if status != .enabled {
                        draft.binding("launchAtLogin", false).wrappedValue = false
                        notice = "请在系统设置 → 通用 → 登录项中允许 Valora。"
                    }
                } catch {
                    permissions.refresh()
                    FileHandle.standardError.write(Data("login-item error \(error)\n".utf8))
                    draft.binding("launchAtLogin", false).wrappedValue = false
                    notice = "无法设置登录项：\(error.localizedDescription)"
                }
            }
            .alert("Valora", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
                Button("好", role: .cancel) { notice = nil }
            } message: { Text(notice ?? "") }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                permissions.refresh()
            }
            .onChange(of: permissions.bluetooth) { _, state in
                if state != .authorized, settings.bluetoothEnabled { settings.bluetoothEnabled = false }
            }
            .onChange(of: permissions.audioCapture) { _, state in
                if state == .denied || state == .restricted {
                    if draft.value("useLiveWaveform", false) { draft.binding("useLiveWaveform", false).wrappedValue = false }
                    LiveAudioTap.shared.stopAsync()
                }
            }
            .onChange(of: permissions.loginItem) { _, state in
                if state == .requiresApproval, draft.value("launchAtLogin", false) {
                    draft.binding("launchAtLogin", false).wrappedValue = false
                }
            }
            .onChange(of: permissions.message) { _, message in
                if let message { notice = message }
            }
    }

    private var bluetoothBinding: Binding<Bool> {
        PermissionToggleRouting.make(
            value: $settings.bluetoothEnabled,
            authorized: permissions.bluetooth == .authorized,
            pending: permissions.bluetoothEnablePending,
            begin: { permissions.beginBluetoothEnable { settings.bluetoothEnabled = true } },
            cancel: { permissions.cancelBluetoothEnable() })
    }

    private var audioBinding: Binding<Bool> {
        let value = draft.binding("useLiveWaveform", false)
        return PermissionToggleRouting.make(
            value: value,
            authorized: permissions.audioCapture == .authorized,
            pending: permissions.audioEnablePending,
            begin: { permissions.beginAudioEnable { value.wrappedValue = true } },
            cancel: { permissions.cancelAudioEnable() })
    }

    private var loginBinding: Binding<Bool> {
        let value = draft.binding("launchAtLogin", false)
        return PermissionToggleRouting.make(
            value: value,
            authorized: permissions.loginItem == .enabled,
            pending: permissions.loginEnablePending,
            begin: { permissions.beginLoginEnable { value.wrappedValue = true } },
            cancel: { permissions.cancelLoginEnable() })
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            navigationRow(.general)
            sectionTitle("Notifications")
            navigationRow(.connectivity)
            sectionTitle("Live Activities")
            navigationRow(.nowPlaying)
            Spacer(minLength: 0)
        }.padding(.horizontal, 12).padding(.top, 53)
            .foregroundStyle(Color.primary.opacity(active == .inactive ? 0.49 : 1))
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(SettingsText.localized(text)).font(.system(size: 13, weight: .medium)).foregroundStyle(Color.primary.opacity(active == .inactive ? 0.28 : 0.45))
            .padding(.horizontal, 8).padding(.top, 16).frame(height: 42, alignment: .center)
    }

    private func navigationRow(_ item: SettingsPage) -> some View {
        Button { navigation.page = item } label: {
            HStack(spacing: 7) {
                SettingsIcon(page: item).opacity(active == .inactive ? 0.8 : 1)
                Text(item.displayTitle).font(.system(size: 13.5))
                Spacer(minLength: 0)
            }.padding(.horizontal, 8).frame(height: 38).contentShape(Rectangle())
                .background(page == item ? SettingsPalette.selectedRow(colorScheme) : .clear, in: RoundedRectangle(cornerRadius: 15))
        }.buttonStyle(.plain)
            .accessibilityLabel(item.displayTitle).accessibilityAddTraits(page == item ? [.isSelected] : [])
    }

    private func heading(_ title: String, symbol: String? = nil) -> some View {
        HStack {
            Text(SettingsText.localized(title)).font(.system(size: 13, weight: .medium)); Spacer()
            if let symbol { Image(systemName: symbol) }
        }.foregroundStyle(.secondary).padding(.horizontal, 8).padding(.bottom, -8)
    }

    private func toggle(_ title: String, _ key: String, _ initial: Bool = false, symbol: String? = nil, info: String? = nil) -> some View {
        SettingsToggleRow(title: title, value: draft.binding(key, initial), symbol: symbol, info: info)
    }

    private func slider(_ title: String, _ key: String, _ initial: Double, _ range: ClosedRange<Double>,
                        unit: String = "s", decimals: Int = 0, step: Double = 1, ticks: Int = 11) -> some View {
        SettingsSliderRow(title: title, value: draft.binding(key, initial), range: range, step: step, unit: unit, decimals: decimals, ticks: ticks)
    }

    private func choices(_ key: String, _ initial: String, _ options: [(String, String)], style: String = "symbol", height: CGFloat = 38) -> some View {
        SettingsChoices(choices: options.map { option in
            SettingsChoice(title: option.0, symbol: option.1, style: style)
        }, selected: draft.binding(key, initial), tileHeight: height)
    }

    @ViewBuilder private var pageContent: some View {
        switch page {
        case .general: general
        case .connectivity: connectivity
        case .nowPlaying: music
        }
    }

    private var general: some View {
        Group {
            SettingsCard {
                SettingsToggleRow(title: "Launch at login",
                                  value: loginBinding,
                                  blocked: permissions.loginBlocked); SettingsRule()
                SettingsToggleRow(title: "Force simulated notch", value: $settings.forceSimulatedNotch); SettingsRule()
                HStack {
                    Text(SettingsText.localized("Display on")); Spacer()
                    Image(systemName: SettingsDisplayCatalog.symbol(for: draft.value("showOnDisplay", "Main display")))
                        .contentTransition(.symbolEffect(.replace))
                        .padding(.trailing, 4)
                    SettingsNativeMenu(value: draft.binding("showOnDisplay", "Main display"), options: SettingsDisplayCatalog.options)
                }.font(.system(size: 13.5)).padding(.horizontal, 12).frame(height: 41)
            }
            heading("Behaviour")
            SettingsCard {
                SettingsToggleRow(title: "Expand on hover", value: $settings.hoverEnabled, info: "Expand the current activity when the pointer rests on the notch.")
                if settings.hoverEnabled {
                    SettingsRule()
                    slider("Hover delay", "hoverDelay", 0, 0...1, unit: "s", decimals: 2, step: 0.05, ticks: 5)
                }
            }
        }
    }

    private var connectivity: some View {
        SettingsCard {
            SettingsToggleRow(title: "Connectivity", value: bluetoothBinding,
                              symbol: "headphones", blocked: permissions.bluetoothBlocked)
            // Appearance is automatic; no 3D/Symbols tile is exposed.
        }
    }

    private var music: some View {
        SettingsCard {
            toggle("Now Playing", "enableNowPlaying", true, symbol: "play.fill"); SettingsRule()
            choices("progressStyle", "Monochrome", [("Monochrome", ""), ("Colored", ""), ("Gradient", "")], style: "progress", height: 36); SettingsRule()
            SettingsToggleRow(title: "Use live waveform",
                              value: audioBinding,
                              blocked: permissions.audioBlocked); SettingsRule()
            toggle("Show lyrics", "showLyrics")
        }
    }
}
