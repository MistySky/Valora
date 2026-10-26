import AppKit
import SwiftUI
import ReferenceCore

/// Read-only connected-audio snapshot used by the connection toast. The ID is
/// stable native Bluetooth address/UID; no random fallback is generated.
struct AudioDevice: Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    var left: Int?
    var right: Int?
    var single: Int?
    var active: Bool
    var isAirPods: Bool
    var modelUID = ""
    var rawColorID: Int? = nil

    /// 0 is a real measured battery value; nil means unavailable/invalid.
    var battery: Int? {
        [left, right, single].compactMap { $0 }.min()
    }
    var airPodsModel: AirPodsModel? { AirPodsModel.identify(modelUID: modelUID) }
    var symbol: String {
        if let model = airPodsModel {
            if NSImage(systemSymbolName: model.symbol, accessibilityDescription: nil) != nil {
                return model.symbol
            }
            return model.fallbackSymbol ?? "airpods"
        }
        return isAirPods ? "airpods" : "headphones"
    }
    var movie: String? {
        if airPodsModel == .max || airPodsModel == .max2 {
            return AirPodsMaxColor.identify(rawColorID: rawColorID).movie
        }
        return airPodsModel?.uncoloredMovie
    }
}

/// Valora music slice. Settings are read through the same draft dictionary as
/// the archived source; the native nine-page settings surface reads these
/// values, while only music/connection/calendar have real backends.
@MainActor
final class RevivalSettings: ObservableObject {
    let defaults: UserDefaults
    private var preferenceObservers: [NSObjectProtocol] = []
    @Published private(set) var musicPreferences: MusicPreferences
    @Published private(set) var connectivityPreferences: ConnectivityPreferences
    @Published private(set) var hideFromScreenCapture = false
    @Published private(set) var selectedDisplay: String
    @Published private(set) var hideWhileInFullscreen = true
    @Published private(set) var hideWhileInMissionControl = true
    @Published private(set) var hideWhileGaming = false
    /// The expanded player's volume slider keeps the archived write timing
    /// (Smooth). The Sound page is out of this round's scope, so no UI writes it.
    let volumePreferences = VolumePreferences()
    @Published var showNotch: Bool { didSet { save() } }
    @Published var hoverEnabled: Bool { didSet { save() } }
    @Published var nowPlayingEnabled: Bool { didSet { defaults.set(nowPlayingEnabled, forKey: "enableNowPlaying") } }
    @Published var hoverDelay: Double { didSet { save() } }
    @Published var hideWhenIdle: Bool { didSet { save() } }
    @Published var autoCollapse: Bool { didSet { save() } }
    @Published var forceSimulatedNotch: Bool { didSet { save() } }
    @Published var bluetoothEnabled: Bool { didSet { save() } }
    @Published var showRemainingTime: Bool { didSet { defaults.set(showRemainingTime, forKey: "showRemainingTime") } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let values = defaults.dictionary(forKey: "referenceSettingsUI") ?? [:]
        musicPreferences = MusicPreferences(values: Self.sanitizedMusicValues(values))
        connectivityPreferences = ConnectivityPreferences(values: values)
        selectedDisplay = values["showOnDisplay"] as? String ?? "Main display"
        showNotch = defaults.object(forKey: "showNotch") as? Bool ?? true
        hoverEnabled = defaults.object(forKey: "hoverEnabled") as? Bool ?? false
        nowPlayingEnabled = defaults.object(forKey: "enableNowPlaying") as? Bool ?? true
        let rawHoverDelay = (values["hoverDelay"] as? NSNumber)?.doubleValue ?? 0
        hoverDelay = rawHoverDelay.isFinite ? min(1, max(0, rawHoverDelay)) : 0
        hideWhenIdle = defaults.object(forKey: "hideWhenIdle") as? Bool ?? false
        autoCollapse = defaults.object(forKey: "autoCollapse") as? Bool ?? true
        forceSimulatedNotch = defaults.bool(forKey: "forceSimulatedNotch")
        bluetoothEnabled = defaults.object(forKey: "bluetoothEnabled") as? Bool ?? false
        // 0x100348004 registers showRemainingTime with a true default.
        showRemainingTime = defaults.object(forKey: "showRemainingTime") as? Bool ?? true
        for name in [UserDefaults.didChangeNotification, Notification.Name("ValoraSettingsDraftChanged")] {
            preferenceObservers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.reloadPreferences() }
            })
        }
    }

    var quickPeekEnabled: Bool { musicPreferences.quickPeekEnabled }
    var peekWhenSongChanges: Bool { musicPreferences.whenSongChanges }
    var peekDuration: Double { musicPreferences.peekDuration }

    /// Re-read the archived preference dictionary after a SettingsDraft edit.
    func reloadPreferences() {
        let values = defaults.dictionary(forKey: "referenceSettingsUI") ?? [:]
        let next = MusicPreferences(values: Self.sanitizedMusicValues(values))
        if next != musicPreferences { musicPreferences = next }
        let connection = ConnectivityPreferences(values: values)
        if connection != connectivityPreferences { connectivityPreferences = connection }
        let display = values["showOnDisplay"] as? String ?? "Main display"
        if display != selectedDisplay { selectedDisplay = display }
        let rawHoverDelay = (values["hoverDelay"] as? NSNumber)?.doubleValue ?? 0
        let nextHoverDelay = rawHoverDelay.isFinite ? min(1, max(0, rawHoverDelay)) : 0
        if nextHoverDelay != hoverDelay { hoverDelay = nextHoverDelay }
    }

    /// Fixed product decisions for this round. Hidden/removed controls must not
    /// be overridden by old persisted values in the settings dictionary.
    private static func sanitizedMusicValues(_ values: [String: Any]) -> [String: Any] {
        var v = values
        v["idleDuration"] = 3.0
        v["disableWaveform"] = false
        v["disableAlbumArtFlip"] = false
        v["hideWhileSourceIsActive"] = false
        v["hideSongTitleExtras"] = false
        v["enableQuickPeek"] = true
        v["whenSongChanges"] = true
        v["peekDuration"] = 2.0
        return v
    }

    isolated deinit { preferenceObservers.forEach { NotificationCenter.default.removeObserver($0) } }

    private func save() {
        let d = defaults
        d.set(showNotch, forKey: "showNotch")
        d.set(hoverEnabled, forKey: "hoverEnabled")
        d.set(hoverDelay, forKey: "hoverDelay")
        d.set(hideWhenIdle, forKey: "hideWhenIdle")
        d.set(autoCollapse, forKey: "autoCollapse")
        d.set(forceSimulatedNotch, forKey: "forceSimulatedNotch")
        d.set(bluetoothEnabled, forKey: "bluetoothEnabled")
    }
}

