#!/usr/bin/env python3
"""V0002 evidence: business-code unchanged vs V0001 and final bundle fingerprint."""
from pathlib import Path
import hashlib, json, subprocess, datetime

ROOT = Path(__file__).resolve().parents[1]
V1 = ROOT / 'docs/verification/v0001'
V2 = ROOT / 'docs/verification/v0002'
APP = ROOT / 'dist/Valora.app'
V2.mkdir(parents=True, exist_ok=True)

def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()

v1_manifest = json.loads((V1 / 'source-manifest.json').read_text())
checked = []
changed = []
missing = []
for entry in v1_manifest['entries']:
    dst = Path(entry['destination'])
    if not (str(dst).startswith(str(ROOT / 'Sources/')) or str(dst).startswith(str(ROOT / 'Tests/'))):
        continue
    record = {
        'destination': str(dst),
        'v0001_sha256': entry['destination_sha256'],
        'v0002_sha256': None,
        'unchanged': False,
    }
    if not dst.exists():
        missing.append(record)
    else:
        current = sha(dst)
        record['v0002_sha256'] = current
        record['unchanged'] = current == entry['destination_sha256']
        if not record['unchanged']:
            changed.append(record)
    checked.append(record)

v1_build = json.loads((V1 / 'build-verification.json').read_text())
v2_build = json.loads((ROOT / 'dist/build-verification.json').read_text())
unchanged = {
    'generated_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'v0001_report': str(ROOT / 'docs/reports/v0001.md'),
    'v0001_report_sha256': sha(ROOT / 'docs/reports/v0001.md'),
    'v0001_source_manifest': str(V1 / 'source-manifest.json'),
    'v0001_source_manifest_sha256': sha(V1 / 'source-manifest.json'),
    'v0001_environment_sha256': sha(V1 / 'environment.json'),
    'checked_files': len(checked),
    'changed_files': len(changed),
    'missing_files': len(missing),
    'all_business_files_unchanged': not changed and not missing,
    'files': checked,
    'binary': {
        'v0001_sha256': v1_build['binary_sha256'],
        'v0002_sha256': v2_build['binary_sha256'],
        'byte_identical': v1_build['binary_sha256'] == v2_build['binary_sha256'],
        'note': 'Swift source files are the authoritative unchanged-code evidence; the linker output was regenerated during the V0002 package builds and is not claimed byte-identical.'
    }
}
(V2 / 'business-code-unchanged.json').write_text(json.dumps(unchanged, indent=2, sort_keys=True))

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
    'bundle_identifier': v2_build['bundle_id'],
    'version': v2_build['version'],
    'build': v2_build['build'],
    'architecture': v2_build['architecture'],
    'info_plist_icon_key': v2_build.get('icon_info_key'),
    'effective_icon_sha256': v2_build.get('icon_resource_sha256'),
    'codesign_verify': subprocess.run(
        ['codesign', '--verify', '--deep', '--strict', '--verbose=2', str(APP)],
        text=True, capture_output=True).stderr.strip(),
    'bundle_bytes': sum(e['bytes'] for e in artifact_entries),
    'file_count': len(artifact_entries),
    'files': artifact_entries,
    'build_verification': v2_build,
}
(V2 / 'artifact-manifest.json').write_text(json.dumps(artifact, indent=2, sort_keys=True))
print(f"business checked={len(checked)} changed={len(changed)} missing={len(missing)}")
print(f"artifact files={len(artifact_entries)} bytes={artifact['bundle_bytes']}")
