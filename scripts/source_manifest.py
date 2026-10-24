#!/usr/bin/env python3
"""Generate the V0001 source-to-destination mapping with SHA-256 fingerprints.

Read-only over the archive source; writes only inside the Valora repository.
"""
from pathlib import Path
import hashlib, json, subprocess, datetime

ROOT = Path(__file__).resolve().parents[1]
SRC = Path('/Users/wangqing/code/alcove-revival-archive')
OUT = ROOT / 'docs/verification/v0001/source-manifest.json'

app_files = sorted(p.name for p in (ROOT / 'Sources/Valora').glob('*.swift'))
core_files = sorted(p.name for p in (ROOT / 'Sources/ReferenceCore').glob('*.swift'))
core_tests = sorted(p.name for p in (ROOT / 'Tests/ReferenceCoreTests').glob('*.swift'))
valora_tests = sorted(p.name for p in (ROOT / 'Tests/ValoraTests').glob('*.swift'))

app_notes = {
    'AppDelegate.swift': 'trimmed to music + General/Now Playing; production services and QA verifier entry points; vendor identity removed',
    'AppRuntimeDefaults.swift': 'QA suite renamed to com.wangqing.valora.qa; removed lock/battery/airpods QA modes',
    'Models.swift': 'music-only AppModel + two-page RevivalSettings; removed bluetooth/battery/brightness/focus/lock/source state',
    'Controllers.swift': 'MediaController only; removed AppleScript/QQ/player-selection branches (system source only)',
    'SystemMediaSource.swift': 'Swift 6 Sendable/lock adaptation; same Perl + MediaRemoteAdapter stream/get/send/seek semantics',
    'AudioOutputController.swift': 'MainActor + scheduler isolation; CoreAudio volume/mute consumers preserved',
    'AudioTap.swift': 'Swift 6 @unchecked Sendable with documented lock/serial-queue invariants; labels renamed to Valora',
    'PresentationController.swift': 'MainActor; notification/lock chevrons removed; expansion lifecycle, peek and idle timing preserved',
    'WindowCoordinator.swift': 'MainActor; notification/lock subscriptions and panels removed; display, hit-test, hover, scroll and secondary compact panels preserved',
    'NotchView.swift': 'music branches only; artwork/compact waveform/Quick Peek/expanded player retained; notification/lock/device/battery branches removed',
    'MusicPlayerContent.swift': 'verbatim layout/controls/output volume row',
    'CompactPlaybackControl.swift': 'verbatim native waveform; MainActor annotations only',
    'MediaProgressView.swift': 'verbatim progress styles, drag/tap rules, remaining-time toggle',
    'MarqueeLabel.swift': 'verbatim native marquee; MainActor annotation only',
    'TransitioningArtwork.swift': 'verbatim artwork flip controller/view; MainActor annotation only',
    'ArtworkPalette.swift': 'verbatim palette extraction',
    'OutputVolumeView.swift': 'verbatim expanded-player volume row',
    'ScreenStateMonitor.swift': 'MainActor; fullscreen/Mission Control/gaming detectors preserved for General',
    'LoginItem.swift': 'verbatim ServiceManagement registration; only user toggles it',
    'SettingsView.swift': 'only General + Now Playing; removed other pages/source cards/About; unsupported rows disabled in place',
    'SettingsCatalog.swift': 'two-page catalog; Valora draft notification name; same preference dictionary',
    'SettingsControls.swift': 'removed vendor brand image previews and airpods movie tiles; added explicit unavailable choice state',
    'SettingsDisplayCatalog.swift': 'verbatim display selection/hit-area catalog',
    'SettingsLocalization.swift': 'verbatim zh-Hans presentation translation',
    'SettingsNumberEditor.swift': 'verbatim inline number editor',
    'SettingsWindow.swift': 'verbatim 620x687 settings window factory',
    'TrafficLightsView.swift': 'verbatim traffic light chrome; MainActor annotation',
    'main.swift': 'verbatim entry point',
}

entries = []
def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()

def add(source: Path, dest: Path, mode: str, note: str):
    source_hash = digest(source) if source.exists() else None
    dest_hash = digest(dest) if dest.exists() else None
    if source_hash == dest_hash:
        mode = 'verbatim'
    entries.append({
        'source': str(source),
        'source_sha256': source_hash,
        'destination': str(dest),
        'destination_sha256': dest_hash,
        'mode': mode,
        'notes': note,
    })

for name in app_files:
    src = SRC / 'Sources/AlcoveRevival' / name
    dst = ROOT / 'Sources/Valora' / name
    if name == 'Verification.swift':
        add(SRC / 'Sources/AlcoveRevival/PresentationVerification.swift', dst,
            'new (harness adapted)', 'music-only synthetic checks + settings renders + read-only system media check; no production commands')
    else:
        add(src, dst, 'adapted' if name in app_notes else 'trimmed', app_notes.get(name, 'trimmed to music vertical slice'))

for name in core_files:
    add(SRC / 'Sources/ReferenceCore' / name, ROOT / 'Sources/ReferenceCore' / name,
        'adapted', 'pure model retained; explicit Sendable conformance for Swift 6 boundaries')

for name in core_tests:
    add(SRC / 'tests/ReferenceCoreTests' / name, ROOT / 'Tests/ReferenceCoreTests' / name,
        'adapted', 'module name only (ReferenceCore unchanged)')

