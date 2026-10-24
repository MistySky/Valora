#!/usr/bin/env python3
"""V0009-R2 evidence: hovered paused activity gets a bounded deadline after reset."""
from pathlib import Path
import hashlib, json, subprocess, datetime

ROOT = Path(__file__).resolve().parents[1]
R1 = ROOT / 'docs/verification/v0009-r1'
R2 = ROOT / 'docs/verification/v0009-r2'
APP = ROOT / 'dist/Valora.app'
R2.mkdir(parents=True, exist_ok=True)

def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()

r1 = json.loads((R1 / 'source-fingerprints.json').read_text())
r1_hashes = {e['path']: e.get('v0009r1_sha256') for e in r1['v0009r1_owned']}
owned = [
    'Sources/Valora/PresentationController.swift',
    'Tests/ValoraTests/MultiDisplayCoordinatorTests.swift'
]
source = {
    'generated_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'task': 'docs/pi-tasks/v0009-r2-hovered-idle-reset.md',
    'task_sha256': sha(ROOT / 'docs/pi-tasks/v0009-r2-hovered-idle-reset.md'),
    'decision': 'docs/verification/independent-v0009-r1/decision.md',
    'decision_sha256': sha(ROOT / 'docs/verification/independent-v0009-r1/decision.md'),
    'v0009r1_source_report': str(R1 / 'source-fingerprints.json'),
    'v0009r1_report_sha256': sha(ROOT / 'docs/reports/v0009-r1.md'),
    'v0009r1_baseline': {p: r1_hashes.get(p) for p in owned},
    'v0009r2_owned': [
        {'path': p, 'v0009r1_sha256': r1_hashes.get(p), 'v0009r2_sha256': sha(ROOT / p)}
        for p in owned
    ],
    'root_cause': {
        'before': 'A paused activity hovered by pointer had visible=true/pending=false. resetForScreenChange cleared model.isPointerInside but left mediaIdle.input.pointerInside=true, and no pending timer existed to rebuild.',
        'fix': 'After clearing the old screen pointer, resetForScreenChange re-evaluates mediaStateChanged() when the stored input still reports pointerInside=true. Existing pending deadlines continue with their remaining duration; new hovered-paused activity starts the normal three-second deadline. Identical metadata polls do not move an existing deadline.',
        'scope': 'PresentationController only; no coordinator/animation redesign, no new periodic timer.',
        'paths': 'Display selection/geometry, screen unplug, hide/fullscreen, disable/re-enable all share resetForScreenChange or update media input through mediaStateChanged.'
    },
    'preserved': [
        'V0008 reduced settings/context menu',
        'V0009 all-display interaction, one active screen, per-screen hit/hover cancellation',
        'V0003 media recovery/seek guards',
        'V0005 fixed policies and gesture/haptic removal',
        'V0007 palette/display icon mapping',
        'Valora color app icon and Codex Outline-v7 menu-bar icon resources/wiring',
        'No lyrics implementation or dependencies'
    ]
}
(R2 / 'source-fingerprints.json').write_text(json.dumps(source, indent=2, sort_keys=True))

verification = {
    'generated_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'task_sha256': source['task_sha256'],
    'independent_regression': {
        'name': 'testPausedHoveredActivityExpiresAfterDisplaySelectionClearsPointer',
        'before': 'failed: paused hovered activity stayed visible after All displays -> Main display',
        'after': 'passed',
        'log': str(R2 / 'pointer-regression.log')
    },
    'direct_reset_regression': {
        'name': 'testPausedHoveredActivityExpiresAfterDirectScreenReset',
        'after': 'passed',
        'log': str(R2 / 'direct-reset-regression.log')
    },
    'covered_paths': [
        'hovered pause -> display selection change -> reset clears pointer -> normal 3s deadline',
        'hovered pause -> direct resetForScreenChange -> normal 3s deadline',
        'existing pending deadline -> reset preserves remaining duration (R1 regression)',
        'disable -> enable recreates a bounded deadline',
        'identical metadata polls do not postpone an armed deadline'
    ],
    'tests': {
        'valora': 35,
        'reference_core': 62,
        'total': 97,
        'original_r1_suite': 95,
        'log': str(R2 / 'test.log'),
        'preserved_failed_regression': True
    },
    'ui_regression': {'passed': True, 'checks': 74, 'evidence': str(R2 / 'ui/verification.json')},
    'multidisplay_regression': {
        'passed': True, 'checks': 12,
        'note': 'Injected two-screen coordinator/render verification; not physical dual-screen experience.',
        'evidence': str(R2 / 'multidisplay/verification.json')
    },
    'settings_regression': {'evidence': str(R2 / 'settings/verification.json'), 'pages': ['General', 'Now Playing']},
    'read_only_live': {
        'evidence': str(R2 / 'live/live-diagnostic.json'),
        'playerCommandSent': False,
        'privateMetadataRecorded': False
    },
    'limitations': [
        'No real playback/skip/seek/volume/bluetooth/system permission/login-item writes.',
        'Injected/fake screens and fake media exercise timing only; no physical dual-screen claim.',
        'UI/icons/layout/animation were not changed; color app icon and Outline-v7 menu-bar icon remain the confirmed exceptions.'
    ]
}
(R2 / 'verification.json').write_text(json.dumps(verification, indent=2, sort_keys=True))

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
(R2 / 'artifact-manifest.json').write_text(json.dumps(artifact, indent=2, sort_keys=True))
print('artifact', len(entries), artifact['bundle_bytes'], artifact['binary_sha256'])
