#!/usr/bin/env python3
"""Verify / upgrade-check the reviewed Convoy DownloadEngine vendor tree.

Usage:
  python3 scripts/verify_convoy_vendor.py --upstream /path/to/clean/convoy
The upstream checkout must be the pinned revision; no .build/checkouts or
user Convoy data is touched. A mismatch fails loudly instead of silently
copying a different source tree over the reviewed local patches.
"""
from pathlib import Path
import argparse, hashlib, json, subprocess, sys
ROOT = Path(__file__).resolve().parents[1]
VENDOR = ROOT / 'Vendor/Convoy'
MANIFEST = json.loads((VENDOR / 'SOURCE-MANIFEST.json').read_text())
REV = MANIFEST['revision']
def sha(path): return hashlib.sha256(Path(path).read_bytes()).hexdigest()
ap = argparse.ArgumentParser()
ap.add_argument('--upstream', required=True, type=Path)
args = ap.parse_args()
up = args.upstream.resolve()
try:
    head = subprocess.check_output(['git', '-C', str(up), 'rev-parse', 'HEAD'], text=True).strip()
except Exception as e:
    print('cannot read upstream git revision:', e); sys.exit(2)
if head != REV:
    print('UPSTREAM REVISION MISMATCH:', head, 'expected', REV); sys.exit(2)
errors = []
for entry in MANIFEST['files']:
    rel = entry['path']
    upath, lpath = up / 'Sources/DownloadEngine' / rel, VENDOR / 'Sources/DownloadEngine' / rel
    if entry['upstream_sha256'] is None:
        if not lpath.exists(): errors.append('missing local addition '+rel)
        elif sha(lpath) != entry['local_sha256']: errors.append('local addition changed without manifest update '+rel)
        continue
    if not upath.exists(): errors.append('upstream missing '+rel); continue
    if sha(upath) != entry['upstream_sha256']:
        errors.append('upstream content differs at '+rel+' (manifest must be upgraded explicitly)'); continue
    if not lpath.exists(): errors.append('vendor missing '+rel); continue
    if sha(lpath) != entry['local_sha256']:
        errors.append('vendor differs from manifest '+rel)
for forbidden in ['.git','.build','build','Sources/Convoy','Sources/NativeMessagingHost','Sources/IPCKit','Extensions']:
    if (VENDOR / forbidden).exists(): errors.append('forbidden vendor content: '+forbidden)
if errors:
    print('CONVOY VENDOR VERIFY FAILED')
    for e in errors: print(' -', e)
    sys.exit(1)
print('CONVOY VENDOR VERIFY OK revision='+REV+' files='+str(len(MANIFEST['files'])))
