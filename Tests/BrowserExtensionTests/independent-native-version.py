# coding: utf-8
import json, os, struct, subprocess, tempfile, sys
host = sys.argv[1]
origin = 'chrome-extension://micfejmbldlgjepdfadhnoalmcbnpllb/'
cases = [
    {'argv': [origin], 'message': {'type': 'status', 'protocolVersion': 999}},
    {'argv': [origin], 'message': {'type': 'status'}},
    {'argv': ['chrome-extension://jfnchkplpoknchbbbnpgobnoolhdahmj/'],
     'message': {'type': 'status', 'protocolVersion': 1}},
    {'argv': [], 'message': {'type': 'status', 'protocolVersion': 1}},
]
failed = 0
with tempfile.TemporaryDirectory(prefix='valora-native-version-', dir='/private/tmp') as root:
    env = os.environ.copy()
    env['TMPDIR'] = root + '/'
    for case in cases:
        message = case['message']
        raw = json.dumps(message).encode()
        p = subprocess.run([host] + case['argv'],
                           input=struct.pack('<I', len(raw)) + raw,
                           capture_output=True, env=env, timeout=8)
        response = json.loads(p.stdout[4:]) if len(p.stdout) >= 4 else {}
        passed = response.get('ok') is False
        failed += not passed
        print(json.dumps({'argv': case['argv'], 'input': message,
                          'passed': passed, 'response': response},
                         ensure_ascii=False))
sys.exit(1 if failed else 0)
