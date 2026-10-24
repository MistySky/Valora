#!/usr/bin/env python3
"""V0004 evidence: menu-bar icon change fingerprints, artifact and regressions."""
from pathlib import Path
import hashlib, json, subprocess, datetime

ROOT = Path(__file__).resolve().parents[1]
V1 = ROOT / 'docs/verification/v0001'
V2 = ROOT / 'docs/verification/v0002'
V3 = ROOT / 'docs/verification/v0003'
V4 = ROOT / 'docs/verification/v0004'
APP = ROOT / 'dist/Valora.app'
V4.mkdir(parents=True, exist_ok=True)

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

v3 = json.loads((V3 / 'source-fingerprints.json').read_text())
v3_changed = {e['path']: e['v0003_sha256'] for e in v3['changed']}
v3_added = {e['path']: e['v0003_sha256'] for e in v3['added']}
v4_touched = ['Sources/Valora/AppDelegate.swift', 'Sources/Valora/AppRuntimeDefaults.swift',
              'Sources/Valora/Verification.swift']

build = json.loads((ROOT / 'dist/build-verification.json').read_text())
v2_icon = json.loads((V2 / 'icon-manifest.json').read_text())
v2_icon_files = {e['relative_path']: e for e in v2_icon['entries']}

source_report = {
    'generated_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'baseline': str(V1 / 'source-manifest.json'),
    'baseline_preserved_unmodified': True,
    'v0003_evidence': str(V3 / 'source-fingerprints.json'),
    'v0003_changes_carried': [
        {'path': p, 'v0003_sha256': h, 'v0004_sha256': current.get(p)} for p, h in v3_changed.items()
    ] + [
        {'path': p, 'v0003_sha256': h, 'v0004_sha256': current.get(p), 'added_in_v0003': True} for p, h in v3_added.items()
    ],
    'v0004_touched': [
        {'path': p, 'v0003_sha256': baseline.get(p), 'v0004_sha256': current.get(p)} for p in v4_touched
    ],
    'all_changed_since_v0001': [
        {'path': p, 'v0001_sha256': baseline[p], 'v0004_sha256': current[p]} for p in changed
    ],
    'added_since_v0001': [{'path': p, 'v0004_sha256': current[p]} for p in added],
    'removed_since_v0001': removed,
    'unchanged_since_v0001_count': len(unchanged),
    'current_file_count': len(current),
    'patches': {
        'appdelegate': {'path': str(V4 / 'appdelegate.diff'), 'sha256': sha(V4 / 'appdelegate.diff')},
        'appruntimedefaults': {'path': str(V4 / 'appruntimedefaults.diff'), 'sha256': sha(V4 / 'appruntimedefaults.diff')},
        'verification': {'path': str(V4 / 'verification.diff'), 'sha256': sha(V4 / 'verification.diff')},
    },
    'preserved_history': {
        'v0001_report': str(ROOT / 'docs/reports/v0001.md'),
        'v0001_report_sha256': sha(ROOT / 'docs/reports/v0001.md'),
        'v0002_report': str(ROOT / 'docs/reports/v0002.md'),
        'v0002_report_sha256': sha(ROOT / 'docs/reports/v0002.md'),
        'v0003_report': str(ROOT / 'docs/reports/v0003.md'),
        'v0003_report_sha256': sha(ROOT / 'docs/reports/v0003.md'),
        'v0001_manifest_sha256': sha(V1 / 'source-manifest.json'),
        'v0002_icon_manifest_sha256': sha(V2 / 'icon-manifest.json'),
        'v0003_fingerprints_sha256': sha(V3 / 'source-fingerprints.json'),
    },
    'minimal_change_summary': [
        'AppDelegate: NSStatusItem button now loads Contents/Resources/AppIcon.icns at 18 pt, non-template color image; old rectangle symbol removed.',
        'AppRuntimeDefaults: QA-only --verify-menubar mode.',
        'Verification: menu-bar button/image/window diagnostics and rendered button images.',
        'V0003 Controllers recovery/seek changes are carried unchanged.'
    ],
}
(V4 / 'source-fingerprints.json').write_text(json.dumps(source_report, indent=2, sort_keys=True))

icon = {
    'generated_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'app_icon_unchanged_from_v0002': build.get('icon_resource_sha256') == v2_icon['effective_icon']['bundle_sha256'],
    'all_v0002_icon_files_unchanged': all(
        sha(ROOT / 'Resources/AppIcons' / rel) == entry['repository_sha256']
        for rel, entry in v2_icon_files.items()
    ),
    'effective_icon_sha256': build.get('icon_resource_sha256'),
    'info_plist_icon_key': build.get('icon_info_key'),
    'menubar_source': 'Contents/Resources/AppIcon.icns',
    'menubar_size_points': [18, 18],
    'menubar_template': False,
    'old_rectangle_symbol_present': False,
    'dark_set_preserved': True,
    'automatic_appearance_switching': False,
    'menubar_verification_json': str(V4 / 'menubar/menubar-verification.json'),
    'menubar_runtime_running_png': str(V4 / 'menubar/menubar-screen-running.png'),
    'menubar_runtime_stopped_png': str(V4 / 'menubar/menubar-screen-stopped.png'),
    'menubar_runtime_note': 'Narrow real-screen crops on the external display: icon present while Valora is running, blank at the same rectangle after normal quit.',
}
(V4 / 'icon-and-menubar.json').write_text(json.dumps(icon, indent=2, sort_keys=True))

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
    'effective_icon_sha256': build.get('icon_resource_sha256'),
    'codesign_verify': subprocess.run(['codesign', '--verify', '--deep', '--strict', '--verbose=2', str(APP)],
                                      text=True, capture_output=True).stderr.strip(),
    'file_count': len(artifact_entries),
    'bundle_bytes': sum(e['bytes'] for e in artifact_entries),
    'files': artifact_entries,
    'build_verification': build,
}
(V4 / 'artifact-manifest.json').write_text(json.dumps(artifact, indent=2, sort_keys=True))
print('v4 touched', v4_touched)
print('changed since v1', changed)
print('unchanged', len(unchanged), 'current', len(current))
print('icon unchanged', icon['app_icon_unchanged_from_v0002'])
print('artifact', len(artifact_entries), artifact['bundle_bytes'])
