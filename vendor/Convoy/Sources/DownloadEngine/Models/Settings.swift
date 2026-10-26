import Foundation
import SwiftUI

@MainActor
public final class AppSettings: ObservableObject {
    public static let shared = AppSettings(defaults: .standard)

    /// Every stored setting's name. The properties below read theirs from
    /// here, so restoring defaults can't miss one added later.
    private enum Key: String, CaseIterable {
        case downloadDirectory
        case maxConcurrentDownloads
        case defaultSegmentCount
        case speedLimit
        case autoStartDownloads
        case bringWindowToFrontOnCapture
        case alwaysFocusForRequiredInput
        case showNotifications
        case playCompletionSound
        case temporaryFilesNoticeThresholdGB
        case theme
        case language
        case preferredAudioLanguage
        case youtubeUseBrowserCookies
        case youtubeCookieBrowser
        case keepHelpersUpToDate
    }
    
    private let defaults: UserDefaults

    public var downloadDirectory: String {
        get { defaults.string(forKey: Key.downloadDirectory.rawValue) ?? "" }
        set { defaults.set(newValue, forKey: Key.downloadDirectory.rawValue); objectWillChange.send() }
    }
    public var maxConcurrentDownloads: Int {
        get { object(forKey: Key.maxConcurrentDownloads.rawValue, default: 3) }
        set { defaults.set(newValue, forKey: Key.maxConcurrentDownloads.rawValue); objectWillChange.send() }
    }
    public var defaultSegmentCount: Int {
        get { object(forKey: Key.defaultSegmentCount.rawValue, default: 8) }
        set { defaults.set(newValue, forKey: Key.defaultSegmentCount.rawValue); objectWillChange.send() }
    }
    public var speedLimit: Int {
        get { object(forKey: Key.speedLimit.rawValue, default: 0) }
        set { defaults.set(newValue, forKey: Key.speedLimit.rawValue); objectWillChange.send() }
    }
    public var autoStartDownloads: Bool {
        get { object(forKey: Key.autoStartDownloads.rawValue, default: true) }
        set { defaults.set(newValue, forKey: Key.autoStartDownloads.rawValue); objectWillChange.send() }
    }
    public var bringWindowToFrontOnCapture: Bool {
        get { object(forKey: Key.bringWindowToFrontOnCapture.rawValue, default: true) }
        set { defaults.set(newValue, forKey: Key.bringWindowToFrontOnCapture.rawValue); objectWillChange.send() }
    }
    public var alwaysFocusForRequiredInput: Bool {
        get { object(forKey: Key.alwaysFocusForRequiredInput.rawValue, default: true) }
        set { defaults.set(newValue, forKey: Key.alwaysFocusForRequiredInput.rawValue); objectWillChange.send() }
    }
    public var showNotifications: Bool {
        get { object(forKey: Key.showNotifications.rawValue, default: true) }
        set { defaults.set(newValue, forKey: Key.showNotifications.rawValue); objectWillChange.send() }
    }
    public var playCompletionSound: Bool {
        get { object(forKey: Key.playCompletionSound.rawValue, default: true) }
        set { defaults.set(newValue, forKey: Key.playCompletionSound.rawValue); objectWillChange.send() }
    }
    public var temporaryFilesNoticeThresholdGB: Double {
        get { object(forKey: Key.temporaryFilesNoticeThresholdGB.rawValue,
                     default: TemporaryStorageNotice.defaultThresholdGB) }
        set { defaults.set(newValue, forKey: Key.temporaryFilesNoticeThresholdGB.rawValue); objectWillChange.send() }
    }
    public var theme: AppTheme {
        get {
            let raw = defaults.string(forKey: Key.theme.rawValue)
            return raw.flatMap(AppTheme.init(rawValue:)) ?? .system
        }
        set { defaults.set(newValue.rawValue, forKey: Key.theme.rawValue); objectWillChange.send() }
    }
    public var language: String {
        get { defaults.string(forKey: Key.language.rawValue) ?? "en" }
        set { defaults.set(newValue, forKey: Key.language.rawValue); objectWillChange.send() }
    }
    public var preferredAudioLanguage: String {
        get { defaults.string(forKey: Key.preferredAudioLanguage.rawValue) ?? "" }
        set { defaults.set(newValue, forKey: Key.preferredAudioLanguage.rawValue); objectWillChange.send() }
    }
    public var youtubeUseBrowserCookies: Bool {
        get { object(forKey: Key.youtubeUseBrowserCookies.rawValue, default: false) }
        set { defaults.set(newValue, forKey: Key.youtubeUseBrowserCookies.rawValue); objectWillChange.send() }
    }
    public var youtubeCookieBrowser: String {
        get { defaults.string(forKey: Key.youtubeCookieBrowser.rawValue) ?? "safari" }
        set { defaults.set(newValue, forKey: Key.youtubeCookieBrowser.rawValue); objectWillChange.send() }
    }
    public var keepHelpersUpToDate: Bool {
        get { object(forKey: Key.keepHelpersUpToDate.rawValue, default: true) }
        set { defaults.set(newValue, forKey: Key.keepHelpersUpToDate.rawValue); objectWillChange.send() }
    }

    private func object<T>(forKey key: String, default fallback: T) -> T {
        defaults.object(forKey: key) as? T ?? fallback
    }

    /// Browsers yt-dlp can read cookies from, limited to those that ship on or
    /// are common on macOS. Values are exactly the keywords yt-dlp's
    /// `--cookies-from-browser` accepts.
    public static let supportedCookieBrowsers = ["safari", "chrome", "brave", "edge", "firefox", "vivaldi", "opera", "chromium"]
    
    public enum AppTheme: String, CaseIterable, Identifiable {
        case light = "Light"
        case dark = "Dark"
        case system = "System"
        
        public var id: String { rawValue }
        public var colorScheme: ColorScheme? {
            switch self {
            case .light: return .light
            case .dark: return .dark
            case .system: return nil
            }
        }
    }
    
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        fillDerivedDefaults()
    }

    /// Puts every setting back to its default. Downloads, helpers and window
    /// state aren't settings and are left alone.
    public func restoreDefaults() {
        objectWillChange.send()
        for key in Key.allCases {
            defaults.removeObject(forKey: key.rawValue)
        }
        fillDerivedDefaults()
    }

    /// Defaults that depend on the Mac rather than being constants.
    private func fillDerivedDefaults() {
        if downloadDirectory.isEmpty {
            downloadDirectory = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path ?? ""
        }
    }
}
