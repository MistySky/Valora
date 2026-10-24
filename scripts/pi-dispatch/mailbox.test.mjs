import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import { consume, SESSION } from '../../.pi/extensions/codex-dispatch/mailbox.mjs';

function fixture(t) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'valora-mailbox-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  fs.mkdirSync(path.join(root, 'docs'));
  fs.mkdirSync(path.join(root, '.pi/dispatch'), { recursive: true });
  const content = 'Only execute the scoped local task.';
  fs.writeFileSync(path.join(root, 'docs/task.txt'), content);
  const request = { id: 'test-1', sessionId: SESSION, taskFile: 'docs/task.txt', sha256: crypto.createHash('sha256').update(content).digest('hex') };
  const file = path.join(root, '.pi/dispatch/request.json');
  const put = (r = request) => fs.writeFileSync(file, JSON.stringify(r));
  const sent = [];
  const args = { root, cwd: root, sessionId: SESSION, idle: true, send: m => sent.push(m) };
  return { root, request, file, put, sent, args };
}

test('matching idle session sends exactly once and receipts reject duplicate', t => {
  const f = fixture(t); f.put(); consume(f.args); consume(f.args);
  assert.equal(f.sent.length, 1); f.put(); consume(f.args); assert.equal(f.sent.length, 1);
});
test('wrong session or busy agent leaves request unclaimed', t => {
  const f = fixture(t); f.put(); consume({ ...f.args, sessionId: 'other' }); consume({ ...f.args, idle: false });
  assert.equal(f.sent.length, 0); assert.ok(fs.existsSync(f.file));
});
test('modified task hash cannot inject a message', t => {
  const f = fixture(t); f.put({ ...f.request, sha256: 'bad' }); consume(f.args); assert.equal(f.sent.length, 0);
});
test('outside docs and symbolic-link escape are rejected', t => {
  const f = fixture(t); fs.writeFileSync(path.join(f.root, 'outside.txt'), 'x');
  fs.symlinkSync('../outside.txt', path.join(f.root, 'docs/link.txt'));
  f.put({ ...f.request, taskFile: 'docs/link.txt' }); consume(f.args); assert.equal(f.sent.length, 0);
});
test('failed/ambiguous injection is never retried', t => {
  const f = fixture(t); f.put(); let attempts = 0;
  const args = { ...f.args, send: () => { attempts++; throw new Error('delivery uncertain'); } };
  consume(args); consume(args); assert.equal(attempts, 1);
});