@MainActor
final class AppModel: ObservableObject {
    let settings: RevivalSettings
    @Published var presentation = NotchTransitionState()
    @Published var screenHidden = false
    var expanded: Bool { presentation.expanded }
    @Published var title = "暂无播放"
    var displayTitle: String {
        MusicTitleFormatting.displayTitle(title, hideExtras: settings.musicPreferences.hideSongTitleExtras)
    }
    @Published var artist = ""
    @Published var album = ""
    @Published var playing = false
    @Published var playbackRate: Double = 1
    @Published var artwork: NSImage? {
        didSet {
            let result = ArtworkPalette.extract(artwork)
            artworkIdentity = result.identity
            artworkColors = result.colors
        }
    }
    @Published private(set) var artworkIdentity = ""
    @Published private(set) var artworkColors: [NSColor] = []
    @Published var duration: Double = 0
    @Published var elapsed: Double = 0 {
        didSet {
            if !settingElapsedWithSampleDate { elapsedSampleDate = Date() }
        }
    }
    private(set) var elapsedSampleDate = Date()
    private var settingElapsedWithSampleDate = false

    /// MediaController records the same wall-clock instant used to derive the
    /// elapsed sample, so a lyric view mounted later can account for its age.
    func setElapsed(_ value: Double, sampledAt date: Date) {
        settingElapsedWithSampleDate = true
        elapsedSampleDate = date
        elapsed = value
        settingElapsedWithSampleDate = false
    }

    func lyricsElapsed(at date: Date) -> TimeInterval {
        LyricsPlaybackClock(anchorElapsed: elapsed, anchorDate: elapsedSampleDate,
                            rate: playbackRate, playing: playing).elapsed(at: date)
    }
    @Published var source = "系统"
    @Published var mediaError: String?
    @Published var mediaBundleIdentifier = ""
    @Published var frontmostBundleIdentifier = ""
    @Published var mediaCanSeek = false
    @Published var mediaCanSkip = false
    @Published var mediaCanControl = false
    @Published var mediaRevisionIdentity = ""
    @Published var audioOutput = ""
    @Published var output = AudioOutputState()
    @Published var showsOutputVolume = false
    @Published var isPointerInside = false
    @Published var mediaIdle = MediaIdleState()
    @Published var songPeek = SongPeekState()
    @Published var lyrics = LyricsDisplayState()
    @Published var devices: [AudioDevice] = []
    @Published var connectionToast: AudioDevice?
    @Published var connectionLowBattery = false
    @Published var connectionArrivalGeneration = 0
    @Published var pinned = false
    @Published var previewMode = false
    @Published var notchGeometry = NotchGeometry.calculate(screenWidth:1728,safeAreaTop:32,auxiliaryLeftWidth:771.5,auxiliaryRightWidth:771.5,menuBarHeight:32,simulated:false)
    var nativeNotchSize: CGSize { notchGeometry.compact }
    var media: MediaController!
    var audio: AudioOutputController!
    var lyricsController: LyricsController?
    var bluetooth: ConnectivityController!
    /// Injected by AppDelegate; keeps the notch context menu on the existing
    /// settings window/controller instead of creating another UI.
    var showSettingsAction: (() -> Void)?
    var quitAction: (() -> Void)?
    var openMediaSourceAction: ((String) -> Void)?
    func openCurrentMediaSource() {
        guard settings.nowPlayingEnabled, hasTrack, !previewMode,
              !mediaBundleIdentifier.isEmpty else { return }
        openMediaSourceAction?(mediaBundleIdentifier)
    }
    /// Set by WindowCoordinator. The shared media controller reports a track
    /// change; the coordinator selects the interaction screen and forwards it.
    var trackChangedHandler: ((String?) -> Void)?
    /// While a media drag is active, panel activation must not steal it.
    private(set) var pointerInteractionActive = false
    func beginPointerInteraction() { pointerInteractionActive = true }
    func endPointerInteraction() { pointerInteractionActive = false }
    lazy var presenter = PresentationController(self)
    init(settings: RevivalSettings) { self.settings = settings }

