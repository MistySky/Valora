#!/usr/bin/env python3
"""V0010 evidence: public QQ lyrics probe, parser/matcher, and unchanged app candidate."""
from pathlib import Path
import hashlib, json, subprocess, datetime

ROOT = Path(__file__).resolve().parents[1]
V9R2 = ROOT / 'docs/verification/v0009-r2'
V10 = ROOT / 'docs/verification/v0010'
APP = ROOT / 'dist/Valora.app'

def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()

v9r2 = json.loads((V9R2 / 'source-fingerprints.json').read_text())
v9r2_hashes = {e['path']: e.get('v0009r2_sha256') for e in v9r2['v0009r2_owned']}
owned = [
    'Sources/ReferenceCore/QQMusicLyrics.swift',
    'Tests/ReferenceCoreTests/QQMusicLyricsTests.swift',
    'scripts/qq_lyrics_probe.swift',
    'scripts/run_qq_lyrics_probe.sh',
    'scripts/qq_lyrics_sample.json'
]
source = {
    'generated_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'task': 'docs/pi-tasks/v0010-qq-lyrics-probe.md',
    'task_sha256': sha(ROOT / 'docs/pi-tasks/v0010-qq-lyrics-probe.md'),
    'continuation_plan_sha256': sha(ROOT / 'docs/CONTINUATION-PLAN.md'),
    'independent_v0009r2_decision_sha256': sha(ROOT / 'docs/verification/independent-v0009-r2/decision.md'),
    'v0009r2_report_sha256': sha(ROOT / 'docs/reports/v0009-r2.md'),
    'v0009r2_source_report': str(V9R2 / 'source-fingerprints.json'),
    'v0010_owned': [
        {'path': p, 'v0009r2_sha256': v9r2_hashes.get(p), 'v0010_sha256': sha(ROOT / p)}
        for p in owned
    ],
    'no_ui_or_startup_wiring': [
        'Package.swift unchanged',
        'AppDelegate.swift unchanged',
        'NotchView.swift unchanged',
        'SettingsView.swift unchanged',
        'WindowCoordinator.swift unchanged',
        'menu-bar icon resources and package.py icon configuration unchanged'
    ],
    'reference_licenses': {
        'LyricsKit': 'MPL-2.0; protocol reference only, no source copied',
        'Lyrimuse': 'GPL-3.0; protocol observation only, no Go/source copied; local QQ database not read',
        'probe': 'original Swift 6 URLSession implementation'
    },
    'scope': {
        'network': 'manual explicit public samples only; no current player, account, cookie, local library or private credential',
        'qrc': 'encrypted content observed but not decoded; no word timing claimed',
        'ui': 'not connected to app startup, settings, player or QuickPeek'
    }
}
(V10 / 'source-fingerprints.json').write_text(json.dumps(source, indent=2, sort_keys=True))

verification = {
    'generated_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'task_sha256': source['task_sha256'],
    'network_probe': {
        'run_at_utc': json.loads((V10 / 'network/network-summary.json').read_text())['generated_at'],
        'command': './scripts/run_qq_lyrics_probe.sh docs/verification/v0010/network',
        'cookies_enabled': False,
        'retry_count': 0,
        'timeout_seconds': 10,
        'summary': str(V10 / 'network/network-summary.json'),
        'samples': ['晴天 / 周杰伦 / 叶惠美 / 269s', '晴天 (Live) / 周杰伦 / 周杰伦地表最强世界巡回演唱会 / 249s'],
        'result': 'Both explicit samples matched by title, artist, album and duration; timed LRC responses had 63 and 36 lines. QRC content was present as encrypted HEX and was not claimed decoded.'
    },
    'offline': {
        'command': 'swift test --filter QQMusicLyricsTests',
        'test_count': 16,
        'log': str(V10 / 'test.log'),
        'fixtures': 'synthetic LRC/search JSON/QRC strings; no network dependency'
    },
    'full_regression': {
        'valora': 35, 'reference_core': 78, 'total': 113,
        'prior_baseline': 97,
        'log': str(V10 / 'test.log')
    },
    'ui_regression': {'checks': 74, 'passed': True, 'evidence': str(V10 / 'ui/verification.json')},
    'multidisplay_regression': {'checks': 12, 'passed': True, 'evidence': str(V10 / 'multidisplay/verification.json'),
                                'note': 'injected screens/fake media; not physical dual-screen'},
    'settings_regression': {'evidence': str(V10 / 'settings/verification.json')},
    'qrc': {
        'decoded': False,
        'reason': 'lyric_download.fcg returned result=0 with HEX content, but decryption/word timing was not implemented or claimed',
        'next_step': str(V10 / 'qrc-next-step.md')
    },
    'limitations': [
        'QQ interfaces are external and may change; only these public samples were tested.',
        'No real media playback/control or system writes were performed.',
        'No physical dual-screen or UI lyrics integration is claimed.',
        'QRC word-level lyrics remain unverified and are not UI-connected.'
    ]
}
(V10 / 'verification.json').write_text(json.dumps(verification, indent=2, sort_keys=True))

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
(V10 / 'artifact-manifest.json').write_text(json.dumps(artifact, indent=2, sort_keys=True))
print('artifact', len(entries), artifact['bundle_bytes'], artifact['binary_sha256'])
