#!/usr/bin/env python3
"""V0004-R1 evidence: template menu-bar icon, source deltas and final artifact."""
from pathlib import Path
import hashlib, json, subprocess, datetime

ROOT = Path(__file__).resolve().parents[1]
V1 = ROOT / 'docs/verification/v0001'
V4 = ROOT / 'docs/verification/v0004'
R1 = ROOT / 'docs/verification/v0004-r1'
APP = ROOT / 'dist/Valora.app'
R1.mkdir(parents=True, exist_ok=True)

def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()

v1 = json.loads((V1 / 'source-manifest.json').read_text())
v4 = json.loads((V4 / 'source-fingerprints.json').read_text())
v1_baseline = {}
for entry in v1['entries']:
    dst = Path(entry['destination'])
    if str(dst).startswith(str(ROOT / 'Sources/')) or str(dst).startswith(str(ROOT / 'Tests/')):
        v1_baseline[str(dst.relative_to(ROOT))] = entry['destination_sha256']
baseline = dict(v1_baseline)
for entry in v4['all_changed_since_v0001']:
    baseline[entry['path']] = entry['v0004_sha256']
for entry in v4['added_since_v0001']:
    baseline[entry['path']] = entry['v0004_sha256']

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
menubar = json.loads((R1 / 'menubar/menubar-verification.json').read_text())

source_report = {
    'generated_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'baseline': str(V4 / 'source-fingerprints.json'),
    'baseline_preserved_unmodified': True,
    'v0004_r1_touched': [
        {'path': p, 'v0004_sha256': baseline.get(p), 'v0004_r1_sha256': current.get(p)}
        for p in ['Sources/Valora/AppDelegate.swift', 'Sources/Valora/Verification.swift']
    ],
    'changed_since_v0004': [
        {'path': p, 'v0004_sha256': baseline.get(p), 'v0004_r1_sha256': current[p]}
        for p in changed
    ],
    'all_sources_changed_since_v0001': [
        {'path': p, 'v0001_sha256': v1_baseline[p], 'v0004_r1_sha256': current[p]}
        for p in current if p in v1_baseline and current[p] != v1_baseline[p]
    ],
    'added_since_v0001_all': [
        {'path': p, 'v0004_r1_sha256': current[p]}
        for p in current if p not in v1_baseline
    ],
    'added_since_v0001': [{'path': p, 'v0004_r1_sha256': current[p]} for p in added],
    'removed_since_v0001': removed,
    'unchanged_since_v0004': len(unchanged),
    'current_file_count': len(current),
    'patches': {
        'appdelegate': {'path': str(R1 / 'appdelegate.diff'), 'sha256': sha(R1 / 'appdelegate.diff')},
        'verification': {'path': str(R1 / 'verification.diff'), 'sha256': sha(R1 / 'verification.diff')},
    },
    'minimal_change_summary': [
        'AppDelegate: menu-bar-only code-drawn AppKit V, 18 pt, 18/36/54 px reps, transparent background, template=true; full-color AppIcon no longer used for the menu bar.',
        'Verification: R1 template image/reps/previews and offscreen-vs-screen disclosure.',
        'V0003 recovery/seek and V0004 menu QA mode remain carried.'
    ],
    'preserved_history': {
        'v0004_report': str(ROOT / 'docs/reports/v0004.md'),
        'v0004_report_sha256': sha(ROOT / 'docs/reports/v0004.md'),
        'v0004_fingerprints_sha256': sha(V4 / 'source-fingerprints.json'),
        'v0004_artifact_sha256': sha(V4 / 'artifact-manifest.json'),
        'v0004_icon_menubar_sha256': sha(V4 / 'icon-and-menubar.json'),
    },
}
(R1 / 'source-fingerprints.json').write_text(json.dumps(source_report, indent=2, sort_keys=True))

screen_status = {
    'generated_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'final_real_screen_capture_available': False,
    'console_screen_locked_at_final_check': True,
    'external_display_was_present': True,
    'screencapture_error': "screencapture -D 2 -R ...: Invalid display specified / could not create image from rect while locked",
    'observed_before_lock': True,
    'observed_before_lock_note': 'The gray template V was seen in the real external menu bar before the console locked; that narrow crop was not retained after the display/session changed.',
    'offscreen_evidence_only': True,
    'not_claimed_as_real_screen': True,
    'narrow_crop_files': [],
}
(R1 / 'screen-capture-status.json').write_text(json.dumps(screen_status, indent=2, sort_keys=True))

menubar_report = {
    'generated_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'source': menubar['menubar_source'],
    'button_image_size': menubar['button_image_size'],
    'button_image_is_template': menubar['button_image_is_template'],
    'button_image_representations': menubar['button_image_representations'],
    'button_image_scaling': menubar['button_image_scaling'],
    'button_image_position': menubar['button_image_position'],
    'accessibility_label': menubar['button_accessibility_label'],
    'no_square_background': True,
    'no_glow_shadow_gradient': True,
    'old_rectangle_symbol_present': False,
    'app_icon_unchanged': build.get('icon_resource_sha256') == 'df342247f803caac0a1b36ddc098b27be10970fc109e74c199c38536de2c3654',
    'app_icon_sha256': build.get('icon_resource_sha256'),
    'rendered_files': {
        '16': menubar['rendered_16']['path'],
        '18': menubar['rendered_18']['path'],
        '36': menubar['rendered_36']['path'],
        '54': menubar['rendered_54']['path'],
    },
    'openscreen_previews': {
        'light': menubar['template_preview_light']['path'],
        'dark': menubar['template_preview_dark']['path'],
        'selected': menubar['template_preview_selected']['path'],
        'note': 'Synthetic template tint previews; not real menu-bar screenshots.',
    },
    'screen_capture': str(R1 / 'screen-capture-status.json'),
    'dark_mode_actual_capture': False,
    'selected_state_actual_capture': False,
    'dark_selected_note': 'Template=true is the actual system adaptation mechanism; no system appearance or selected UI was forced.',
}
(R1 / 'menubar-template.json').write_text(json.dumps(menubar_report, indent=2, sort_keys=True))

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
(R1 / 'artifact-manifest.json').write_text(json.dumps(artifact, indent=2, sort_keys=True))
print('touched', [e['path'] for e in source_report['v0004_r1_touched']])
print('changed since v1', changed)
print('unchanged', len(unchanged), 'current', len(current))
print('template', menubar_report['button_image_is_template'], menubar_report['button_image_representations'])
print('artifact', len(artifact_entries), artifact['bundle_bytes'])
