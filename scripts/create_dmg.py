#!/usr/bin/env python3
"""Create a read-only DMG from an already packaged Valora.app (no rebuild)."""
import argparse
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--app', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
app = args.app.resolve()
output = args.output.resolve()
if output.exists():
    parser.error('output already exists; choose a new filename')
info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
if info.get('CFBundleIdentifier') != 'com.wangqing.valora':
    parser.error('expected a packaged Valora application')
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
output.parent.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix='valora-dmg-') as folder:
    staging = Path(folder)
    subprocess.run(['ditto', str(app), str(staging / 'Valora.app')], check=True)
    (staging / 'Applications').symlink_to('/Applications')
    subprocess.run(['hdiutil', 'create', '-volname',
                    'Valora ' + info['CFBundleShortVersionString'],
                    '-srcfolder', str(staging), '-format', 'UDZO',
                    str(output)], check=True)
subprocess.run(['hdiutil', 'verify', str(output)], check=True)
print(output)
