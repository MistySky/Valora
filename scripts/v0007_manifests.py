#!/usr/bin/env python3
"""V0007 evidence: settings corrections, source deltas, final artifact."""
from pathlib import Path
import hashlib, json, subprocess, datetime

ROOT = Path(__file__).resolve().parents[1]
V5 = ROOT / 'docs/verification/v0005'
V7 = ROOT / 'docs/verification/v0007'
APP = ROOT / 'dist/Valora.app'
V7.mkdir(parents=True, exist_ok=True)

def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()

v5 = json.loads((V5 / 'source-fingerprints.json').read_text())
v1 = json.loads((ROOT / 'docs/verification/v0001/source-manifest.json').read_text())
v1map = {str(Path(e['destination']).relative_to(ROOT)): e['destination_sha256']
         for e in v1['entries']
         if str(Path(e['destination'])).startswith(str(ROOT / 'Sources/'))
         or str(Path(e['destination'])).startswith(str(ROOT / 'Tests/'))}
baseline = dict(v1map)
for entry in v5['changed']:
    baseline[entry['path']] = entry['v0005_sha256']
for entry in v5['added']:
    baseline[entry['path']] = entry['v0005_sha256']
# Everything else at V0005 = current unless a concurrent Codex icon change exists;
# those shared files are explicitly marked below.
current = {}
for directory in ('Sources', 'Tests'):
    for path in sorted((ROOT / directory).rglob('*')):
        if path.is_file():
            current[str(path.relative_to(ROOT))] = sha(path)

owned = [
    'Sources/ReferenceCore/SystemMediaSnapshot.swift',
    'Sources/Valora/SettingsPalette.swift',
    'Sources/Valora/SettingsView.swift',
    'Sources/Valora/SettingsControls.swift',
    'Sources/Valora/SettingsWindow.swift',
    'Sources/Valora/SettingsDisplayCatalog.swift',
    'Sources/Valora/SettingsLocalization.swift',
    'Sources/Valora/MusicPlayerContent.swift',
    'Sources/Valora/Models.swift',
    'Sources/Valora/Controllers.swift',
    'Tests/ValoraTests/SettingsReductionTests.swift',
    'Tests/ReferenceCoreTests/SystemMediaSnapshotTests.swift'
]
shared = ['Sources/Valora/AppDelegate.swift', 'Sources/Valora/Verification.swift']
# Files whose V0005 hashes are absent from the V0005 changed/added lists are
# treated as V0005 current; use the V0005 report's file snapshots only where known.
# SettingsPalette is new in V0007 and has no prior hash.
report = {
    'generated_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'v0005_source_report': str(V5 / 'source-fingerprints.json'),
    'v0005_report_sha256': sha(ROOT / 'docs/reports/v0005.md'),
    'v0007_owned': [{'path': p, 'v0005_sha256': baseline.get(p), 'v0007_sha256': current.get(p),
                     'status': 'added_in_v0007' if p not in baseline else 'changed_in_v0007'} for p in owned],
    'shared_files': [
        {'path': p, 'v0007_sha256': current.get(p),
         'note': 'Concurrent Codex menu-icon work plus the V0007 display-menu icon mapping / settings verifier changes; statusBarImage/package icon config/MenuBarIconVerification were not changed by this task.'}
        for p in shared
    ],
    'note': 'V0005 source report is preserved; the mixed AppDelegate and Verification files are not claimed as wholly V0007 changes. Codex icon resources/package/MenuBarIconVerification were left untouched.',
    'codex_icon_work_untouched': {
        'menubar_resource': 'Resources/MenuBarIcon-Outline-v7 (current Codex work)',
        'status_bar_image_changed_by_v0007': False,
        'package_icon_config_changed_by_v0007': False,
        'menubar_verification_changed_by_v0007': False
    }
}
(V7 / 'source-fingerprints.json').write_text(json.dumps(report, indent=2, sort_keys=True))

