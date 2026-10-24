#!/usr/bin/env python3
"""V0009 evidence: multi-display interaction and corrected notch context menu."""
from pathlib import Path
import hashlib, json, subprocess, datetime

ROOT = Path(__file__).resolve().parents[1]
V8 = ROOT / 'docs/verification/v0008'
V9 = ROOT / 'docs/verification/v0009'
APP = ROOT / 'dist/Valora.app'
V9.mkdir(parents=True, exist_ok=True)

def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()

owned = [
    'Sources/Valora/WindowCoordinator.swift',
    'Sources/Valora/Models.swift',
    'Sources/Valora/PresentationController.swift',
    'Sources/Valora/NotchView.swift',
    'Sources/Valora/MediaProgressView.swift',
    'Sources/Valora/OutputVolumeView.swift',
    'Sources/Valora/Controllers.swift',
    'Sources/Valora/AppMenuCommands.swift',
    'Sources/Valora/MultiDisplayVerification.swift',
    'Sources/Valora/AppRuntimeDefaults.swift',
    'Sources/Valora/Verification.swift',
    'Tests/ValoraTests/MultiDisplayCoordinatorTests.swift',
    'Tests/ValoraTests/MediaControllerRecoveryTests.swift'
]
shared = ['Sources/Valora/AppDelegate.swift']
v8 = json.loads((V8 / 'source-fingerprints.json').read_text())
v8_hashes = {e['path']: e.get('v0008_sha256') for e in v8['v0008_owned']}
for e in v8['shared_files']:
    v8_hashes[e['path']] = e.get('v0008_sha256')
source = {
    'generated_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'task': 'docs/pi-tasks/v0009-multidisplay-active-interaction.md',
    'task_sha256': sha(ROOT / 'docs/pi-tasks/v0009-multidisplay-active-interaction.md'),
    'v0008_source_report': str(V8 / 'source-fingerprints.json'),
    'v0008_report_sha256': sha(ROOT / 'docs/reports/v0008.md'),
    'user_authorization': 'User approved: all enabled displays may be operated; dynamic playback presentation follows the screen being operated. Not claimed as the original Alcove default.',
    'v0009_owned': [
        {'path': p, 'v0008_sha256': v8_hashes.get(p), 'v0009_sha256': sha(ROOT / p)}
        for p in owned
    ],
    'shared_files': [
        {'path': p, 'v0009_sha256': sha(ROOT / p),
         'note': 'Contains concurrent Codex menu-bar icon wiring; V0009 did not modify statusBarImage, package.py icon config, MenuBarIconVerification or Resources/MenuBarIcon-*.'}
        for p in shared
    ],
    'state_ownership': {
        'shared_media': 'AppModel.media/title/artist/album/artwork/playing/elapsed/duration/output; MediaController and SystemMediaSource remain single instances.',
        'per_screen': 'WindowCoordinator.ScreenPanel owns its DisplayDescriptor, NSPanel, NotchGeometry, pointerInside, pendingHover and hoverGeneration.',
        'active_screen': 'WindowCoordinator.active selects the only full NotchView; other enabled panels render compactOnly with fixed geometryOverride.',
        'expanded': 'AppModel.presentation.expanded remains the one visual transition for the active panel; switching active collapses first, then activates the new panel.',
        'hit_testing': 'DisplayDescriptor frames (including negative origins) + per-screen geometry/localContour; containsMouse is a pure static seam tested with injected coordinates.',
        'hover_cancel': 'Per-panel DispatchWorkItem is generation-guarded and cancelled on pointer exit, activation, display selection/place, disable/hide and deinit.',
        'peek_target': 'MediaController.updateSongPeek -> AppModel.trackChangedHandler -> WindowCoordinator.handleTrackChanged -> peekTarget (active pointer, pointer screen, then active fallback).',
        'drag_ownership': 'AppModel.pointerInteractionActive is set by progress/volume drag begin and cleared on end/cancel; WindowCoordinator refuses activation while set.',
        'multi_display_peek': 'AppModel.allowsMultiDisplayDynamic is true only for multiple enabled all-display panels; it permits the existing peek path on an external pill without changing single-display policy.',
        'context_menu': 'AppMenuCommands shared wording/shortcuts; NotchView contextMenu renders disabled version, Settings…, separator, Quit Valora; actions reuse showSettings/quit.'
    },
    'context_menu': {
        'source': 'NotchView.settingsMenuItem on outer compact ZStack and expanded content',
        'commands': 'AppMenuCommands.versionText/settingsTitle/quitTitle/settingsKey/quitKey',
        'settings_action': 'AppDelegate.showSettings reuses the existing settingsWindow',
        'quit_action': 'AppDelegate.quit via model.quitAction; not executed in verification',
        'no_extra_items': True
    },
    'preserved': [
        'V0005 fixed policies and gesture/haptic removal',
        'V0007 settings palette and display icon mapping',
        'V0003 media recovery and finite seek guards',
        'single-screen expanded/compact/artwork flip/waveform/marquee/volume behavior',
        'menu-bar playback/display items (not copied into the notch menu)'
    ]
}
(V9 / 'source-fingerprints.json').write_text(json.dumps(source, indent=2, sort_keys=True))

context = {
    'generated_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'reference': str(V9 / 'reference/original-notch-context-menu.png'),
    'expected_items': ['disabled 版本 <current Valora version>', '设置… ⌘,', 'separator', '退出 Valora ⌘Q'],
    'compact_actual': {
        'tested': True,
        'method': 'CGEvent right click on the real compact external-pill panel; menu captured on screen',
        'screenshot': str(V9 / 'context-menu/compact-menu.png'),
        'version_text': '版本 0.1.0',
        'items_match': True
    },
    'expanded_actual': {
        'tested': True,
        'method': 'CGEvent right click inside the real --expand-media expanded panel; menu captured on screen',
        'screenshot': str(V9 / 'context-menu/expanded-menu.png'),
        'items_match': True
    },
    'settings_actual': {
        'tested': True,
        'screenshot': str(V9 / 'context-menu/settings-reused.png'),
        'opened_window_title': '通用',
        'window_points': [620, 687],
        'reuse_test': 'SettingsReductionTests.testExistingSettingsWindowIsReused'
    },
    'quit_actual': {
        'tested': False,
        'note': 'Deliberately not clicked; quit action reused, and verification must not close the user candidate.'
    },
    'no_new_popup_or_icon': True,
    'outside_shape_passthrough_unchanged': True
}
(V9 / 'context-menu-verification.json').write_text(json.dumps(context, indent=2, sort_keys=True))

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
(V9 / 'artifact-manifest.json').write_text(json.dumps(artifact, indent=2, sort_keys=True))
print('owned', len(owned), 'shared', shared)
print('artifact', len(entries), artifact['bundle_bytes'], artifact['binary_sha256'])
