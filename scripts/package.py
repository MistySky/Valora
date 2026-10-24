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

# SwiftPM resource bundle (format icons) and the MediaRemote adapter payload.
bundle = binary.parent / 'Valora_Valora.bundle'
if bundle.exists():
    shutil.copytree(bundle, resources / bundle.name)
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
    'NSAudioCaptureUsageDescription': 'Valora 需要读取系统音频以显示实时波形。',
    'CFBundleIconFile': 'AppIcon',
}
(contents / 'Info.plist').write_bytes(plistlib.dumps(info))

subprocess.run(['codesign', '--force', '--sign', '-', '--options', 'runtime', str(app)], check=True)
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
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
    'icon_info_key': info['CFBundleIconFile'],
    'bundle_id': info['CFBundleIdentifier'],
    'adhoc_signed': True,
    'notarized': False,
    'source_rebuilt': True,
}, indent=2, sort_keys=True))
print(app)