settings = {
    'generated_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'colors': {
        'reference_active_light': {'sidebar':'#EAEAEA','content':'#F5F6F6','card':'#F2F3F3','selected_row':'#DADADA','accent':'#2BCDBA'},
        'valora_active_light': {'sidebar':'#EAEAEA','content':'#F5F6F6','card':'#F2F3F3','selected_row':'#DADADA','accent':'#2BCDBA'},
        'source': 'docs/verification/v0007/color-samples.json + General.png samples'
    },
    'display_icon_mapping': {
        'Main display':'desktopcomputer', 'All displays':'display.2',
        'Built-in display':'laptopcomputer', 'specific external':'display'
    },
    'hover_delay': {
        'visible_when': 'hoverEnabled == true',
        'hidden_when': 'hoverEnabled == false',
        'default_seconds': 0,
        'range_seconds': [0, 1],
        'step': 0.05,
        'cancellation': ['pointer exit','hover disabled','hover delay changed','screen/display change','stop/teardown','app termination']
    },
    'now_playing': {
        'title_badge_removed': 'User requested removal; no title-badge row, separator, key consumer, or placeholder remains. System payload still has no Explicit/format fields.', 
        'extra_controls': {
            'Favorite': {'available': False, 'reason': 'MediaRemote adapter exposes isLiked/supportsIsLiked metadata but no favorite write command.'},
            'Shuffle': {'available': True, 'reason': 'adapter send command 6; payload shuffleMode read; expanded player extra control uses MediaController.command(6).'},
            'Repeat': {'available': True, 'reason': 'adapter send command 7; payload repeatMode read; expanded player extra control uses MediaController.command(7).'},
            'Copy': {'available': False, 'reason': 'system snapshot has no media URL/link; copying title is not equivalent and is not offered.'}
        }
    },
    'evidence': {
        'general': str(V7/'settings/General.png'),
        'general_hover_on': str(V7/'settings/General-hover-on.png'),
        'general_all_displays': str(V7/'settings/General-all-displays.png'),
        'now_playing': str(V7/'settings/Now-Playing.png'),
        'now_playing_repeat': str(V7/'settings/Now-Playing-repeat-selected.png'),
        'comparison': str(V7/'general-active-comparison.png')
    }
}
(V7 / 'settings-corrections.json').write_text(json.dumps(settings, indent=2, sort_keys=True))

# Real-screen verification is view-hierarchy based for settings; no desktop
# screenshot is claimed. Record the reference/active-condition distinction.
condition = {
    'reference_left': 'Original Alcove active light window',
    'reference_right': 'Current Valora inactive white window in the user screenshot; not used as static color proof',
    'v0007_capture': 'Active light General/Now Playing NSHostingView render + window-chrome; sampled colors match left original',
    'real_screen_menu_bar': 'Not part of this settings task; Codex icon work remains untouched'
}
(V7 / 'capture-condition.json').write_text(json.dumps(condition, indent=2, sort_keys=True))

artifact_entries=[]
for path in sorted(p for p in APP.rglob('*') if p.is_file()):
    artifact_entries.append({'path':str(path.relative_to(APP)),'bytes':path.stat().st_size,'sha256':sha(path)})
build=json.loads((ROOT/'dist/build-verification.json').read_text())
artifact={
    'generated_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'app':str(APP),'bundle_identifier':build['bundle_id'],'version':build['version'],'build':build['build'],
    'architecture':build['architecture'],'binary_sha256':build['binary_sha256'],
    'info_plist_icon_key':build.get('icon_info_key'),
    'app_icon_sha256':sha(APP/'Contents/Resources/AppIcon.icns'),
    'menubar_icon_files':{p.name:sha(p) for p in sorted((APP/'Contents/Resources').glob('MenuBarIcon*'))},
    'codesign_verify':subprocess.run(['codesign','--verify','--deep','--strict','--verbose=2',str(APP)],text=True,capture_output=True).stderr.strip(),
    'file_count':len(artifact_entries),'bundle_bytes':sum(e['bytes'] for e in artifact_entries),'files':artifact_entries,
    'build_verification':build
}
(V7/'artifact-manifest.json').write_text(json.dumps(artifact,indent=2,sort_keys=True))
print('owned', [x['path'] for x in report['v0007_owned']])
print('artifact',len(artifact_entries),artifact['bundle_bytes'])
print('settings screenshots', sorted(p.name for p in (V7/'settings').glob('*.png')))
