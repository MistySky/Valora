# DownloadEngine public API / side-effect audit

Source: `TheDynamicPunk/Convoy` revision `007a20973923fcd69c42a3571fc299f5b8582dc6`.
Read-only checkout used for audit; no Convoy application was launched.

## Public surface relevant to Valora

### DownloadManager (Services/DownloadManager.swift)

- `public static let shared: DownloadManager`, `private init()` (line ~6/78).
- Published read state: `tasks`, `completedTasks`, `activeCount`, `totalSpeed`, `orphanedTemporaryBytes`, `temporaryStorageNoticeDueAtLaunch`, `pendingConflict`.
- Read: `maxConcurrentDownloads`, `ownsDownloadList`, `failedTasks`.
- Actions: `addDownload`, `addDownloads`, `addYouTubeDownload`, `addStreamDownload`, `startDownload`, `pauseDownload`, `resumeDownload`, `cancelDownload`, `delete(taskIDs:moveFilesToTrash:)`, `removeTask`, `retryFailed`, `pauseAll`, `resumeAll`, `setSpeedLimit`, `resolveConflict`, `clearOrphanedTemporaryFiles`, `refreshOrphanedTemporaryBytes`, `saveBeforeTermination`.
- `DownloadTask` is returned by add APIs; manager owns starts, speed timer, persistence and conflict continuation.

### DownloadTask (Models/DownloadTask.swift)

- Public identity/metadata: `id`, `url`, `destinationURL`, `priority`, `createdAt`, `originalName`, `filename`, `category`, `filenameSource`.
- Public live state: `status`, `activityMessage`, `totalBytes`, `downloadedBytes`, `speed`, `error`, `segmentCount`, `progressBasis`, `isMerging`, `segmentMap`, `progress`, `estimatedTimeRemaining`, `averageSpeed`, `endTime`.
- Public `init` can construct a value fixture; task start/pause/resume/cancel are internal and manager-driven.
- Public user actions: `relocateDestinationFolder`, `recreateOriginalDestinationFolder`, `showInFinder`, `openFile`, `copyURL`, `copyFilePath`.
- `DownloadStatus` covers waiting/starting/validating/refreshingLink/downloading/paused/completed/failed/cancelled/urlExpired/destinationMissing/awaitingDuplicateResolution.

### SegmentMap / Segment

- `SegmentMap` and `SegmentMap.Span` are public read-only value types: layout, fractional start/end, fill, active.
- `DownloadSegment` is an internal actor; no public creation/configuration.

### Settings (Models/Settings.swift)

- `public static let shared = AppSettings()` with `private init()`.
- All settings are `@AppStorage` on `.standard` (download directory, concurrency, segments, speed, autostart, notifications, theme, language, YouTube helpers/cookies, temporary notice threshold).
- `fillDerivedDefaults()` writes the user's Downloads directory when empty.
- No initializer accepting `UserDefaults`, a suite, or a root path.

### Temporary/persistence (DownloadManager, DownloadSegment, TaskScratchDirectory, TemporaryStorage)

- `DownloadManager.persistenceURL` is a private static fixed to
  `~/Library/Application Support/Convoy/downloads.json`; it creates that directory.
- `DownloadListLock` is created beside that URL (`downloads.lock`).
- `DownloadSegment` creates `<task-id>-segment-<n>.tmp` in `FileManager.default.temporaryDirectory`.
- `TaskScratchDirectory` is internal and defaults to the system temporary directory; no public manager root injection.
- `TemporaryStorage.report(knownTaskIDs:in:)` and `remove` accept a container for isolated reporting, but manager task operations do not receive that container.
- `savePersistedTasks()` atomically writes the fixed persistence URL; unreadable lists are moved aside with `UnreadableDownloadList.setAside`.

## Automatic side effects of shared initialization

Accessing `DownloadManager.shared` would immediately:

1. create/acquire the fixed Application Support lock,
2. load and decode `downloads.json`,
3. possibly move an unreadable list aside,
4. schedule temporary-storage measurement in the system temp dir,
5. subscribe to `AppSettings.shared`.

`AppSettings.shared` immediately registers `@AppStorage` defaults on `.standard` and can write the derived Downloads directory. These effects cannot be redirected by a public configure call.

## Consequence

`DownloadTask` and `SegmentMap` can be used for pure mapping/fixtures without manager startup. The real manager cannot be safely instantiated under Valora's separate application identity/root using the public API; changing `HOME`/`UserDefaults.standard` or a sandbox-external process would not be a maintainable isolation boundary. No real manager was instantiated and no Range HTTP download was run.
