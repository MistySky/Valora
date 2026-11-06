# V0030 source mapping

Upstream: `https://github.com/TheDynamicPunk/Convoy.git`
Revision: `007a20973923fcd69c42a3571fc299f5b8582dc6`
License: GPL-3.0 (`Convoy-GPL-3.0.txt`; notices copied).

| Upstream | Local | Necessary adaptation |
|---|---|---|
| `Views/DownloadRowView.swift` | `DownloadRowView.swift` | Mature row hierarchy, status pill, icon, metrics, SegmentBar and context actions retained; `DownloadTask`/`DownloadManager` replaced by immutable `DownloadItemSnapshot` and injected closures. No per-row timer/TimelineView. |
| `Views/SegmentBar.swift` | `DownloadSegmentBar.swift` | Engine SegmentMap replaced by `[DownloadSegmentSnapshot]`; capsule/parts/ripple Canvas retained. |
| `Views/NewDownloadView.swift` | `DownloadNewView.swift` | URL/card/footer/explicit-submit layout retained; YouTube/helper/clipboard paths removed for HTTP(S)-only V0030. |
| `Views/DeleteConfirmationSheet.swift` | `DownloadDeleteConfirmation.swift` | One confirmation, record-only default, explicit Trash checkbox and progress-discard wording retained; plan/action are UI-safe and injected. |
| `Views/DuplicateDownloadSheet.swift` | `DownloadConflictSheet.swift` | Four native decisions retained; conflict is an immutable snapshot; resolution is handled by the adapter. |
| `Views/ContentView.swift` | `DownloadPopoverView.swift` | Stable row order, selection/context-delete/keyboard semantics in a bounded scroll; no sidebar/categories/Convoy window. |
| `Services/StatusItemManager.swift` | `DownloadMenuBarController.swift` | Independent status item, left popover, right-click new-download + version/settings/quit; no Convoy update/main-window items. |

The upstream files are evidence under `source/upstream/`; local adapted files are under
`source/local/`. SHA256 values are in `source-manifest.json`. No source archive was
modified and no GitHub fork was created.
