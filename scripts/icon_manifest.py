#!/usr/bin/env python3
"""Record the confirmed icon source, repository copies and effective bundle icon.

Read-only over the Downloads source; writes only inside the Valora repository.
"""
from pathlib import Path
import hashlib, json, subprocess, datetime, tempfile, shutil

ROOT = Path(__file__).resolve().parents[1]
SRC = Path('/Users/wangqing/Downloads/Velora-macOS-Icons-Transparent')
REPO = ROOT / 'Resources/AppIcons'
APP = ROOT / 'dist/Valora.app'
OUT = ROOT / 'docs/verification/v0002/icon-manifest.json'

def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()

def png_size(path: Path) -> list[int] | None:
    out = subprocess.run(['sips', '-g', 'pixelWidth', '-g', 'pixelHeight', str(path)],
                         text=True, capture_output=True).stdout
    values = {}
    for line in out.splitlines():
        if ':' in line:
            key, value = line.split(':', 1)
            values[key.strip()] = value.strip()
    try:
        return [int(values['pixelWidth']), int(values['pixelHeight'])]
    except (KeyError, ValueError):
        return None

source_files = sorted(p for p in SRC.rglob('*') if p.is_file())
entries = []
for source in source_files:
    rel = source.relative_to(SRC)
    if rel.parts[0] not in ('light', 'dark'):
        continue
    target = REPO / rel
    entries.append({
        'source': str(source),
        'relative_path': str(rel),
        'source_sha256': sha(source),
        'source_bytes': source.stat().st_size,
        'repository': str(target),
        'repository_sha256': sha(target) if target.exists() else None,
        'repository_bytes': target.stat().st_size if target.exists() else None,
        'byte_identical': target.exists() and sha(target) == sha(source),
        'png_size': png_size(source) if source.suffix == '.png' else None,
    })

source_readme = SRC / 'README.md'
repo_readme = REPO / 'README-source.md'

# Enumerate the iconset members inside the effective .icns in a temp directory.
icns_members = []
with tempfile.TemporaryDirectory() as tmp:
    out = Path(tmp) / 'effective.iconset'
    result = subprocess.run(['iconutil', '-c', 'iconset', str(REPO / 'light/Velora-light.icns'), '-o', str(out)],
                            text=True, capture_output=True)
    if result.returncode == 0:
        icns_members = sorted(p.name for p in out.glob('*.png'))

effective_repo = REPO / 'light/Velora-light.icns'
effective_bundle = APP / 'Contents/Resources/AppIcon.icns'
build_info_path = ROOT / 'dist/build-verification.json'
build_info = json.loads(build_info_path.read_text()) if build_info_path.exists() else {}

data = {
    'generated_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'source_root': str(SRC),
    'source_read_only': True,
    'source_note': 'User-confirmed transparent-edge light/dark icon sets. No image editing or edge rework.',
    'source_readme': {
        'source': str(source_readme),
        'source_sha256': sha(source_readme),
        'repository': str(repo_readme),
        'repository_sha256': sha(repo_readme) if repo_readme.exists() else None,
    },
    'repository_root': str(REPO),
    'file_count': len(entries),
    'all_byte_identical': all(e['byte_identical'] for e in entries),
    'entries': entries,
    'effective_icon': {
        'source': str(effective_repo),
        'source_sha256': sha(effective_repo),
        'bundle': str(effective_bundle),
        'bundle_sha256': sha(effective_bundle) if effective_bundle.exists() else None,
        'bundle_exists': effective_bundle.exists(),
        'info_key': build_info.get('icon_info_key'),
        'iconset_members_readable': icns_members,
        'iconset_member_count': len(icns_members),
    },
    'dark_set': {
        'preserved_in_repository': True,
        'bundle_icon': False,
        'automatic_appearance_switching': False,
        'note': 'macOS does not derive a per-app dark icon from a second .icns alone; the light .icns is the normal default.',
    },
    'build_verification': build_info,
}
OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_text(json.dumps(data, indent=2, sort_keys=True))
print(f'{OUT} files={len(entries)} all_identical={data["all_byte_identical"]} icns_members={len(icns_members)}')
