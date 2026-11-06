#!/usr/bin/env python3
"""Read this project's OpenCode conversation text locally; never run OpenCode or write its DB."""
import argparse
import json
import sqlite3
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[1]
ALLOWED = {PROJECT.resolve(), Path('/Users/wangqing/code/alcove-revival-archive').resolve()}
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--directory', type=Path, default=PROJECT)
parser.add_argument('--session', help='Read a specific session belonging to the selected directory')
parser.add_argument('--limit', type=int, default=10, help='Latest user/assistant messages, maximum 100')
parser.add_argument('--list', action='store_true', help='List the latest 10 sessions in this directory')
args = parser.parse_args()
directory = args.directory.resolve()
if directory not in ALLOWED:
    parser.error('Directory is outside the two explicitly authorized project roots')
if not 1 <= args.limit <= 100:
    parser.error('--limit must be between 1 and 100')
db = Path.home() / '.local/share/opencode/opencode.db'
if not db.is_file():
    parser.exit(1, 'OpenCode database is missing: ' + str(db) + '\n')
conn = sqlite3.connect(db.as_uri() + '?mode=ro', uri=True, timeout=3)
conn.execute('PRAGMA query_only=ON')
tables = {r[0] for r in conn.execute("SELECT name FROM sqlite_master WHERE type='table'")}
sessions = []
for table in ('session_v2', 'session'):
    if table not in tables:
        continue
    for row in conn.execute(f'SELECT id,directory,title,time_updated FROM {table} WHERE lower(rtrim(directory,?))=lower(?) ORDER BY time_updated DESC LIMIT 10', ('/', str(directory))):
        sessions.append((table, *row))
sessions.sort(key=lambda row: row[-1], reverse=True)
if args.list:
    print(json.dumps([dict(schema=r[0], id=r[1], directory=r[2], title=r[3], updated_ms=r[4]) for r in sessions[:10]], ensure_ascii=False, indent=2))
    raise SystemExit(0)
selected = next((r for r in sessions if r[1] == args.session), None) if args.session else next(iter(sessions), None)
if selected is None:
    parser.exit(1, 'No matching OpenCode session in the selected directory\n')
schema, sid, workdir, title, updated = selected
print(json.dumps(dict(session=sid, directory=workdir, title=title, updated_ms=updated, schema=schema), ensure_ascii=False))
if schema == 'session_v2':
    rows = conn.execute("SELECT type,seq,data FROM session_message WHERE session_id=? AND type IN ('user','assistant') ORDER BY seq DESC LIMIT ?", (sid, args.limit)).fetchall()
else:
    rows = [(None, r[0], r[1]) for r in conn.execute('SELECT time_created,data FROM message WHERE session_id=? ORDER BY time_created DESC LIMIT ?', (sid, args.limit))]
for role, seq, raw in reversed(rows):
    data = json.loads(raw)
    role = role or data.get('role')
    texts = []
    if role == 'user' and isinstance(data.get('text'), str):
        texts.append(data['text'])
    for part in data.get('content', []):
        if isinstance(part, dict) and part.get('type') == 'text' and isinstance(part.get('text'), str):
            texts.append(part['text'])
    # Deliberately exclude reasoning, tool arguments/results, credentials and all other projects.
    if texts:
        print(json.dumps(dict(role=role, sequence=seq, text='\n'.join(texts)), ensure_ascii=False))
conn.close()