    var expandedSize: CGSize { notchGeometry.expanded }

    var requestedExpansionActivity: ExpandedActivity {
        settings.nowPlayingEnabled && hasTrack ? .nowPlaying : .none
    }
    var canExpandActivity: Bool {
        requestedExpansionActivity != .none || connectionToast != nil
    }
    var connectionStatusNotification: NotchNotification {
        guard connectionToast != nil else { return .none }
        return connectionLowBattery ? .lowAirPodsBattery : .connectedAirPods
    }
    var hasActiveNotification: Bool { connectionStatusNotification != .none }
    /// True only while multiple enabled displays share the music surface. It
    /// lets an external pill use the same peek path without changing the
    /// single-display/simulated-notch policy.
    var allowsMultiDisplayDynamic = false

    // Single source of geometry for rendering and input hit testing.
    var visibleSize: CGSize {
        let size = PresentationMetrics.stationarySize(geometry: notchGeometry, simulated: settings.forceSimulatedNotch,
            expanded: expanded ? .nowPlaying : .none, hasOutput: showsOutputVolume,
            notification: connectionStatusNotification,
            liveActivity: (connectionToast == nil && showsMusicActivity) ? .playing : .none,
            quickPeek: (connectionToast == nil && ((!settings.musicPreferences.showLyrics && songPeek.visible) || showsCompactLyrics)) ? .playing : .none,
            tuning: .zero)
        if expanded, showsLyricsInExpanded {
            // 32pt lyric row plus the existing 8pt player stack spacing.
            return CGSize(width: size.width, height: size.height + 40)
        }
        return size
    }
    var hoverScale: CGSize { NotchHoverMetrics.scale(inside:isPointerInside, expanded:expanded) }
    var contour: NotchContour {
        .stationary(geometry: notchGeometry, simulated: settings.forceSimulatedNotch,
                    expanded: expanded, expandedCorners: presentation.usesExpandedCornerRadius,
                    active: showsMusicActivity || connectionToast != nil, visibleHeight: visibleSize.height)
    }
    var sourceActivityHidden: Bool {
        settings.musicPreferences.hidesActivity(source:mediaBundleIdentifier,frontmost:frontmostBundleIdentifier)
    }

    var showsMusicActivity: Bool {
        settings.nowPlayingEnabled && hasTrack && mediaIdle.visible && !sourceActivityHidden
    }
    var showsCompactWaveform: Bool { showsMusicActivity && !settings.musicPreferences.disableWaveform }
    var lyricsAvailable: Bool {
        settings.nowPlayingEnabled && settings.musicPreferences.showLyrics
            && showsMusicActivity && lyrics.hasTimedLyrics
    }
    var showsCompactLyrics: Bool {
        lyricsAvailable && !expanded && settings.showNotch && !screenHidden
            && connectionToast == nil
    }
    var showsLyricsInExpanded: Bool { lyricsAvailable && settings.showNotch && !screenHidden }
    var currentLyricLine: LyricLine? {
        guard lyricsAvailable, let timeline = lyrics.timeline else { return nil }
        return timeline.line(at: elapsed)
    }
    var lyricsAccentColor: NSColor {
        guard let color = artworkColors.first else { return NSColor.gray.withAlphaComponent(0.9) }
        let lum = ArtworkPalette.luminance(color)
        if lum < 0.22 {
            return NSColor(srgbRed: min(1, color.redComponent + 0.28),
                           green: min(1, color.greenComponent + 0.28),
                           blue: min(1, color.blueComponent + 0.28), alpha: 1)
        }
        return color
    }
    var hasTrack: Bool { title != "暂无播放" && !title.isEmpty }
    var displayDevices: [AudioDevice] {
        devices.sorted { $0.active && !$1.active }
    }
}
