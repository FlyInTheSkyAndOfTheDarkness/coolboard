import test from 'node:test';
import assert from 'node:assert/strict';
import { ClipboardWatcher } from '../preview/clipboard.js';

function fixture(patch = {}) {
  const saved = [], statuses = [], hashes = [];
  const watcher = new ClipboardWatcher({ enabled: () => true, active: () => true, permission: async () => 'granted', readText: async () => 'copied',
    save: text => saved.push(text), status: (...args) => statuses.push(args), fingerprint: async text => `hash:${text}`, remember: hash => hashes.push(hash), ...patch });
  return { watcher, saved, statuses, hashes };
}
test('automatic scanning stores clipboard changes without a manual save', async () => {
  let current = 'first'; const f = fixture({ readText: async () => current });
  await f.watcher.scan(); current = 'second'; await f.watcher.scan();
  assert.deepEqual(f.saved, ['first', 'second']); assert.deepEqual(f.hashes, ['hash:first', 'hash:second']);
});
test('polling deduplicates but an explicit new copy can move the same text to the top', async () => {
  const f = fixture(); await f.watcher.scan(); await f.watcher.scan();
  await f.watcher.capture('copied', { newCopy: true }); await f.watcher.scan();
  assert.deepEqual(f.saved, ['copied', 'copied']);
});
test('deleted or cleared text is not resurrected after a new monitor starts', async () => {
  const f = fixture({ lastFingerprint: 'hash:copied' }); await f.watcher.scan();
  assert.deepEqual(f.saved, []);
  await f.watcher.capture('copied', { newCopy: true }); assert.deepEqual(f.saved, ['copied']);
});
test('automatic reading never requests ungranted browser permission', async () => {
  let reads = 0; const f = fixture({ permission: async () => 'prompt', readText: async () => { reads++; return 'current'; } });
  await f.watcher.scan(); await f.watcher.scan(); assert.equal(reads, 0);
  await f.watcher.scan({ requestAccess: true }); assert.equal(reads, 1); assert.deepEqual(f.saved, ['current']);
});
test('denial stops repeated reads and local copy events continue working', async () => {
  let reads = 0; const f = fixture({ readText: async () => { reads++; throw new Error('denied'); } });
  await f.watcher.scan(); await f.watcher.scan(); await f.watcher.scan(); assert.equal(reads, 1);
  await f.watcher.capture('copied in page', { newCopy: true }); assert.deepEqual(f.saved, ['copied in page']);
});
test('disabled history and invisible page never read clipboard contents', async () => {
  let reads = 0; const disabled = fixture({ enabled: () => false, readText: async () => { reads++; return 'private'; } });
  const hidden = fixture({ active: () => false, readText: async () => { reads++; return 'private'; } });
  await disabled.watcher.scan(); await disabled.watcher.capture('private', { newCopy: true }); await hidden.watcher.scan();
  assert.equal(reads, 0); assert.deepEqual(disabled.saved, []);
});
test('a late read cannot repopulate a cleared history or save after disabling', async () => {
  let finish; const f = fixture({ readText: () => new Promise(resolve => { finish = resolve; }) });
  const scan = f.watcher.scan(); await Promise.resolve(); f.watcher.invalidate(); finish('old clipboard'); await scan;
  assert.deepEqual(f.saved, []);
});
test('empty and unsupported oversized text do not consume history slots', async () => {
  const f = fixture(); await f.watcher.capture('  '); await f.watcher.capture('a'.repeat(10001));
  assert.deepEqual(f.saved, []);
});
