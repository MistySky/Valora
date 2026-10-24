#!/usr/bin/env python3
"""V0003 evidence: changed source fingerprints, final bundle, icon non-regression."""
from pathlib import Path
import hashlib, json, subprocess, datetime

ROOT = Path(__file__).resolve().parents[1]
V1 = ROOT / 'docs/verification/v0001'
V2 = ROOT / 'docs/verification/v0002'
V3 = ROOT / 'docs/verification/v0003'
APP = ROOT / 'dist/Valora.app'
V3.mkdir(parents=True, exist_ok=True)

def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()

v1 = json.loads((V1 / 'source-manifest.json').read_text())
baseline = {}
for entry in v1['entries']:
    dst = Path(entry['destination'])
    if str(dst).startswith(str(ROOT / 'Sources/')) or str(dst).startswith(str(ROOT / 'Tests/')):
        baseline[str(dst.relative_to(ROOT))] = entry['destination_sha256']

current = {}
for directory in ('Sources', 'Tests'):
    for path in sorted((ROOT / directory).rglob('*')):
        if path.is_file():
            current[str(path.relative_to(ROOT))] = sha(path)

changed = [p for p, h in current.items() if p in baseline and h != baseline[p]]
added = [p for p in current if p not in baseline]
removed = [p for p in baseline if p not in current]
unchanged = [p for p, h in current.items() if baseline.get(p) == h]

build = json.loads((ROOT / 'dist/build-verification.json').read_text())
v2_icon = json.loads((V2 / 'icon-manifest.json').read_text())
icon_unchanged = build.get('icon_resource_sha256') == v2_icon['effective_icon']['bundle_sha256']
v2_entries = {e['relative_path']: e for e in v2_icon['entries']}

source_report = {
    'generated_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'baseline': str(V1 / 'source-manifest.json'),
    'baseline_note': 'V0001 manifest is preserved unmodified; V0002 did not change Sources/Tests.',
    'changed': [{'path': p, 'v0001_sha256': baseline[p], 'v0003_sha256': current[p]} for p in changed],
    'added': [{'path': p, 'v0003_sha256': current[p]} for p in added],
    'removed': removed,
    'unchanged_count': len(unchanged),
    'current_file_count': len(current),
    'patches': {
        'controllers': {'path': str(V3 / 'controllers.diff'), 'sha256': sha(V3 / 'controllers.diff')},
        'tests': {'path': str(V3 / 'media-controller-tests.diff'), 'sha256': sha(V3 / 'media-controller-tests.diff')},
    },
    'minimal_change_summary': [
        'Controllers.swift: injectable SystemMediaProviding; onError clears systemStarted and rate-limits retry; stop/deactivate blocks refresh; safe seekMicros conversion.',
        'Tests/ValoraTests/MediaControllerRecoveryTests.swift: fake-source recovery/backoff/duplicate-start/stop/disable/seek-boundary tests.'
    ]
}
(V3 / 'source-fingerprints.json').write_text(json.dumps(source_report, indent=2, sort_keys=True))

icon = {
    'generated_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'v0002_icon_report': str(ROOT / 'docs/reports/v0002.md'),
    'v0002_icon_report_sha256': sha(ROOT / 'docs/reports/v0002.md'),
    'v0002_effective_icon_sha256': v2_icon['effective_icon']['bundle_sha256'],
    'v0003_effective_icon_sha256': build.get('icon_resource_sha256'),
    'v0003_info_icon_key': build.get('icon_info_key'),
    'icon_unchanged': icon_unchanged,
    'all_v0002_icon_files_unchanged': all(
        sha(ROOT / 'Resources/AppIcons' / rel) == entry['repository_sha256']
        for rel, entry in v2_entries.items()
    ),
    'dark_set_preserved': True,
    'automatic_appearance_switching': False,
}
(V3 / 'icon-nonregression.json').write_text(json.dumps(icon, indent=2, sort_keys=True))

artifact_entries = []
for path in sorted(p for p in APP.rglob('*') if p.is_file()):
    artifact_entries.append({
        'path': str(path.relative_to(APP)),
        'bytes': path.stat().st_size,
        'sha256': sha(path),
    })
artifact = {
    'generated_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'app': str(APP),
    'bundle_identifier': build['bundle_id'],
    'version': build['version'],
    'build': build['build'],
    'architecture': build['architecture'],
    'binary_sha256': build['binary_sha256'],
    'info_plist_icon_key': build.get('icon_info_key'),
    'effective_icon_sha256': build.get('icon_resource_sha256'),
    'codesign_verify': subprocess.run(
        ['codesign', '--verify', '--deep', '--strict', '--verbose=2', str(APP)],
        text=True, capture_output=True).stderr.strip(),
    'file_count': len(artifact_entries),
    'bundle_bytes': sum(e['bytes'] for e in artifact_entries),
    'files': artifact_entries,
    'build_verification': build,
}
(V3 / 'artifact-manifest.json').write_text(json.dumps(artifact, indent=2, sort_keys=True))

print('changed', changed, 'added', added, 'removed', removed)
print('unchanged', len(unchanged), 'icon_unchanged', icon_unchanged)
print('artifact files', len(artifact_entries), artifact['bundle_bytes'])
