import AppKit
import SwiftUI
import ReferenceCore

/// Valora music slice. Settings are read through the same draft dictionary as
/// the archived source, but only General and Now Playing pages remain visible.
@MainActor
final class RevivalSettings: ObservableObject {
    let defaults: UserDefaults
    private var preferenceObservers: [NSObjectProtocol] = []
    @Published private(set) var musicPreferences: MusicPreferences
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
    @Published var showRemainingTime: Bool { didSet { defaults.set(showRemainingTime, forKey: "showRemainingTime") } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let values = defaults.dictionary(forKey: "referenceSettingsUI") ?? [:]
        musicPreferences = MusicPreferences(values: Self.sanitizedMusicValues(values))
        selectedDisplay = values["showOnDisplay"] as? String ?? "Main display"
        showNotch = defaults.object(forKey: "showNotch") as? Bool ?? true
        hoverEnabled = defaults.object(forKey: "hoverEnabled") as? Bool ?? false
        nowPlayingEnabled = defaults.object(forKey: "enableNowPlaying") as? Bool ?? true
        let rawHoverDelay = (values["hoverDelay"] as? NSNumber)?.doubleValue ?? 0
        hoverDelay = rawHoverDelay.isFinite ? min(1, max(0, rawHoverDelay)) : 0
        hideWhenIdle = defaults.object(forKey: "hideWhenIdle") as? Bool ?? false
        autoCollapse = defaults.object(forKey: "autoCollapse") as? Bool ?? true
        forceSimulatedNotch = defaults.bool(forKey: "forceSimulatedNotch")
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
    @Published var elapsed: Double = 0
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
    @Published var pinned = false
    @Published var previewMode = false
    @Published var notchGeometry = NotchGeometry.calculate(screenWidth:1728,safeAreaTop:32,auxiliaryLeftWidth:771.5,auxiliaryRightWidth:771.5,menuBarHeight:32,simulated:false)
    var nativeNotchSize: CGSize { notchGeometry.compact }
    var media: MediaController!
    var audio: AudioOutputController!
    var lyricsController: LyricsController?
    /// Injected by AppDelegate; keeps the notch context menu on the existing
    /// settings window/controller instead of creating another UI.
    var showSettingsAction: (() -> Void)?
    var quitAction: (() -> Void)?
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
    var canExpandActivity: Bool { requestedExpansionActivity != .none }
    /// True only while multiple enabled displays share the music surface. It
    /// lets an external pill use the same peek path without changing the
    /// single-display/simulated-notch policy.
    var allowsMultiDisplayDynamic = false

    // Single source of geometry for rendering and input hit testing.
    var visibleSize: CGSize {
        PresentationMetrics.stationarySize(geometry: notchGeometry, simulated: settings.forceSimulatedNotch,
            expanded: expanded ? .nowPlaying : .none, hasOutput: showsOutputVolume,
            notification: .none,
            liveActivity: showsMusicActivity ? .playing : .none,
            quickPeek: (songPeek.visible || showsCompactLyrics) ? .playing : .none,
            tuning: .zero)
    }
    var hoverScale: CGSize { NotchHoverMetrics.scale(inside:isPointerInside, expanded:expanded) }
    var contour: NotchContour {
        .stationary(geometry: notchGeometry, simulated: settings.forceSimulatedNotch,
                    expanded: expanded, expandedCorners: presentation.usesExpandedCornerRadius,
                    active: showsMusicActivity, visibleHeight: visibleSize.height)
    }
    var sourceActivityHidden: Bool {
        settings.musicPreferences.hidesActivity(source:mediaBundleIdentifier,frontmost:frontmostBundleIdentifier)
    }

    var showsMusicActivity: Bool {
        settings.nowPlayingEnabled && hasTrack && mediaIdle.visible && !sourceActivityHidden
    }
    var showsCompactWaveform: Bool { showsMusicActivity && !settings.musicPreferences.disableWaveform }
    var showsCompactLyrics: Bool {
        settings.nowPlayingEnabled && settings.musicPreferences.showLyrics
            && showsMusicActivity && !expanded
    }
    var currentLyricLine: LyricLine? {
        guard showsCompactLyrics, lyrics.hasTimedLyrics, let timeline = lyrics.timeline else { return nil }
        return timeline.line(at: elapsed)
    }
    var lyricFallbackText: String {
        displayTitle + (artist.isEmpty ? "" : " · " + artist)
    }
    var hasTrack: Bool { title != "暂无播放" && !title.isEmpty }
}
