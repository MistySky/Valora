import Foundation

/// The complete external ownership boundary for one DownloadEngine instance.
/// It contains no routing or UI state; every mutable path/defaults source is
/// supplied by the host so multiple isolated engines cannot share Convoy's
/// global Application Support or UserDefaults.standard.
@MainActor
public final class DownloadEnvironment {
    public let persistenceURL: URL
    public let scratchContainer: URL
    public let defaults: UserDefaults
    public let settings: AppSettings
    public let allowExternalHelpers: Bool
    public let measureTemporaryStorageAtLaunch: Bool
    public let defaultDownloadDirectory: URL?
    /// Injectable trash operation. Production uses the real user Trash; QA
    /// supplies an isolated directory so tests never move user files.
    public let trashItem: (URL) throws -> Void

    public init(persistenceURL: URL,
                scratchContainer: URL,
                defaults: UserDefaults,
                defaultDownloadDirectory: URL? = nil,
                allowExternalHelpers: Bool = false,
                measureTemporaryStorageAtLaunch: Bool = false,
                trashItem: @escaping (URL) throws -> Void = { url in
                    var resulting: NSURL?
                    try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
                }) {
        self.persistenceURL = persistenceURL
        self.scratchContainer = scratchContainer
        self.defaults = defaults
        self.defaultDownloadDirectory = defaultDownloadDirectory
        self.allowExternalHelpers = allowExternalHelpers
        self.measureTemporaryStorageAtLaunch = measureTemporaryStorageAtLaunch
        self.trashItem = trashItem
        self.settings = AppSettings(defaults: defaults)
        if let defaultDownloadDirectory {
            settings.downloadDirectory = defaultDownloadDirectory.path
            try? FileManager.default.createDirectory(at: defaultDownloadDirectory,
                                                      withIntermediateDirectories: true)
        }
    }

    /// Compatibility path used only by upstream `DownloadManager.shared`.
    /// Valora never calls this.
    public static func upstreamDefault() -> DownloadEnvironment {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let download = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        return DownloadEnvironment(
            persistenceURL: support.appendingPathComponent("Convoy/downloads.json"),
            scratchContainer: FileManager.default.temporaryDirectory,
            defaults: .standard,
            defaultDownloadDirectory: download,
            allowExternalHelpers: true,
            measureTemporaryStorageAtLaunch: true)
    }
}
