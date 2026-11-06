# DownloadEngine isolation decision

## Verdict

**Blocked for safe production download execution** at fixed revision `007a20973923fcd69c42a3571fc299f5b8582dc6`.

The package can be resolved, compiled and linked; the public read-only mapping/fixture layer is implemented. It does not provide a public way to instantiate `DownloadManager` against Valora's own Application Support/scratch/settings roots.

## Blocking facts

- `DownloadManager.shared` is the only way to instantiate the manager; its initializer is private.
- The initializer loads `~/Library/Application Support/Convoy/downloads.json` and measures the system temp folder.
- The persistence URL, lock URL and list file are private statics; there is no public root injection.
- `AppSettings.shared` is a private-init `@AppStorage(.standard)` singleton; no UserDefaults suite/root injection.
- Task segment temp files use `FileManager.default.temporaryDirectory`; `TaskScratchDirectory` is internal.
- `TemporaryStorage` accepts a container only for its standalone report/remove APIs, not for manager-owned tasks.
- Using a different `HOME`, mutating global UserDefaults, or launching an external sandboxed process would not be a maintainable isolation boundary and was not attempted.

## Implemented instead

- SPM dependency on the fixed Convoy revision, only the `DownloadEngine` product.
- Pure `DownloadEngineCompatibility` mapping and an immutable `DownloadItemSnapshot`/`DownloadServicing` boundary.
- `FakeDownloadService` for future UI contract tests.
- No manager/settings singleton, task start, download, file creation, network probe or user-directory access in Valora.
- No AppDelegate download-service initialization; settings Downloads UI remains its existing placeholder.

## Proposed upstream isolation patch (not applied)

A future Convoy revision would need an injected environment (public or internal factory) covering at least:

1. persistence URL and lock URL,
2. task scratch container used by `DownloadSegment` and `TaskScratchDirectory`,
3. `UserDefaults`/settings instance,
4. optional explicit public factory that does not run launch measurements until requested.

A maintainable Valora integration would then use:
`Application Support/com.wangqing.valora/Downloads/` for persistence and
`~/Library/Caches/com.wangqing.valora/Downloads/` (or a dedicated temp root) for scratch, with a Valora-owned UserDefaults suite. Until that API exists, do not ship a manager-backed download feature.

A proposed change sketch is in `proposed-isolation.patch`; it is documentation only and does not modify the pinned checkout.
