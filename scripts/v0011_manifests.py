#!/usr/bin/env python3
"""V0011 evidence: compact line lyrics, sync state, and isolated QA."""
from pathlib import Path
import hashlib, json, subprocess, datetime

ROOT = Path(__file__).resolve().parents[1]
V10R1 = ROOT / 'docs/verification/v0010-r1'
V11 = ROOT / 'docs/verification/v0011'
APP = ROOT / 'dist/Valora.app'

def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()

owned = [
    'Sources/ReferenceCore/LyricsTimeline.swift',
    'Sources/ReferenceCore/QQMusicLyrics.swift',
    'Sources/ReferenceCore/MusicPreferences.swift',
    'Sources/Valora/LyricsService.swift',
    'Sources/Valora/LyricsController.swift',
    'Sources/Valora/CompactLyricsView.swift',
    'Sources/Valora/LyricsVerification.swift',
    'Sources/Valora/Models.swift',
    'Sources/Valora/NotchView.swift',
    'Sources/Valora/MarqueeLabel.swift',
    'Sources/Valora/SettingsView.swift',
    'Sources/Valora/SettingsLocalization.swift',
    'Sources/Valora/AppDelegate.swift',
    'Sources/Valora/AppRuntimeDefaults.swift',
    'Sources/Valora/Controllers.swift',
    'Sources/Valora/Verification.swift',
    'Tests/ReferenceCoreTests/LyricsTimelineTests.swift',
    'Tests/ValoraTests/LyricsServiceTests.swift',
    'Tests/ValoraTests/MultiDisplayCoordinatorTests.swift',
    'Tests/ValoraTests/RevivalSettingsReloadTests.swift',
    'Tests/ValoraTests/SettingsReductionTests.swift'
]
source = {
    'generated_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'task': 'docs/pi-tasks/v0011-line-lyrics-display-sync.md',
    'task_sha256': sha(ROOT / 'docs/pi-tasks/v0011-line-lyrics-display-sync.md'),
    'resume_task': 'docs/pi-tasks/v0011-resume-01.md',
    'resume_task_sha256': sha(ROOT / 'docs/pi-tasks/v0011-resume-01.md'),
    'continuation_plan_sha256': sha(ROOT / 'docs/CONTINUATION-PLAN.md'),
    'v0010r1_decision_sha256': sha(ROOT / 'docs/verification/independent-v0010-r1/decision.md'),
    'v0010r1_report_sha256': sha(ROOT / 'docs/reports/v0010-r1.md'),
    'v0010r1_source_report': str(V10R1 / 'source-fingerprints.json'),
    'v0011_owned': [
        {'path': p, 'v0011_sha256': sha(ROOT / p)} for p in owned
    ],
    'scope': {
        'ui': 'compact 32pt QuickPeek row on the active screen only; expanded player unchanged',
        'settings': 'one Show lyrics toggle, default off; existing General/Now Playing pages retained',
        'service': 'URLSession Swift 6 actor with V0010-R1 evaluators; no scripts, Go, QRC, local QQ database or account',
        'sync': 'current model.elapsed/playing state; no independent accumulated clock',
        'word_timing': 'QRC encrypted/undecoded; no synthetic per-word highlight'
    },
    'preserved': [
        'V0008 reduced settings and context menu',
        'V0009 per-screen active ownership and one expanded panel',
        'V0003 media recovery/seek guards',
        'V0005 fixed policies and gesture removal',
        'V0007 palette/display icon mapping',
        'Valora color app icon and Outline-v7 menu bar resources/wiring'
    ]
}
(V11 / 'source-fingerprints.json').write_text(json.dumps(source, indent=2, sort_keys=True))

qa = json.loads((V11 / 'qa/verification.json').read_text())
ui = json.loads((V11 / 'ui/verification.json').read_text())
multi = json.loads((V11 / 'multidisplay/verification.json').read_text())
settings = json.loads((V11 / 'settings/verification.json').read_text())
verification = {
    'generated_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'task_sha256': source['task_sha256'],
    'xctest': {
        'valora': 47,
        'reference_core': 89,
        'total': 136,
        'prior_v0010r1_baseline': 119,
        'log': str(V11 / 'test.log')
    },
    'lyrics_qa': {
        'passed': qa.get('passed'),
        'checks': len(qa.get('checks', [])),
        'provider': qa.get('provider'),
        'screens': [
            'lyrics-short.png', 'lyrics-long.png', 'lyrics-paused.png',
            'lyrics-resumed.png', 'lyrics-seek.png', 'lyrics-interstitial.png',
            'lyrics-fallback.png', 'lyrics-song-peek-priority.png',
            'lyrics-after-peek.png', 'lyrics-active-external.png',
            'lyrics-passive-builtin.png'
        ],
        'command': './dist/Valora.app/Contents/MacOS/Valora --verify-lyrics docs/verification/v0011/qa',
        'log': str(V11 / 'qa.log'),
        'evidence': str(V11 / 'qa/verification.json')
    },
    'music_ui': {'passed': ui.get('passed'), 'checks': len(ui.get('checks', [])), 'evidence': str(V11 / 'ui/verification.json')},
    'multidisplay': {'passed': multi.get('passed'), 'checks': len(multi.get('checks', [])), 'evidence': str(V11 / 'multidisplay/verification.json'),
                     'note': 'injected/fake screens; not physical dual-screen'},
    'settings': {'preferencePersistenceVerified': settings.get('preferencePersistenceVerified'),
                 'pages': settings.get('renderedPages'), 'evidence': str(V11 / 'settings/verification.json')},
    'limitations': [
        'Lyrics QA uses a static provider and synthetic elapsed positions; no real QQ network fetch or real player alignment is claimed.',
        'QRC remains encrypted/undecoded; no word-level highlighting.',
        'Physical dual-screen and real playback/skip/seek behavior remain locally unverified in this batch.',
        'No real media/system/device writes were performed.'
    ]
}
(V11 / 'verification.json').write_text(json.dumps(verification, indent=2, sort_keys=True))

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
(V11 / 'artifact-manifest.json').write_text(json.dumps(artifact, indent=2, sort_keys=True))
print('owned', len(owned), 'artifact', len(entries), artifact['bundle_bytes'], artifact['binary_sha256'])
