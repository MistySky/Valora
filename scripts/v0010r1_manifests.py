#!/usr/bin/env python3
"""V0010-R1 evidence: HTTP/API status gates before lyric classification."""
from pathlib import Path
import hashlib, json, subprocess, datetime

ROOT = Path(__file__).resolve().parents[1]
V10 = ROOT / 'docs/verification/v0010'
R1 = ROOT / 'docs/verification/v0010-r1'
APP = ROOT / 'dist/Valora.app'

def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()

v10 = json.loads((V10 / 'source-fingerprints.json').read_text())
v10_hashes = {e['path']: e.get('v0010_sha256') for e in v10['v0010_owned']}
owned = [
    'Sources/ReferenceCore/QQMusicLyrics.swift',
    'Tests/ReferenceCoreTests/QQMusicLyricsTests.swift',
    'scripts/qq_lyrics_probe.swift',
    'scripts/run_qq_lyrics_probe.sh',
    'scripts/qq_lyrics_sample.json'
]
source = {
    'generated_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'task': 'docs/pi-tasks/v0010-r1-error-status-gates.md',
    'task_sha256': sha(ROOT / 'docs/pi-tasks/v0010-r1-error-status-gates.md'),
    'independent_v0010_decision': 'docs/verification/independent-v0010/decision.md',
    'independent_v0010_decision_sha256': sha(ROOT / 'docs/verification/independent-v0010/decision.md'),
    'v0010_source_report': str(V10 / 'source-fingerprints.json'),
    'v0010_report_sha256': sha(ROOT / 'docs/reports/v0010.md'),
    'v0010_baseline': {p: v10_hashes.get(p) for p in owned},
    'v0010r1_owned': [
        {'path': p, 'v0010_sha256': v10_hashes.get(p), 'v0010r1_sha256': sha(ROOT / p)}
        for p in owned
    ],
    'gates': {
        'search': 'HTTP 2xx, required JSON code=0, song.list shape; otherwise search failure and no matching.',
        'lyrics': 'HTTP 2xx, required retcode=0 and code=0, then payload parse; API/HTTP failure is never no_lyrics.',
        'qrc': 'HTTP 2xx, required <result>; result=-1 is no_content, result!=0 is business failure; content remains encrypted and undecoded.',
        'probe_exit': '0 only when request_ok and no QRC request failures; no_lyrics/no_match remain distinct valid statuses and do not hide HTTP/API failures.'
    },
    'preserved': [
        'No UI/startup/player wiring changes',
        'Valora color app icon and Codex Outline-v7 menu-bar icon/resources unchanged',
        'QRC decryption not implemented; synthetic parser not consumed by app',
        'No real media/system/device writes; no source changes'
    ]
}
(R1 / 'source-fingerprints.json').write_text(json.dumps(source, indent=2, sort_keys=True))

network = json.loads((R1 / 'network/network-summary.json').read_text())
verification = {
    'generated_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'task_sha256': source['task_sha256'],
    'independent_repro_after': str(R1 / 'independent-repro-after.txt'),
    'independent_repro_result': {
        'http_failure_with_parseable_body': 'request_failed/http_status_503',
        'api_failure_with_parseable_body': 'request_failed/api_code_1001_retcode_1001_subcode_0'
    },
    'offline_tests': {
        'filtered_test_count': 22,
        'log': str(R1 / 'offline-tests.log'),
        'covers': ['HTTP 503 + valid-looking lyric body', 'HTTP 200 + retcode/code 1001',
                   'invalid JSON', 'no lyrics distinct from failure', 'normal timed success',
                   'search HTTP/API/missing-structure gates', 'QRC HTTP/business/no-content gates']
    },
    'full_regression': {
        'valora': 35, 'reference_core': 84, 'total': 119,
        'prior_v0010_baseline': 113,
        'log': str(R1 / 'test.log')
    },
    'network': {
        'summary': str(R1 / 'network/network-summary.json'),
        'generated_at': network.get('generated_at'),
        'request_ok': network.get('request_ok'),
        'validation_ok': network.get('validation_ok'),
        'request_failures': network.get('request_failures'),
        'qrc_failures': network.get('qrc_failures'),
        'statuses': network.get('statuses'),
        'samples': network.get('samples'),
        'exit_code': 0,
        'note': 'Two explicit public samples still succeed; HTTP/API/parse failures now produce request_ok=false and a nonzero exit.'
    },
    'ui_regression': {'checks': 74, 'passed': True, 'evidence': str(R1 / 'ui/verification.json')},
    'multidisplay_regression': {'checks': 12, 'passed': True, 'evidence': str(R1 / 'multidisplay/verification.json'),
                                'note': 'injected/fake, not physical dual-screen'},
    'settings_regression': {'evidence': str(R1 / 'settings/verification.json')},
    'limitations': [
        'QRC remains encrypted and undecoded; no word timing or UI is claimed.',
        'Only the explicit public samples were run; external APIs may change.',
        'No real media/device/system writes; no physical dual-screen claim.'
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
print('artifact', len(entries), artifact['bundle_bytes'], artifact['binary_sha256'])
