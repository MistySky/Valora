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
    @Published private(set) var audioCapture: PermissionAccess
    @Published private(set) var loginItem: LoginItemAccess
    @Published private(set) var bluetoothEnablePending = false
    @Published private(set) var audioEnablePending = false
    @Published private(set) var loginEnablePending = false
    @Published var message: String?

    private var pendingBluetooth: (() -> Void)?
    private var pendingAudio: (() -> Void)?
    private var pendingLogin: (() -> Void)?
    private var audioIntentGeneration: UInt64 = 0
    private var audioAttemptInFlight = false
    private var audioNeedsReturnAttempt = false
    private var loginIntentGeneration: UInt64 = 0
    private var loginRegistrationOwned = false

    private let injected: Bool
    private let refreshStateProvider: (() -> (PermissionAccess, PermissionAccess, LoginItemAccess))?
    private let bluetoothRequest: () -> Void
    private let openBluetoothSettings: () -> Void
    private let audioRequest: (@MainActor @escaping (Bool) -> Void) -> Void
    private let openAudioSettings: () -> Void
    private let loginRegister: (@MainActor @escaping (LoginItemAccess) -> Void) -> Void
    private let loginUnregister: (@MainActor @escaping (LoginItemAccess) -> Void) -> Void
    private let openLoginSettings: () -> Void

    init(bluetooth: PermissionAccess? = nil,
         audioCapture: PermissionAccess? = nil,
         loginItem: LoginItemAccess? = nil,
         bluetoothRequest: @escaping () -> Void = {},
         openBluetoothSettings: @escaping () -> Void = {},
         audioRequest: @escaping (@MainActor @escaping (Bool) -> Void) -> Void = { $0(false) },
         openAudioSettings: @escaping () -> Void = {},
         loginRegister: @escaping (@MainActor @escaping (LoginItemAccess) -> Void) -> Void = { $0(.unknown) },
         loginUnregister: @escaping (@MainActor @escaping (LoginItemAccess) -> Void) -> Void = { $0(.unknown) },
         openLoginSettings: @escaping () -> Void = {},
         refreshStateProvider: (() -> (PermissionAccess, PermissionAccess, LoginItemAccess))? = nil) {
        self.injected = bluetooth != nil || audioCapture != nil || loginItem != nil
        self.refreshStateProvider = refreshStateProvider
        self.bluetooth = bluetooth ?? Self.currentBluetooth
        self.audioCapture = audioCapture ?? .unknown
        self.loginItem = loginItem ?? Self.currentLoginItem
        self.bluetoothRequest = bluetoothRequest
        self.openBluetoothSettings = openBluetoothSettings
        self.audioRequest = audioRequest
        self.openAudioSettings = openAudioSettings
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
    var audioBlocked: Bool { audioCapture != .authorized }
    var loginBlocked: Bool { loginItem == .requiresApproval }
    var canOpenBluetoothSettings: Bool { bluetooth == .denied || bluetooth == .restricted }

    func refresh() {
        let nextBluetooth: PermissionAccess
        let nextAudio: PermissionAccess?
        let nextLogin: LoginItemAccess
        if let refreshStateProvider {
            (nextBluetooth, nextAudio, nextLogin) = refreshStateProvider()
        } else {
            guard !injected else { return }
            (nextBluetooth, nextAudio, nextLogin) = (Self.currentBluetooth, nil, Self.currentLoginItem)
        }
        if bluetooth != nextBluetooth { bluetooth = nextBluetooth }
        if let nextAudio, audioCapture != nextAudio { audioCapture = nextAudio }
        if loginItem != nextLogin { loginItem = nextLogin }

        // A denied audio intent opened System Settings. On return, make one
        // concrete attempt through the existing process-tap path, then resolve
        // from its actual callback (never from a timeout or a guessed TCC
        // status).
        if pendingAudio != nil, audioNeedsReturnAttempt {
            audioNeedsReturnAttempt = false
            attemptAudioRequest()
        }
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
        if let completion = pendingAudio {
            // A return attempt is asynchronous. Do not use the old denied/
            // unknown snapshot to clear the intent while its callback is live.
            if !audioAttemptInFlight {
                switch audioCapture {
            case .authorized:
                finishAudio(completion)
            case .denied, .restricted:
                clearAudio()
                message = "系统音频读取未获授权，功能保持关闭。"
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

    // MARK: Audio intent

    func beginAudioEnable(completion: @escaping () -> Void) {
        guard pendingAudio == nil else { return }
        message = nil
        switch audioCapture {
        case .authorized:
            completion()
        case .denied, .restricted:
            pendingAudio = completion
            audioEnablePending = true
            audioNeedsReturnAttempt = true
            openAudioSettings()
        case .notDetermined, .unknown:
            pendingAudio = completion
            audioEnablePending = true
            audioNeedsReturnAttempt = false
            attemptAudioRequest()
        }
    }

    func cancelAudioEnable() {
        clearAudio()
        audioIntentGeneration &+= 1
    }

    func requestAudioCapture() {
        beginAudioEnable(completion: {})
    }

    private func attemptAudioRequest() {
        guard pendingAudio != nil, !audioAttemptInFlight else { return }
        audioAttemptInFlight = true
        audioIntentGeneration &+= 1
        let generation = audioIntentGeneration
        audioRequest { [weak self] granted in
            guard let self, self.audioIntentGeneration == generation else { return }
            self.audioAttemptInFlight = false
            self.audioCapture = granted ? .authorized : .unknown
            self.audioNeedsReturnAttempt = false
            guard let completion = self.pendingAudio else { return }
            if granted {
                self.finishAudio(completion)
            } else {
                self.clearAudio()
                self.message = "系统音频读取未获授权，功能保持关闭。请在系统设置 → 隐私与安全中检查音频/系统音频权限。"
            }
        }
    }

    private func finishAudio(_ completion: () -> Void) {
        pendingAudio = nil
        audioEnablePending = false
        audioNeedsReturnAttempt = false
        audioAttemptInFlight = false
        completion()
    }

    private func clearAudio() {
        pendingAudio = nil
        audioEnablePending = false
        audioNeedsReturnAttempt = false
        audioAttemptInFlight = false
    }

    // MARK: Login item intent

    func beginLoginEnable(completion: @escaping () -> Void) {
        guard pendingLogin == nil else { return }
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

    private func undoLoginRegistration() {
        loginUnregister { [weak self] result in
            guard let self else { return }
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

    // MARK: QA seams

    /// QA-only state injection without mutating system permissions.
    func verificationSet(bluetooth: PermissionAccess? = nil,
                         audioCapture: PermissionAccess? = nil,
                         loginItem: LoginItemAccess? = nil) {
        if let bluetooth { self.bluetooth = bluetooth }
        if let audioCapture { self.audioCapture = audioCapture }
        if let loginItem { self.loginItem = loginItem }
    }

    func verificationResolvePending() { resolvePendingIntents() }

    static func openBluetoothPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth") else { return }
        NSWorkspace.shared.open(url)
    }

    static func openAudioPrivacySettings() {
        // The exact pane name for system-audio capture is not established
        // publicly; open the privacy root instead of guessing a TCC pane.
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security") else { return }
        NSWorkspace.shared.open(url)
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
            value.wrappedValue || pending
        }, set: { requested in
            if requested {
                guard !value.wrappedValue else { return }
                if authorized { value.wrappedValue = true }
                else { begin() }
            } else {
                cancel()
                if value.wrappedValue { value.wrappedValue = false }
            }
        })
    }
}
