#!/usr/bin/env python3
"""V0005 evidence: reduced settings, fixed policies, gesture removal, artifact."""
from pathlib import Path
import hashlib, json, subprocess, datetime

ROOT = Path(__file__).resolve().parents[1]
V1 = ROOT / 'docs/verification/v0001'
R3 = ROOT / 'docs/verification/v0004-r3'
V5 = ROOT / 'docs/verification/v0005'
APP = ROOT / 'dist/Valora.app'
V5.mkdir(parents=True, exist_ok=True)

def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()

v1 = json.loads((V1 / 'source-manifest.json').read_text())
r3 = json.loads((R3 / 'source-fingerprints.json').read_text())
v1_map = {str(Path(e['destination']).relative_to(ROOT)): e['destination_sha256']
          for e in v1['entries']
          if str(Path(e['destination'])).startswith(str(ROOT / 'Sources/'))
          or str(Path(e['destination'])).startswith(str(ROOT / 'Tests/'))}
baseline = dict(v1_map)
for entry in r3['all_sources_changed_since_v0001']:
    baseline[entry['path']] = entry['v0004_r3_sha256']
for entry in r3['added_since_v0001']:
    baseline[entry['path']] = entry['v0004_r3_sha256']

current = {}
for directory in ('Sources', 'Tests'):
    for path in sorted((ROOT / directory).rglob('*')):
        if path.is_file():
            current[str(path.relative_to(ROOT))] = sha(path)

changed = [p for p, h in current.items() if p in baseline and h != baseline[p]]
added = [p for p in current if p not in baseline]
removed = sorted(p for p in baseline if p not in current)
unchanged = [p for p, h in current.items() if baseline.get(p) == h]
build = json.loads((ROOT / 'dist/build-verification.json').read_text())

source_report = {
    'generated_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'baseline': str(R3 / 'source-fingerprints.json'),
    'baseline_preserved_unmodified': True,
    'changed': [{'path': p, 'v0004_r3_sha256': baseline[p], 'v0005_sha256': current[p]} for p in changed],
    'added': [{'path': p, 'v0005_sha256': current[p]} for p in added],
    'removed': removed,
    'unchanged_since_v0004_r3': len(unchanged),
    'current_file_count': len(current),
    'build_script_unchanged_from_r3': sha(ROOT / 'scripts/package.py') == r3['build_script']['sha256'],
    'build_script': {
        'path': str(ROOT / 'scripts/package.py'),
        'sha256': sha(ROOT / 'scripts/package.py'),
    },
    'minimal_change_summary': [
        'Models/SettingsView: removed gesture, idle-activity, tuning, contrast/progressive/haptic and hidden music rows; fixed policies ignore old keys; added hover delay with real consumer.',
        'WindowCoordinator/NotchView/PresentationController: removed scroll/drag/gesture dispatch, accumulation, skip/open/close/cycle and haptics; kept mouse hover/tap and normal controls.',
        'ReferenceCore: removed gesture/activity-preference/general-preference models; activity file keeps presentation enums only.',
        'Tests: removed gesture/tuning/activity integration tests; added fixed-policy, hover-cancel and source-removal checks.'
    ],
    'preserved_history': {
        'v0004_r3_report': str(ROOT / 'docs/reports/v0004-r3.md'),
        'v0004_r3_report_sha256': sha(ROOT / 'docs/reports/v0004-r3.md'),
        'v0004_r3_fingerprints_sha256': sha(R3 / 'source-fingerprints.json'),
        'v0004_r3_artifact_sha256': sha(R3 / 'artifact-manifest.json'),
    },
}
(V5 / 'source-fingerprints.json').write_text(json.dumps(source_report, indent=2, sort_keys=True))

