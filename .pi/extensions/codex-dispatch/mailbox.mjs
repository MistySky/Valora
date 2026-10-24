import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

export const ROOT = '/Users/wangqing/code/Valora';
export const SESSION = '01a1664f-f5e9-70bd-b053-21a027d5407a';

// No shell, network listener, terminal injection, or direct history writes.
export function consume({ root = ROOT, sessionId, cwd, idle, send }) {
  // Check identity before creating a mailbox or publishing status.
  if (sessionId !== SESSION || fs.realpathSync(cwd) !== fs.realpathSync(root)) return;
  const box = path.join(root, '.pi/dispatch');
  fs.mkdirSync(box, { recursive: true, mode: 0o700 });
  const status = (value) => fs.writeFileSync(path.join(box, 'status.json'),
    JSON.stringify({ ...value, time: new Date().toISOString(), sessionId, cwd }, null, 2), { mode: 0o600 });
  if (sessionId !== SESSION || fs.realpathSync(cwd) !== fs.realpathSync(root)) {
    return; // An unrelated session must never claim or overwrite this mailbox.
  }
  const input = path.join(box, 'request.json');
  const claim = path.join(box, 'claimed.json');
  if (fs.existsSync(claim)) return; // Ambiguous interruption requires manual history reconciliation.
  if (!idle) { status({ state: 'busy' }); return; }
  if (!fs.existsSync(input)) { status({ state: 'ready' }); return; }
  let request;
  try {
    const stat = fs.lstatSync(input);
    if (!stat.isFile() || stat.isSymbolicLink() || stat.size > 4096) throw new Error('Invalid request file');
    request = JSON.parse(fs.readFileSync(input, 'utf8'));
    if (request.sessionId !== SESSION || !/^[a-zA-Z0-9_-]{1,100}$/.test(request.id)) throw new Error('Invalid target or id');
    const target = fs.realpathSync(path.resolve(root, request.taskFile));
    if (!target.startsWith(path.join(fs.realpathSync(root), 'docs') + path.sep)) throw new Error('Task must be under project docs');
    const bytes = fs.readFileSync(target);
    if (bytes.length > 65536 || crypto.createHash('sha256').update(bytes).digest('hex') !== request.sha256) throw new Error('Task hash/size mismatch');
    const receipt = path.join(box, request.id + '.receipt.json');
    if (fs.existsSync(receipt)) throw new Error('Duplicate request id');
    fs.renameSync(input, claim);
    // Persist the claim before injection; never automatically resend after a crash.
    fs.writeFileSync(receipt, JSON.stringify({ state: 'claimed', id: request.id }), { mode: 0o600, flag: 'wx' });
    send(`[Codex直接派工 ${request.id}]\n任务文件：${request.taskFile}\nSHA256：${request.sha256}\n\n${bytes.toString('utf8')}`);
    fs.writeFileSync(receipt, JSON.stringify({ state: 'sent', id: request.id, time: new Date().toISOString() }), { mode: 0o600 });
    fs.renameSync(claim, path.join(box, request.id + '.sent.json'));
    status({ state: 'sent', id: request.id });
  } catch (error) {
    status({ state: 'error', id: request?.id, error: String(error) });
    // Keep the request/claim untouched for inspection, never retry injection automatically.
    if (fs.existsSync(input)) fs.renameSync(input, path.join(box, 'rejected.json'));
  }
}
