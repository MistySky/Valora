import Foundation

/// Runtime subset of the existing 1.7.9 settings dictionary. No extra UI keys.
public struct MusicPreferences: Equatable, Sendable {
    public var disableArtworkFlip: Bool
    public var progressStyle: MusicProgressStyle
    public var disableWaveform: Bool
    public var hideWhileSourceIsActive: Bool
    public var quickPeekEnabled: Bool
    public var whenSongChanges: Bool
    public var peekDuration: Double
    public var idleDuration: Double
    public var hideSongTitleExtras: Bool
    public var useLiveWaveform: Bool
    public var showLyrics: Bool

    public init(values: [String: Any] = [:]) {
        disableArtworkFlip = values["disableAlbumArtFlip"] as? Bool ?? false
        progressStyle = MusicProgressStyle(rawValue:values["progressStyle"] as? String ?? "") ?? .monochrome
        disableWaveform = values["disableWaveform"] as? Bool ?? false
        hideWhileSourceIsActive = values["hideWhileSourceIsActive"] as? Bool ?? false
        quickPeekEnabled = values["enableQuickPeek"] as? Bool ?? true
        whenSongChanges = values["whenSongChanges"] as? Bool ?? true
        let seconds = (values["peekDuration"] as? NSNumber)?.doubleValue ?? 2
        peekDuration = seconds.isFinite ? min(5, max(1, seconds)) : 2
        let idle = (values["idleDuration"] as? NSNumber)?.doubleValue ?? 3
        idleDuration = idle.isFinite ? min(10, max(0, idle)) : 3
        hideSongTitleExtras = values["hideSongTitleExtras"] as? Bool ?? false
        useLiveWaveform = values["useLiveWaveform"] as? Bool ?? false
        showLyrics = values["showLyrics"] as? Bool ?? false
    }

    public func hidesActivity(source: String, frontmost: String) -> Bool {
        hideWhileSourceIsActive && !source.isEmpty && source == frontmost
    }
}