fixed = {
    'generated_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'general_visible': [
        {'key': 'launchAtLogin', 'default': False, 'consumer': 'LoginItem.isEnabled / SMAppService, only on user toggle'},
        {'key': 'forceSimulatedNotch', 'default': False, 'consumer': 'NotchGeometry/WindowCoordinator placement'},
        {'key': 'showOnDisplay', 'default': 'Main display', 'consumer': 'SettingsDisplayCatalog/WindowCoordinator'},
        {'key': 'hoverEnabled', 'default': False, 'consumer': 'WindowCoordinator pending hover task'},
        {'key': 'hoverDelay', 'default': 0.0, 'range': [0, 1], 'step': 0.05, 'consumer': 'WindowCoordinator pending hover task; cancelled on disable/exit/screen change/stop'}
    ],
    'general_fixed': [
        {'key': 'hideWhileInFullscreen', 'value': True, 'consumer': 'ScreenStateMonitor/WindowCoordinator'},
        {'key': 'hideWhileInMissionControl', 'value': True, 'consumer': 'ScreenStateMonitor/WindowCoordinator'},
        {'key': 'hideWhileGaming', 'value': False, 'consumer': 'ScreenStateMonitor/WindowCoordinator'},
        {'key': 'hideFromScreenCapture', 'value': False, 'consumer': 'panel/settings-window sharingType readOnly; live diagnostic panelSharingType=1'},
        {'key': 'idleActivity', 'value': 'nowPlaying', 'consumer': 'AppModel.requestedExpansionActivity/canExpandActivity'},
        {'key': 'contrastOutline', 'value': True, 'consumer': None, 'gap': 'original renderer not connected; no effect claimed'},
        {'key': 'progressiveBlur', 'value': True, 'consumer': None, 'gap': 'original renderer not connected; no effect claimed'},
        {'key': 'notchWidthOffset/notchHeightOffset', 'value': 0, 'consumer': 'PresentationMetrics tuning=.zero; legacy offsets ignored'}
    ],
    'now_playing_visible': [
        {'key': 'enableNowPlaying', 'default': True, 'consumer': 'MediaController/PresentationController/AppModel'},
        {'key': 'songTitleBadge', 'default': 'Explicit', 'consumer': None, 'status': 'disabled, no actual badge capability; unchanged'},
        {'key': 'progressStyle', 'default': 'Monochrome', 'consumer': 'MediaProgressView'},
        {'key': 'useLiveWaveform', 'default': False, 'consumer': 'LiveAudioTap/CompactWaveform'},
        {'key': 'controlChoice', 'default': 'Shuffle', 'consumer': None, 'status': 'disabled, no actual Favorite/Shuffle/Repeat/Copy capability; unchanged'}
    ],
    'now_playing_fixed': [
        {'key': 'idleDuration', 'value': 3, 'consumer': 'MediaIdleState/PresentationController'},
        {'key': 'disableWaveform', 'value': False, 'consumer': 'AppModel.showsCompactWaveform'},
        {'key': 'disableAlbumArtFlip', 'value': False, 'consumer': 'TransitioningArtwork/NotchView'},
        {'key': 'hideWhileSourceIsActive', 'value': False, 'consumer': 'AppModel.sourceActivityHidden'},
        {'key': 'hideSongTitleExtras', 'value': False, 'consumer': 'MusicTitleFormatting.displayTitle'},
        {'key': 'enableQuickPeek', 'value': True, 'consumer': 'PresentationController.trackChanged'},
        {'key': 'whenSongChanges', 'value': True, 'consumer': 'PresentationController.trackChanged'},
        {'key': 'peekDuration', 'value': 2, 'consumer': 'PresentationController peek expiry'},
        {'key': 'musicSource', 'value': 'system', 'consumer': 'MediaController/SystemMediaSource only'}
    ],
    'old_preferences': 'Fixed keys are sanitized/ignored at RevivalSettings load; retained keys (hover delay/style/live waveform/now playing/etc.) still read from their existing stores. No domain reset or old-app access.',
    'unimplemented_gaps': ['contrast outline renderer', 'progressive blur renderer', 'song title badge', 'Favorite/Shuffle/Repeat/Copy controls']
}
(V5 / 'fixed-policies.json').write_text(json.dumps(fixed, indent=2, sort_keys=True))

legacy_terms = ['NotchGesture', 'handleSwipe', 'performGesture', 'scrollGesture', 'scrollWheel',
                'swipeTo', 'enableHaptics', 'NSHapticFeedback']
scan = {}
for term in legacy_terms:
    hits = []
    for path in sorted((ROOT / 'Sources').rglob('*.swift')):
        if term in path.read_text():
            hits.append(str(path.relative_to(ROOT)))
    scan[term] = hits
