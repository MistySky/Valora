#!/usr/bin/env python3
"""V0008 evidence: extra-control removal, notch context menu, final artifact."""
from pathlib import Path
import hashlib, json, subprocess, datetime

ROOT = Path(__file__).resolve().parents[1]
V7 = ROOT / 'docs/verification/v0007'
V8 = ROOT / 'docs/verification/v0008'
APP = ROOT / 'dist/Valora.app'
V8.mkdir(parents=True, exist_ok=True)

def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()

owned = [
    'Sources/ReferenceCore/SystemMediaSnapshot.swift',
    'Sources/Valora/SettingsView.swift',
    'Sources/Valora/SettingsControls.swift',
    'Sources/Valora/SettingsLocalization.swift',
    'Sources/Valora/MusicPlayerContent.swift',
    'Sources/Valora/Models.swift',
    'Sources/Valora/Controllers.swift',
    'Sources/Valora/NotchView.swift',
    'Tests/ValoraTests/SettingsReductionTests.swift',
    'Tests/ValoraTests/MediaControllerRecoveryTests.swift',
    'Tests/ReferenceCoreTests/SystemMediaSnapshotTests.swift'
]
shared = ['Sources/Valora/AppDelegate.swift', 'Sources/Valora/Verification.swift']
v7 = json.loads((V7 / 'source-fingerprints.json').read_text())
v7_hashes = {e['path']: e.get('v0007_sha256') for e in v7['v0007_owned']}
for e in v7['shared_files']:
    v7_hashes[e['path']] = e.get('v0007_sha256')
source = {
    'generated_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'v0007_source_report': str(V7 / 'source-fingerprints.json'),
    'v0007_report_sha256': sha(ROOT / 'docs/reports/v0007.md'),
    'v0008_owned': [
        {'path': p, 'v0007_sha256': v7_hashes.get(p), 'v0008_sha256': sha(ROOT / p)}
        for p in owned
    ],
    'shared_files': [
        {'path': p, 'v0008_sha256': sha(ROOT / p),
         'note': 'Also contains concurrent Codex menu-icon work; V0008 did not modify statusBarImage/package.py icon config/MenuBarIconVerification.'}
        for p in shared
    ],
    'removed_dedicated_chain': [
        'SettingsView: whole Favorite/Shuffle/Repeat/Copy choices group and controlChoice binding',
        'RevivalSettings: controlChoice storage/sanitization',
        'MusicPlayerContent: extraControl button and controlChoice branch',
        'AppModel: shuffleMode/repeatMode fields',
        'MediaController: shuffle/repeat snapshot fields, clear/reset and send 6/7 command path',
        'SystemMediaSnapshot: shuffleMode/repeatMode parsing',
        'MediaControllerRecoveryTests: shuffle/repeat command test',
        'SystemMediaSnapshotTests: shuffle/repeat mode test',
        'SettingsReductionTests: controlChoice/consumer assertions',
        'SettingsVerification: Repeat-selected capture and controlChoice mutation',
        'SettingsControls/Localization: Favorite preview cycle and resting labels'
    ],
    'context_menu': {
        'notch_view': 'Sources/Valora/NotchView.swift outer ZStack .contextMenu { Button("设置…") { model.showSettingsAction?() } }',
        'callback': 'Sources/Valora/AppDelegate.swift model.showSettingsAction = { [weak self] in self?.showSettings() }',
        'shared_window': 'AppDelegate.showSettings reuses SettingsWindowFactory window if settingsWindow != nil',
        'scope': 'outer ZStack and expanded content share settingsMenuItem; secondary compact panels use the same NotchView'
    },
    'preserved': [
        'General: launch at login, force simulated notch, display on, hover toggle/conditional delay',
        'Now Playing: master toggle, progress style, live waveform',
        'play/pause, previous/next, progress seek drag, volume/output, media read, artwork flip, QuickPeek, pause/resume grace',
        'V0005 fixed defaults and gesture/haptic removal; V0007 colors and display icon mapping'
    ]
}
(V8 / 'source-fingerprints.json').write_text(json.dumps(source, indent=2, sort_keys=True))

settings = {
    'generated_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'visible': {
        'General': ['Launch at login','Force simulated notch','Display on','Expand on hover'],
        'General conditional': ['Hover delay only when Expand on hover is enabled'],
        'Now Playing': ['Now Playing','Progress style','Use live waveform']
    },
    'removed': ['title badge group (user addendum)','Favorite/Shuffle/Repeat/Copy extra controls group'],
    'fixed': 'V0005 fixed policies remain; no new fixed rows or placeholders.',
    'title_badge': 'removed; no key consumer or placeholder',
    'extra_controls': 'removed; no controlChoice, shuffleMode/repeatMode, send 6/7, extra player button or dedicated tests',
    'gaps': ['contrast outline / progressive blur renderers remain unsupported (previously disclosed)','no fabricated explicit/format data','no real player control verification executed']
}
(V8 / 'settings-final.json').write_text(json.dumps(settings, indent=2, sort_keys=True))

context = {
    'generated_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'compact_actual': {
        'tested': True,
        'method': 'CGEvent right click at physical notch compact panel, menu visible',
        'screenshot': str(V8 / 'context-menu-compact.png'),
        'menu_item': '设置…',
        'opened_settings_window_title': '通用',
        'settings_window_points': [620,687],
        'settings_window_number_first': 13378,
        'repeat_open_window_count': 1,
        'repeat_reused_same_window': True
    },
    'expanded_actual': {
        'tested': False,
        'note': 'The same outer SwiftUI contextMenu covers expanded content; automated synthetic expanded-right-click did not reliably reach the non-activating panel and was not claimed as a real-screen success.'
    },
    'settings_window_reuse_test': 'SettingsReductionTests.testExistingSettingsWindowIsReused',
    'no_global_mouse_interceptor_added': True,
    'outside_shape_passthrough_unchanged': True,
    'source_scope': 'NotchView outer ZStack shared by compact and expanded; secondary panels use same view'
}
(V8 / 'context-menu-verification.json').write_text(json.dumps(context, indent=2, sort_keys=True))

build = json.loads((ROOT / 'dist/build-verification.json').read_text())
entries = []
for path in sorted(p for p in APP.rglob('*') if p.is_file()):
    entries.append({'path': str(path.relative_to(APP)), 'bytes': path.stat().st_size, 'sha256': sha(path)})
artifact = {
    'generated_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'app': str(APP), 'bundle_identifier': build['bundle_id'],
    'version': build['version'], 'build': build['build'], 'architecture': build['architecture'],
    'binary_sha256': build['binary_sha256'],
    'info_plist_icon_key': build.get('icon_info_key'),
    'app_icon_sha256': sha(APP / 'Contents/Resources/AppIcon.icns'),
    'menubar_icon_files': {p.name: sha(p) for p in sorted((APP / 'Contents/Resources').glob('MenuBarIcon*'))},
    'codesign_verify': subprocess.run(['codesign','--verify','--deep','--strict','--verbose=2',str(APP)],
                                      text=True, capture_output=True).stderr.strip(),
    'file_count': len(entries), 'bundle_bytes': sum(e['bytes'] for e in entries),
    'files': entries, 'build_verification': build
}
(V8 / 'artifact-manifest.json').write_text(json.dumps(artifact, indent=2, sort_keys=True))
print('owned', len(owned), 'shared', shared)
print('artifact', len(entries), artifact['bundle_bytes'], artifact['binary_sha256'])
