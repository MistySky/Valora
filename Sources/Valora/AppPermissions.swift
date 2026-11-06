import AppKit
import Combine
import CoreBluetooth
import ServiceManagement
import SwiftUI

enum PermissionAccess: Equatable, Sendable {
    case authorized
    case notDetermined
    case denied
    case restricted
    case unknown
}

enum LoginItemAccess: Equatable, Sendable {
    case notRegistered
    case enabled
    case requiresApproval
    case notFound
    case unknown
}

/// Small adapter around public permission state and user-initiated entry points.
/// It never reads TCC or issues an authorization request from a poll. A pending
/// intent is published so the real settings view can immediately return to off
/// when the user cancels it.
@MainActor
final class AppPermissions: ObservableObject {
    @Published private(set) var bluetooth: PermissionAccess
    @Published private(set) var loginItem: LoginItemAccess
    @Published private(set) var calendar: CalendarAccess
    @Published private(set) var bluetoothEnablePending = false
    @Published private(set) var loginEnablePending = false
    @Published private(set) var calendarEnablePending = false
    @Published var message: String?

    private var pendingBluetooth: (() -> Void)?
    private var pendingLogin: (() -> Void)?
    private var pendingCalendar: (() -> Void)?
    private var loginIntentGeneration: UInt64 = 0
    private var loginRegistrationOwned = false
    private var calendarIntentGeneration: UInt64 = 0
    private var calendarAttemptInFlight = false

    private let injected: Bool
    private let refreshStateProvider: (() -> (PermissionAccess, LoginItemAccess))?
    private let bluetoothRequest: () -> Void
    private let openBluetoothSettings: () -> Void
    private let loginRegister: (@MainActor @escaping (LoginItemAccess) -> Void) -> Void
    private let loginUnregister: (@MainActor @escaping (LoginItemAccess) -> Void) -> Void
    private let openLoginSettings: () -> Void
    private let calendarProvider: any CalendarAuthorizationProviding
    private let openCalendarSettings: () -> Void

    init(bluetooth: PermissionAccess? = nil,
         loginItem: LoginItemAccess? = nil,
         calendar: CalendarAccess? = nil,
         bluetoothRequest: @escaping () -> Void = {},
         openBluetoothSettings: @escaping () -> Void = {},
         loginRegister: @escaping (@MainActor @escaping (LoginItemAccess) -> Void) -> Void = { $0(.unknown) },
         loginUnregister: @escaping (@MainActor @escaping (LoginItemAccess) -> Void) -> Void = { $0(.unknown) },
         openLoginSettings: @escaping () -> Void = {},
         calendarProvider: (any CalendarAuthorizationProviding)? = nil,
         openCalendarSettings: @escaping () -> Void = {},
         refreshStateProvider: (() -> (PermissionAccess, LoginItemAccess))? = nil) {
        self.injected = bluetooth != nil || loginItem != nil || calendar != nil
        self.calendarProvider = calendarProvider ?? EventKitCalendarAuthorization()
        self.openCalendarSettings = openCalendarSettings
        self.refreshStateProvider = refreshStateProvider
        self.bluetooth = bluetooth ?? Self.currentBluetooth
        self.loginItem = loginItem ?? Self.currentLoginItem
        self.calendar = calendar ?? (calendarProvider?.status ?? .unknown)
        self.bluetoothRequest = bluetoothRequest
        self.openBluetoothSettings = openBluetoothSettings
        self.loginRegister = loginRegister
        self.loginUnregister = loginUnregister
        self.openLoginSettings = openLoginSettings
    }

    static var currentBluetooth: PermissionAccess {
        switch CBManager.authorization {
        case .allowedAlways: return .authorized
        case .denied: return .denied
        case .restricted: return .restricted
        case .notDetermined: return .notDetermined
        @unknown default: return .unknown
        }
    }

    static var currentLoginItem: LoginItemAccess { loginAccess(from: SMAppService.mainApp.status) }

    static func loginAccess(from status: SMAppService.Status) -> LoginItemAccess {
        switch status {
        case .notRegistered: return .notRegistered
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notFound: return .notFound
        @unknown default: return .unknown
        }
    }

    var bluetoothBlocked: Bool { bluetooth != .authorized }
    var loginBlocked: Bool { loginItem == .requiresApproval }
    var calendarBlocked: Bool { calendar != .fullAccess }
    var canOpenBluetoothSettings: Bool { bluetooth == .denied || bluetooth == .restricted }

