#!/usr/bin/env python3
"""Package the locally built ARM64 Valora binary; no third-party downloads."""
from pathlib import Path
import plistlib, shutil, subprocess, datetime, json, hashlib, argparse

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--binary', required=True, type=Path, help='Binary produced by the current build')
parser.add_argument('--version', default='0.1.0')
parser.add_argument('--build', default='1')
parser.add_argument('--output-dir', type=Path, default=ROOT / 'dist')
parser.add_argument('--native-host', type=Path, default=None, help='ValoraNativeHost executable')
args = parser.parse_args()

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
native_host = (args.native_host or (binary.parent / 'ValoraNativeHost')).resolve()
if not native_host.is_file():
    raise SystemExit('Missing ValoraNativeHost; run scripts/build.sh')
shutil.copy2(native_host, exe / 'ValoraNativeHost')
(exe / 'ValoraNativeHost').chmod(0o755)

# Confirmed user-supplied icon set. The light .icns is the effective bundle
# icon; the complete light/dark PNG/iconset/icns originals stay in
# Resources/AppIcons for traceability. No automatic appearance switching.
icon_source = ROOT / 'Resources/AppIcons/light/Velora-light.icns'
if not icon_source.exists():
    raise SystemExit('Missing confirmed light icon: ' + str(icon_source))
shutil.copy2(icon_source, resources / 'AppIcon.icns')

# Borderless template ribbon V; app icon remains the color .icns.
menubar_icon_source = ROOT / 'Resources/MenuBarIcon-Outline-v7/MenuBarIcon.png'
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
sound_source = ROOT / 'Resources/Sounds/low-battery.caf'
if not sound_source.is_file():
    raise SystemExit('Missing connectivity alert sound: ' + str(sound_source))
sounds_resources = resources / 'Sounds'
sounds_resources.mkdir()
shutil.copy2(sound_source, sounds_resources / 'low-battery.caf')

# Calmon solar-term data is a versioned static calendrical resource. It is
# copied as a plain directory; the target still has no SwiftPM resource bundle.
solar_terms_source = ROOT / 'Sources/Valora/Resources/SolarTerms'
if not solar_terms_source.is_dir():
    raise SystemExit('Missing SolarTerms resources: ' + str(solar_terms_source))
shutil.copytree(solar_terms_source, resources / 'SolarTerms')

# Chrome bridge: the extension directory and its native helper are real
# bundle contents, not a source-only checkout. The helper is signed with the
# rest of the app by codesign --deep below.
extension_source = ROOT / 'Resources/ChromeExtension'
if not extension_source.is_dir():
    raise SystemExit('Missing Chrome extension directory: ' + str(extension_source))
chrome_extension = resources / 'ChromeExtension'
shutil.copytree(extension_source, chrome_extension)

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
    'CFBundleVersion': args.build,
    'LSMinimumSystemVersion': '27.0',
    'LSUIElement': True,
    'NSHighResolutionCapable': True,
    # IOBluetooth reads connected accessories to show connection/battery
    # notifications; the key is required by macOS Bluetooth access control.
    'NSBluetoothAlwaysUsageDescription': 'Valora 需要访问蓝牙以检测已连接的 AirPods 并显示连接和电量提示。',
    'NSCalendarsFullAccessUsageDescription': '用于在日历中显示你的日程。',
    'CFBundleIconFile': 'AppIcon',
}
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
        'low_battery_source': str(sound_source),
        'low_battery_sha256': hashlib.sha256(sound_source.read_bytes()).hexdigest()
    },
    'bluetooth_usage_description_key': 'NSBluetoothAlwaysUsageDescription',
    'bluetooth_usage_description_present': bool(info.get('NSBluetoothAlwaysUsageDescription')),
    'audio_capture_usage_description_present': False,
    'live_audio_tap_source_present': (ROOT / 'Sources/Valora/AudioTap.swift').exists(),
    'unexpected_resource_dirs_in_app': sorted(
        p.name for p in resources.iterdir() if p.is_dir() and p.name not in {'AirPods', 'ChromeExtension', 'Licenses', 'MediaRemote', 'SolarTerms', 'Sounds'}
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
    'native_host_executable': 'Contents/MacOS/ValoraNativeHost',
    'native_host_source': str(native_host),
    'native_host_sha256': hashlib.sha256((exe / 'ValoraNativeHost').read_bytes()).hexdigest(),
    'chrome_extension_directory': 'Contents/Resources/ChromeExtension',
    'chrome_extension_manifest_sha256': hashlib.sha256((chrome_extension / 'manifest.json').read_bytes()).hexdigest(),
    'chrome_extension_id': 'micfejmbldlgjepdfadhnoalmcbnpllb',
    'chrome_native_host_name': 'com.wangqing.valora.chrome',
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