for name in valora_tests:
    src = SRC / 'tests/AlcoveSettingsTests' / name
    dst = ROOT / 'Tests/ValoraTests' / name
    if name == 'RevivalSettingsReloadTests.swift':
        add(src, dst, 'new', 'rewritten for the two-page RevivalSettings surface')
    else:
        add(src, dst, 'adapted', 'module/suite renamed; API rename reloadPreferences; MainActor annotations')

add(SRC / 'Sources/NativeBridge/include/NativeBridge.h', ROOT / 'Sources/NativeBridge/include/NativeBridge.h',
    'new (trimmed bridge)', 'four music-only C functions: portable flag, output snapshot, set volume, set mute')
add(SRC / 'Sources/NativeBridge/NativeBridge.m', ROOT / 'Sources/NativeBridge/NativeBridge.m',
    'new (trimmed bridge)', 'CoreAudio output/volume implementations copied; battery/Bluetooth/QQ/lock-space bridges excluded')
add(SRC / 'scripts/build_media_adapter.py', ROOT / 'scripts/build_media_adapter.py',
    'adapted', 'macOS 27 minimum, explicit provenance hashes, no network')
add(SRC / 'scripts/package.py', ROOT / 'scripts/package.py',
    'adapted', 'Valora identity, new bundle ID, no vendor icon/entitlements, adapter framework + license + provenance')
add(SRC / 'scripts/build.sh', ROOT / 'scripts/build.sh', 'adapted', 'Valora product/package paths')

vendor = ROOT / 'vendor/mediaremote-adapter'
for path in sorted(vendor.rglob('*')):
    if path.is_file():
        rel = path.relative_to(vendor)
        add(SRC / 'vendor/mediaremote-adapter' / rel, path, 'verbatim', 'pinned BSD-3-Clause upstream source kept intact')

excluded_app = sorted(p.name for p in (SRC / 'Sources/AlcoveRevival').iterdir()
                      if p.is_file() and p.suffix == '.swift' and p.name not in app_files)
excluded_app += ['PresentationVerification.swift', 'SettingsVerification.swift']
excluded_core = sorted(p.name for p in (SRC / 'Sources/ReferenceCore').glob('*.swift')
                       if p.name not in core_files)
excluded_tests = sorted(str(p.relative_to(SRC)) for p in (SRC / 'tests/AlcoveSettingsTests').glob('*.swift')
                        if p.name not in valora_tests)

excluded_notes = {
    'BatteryMonitor.swift': 'battery activity out of scope',
    'BatteryNoticeView.swift': 'battery activity out of scope',
    'BrightnessController.swift': 'brightness HUD out of scope',
    'BrightnessNoticeView.swift': 'brightness HUD out of scope',
    'BrightnessServices.swift': 'brightness HUD out of scope',
    'ConnectionArrivalArtwork.swift': 'device connection activity out of scope',
    'FocusManager.swift': 'Focus integration out of scope',
    'FocusNoticeView.swift': 'Focus activity out of scope',
    'LockFrostedBackground.swift': 'lock screen out of scope',
    'LockInformationView.swift': 'lock screen out of scope',
    'LockMusicCoordinator.swift': 'lock screen music out of scope',
    'LockMusicVerification.swift': 'lock screen harness out of scope',
    'VolumeKeyMonitor.swift': 'volume-key HUD out of scope (expanded-player slider kept)',
    'VolumeNoticeController.swift': 'volume HUD out of scope',
    'VolumeNoticeView.swift': 'volume HUD out of scope',
    'PresentationVerification.swift': 'replaced by music-only Verification.swift',
    'SettingsVerification.swift': 'replaced by two-page renderer in Verification.swift',
}

excluded = []
for name in excluded_app:
    excluded.append({'source': f'Sources/AlcoveRevival/{name}', 'reason': excluded_notes.get(name, 'out of this slice')})
for name in excluded_core:
    excluded.append({'source': f'Sources/ReferenceCore/{name}', 'reason': 'belongs to an excluded product feature'})
for name in excluded_tests:
    excluded.append({'source': name, 'reason': 'tests an excluded feature or removed settings page'})
excluded.append({'source': 'Sources/AlcoveRevival/Resources/airpods-*.mp4',
                 'reason': '3D device connection movies out of scope; vendor media not redistributed'})
excluded.append({'source': 'Sources/AlcoveRevival/Resources/*.caf',
                 'reason': 'lock/battery sound effects out of scope; vendor audio not redistributed'})
excluded.append({'source': 'scripts/AppIcon.icns / AppIcon.iconset',
                 'reason': 'vendor app identity/icon not migrated; Valora has its own new identity'})
excluded.append({'source': 'Sources/AlcoveRevival/Resources/format-*.png',
                 'reason': 'vendor brand marks used only by the disabled audio-format tile; removed in favor of SF Symbol'})

report = {
    'task': 'V0001 local source migration',
    'generated_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'source_root': str(SRC),
    'source_root_read_only': True,
    'toolchain': subprocess.check_output(['swift', '--version'], text=True).strip(),
    'sdk': subprocess.check_output(['xcrun', '--sdk', 'macosx', '--show-sdk-version'], text=True).strip(),
    'entries': entries,
    'excluded': excluded,
    'entry_count': len(entries),
}
OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_text(json.dumps(report, indent=2, sort_keys=True))
print(f'{OUT} entries={len(entries)} excluded={len(excluded)}')