    func refresh() {
        let nextBluetooth: PermissionAccess
        let nextLogin: LoginItemAccess
        let nextCalendar = calendarProvider.status
        if let refreshStateProvider {
            (nextBluetooth, nextLogin) = refreshStateProvider()
        } else {
            guard !injected else { return }
            (nextBluetooth, nextLogin) = (Self.currentBluetooth, Self.currentLoginItem)
        }
        if bluetooth != nextBluetooth { bluetooth = nextBluetooth }
        if loginItem != nextLogin { loginItem = nextLogin }
        if calendar != nextCalendar { calendar = nextCalendar }
        resolvePendingIntents()
    }

    /// Resolve only a still-valid user intent. External permission changes
    /// without a pending enable do not turn a feature on.
    private func resolvePendingIntents() {
        if let completion = pendingBluetooth {
            switch bluetooth {
            case .authorized:
                finishBluetooth(completion)
            case .denied, .restricted:
                clearBluetooth()
                message = "蓝牙访问未获授权，功能保持关闭。请到系统设置 → 隐私与安全 → 蓝牙检查。"
            case .notDetermined, .unknown:
                break
            }
        }
        if let completion = pendingCalendar {
            if !calendarAttemptInFlight {
                switch calendar {
                case .fullAccess:
                    finishCalendar(completion)
                case .denied, .restricted, .writeOnly:
                    clearCalendar()
                    message = "日历读取权限不可用（需要完整访问）。功能保持关闭。"
                case .notDetermined, .unknown:
                    break
                }
            }
        }
        if let completion = pendingLogin {
            switch loginItem {
            case .enabled:
                finishLogin(completion)
            case .requiresApproval:
                break
            case .notRegistered, .notFound, .unknown:
                clearLogin()
            }
        }
    }

    // MARK: Bluetooth intent

    func beginBluetoothEnable(completion: @escaping () -> Void) {
        guard pendingBluetooth == nil else { return }
        message = nil
        switch bluetooth {
        case .authorized:
            completion()
        case .denied, .restricted:
            pendingBluetooth = completion
            bluetoothEnablePending = true
            openBluetoothSettings()
        case .notDetermined, .unknown:
            pendingBluetooth = completion
            bluetoothEnablePending = true
            bluetoothRequest()
        }
    }

    func cancelBluetoothEnable() {
        pendingBluetooth = nil
        bluetoothEnablePending = false
    }

    /// Compatibility entry for earlier callers/tests; the switch routes through
    /// beginBluetoothEnable so a successful authorization completes that intent.
    func requestBluetoothAccess() {
        beginBluetoothEnable(completion: {})
    }

    private func finishBluetooth(_ completion: () -> Void) {
        pendingBluetooth = nil
        bluetoothEnablePending = false
        completion()
    }

    private func clearBluetooth() {
        pendingBluetooth = nil
        bluetoothEnablePending = false
    }

    // MARK: Login item intent

    func beginLoginEnable(completion: @escaping () -> Void) {
        guard pendingLogin == nil else { return }
        // Invalidate an older unregister/registration callback when the user
        // starts a new intent.
        loginIntentGeneration &+= 1
        message = nil
        switch loginItem {
        case .enabled:
            completion()
        case .requiresApproval:
            pendingLogin = completion
            loginEnablePending = true
            openLoginSettings()
        case .notRegistered, .notFound, .unknown:
            pendingLogin = completion
            loginEnablePending = true
            loginRegistrationOwned = true
            loginIntentGeneration &+= 1
            let generation = loginIntentGeneration
            loginRegister { [weak self] result in
                guard let self, self.loginIntentGeneration == generation else { return }
                guard self.pendingLogin != nil else { return }
                self.loginItem = result
                switch result {
                case .enabled:
                    self.loginRegistrationOwned = false
                    if let completion = self.pendingLogin { self.finishLogin(completion) }
                case .requiresApproval:
                    // Keep the original intent alive while the user approves
                    // the newly registered login item in System Settings.
                    self.openLoginSettings()
                case .notRegistered, .notFound, .unknown:
                    let owned = self.loginRegistrationOwned
                    self.clearLogin()
                    if owned { self.undoLoginRegistration() }
                    self.message = "登录时启动未能完成注册。"
                }
            }
        }
    }

    func cancelLoginEnable() {
        loginIntentGeneration &+= 1
        let owned = loginRegistrationOwned
        loginRegistrationOwned = false
        clearLogin()
        if owned { undoLoginRegistration() }
    }

