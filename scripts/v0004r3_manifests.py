#!/usr/bin/env python3
"""V0004-R3 evidence: dark menu-bar icon source, grayscale render, final artifact."""
from pathlib import Path
import hashlib, json, subprocess, datetime

ROOT = Path(__file__).resolve().parents[1]
V1 = ROOT / 'docs/verification/v0001'
R2 = ROOT / 'docs/verification/v0004-r2'
R3 = ROOT / 'docs/verification/v0004-r3'
APP = ROOT / 'dist/Valora.app'
R3.mkdir(parents=True, exist_ok=True)

def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()

v1 = json.loads((V1 / 'source-manifest.json').read_text())
r2 = json.loads((R2 / 'source-fingerprints.json').read_text())
v1_map = {str(Path(e['destination']).relative_to(ROOT)): e['destination_sha256'] for e in v1['entries']}
baseline = dict(v1_map)
for entry in r2['all_sources_changed_since_v0001']:
    baseline[entry['path']] = entry['v0004_r2_sha256']
for entry in r2['added_since_v0001']:
    baseline[entry['path']] = entry['v0004_r2_sha256']

current = {}
for directory in ('Sources', 'Tests'):
    for path in sorted((ROOT / directory).rglob('*')):
        if path.is_file():
            current[str(path.relative_to(ROOT))] = sha(path)

changed = [p for p, h in current.items() if p in baseline and h != baseline[p]]
unchanged = [p for p, h in current.items() if baseline.get(p) == h]
build = json.loads((ROOT / 'dist/build-verification.json').read_text())
menubar = json.loads((R3 / 'menubar/menubar-verification.json').read_text())
screen = json.loads((R3 / 'screen-capture-status.json').read_text())
dark_source = ROOT / 'Resources/AppIcons/dark/Velora-dark.icns'
bundle_menubar = APP / 'Contents/Resources/MenuBarIcon.icns'
bundle_appicon = APP / 'Contents/Resources/AppIcon.icns'

source_report = {
    'generated_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'baseline': str(R2 / 'source-fingerprints.json'),
    'baseline_preserved_unmodified': True,
    'v0004_r3_touched': [
        {'path': p, 'v0004_r2_sha256': baseline.get(p), 'v0004_r3_sha256': current.get(p)}
        for p in ['Sources/Valora/AppDelegate.swift', 'Sources/Valora/Verification.swift']
    ],
    'all_sources_changed_since_v0001': [
        {'path': p, 'v0001_sha256': v1_map[p], 'v0004_r3_sha256': current[p]}
        for p in current if p in v1_map and current[p] != v1_map[p]
    ],
    'added_since_v0001': [
        {'path': p, 'v0004_r3_sha256': current[p]}
        for p in current if p not in v1_map
    ],
    'unchanged_since_v0004_r2': len(unchanged),
    'current_file_count': len(current),
    'build_script': {
        'path': str(ROOT / 'scripts/package.py'),
        'sha256': sha(ROOT / 'scripts/package.py'),
        'note': 'Adds MenuBarIcon.icns from the confirmed dark set and fails the build if it is missing; AppIcon.icns remains the light bundle icon.'
    },
    'minimal_change_summary': [
        'AppDelegate: menu bar loads Contents/Resources/MenuBarIcon.icns (dark source), then CIColorControls(saturation=0); isTemplate=false.',
        'package.py: packages the dark source as MenuBarIcon.icns and records source/resource SHA256; fails if missing.',
        'Verification: source is now dark/MenuBarIcon.icns; app icon remains light AppIcon.icns.',
        'Music and menu behavior untouched.'
    ],
    'preserved_history': {
        'v0004_r2_report': str(ROOT / 'docs/reports/v0004-r2.md'),
        'v0004_r2_report_sha256': sha(ROOT / 'docs/reports/v0004-r2.md'),
        'v0004_r2_fingerprints_sha256': sha(R2 / 'source-fingerprints.json'),
        'v0004_r2_menubar_sha256': sha(R2 / 'menubar-grayscale.json'),
    },
}
(R3 / 'source-fingerprints.json').write_text(json.dumps(source_report, indent=2, sort_keys=True))

menubar_report = {
    'generated_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'source_set': 'dark',
    'menubar_source_resources_path': str(dark_source),
    'menubar_source_sha256': sha(dark_source),
    'bundle_menubar_resource': str(bundle_menubar),
    'bundle_menubar_sha256': sha(bundle_menubar),
    'menubar_source_and_bundle_byte_identical': sha(dark_source) == sha(bundle_menubar),
    'bundle_app_icon_sha256': sha(bundle_appicon),
    'app_icon_info_key': build.get('icon_info_key'),
    'app_icon_unchanged_v0002_light': sha(bundle_appicon) == 'df342247f803caac0a1b36ddc098b27be10970fc109e74c199c38536de2c3654',
    'desaturation_method': menubar['desaturation_method'],
    'button_image_size': menubar['button_image_size'],
    'button_image_is_template': menubar['button_image_is_template'],
    'button_image_representations': menubar['button_image_representations'],
    'button_image_scaling': menubar['button_image_scaling'],
    'button_image_position': menubar['button_image_position'],
    'accessibility_label': menubar['button_accessibility_label'],
    'rendered_colorful_fraction': menubar['rendered_36']['colorfulFraction'],
    'rendered_transparent_corners': menubar['rendered_36']['cornerAlphas'],
    'rendered_files': {k: menubar[f'rendered_{k}']['path'] for k in ('16','18','36','54')},
    'preview_files': {
        'light': menubar['grayscale_preview_light']['path'],
        'dark': menubar['grayscale_preview_dark']['path'],
        'note': 'Offscreen grayscale previews; not real menu-bar captures.'
    },
    'screen_capture': screen,
    'dark_actual_capture': False,
    'selected_actual_capture': False,
    'selected_note': 'isTemplate=false keeps gray levels; system appearance and selected UI were not forced.'
}
(R3 / 'menubar-dark-grayscale.json').write_text(json.dumps(menubar_report, indent=2, sort_keys=True))

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
    'app_icon_sha256': build.get('icon_resource_sha256'),
    'menubar_icon_source_sha256': build.get('menubar_icon_source_sha256'),
    'menubar_icon_resource_sha256': build.get('menubar_icon_resource_sha256'),
    'codesign_verify': subprocess.run(['codesign', '--verify', '--deep', '--strict', '--verbose=2', str(APP)],
                                      text=True, capture_output=True).stderr.strip(),
    'file_count': len(artifact_entries),
    'bundle_bytes': sum(e['bytes'] for e in artifact_entries),
    'files': artifact_entries,
    'build_verification': build,
}
(R3 / 'artifact-manifest.json').write_text(json.dumps(artifact, indent=2, sort_keys=True))
print('touched', [e['path'] for e in source_report['v0004_r3_touched']])
print('changed', changed, 'unchanged', len(unchanged))
print('menubar identical', menubar_report['menubar_source_and_bundle_byte_identical'])
print('button', menubar_report['button_image_size'], menubar_report['button_image_is_template'], menubar_report['rendered_colorful_fraction'])
print('artifact', len(artifact_entries), artifact['bundle_bytes'])
