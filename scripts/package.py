#!/usr/bin/env python3
"""Package the locally built ARM64 Valora binary; no third-party downloads."""
from pathlib import Path
import plistlib, shutil, subprocess, datetime, json, hashlib, argparse, sys

ROOT = Path(__file__).resolve().parents[1]

sys.path.insert(0, str(Path(__file__).resolve().parent))
import package_args  # noqa: E402  (local helper, no third-party code)

# The real packaging entry: arguments plus exactly one monotonic build number.
args, build_number = package_args.resolve(sys.argv[1:])

binary = args.binary.resolve()
dist = args.output_dir.resolve()
dist.mkdir(parents=True, exist_ok=True)
if not binary.exists():
    raise SystemExit('Run scripts/build.sh first.')

app = dist / 'Valora.app'
if app.exists():
    shutil.rmtree(app)
contents = app / 'Contents'
exe = contents / 'MacOS'
resources = contents / 'Resources'
frameworks = contents / 'Frameworks'
exe.mkdir(parents=True)
resources.mkdir()
frameworks.mkdir()

shutil.copy2(binary, exe / 'Valora')
(exe / 'Valora').chmod(0o755)
# Confirmed user-supplied icon set. The light .icns is the effective bundle
# icon; the complete light/dark PNG/iconset/icns originals stay in
# Resources/AppIcons for traceability. No automatic appearance switching.
icon_source = ROOT / 'Resources/AppIcons/light/Velora-light.icns'
if not icon_source.exists():
    raise SystemExit('Missing confirmed light icon: ' + str(icon_source))
shutil.copy2(icon_source, resources / 'AppIcon.icns')

# Borderless template ribbon V; app icon remains the color .icns.
menubar_icon_source = ROOT / 'Resources/MenuBarIcon-User-v11/MenuBarIcon.png'
for name in ['MenuBarIcon.png', 'MenuBarIcon@2x.png', 'MenuBarIcon@3x.png']:
    source = menubar_icon_source.parent / name
    if not source.is_file():
        raise SystemExit('Missing menu-bar PNG: ' + str(source))
    shutil.copy2(source, resources / name)

# Connectivity movies and alert sound: copied as a narrow payload, not the
# archived project's whole resource directory.
airpods_source = ROOT / 'Resources/AirPods'
if not airpods_source.is_dir():
    raise SystemExit('Missing connectivity movie directory: ' + str(airpods_source))
airpods_resources = resources / 'AirPods'
shutil.copytree(airpods_source, airpods_resources)
sounds_source = ROOT / 'Resources/Sounds'
if not sounds_source.is_dir():
    raise SystemExit('Missing sound resources: ' + str(sounds_source))
sounds_resources = resources / 'Sounds'
shutil.copytree(sounds_source, sounds_resources)

# Calmon solar-term data is a versioned static calendrical resource. It is
# copied as a plain directory; the target still has no SwiftPM resource bundle.
solar_terms_source = ROOT / 'Sources/Valora/Resources/SolarTerms'
if not solar_terms_source.is_dir():
    raise SystemExit('Missing SolarTerms resources: ' + str(solar_terms_source))
shutil.copytree(solar_terms_source, resources / 'SolarTerms')

# Third-party notices retained outside the app UI.
licenses_source = ROOT / 'Resources/Licenses'
if licenses_source.is_dir():
    shutil.copytree(licenses_source, resources / 'Licenses')

# The target currently has no SwiftPM resources. Do not copy any stale
# resource bundle left over from an earlier build.
adapter = resources / 'MediaRemote'
adapter.mkdir()
shutil.copy2(ROOT / 'vendor/mediaremote-adapter/bin/mediaremote-adapter.pl', adapter / 'mediaremote-adapter.pl')
shutil.copy2(ROOT / 'vendor/mediaremote-adapter/LICENSE', adapter / 'LICENSE')
shutil.copy2(ROOT / '.build/media-adapter/provenance.json', adapter / 'provenance.json')
shutil.copytree(ROOT / '.build/media-adapter/MediaRemoteAdapter.framework',
                frameworks / 'MediaRemoteAdapter.framework')

info = {
    'CFBundleIdentifier': 'com.wangqing.valora',
    'CFBundleExecutable': 'Valora',
    'CFBundleName': 'Valora',
    'CFBundleDisplayName': 'Valora',
    'CFBundlePackageType': 'APPL',
    'CFBundleShortVersionString': args.version,
    'CFBundleVersion': build_number,
    'LSMinimumSystemVersion': '27.0',
    'LSUIElement': True,
    'NSHighResolutionCapable': True,
    # IOBluetooth reads connected accessories to show connection/battery
    # notifications; the key is required by macOS Bluetooth access control.
    'NSBluetoothAlwaysUsageDescription': 'Valora 需要访问蓝牙以检测已连接的 AirPods 并显示连接和电量提示。',
    'NSCalendarsFullAccessUsageDescription': '用于读取日历中的节假日与休班信息。',
    'CFBundleIconFile': 'AppIcon',
}
if args.lock_diagnostic_path:
    info['LSEnvironment'] = {'VALORA_NOTCH_DIAGNOSTIC': args.lock_diagnostic_path}
(contents / 'Info.plist').write_bytes(plistlib.dumps(info))

