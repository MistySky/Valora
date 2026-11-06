# Valora

Swift 6 / macOS 27 migration of the archived Alcove experience, with a personal
lyrics feature.

- Minimum system: macOS 27.0
- Swift language mode: 6 (`swift-tools-version: 6.4`)
- Repo layout: `ReferenceCore` (pure logic), `NativeBridge` (Objective-C: Space
  migration and lock/device plumbing), `Valora` (AppKit/SwiftUI app)
- Media source: the system Now Playing session only, read through the bundled
  adapter. No per-player branches.
- Current state: `1.0.0`; accepted cleanup is merged into `main`. Build numbers remain monotonic. Local DMG distribution uses ad-hoc signing (not notarized).

## Scope

Music with compact/expanded lyrics, lock-screen music card and lock/unlock
animation, device connectivity switch with automatic 3D artwork, Calmon calendar
and system monitor status items, and a Codex usage row inside the shared monitor
panel. Downloads, the Chrome bridge and the composite status ring were removed
and are not coming back.

Settings: General, Music, Lock Screen, Connectivity, Calendar, System Monitor,
Codex Usage, About. See `AGENTS.md` for the current per-page contract.

## Branding

- App icon: the user-confirmed coloured icns.
- Menu bar: `Resources/MenuBarIcon-User-v11`, system template, 20×13.64 pt
  visible on a 22×18 pt canvas.

## Build

```sh
./scripts/build.sh --output-dir /private/tmp/valora-candidate
```

This builds the pinned MediaRemote adapter, the SwiftPM release binary and a
signed `.app` in the given output directory. The build number is allocated
automatically (`scripts/build_number.py`) and is monotonic; `--build` overrides
are rejected. No network access, no install, no publishing.

## Run

```sh
open /private/tmp/valora-candidate/Valora.app
```

## Development verification

Verification suites, audits and previews are compiled only into debug builds
(`VALORA_DEVELOPMENT`). The release app rejects `--verify*`, `--audit*`,
`--preview*`, `--expand-media` and `--lock-card-preview` before AppKit starts.

```sh
swift build                      # debug, QA entry points available
swift test --filter LaunchPolicyTests
```

QA modes use the isolated preference suite `com.wangqing.valora.qa` and never
read normal user preferences. `--lock-card-preview` is a valid isolated preview;
`--expand-media` and `--preview-long-title` require `--preview-music`.

## Docs

- `AGENTS.md` — current contract, boundaries, delivery rules
- `REQUIREMENTS.md` — migration scope
- `docs/CONTINUATION-PLAN.md` — current sequence and pending on-device checks
- `docs/reports/` — per-batch delivery reports
- `docs/verification/` — independent acceptance decisions
- `docs/history/` — archived long-form history