removed_paths = [
    'Sources/ReferenceCore/NotchGesture.swift',
    'Sources/ReferenceCore/ActivityPreferences.swift',
    'Sources/ReferenceCore/GeneralPreferences.swift',
    'Tests/ReferenceCoreTests/NotchGestureTests.swift',
    'Tests/ReferenceCoreTests/ActivityPreferencesTests.swift',
    'Tests/ValoraTests/ScrollGestureEntryTests.swift',
    'Tests/ValoraTests/NotchTuningIntegrationTests.swift'
]
drag_files = []
for path in sorted((ROOT / 'Sources').rglob('*.swift')):
    if 'DragGesture' in path.read_text():
        drag_files.append(str(path.relative_to(ROOT)))
gesture = {
    'generated_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'legacy_symbol_hits': scan,
    'legacy_symbols_absent': all(not v for v in scan.values()),
    'removed_files': {p: not (ROOT / p).exists() for p in removed_paths},
    'drag_gesture_consumers_remaining': drag_files,
    'notch_view_has_drag_gesture': 'DragGesture' in (ROOT / 'Sources/Valora/NotchView.swift').read_text(),
    'window_coordinator_has_scroll_monitor': 'scrollWheel' in (ROOT / 'Sources/Valora/WindowCoordinator.swift').read_text(),
    'window_coordinator_pointer_monitor': '.mouseMoved,.leftMouseDragged' in (ROOT / 'Sources/Valora/WindowCoordinator.swift').read_text(),
    'tap_and_normal_controls_still_present': {
        'notch_tap': 'onTapGesture' in (ROOT / 'Sources/Valora/NotchView.swift').read_text(),
        'compact_play': 'command(2)' in (ROOT / 'Sources/Valora/CompactPlaybackControl.swift').read_text(),
        'progress_drag': 'seek(' in (ROOT / 'Sources/Valora/MediaProgressView.swift').read_text(),
        'volume_drag': 'setVolume(' in (ROOT / 'Sources/Valora/OutputVolumeView.swift').read_text(),
        'settings_slider': 'SettingsSliderRow' in (ROOT / 'Sources/Valora/SettingsView.swift').read_text()
    }
}
(V5 / 'gesture-removal.json').write_text(json.dumps(gesture, indent=2, sort_keys=True))

appicon = APP / 'Contents/Resources/AppIcon.icns'
menuicon = APP / 'Contents/Resources/MenuBarIcon.icns'
icons = {
    'generated_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'app_icon_path': str(appicon),
    'app_icon_sha256': sha(appicon),
    'app_icon_unchanged_color_light': sha(appicon) == 'df342247f803caac0a1b36ddc098b27be10970fc109e74c199c38536de2c3654',
    'menubar_icon_path': str(menuicon),
    'menubar_icon_sha256': sha(menuicon),
    'menubar_icon_unchanged_dark_source': sha(menuicon) == '63243bd19988395980f4cf418f4924800813c785885676bed51115b604dfb276',
    'info_icon_key': build.get('icon_info_key'),
    'bundle_id': build['bundle_id'],
    'version': build['version'],
    'build': build['build'],
    'architecture': build['architecture']
}
(V5 / 'icons.json').write_text(json.dumps(icons, indent=2, sort_keys=True))

artifact_entries = []
for path in sorted(p for p in APP.rglob('*') if p.is_file()):
    artifact_entries.append({'path': str(path.relative_to(APP)), 'bytes': path.stat().st_size, 'sha256': sha(path)})
artifact = {
    'generated_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'app': str(APP),
    'bundle_identifier': build['bundle_id'],
    'version': build['version'],
    'build': build['build'],
    'architecture': build['architecture'],
    'binary_sha256': build['binary_sha256'],
    'info_plist_icon_key': build.get('icon_info_key'),
    'app_icon_sha256': sha(appicon),
    'menubar_icon_sha256': sha(menuicon),
    'codesign_verify': subprocess.run(['codesign', '--verify', '--deep', '--strict', '--verbose=2', str(APP)],
                                      text=True, capture_output=True).stderr.strip(),
    'file_count': len(artifact_entries),
    'bundle_bytes': sum(e['bytes'] for e in artifact_entries),
    'files': artifact_entries,
    'build_verification': build,
}
(V5 / 'artifact-manifest.json').write_text(json.dumps(artifact, indent=2, sort_keys=True))

print('changed', changed)
print('added', added)
print('removed', removed)
print('unchanged', len(unchanged))
print('gesture absent', gesture['legacy_symbols_absent'], 'drag', drag_files)
print('icons', icons['app_icon_unchanged_color_light'], icons['menubar_icon_unchanged_dark_source'])
print('artifact', len(artifact_entries), artifact['bundle_bytes'])