entitlements_source = ROOT / 'Resources/Valora.entitlements'
if not entitlements_source.is_file():
    raise SystemExit('Missing signing entitlements: ' + str(entitlements_source))
subprocess.run(['codesign', '--force', '--sign', '-', '--options', 'runtime',
                '--entitlements', str(entitlements_source), str(app)], check=True)
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
# Read the real signature, not only the source plist.
signed = subprocess.run(['codesign', '-d', '--entitlements', ':-', str(app)],
                        capture_output=True, text=True)
signed_output = (signed.stdout or '') + (signed.stderr or '')
signed_plist = None
start = signed_output.find('<?xml')
end = signed_output.find('</plist>')
if start >= 0 and end >= start:
    signed_plist = plistlib.loads(signed_output[start:end + len('</plist>')].encode())
if not isinstance(signed_plist, dict) or signed_plist.get('com.apple.security.personal-information.calendars') is not True:
    raise SystemExit('Signed app is missing com.apple.security.personal-information.calendars')
display = subprocess.run(['codesign', '-d', '--verbose=2', str(app)],
                         capture_output=True, text=True)
display_output = (display.stdout or '') + (display.stderr or '')
arch = subprocess.check_output(['lipo', '-archs', str(exe / 'Valora')], text=True).strip()
if arch != 'arm64':
    raise SystemExit('Expected ARM64 only, found ' + arch)
(dist / 'build-verification.json').write_text(json.dumps({
    'architecture': arch,
    'version': info['CFBundleShortVersionString'],
    'build': info['CFBundleVersion'],
    'build_input': str(binary),
    'built_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'binary_sha256': hashlib.sha256((exe / 'Valora').read_bytes()).hexdigest(),
    'icon_source': str(icon_source),
    'icon_source_sha256': hashlib.sha256(icon_source.read_bytes()).hexdigest(),
    'icon_resource_sha256': hashlib.sha256((resources / 'AppIcon.icns').read_bytes()).hexdigest(),
    'menubar_icon_source': str(menubar_icon_source),
    'menubar_icon_source_sha256': hashlib.sha256(menubar_icon_source.read_bytes()).hexdigest(),
    'menubar_icon_resource_sha256': hashlib.sha256((resources / 'MenuBarIcon.png').read_bytes()).hexdigest(),
    'connectivity_resources': {
        'airpods_movies': sorted(p.name for p in airpods_resources.glob('*.mp4')),
        'airpods_source': str(airpods_source),
        'airpods_source_sha256': {
            p.name: hashlib.sha256(p.read_bytes()).hexdigest()
            for p in sorted(airpods_source.glob('*.mp4'))
        },
        'low_battery_sound': 'Sounds/low-battery.caf',
        'low_battery_source': str(sounds_source / 'low-battery.caf'),
        'low_battery_sha256': hashlib.sha256((sounds_source / 'low-battery.caf').read_bytes()).hexdigest(),
        'lock_sound': 'Sounds/lock.caf',
        'lock_source': str(sounds_source / 'lock.caf'),
        'lock_sha256': hashlib.sha256((sounds_source / 'lock.caf').read_bytes()).hexdigest(),
        'unlock_sound': 'Sounds/unlock.caf',
        'unlock_source': str(sounds_source / 'unlock.caf'),
        'unlock_sha256': hashlib.sha256((sounds_source / 'unlock.caf').read_bytes()).hexdigest()
    },
    'bluetooth_usage_description_key': 'NSBluetoothAlwaysUsageDescription',
    'bluetooth_usage_description_present': bool(info.get('NSBluetoothAlwaysUsageDescription')),
    'audio_capture_usage_description_present': False,
    'live_audio_tap_source_present': (ROOT / 'Sources/Valora/AudioTap.swift').exists(),
    'unexpected_resource_dirs_in_app': sorted(
        p.name for p in resources.iterdir() if p.is_dir() and p.name not in {'AirPods', 'Licenses', 'MediaRemote', 'SolarTerms', 'Sounds'}
    ),
    'swiftpm_resource_bundles_in_app': sorted(p.name for p in resources.glob('*.bundle')),
    'solar_terms_source': str(solar_terms_source),
    'solar_terms_source_sha256': {
        p.name: hashlib.sha256(p.read_bytes()).hexdigest()
        for p in sorted(solar_terms_source.glob('*.json'))
    },
    'calendars_usage_description_key': 'NSCalendarsFullAccessUsageDescription',
    'calendars_usage_description_present': bool(info.get('NSCalendarsFullAccessUsageDescription')),
    'entitlements_source': str(entitlements_source),
    'entitlements_source_sha256': hashlib.sha256(entitlements_source.read_bytes()).hexdigest(),
    'calendars_entitlement_present_in_signed_app': signed_plist.get('com.apple.security.personal-information.calendars') is True,
    'signed_entitlements_sha256': hashlib.sha256(
        plistlib.dumps(signed_plist, sort_keys=True)).hexdigest(),
    'codesign_runtime_flag_present': 'runtime' in display_output.lower(),
    'icon_info_key': info['CFBundleIconFile'],
    'bundle_id': info['CFBundleIdentifier'],
    'adhoc_signed': True,
    'notarized': False,
    'source_rebuilt': True,
}, indent=2, sort_keys=True))
print(app)