    /// Called only by an explicit user switch-off. A pending intent is
    /// cancelled/owned registration undone; an already-enabled login item is
    /// unregistered through the injected action. Programmatic normalization
    /// must never call this.
    func disableLoginItem() {
        guard pendingLogin == nil else {
            cancelLoginEnable()
            return
        }
        guard loginItem == .enabled else { return }
        loginIntentGeneration &+= 1
        let generation = loginIntentGeneration
        loginUnregister { [weak self] result in
            guard let self, self.loginIntentGeneration == generation else { return }
            self.loginItem = result
            if result != .notRegistered {
                self.message = "登录时启动的注册撤销未完成，请到系统设置 → 通用 → 登录项检查。"
            }
        }
    }

    private func undoLoginRegistration() {
        let generation = loginIntentGeneration
        loginUnregister { [weak self] result in
            guard let self, self.loginIntentGeneration == generation else { return }
            self.loginItem = result
            if result != .notRegistered {
                self.message = "登录时启动的注册撤销未完成，请到系统设置 → 通用 → 登录项检查。"
            }
        }
    }

    /// Compatibility entry retained for earlier callers/tests; the switch uses
    /// beginLoginEnable so registration/approval can complete the intent.
    func requestLoginItemAccess() {
        openLoginSettings()
    }

    private func finishLogin(_ completion: () -> Void) {
        pendingLogin = nil
        loginEnablePending = false
        completion()
    }

    private func clearLogin() {
        pendingLogin = nil
        loginEnablePending = false
    }

    // MARK: Calendar intent

    func beginCalendarEnable(completion: @escaping () -> Void) {
        guard pendingCalendar == nil else { return }
        message = nil
        switch calendar {
        case .fullAccess:
            completion()
        case .denied, .restricted:
            pendingCalendar = completion
            calendarEnablePending = true
            openCalendarSettings()
        case .notDetermined, .writeOnly, .unknown:
            pendingCalendar = completion
            calendarEnablePending = true
            calendarIntentGeneration &+= 1
            let generation = calendarIntentGeneration
            calendarAttemptInFlight = true
            calendarProvider.requestFullAccessWithFailure { [weak self] result, failure in
                guard let self, self.calendarIntentGeneration == generation else { return }
                self.calendarAttemptInFlight = false
                self.calendar = result
                guard let completion = self.pendingCalendar else { return }
                if result == .fullAccess {
                    self.finishCalendar(completion)
                } else {
                    self.clearCalendar()
                    if let failure {
                        // Keep domains/codes only; never log or display event data.
                        self.message = "日历授权请求失败（\(failure.domain) \(failure.code)），功能保持关闭。"
                    } else {
                        self.message = result == .writeOnly
                            ? "系统只授予了写入权限；读取日程需要完整访问。"
                            : "日历读取未获授权，功能保持关闭。"
                    }
                }
            }
        }
    }

    func cancelCalendarEnable() {
        calendarIntentGeneration &+= 1
        calendarAttemptInFlight = false
        clearCalendar()
    }

    private func finishCalendar(_ completion: () -> Void) {
        pendingCalendar = nil
        calendarEnablePending = false
        calendarAttemptInFlight = false
        completion()
    }

    private func clearCalendar() {
        pendingCalendar = nil
        calendarEnablePending = false
        calendarAttemptInFlight = false
    }

    // MARK: QA seams

    /// QA-only state injection without mutating system permissions.
    func verificationSet(bluetooth: PermissionAccess? = nil,
                         loginItem: LoginItemAccess? = nil,
                         calendar: CalendarAccess? = nil) {
        if let bluetooth { self.bluetooth = bluetooth }
        if let loginItem { self.loginItem = loginItem }
        if let calendar { self.calendar = calendar }
    }

    func verificationResolvePending() { resolvePendingIntents() }

    static func openBluetoothPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth") else { return }
        NSWorkspace.shared.open(url)
    }

    static func openCalendarPrivacySettings() {
        EventKitCalendarAuthorization.openPrivacySettings()
    }

    static func openLoginItemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

/// Shared switch routing used by the real settings rows. The hand is not an
/// action; tapping the switch either performs the normal change or starts one
/// user-intent authorization flow.
@MainActor
enum PermissionToggleRouting {
    static func make(value: Binding<Bool>, authorized: Bool, pending: Bool,
                     begin: @escaping () -> Void,
                     cancel: @escaping () -> Void) -> Binding<Bool> {
        Binding(get: {
            // A persisted "on" preference is not an authorization. Only a
            // currently authorized feature or a live enable intent may render
            // as on. This also keeps a stale preference from swallowing the
            // next user click.
            pending || (authorized && value.wrappedValue)
        }, set: { requested in
            if requested {
                if pending { return }
                if authorized && value.wrappedValue { return }
                if authorized { value.wrappedValue = true }
                else { begin() }
            } else {
                cancel()
                if value.wrappedValue { value.wrappedValue = false }
            }
        })
    }
}
