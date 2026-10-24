# Valora

Swift 6 / macOS 27 migration of the archived Alcove music revival sources.

- Minimum system: macOS 27.0
- Swift language mode: 6 (`swift-tools-version: 6.4`)
- Scope: system Now Playing music only + General / Now Playing settings
- Direct source: `/Users/wangqing/code/alcove-revival-archive` (read-only)
- App icon: user-confirmed light `icns` as the normal bundle icon; both light
  and dark originals are preserved under `Resources/AppIcons` (no automatic
  appearance switching, and no asset editing)
- Menu bar: the confirmed Outline-v7 ribbon V, packaged as 20/40/60 px
  PNGs at 20 pt with system template tinting. The app icon remains colored.

## Development baseline

This repository preserves the current migration and the first line-lyrics
candidate before the next lyrics revision. Word-synchronized color filling,
the revised transition/layout, the three-second request deadline and bounded
cache improvements are pending; this baseline is not a fully accepted release.

Sources, confirmed resources, task specifications and verification evidence are
versioned. Build caches, packaged apps and local pi dispatch state are excluded.
See `docs/CONTINUATION-PLAN.md` for the current development sequence.

## Build

```sh
./scripts/build.sh
```

This builds the pinned BSD-3-Clause MediaRemote adapter, the SwiftPM release
binary and `dist/Valora.app` (ad-hoc signed, arm64). No network access, no
install, no publishing.

## Run

```sh
open dist/Valora.app
```

## Verification (synthetic, isolated preference domain)

```sh
dist/Valora.app/Contents/MacOS/Valora --verify-music docs/verification/v0001/ui
dist/Valora.app/Contents/MacOS/Valora --verify-settings docs/verification/v0001/settings
dist/Valora.app/Contents/MacOS/Valora --verify-system-media docs/verification/v0001/system-media
dist/Valora.app/Contents/MacOS/Valora --no-settings --diagnostic docs/verification/v0001/live
```

`--verify-system-media` is read-only: it never sends a player command. Report:
`docs/reports/v0001.md`. Source fingerprints:
`docs/verification/v0001/source-manifest.json`.
