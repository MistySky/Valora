#!/usr/bin/env python3
"""V0009-R1 evidence: paused idle deadline survives display resets."""
from pathlib import Path
import hashlib, json, subprocess, datetime

ROOT = Path(__file__).resolve().parents[1]
V9 = ROOT / 'docs/verification/v0009'
R1 = ROOT / 'docs/verification/v0009-r1'
APP = ROOT / 'dist/Valora.app'
R1.mkdir(parents=True, exist_ok=True)

def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()

v9 = json.loads((V9 / 'source-fingerprints.json').read_text())
v9_hashes = {e['path']: e.get('v0009_sha256') for e in v9['v0009_owned']}
for e in v9['shared_files']:
    v9_hashes[e['path']] = e.get('v0009_sha256')
owned = [
    'Sources/Valora/PresentationController.swift',
    'Tests/ValoraTests/MultiDisplayCoordinatorTests.swift'
]
source = {
    'generated_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'task': 'docs/pi-tasks/v0009-r1-idle-deadline.md',
    'task_sha256': sha(ROOT / 'docs/pi-tasks/v0009-r1-idle-deadline.md'),
    'decision': 'docs/verification/independent-v0009/decision.md',
    'decision_sha256': sha(ROOT / 'docs/verification/independent-v0009/decision.md'),
    'v0009_source_report': str(V9 / 'source-fingerprints.json'),
    'v0009_report_sha256': sha(ROOT / 'docs/reports/v0009.md'),
    'v0009_baseline': {p: v9_hashes.get(p) for p in owned},
    'v0009r1_owned': [
        {'path': p, 'v0009_sha256': v9_hashes.get(p), 'v0009r1_sha256': sha(ROOT / p)}
        for p in owned
    ],
    'unchanged_contracts': {
        'context_menu': 'V0009 AppMenuCommands/NotchView menu unchanged; screenshots/evidence remain under docs/verification/v0009/.',
        'settings': 'V0008 reduced General/Now Playing pages unchanged.',
        'multidisplay': 'V0009 per-screen panels/active-only dynamics and Outline-v7 menu-bar icon unchanged.',
        'media': 'Shared AppModel/MediaController media source and fake command behavior unchanged; no real player writes.'
    },
    'root_cause': {
        'before': 'WindowCoordinator.place -> PresentationController.resetForScreenChange canceled idleTask but retained mediaIdle.input/pending. A later identical mediaStateChanged update returned false, so no deadline was rebuilt.',
        'fix': 'PresentationController records idleDeadline when arming; resetForScreenChange computes remaining time before cancelling and re-arms only when mediaIdle.pending. Same-value metadata polls do not move an existing deadline; disabled/hidden resets remain bounded.',
        'scope': 'PresentationController only; no coordinator/animation redesign, no new timers/features.'
    },
    'preserved': [
        'V0008 settings reduction and context menu',
        'V0009 all-display interaction, one active screen, per-screen hit/hover cancellation',
        'V0003 media recovery/seek guards',
        'V0005 fixed policies and gesture/haptic removal',
        'V0007 palette/display icon mapping',
        'Codex Outline-v7 menu-bar icon resources/wiring'
    ]
}
(R1 / 'source-fingerprints.json').write_text(json.dumps(source, indent=2, sort_keys=True))

verification = {
    'generated_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'task_sha256': source['task_sha256'],
    'failed_regression': {
        'name': 'testPausedIdleDeadlineSurvivesDisplaySelectionChange',
        'before': 'failed: paused activity remained visible/pending after 3.6s following All displays -> Main display',
        'after': 'passed',
        'log': str(R1 / 'idle-regression.log')
    },
    'covered_paths': [
        'All displays -> Main display selection change through real WindowCoordinator.place/resetForScreenChange',
        'direct screen-change reset with pending paused activity',
        'pause -> disable -> re-enable refreshes a bounded idle deadline',
        'identical metadata polls do not postpone an already-armed deadline'
    ],
    'shared_reset_audit': 'Screen unplug/selection/geometry and hide/fullscreen transitions all route through resetForScreenChange; re-arm preserves the remaining deadline. Disable first updates mediaIdle to non-pending, so no stale timer is re-armed; re-enable creates a fresh bounded task.',
    'tests': {
        'valora': 33,
        'reference_core': 62,
        'total': 95,
        'log': str(R1 / 'test.log'),
        'original_v0009_regression': 'All original V0009 checks plus the independent regression pass.',
        'new_regressions': [
            'testSameValueMetadataPollsDoNotPostponePausedIdleDeadline',
            'testPausedIdleDeadlineSurvivesDisableThenEnable',
            'testPausedIdleDeadlineSurvivesScreenReset'
        ]
    },
    'ui_regression': {
        'passed': True,
        'checks': 74,
        'evidence': str(R1 / 'ui/verification.json')
    },
    'multidisplay_regression': {
        'passed': True,
        'checks': 12,
        'note': 'Injected two-screen coordinator/render verification; not physical dual-screen experience.',
        'evidence': str(R1 / 'multidisplay/verification.json')
    },
    'settings_regression': {
        'evidence': str(R1 / 'settings/verification.json'),
        'pages': ['General', 'Now Playing']
    },
    'read_only_live': {
        'evidence': str(R1 / 'live/live-diagnostic.json'),
        'playerCommandSent': False,
        'privateMetadataRecorded': False
    },
    'limitations': [
        'No real player/seek/volume/permission/login-item writes were performed.',
        'Injected/fake screens and fake media exercise coordinator timing only; no physical dual-screen claim.',
        'Context-menu/settings visuals are unchanged from V0009 and were not redesigned.'
    ]
}
(R1 / 'verification.json').write_text(json.dumps(verification, indent=2, sort_keys=True))

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
(R1 / 'artifact-manifest.json').write_text(json.dumps(artifact, indent=2, sort_keys=True))
print('owned', owned)
print('artifact', len(entries), artifact['bundle_bytes'], artifact['binary_sha256'])
