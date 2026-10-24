#!/usr/bin/env python3
"""Build the pinned BSD-3-Clause MediaRemote adapter for ARM64/macOS 27, offline."""
from pathlib import Path
import hashlib, json, plistlib, subprocess

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'vendor/mediaremote-adapter'
FRAMEWORK = ROOT / '.build/media-adapter/MediaRemoteAdapter.framework'
PINNED_COMMIT = '797729d9b16316dc313844476c153d7a107ca0df'
FRAMEWORK.mkdir(parents=True, exist_ok=True)

files = (sorted((SOURCE / 'src/adapter').glob('*.m'))
         + sorted((SOURCE / 'src/private').glob('*.m'))
         + sorted((SOURCE / 'src/utility').glob('*.m')))
if not files:
    raise SystemExit('Missing vendored MediaRemote adapter source')

subprocess.run([
    'xcrun', 'clang', '-dynamiclib', '-arch', 'arm64',
    '-mmacosx-version-min=27.0', '-fobjc-arc', '-fvisibility=default',
    '-I' + str(SOURCE / 'include'), '-I' + str(SOURCE / 'src'),
    *map(str, files),
    '-framework', 'Foundation', '-framework', 'AppKit', '-framework', 'UniformTypeIdentifiers',
    '-o', str(FRAMEWORK / 'MediaRemoteAdapter')
], check=True)

(FRAMEWORK / 'Resources').mkdir(exist_ok=True)
(FRAMEWORK / 'Resources/Info.plist').write_bytes(plistlib.dumps({
    'CFBundleIdentifier': 'com.vandenbe.MediaRemoteAdapter',
    'CFBundleName': 'MediaRemoteAdapter',
    'CFBundleExecutable': 'MediaRemoteAdapter',
    'CFBundlePackageType': 'FMWK',
    'CFBundleVersion': '1',
    'LSMinimumSystemVersion': '27.0',
}))
subprocess.run(['codesign', '--force', '--sign', '-', str(FRAMEWORK)], check=True)

provenance = {
    'upstream': 'https://github.com/ungive/mediaremote-adapter',
    'commit': PINNED_COMMIT,
    'architecture': 'arm64',
    'minimum_macos': '27.0',
    'license': 'BSD-3-Clause',
    'license_sha256': hashlib.sha256((SOURCE / 'LICENSE').read_bytes()).hexdigest(),
    'source_sha256': {str(p.relative_to(SOURCE)): hashlib.sha256(p.read_bytes()).hexdigest() for p in files},
    'binary_sha256': hashlib.sha256((FRAMEWORK / 'MediaRemoteAdapter').read_bytes()).hexdigest(),
}
(ROOT / '.build/media-adapter/provenance.json').write_text(json.dumps(provenance, indent=2, sort_keys=True))
print(FRAMEWORK)
