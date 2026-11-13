import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { addClip, readClips, insertText, deleteText, moveCursor, shouldCapitalize } from '../preview/core.js';

test('Kazakh layout exposes every specific letter and full Cyrillic alphabet', async () => {
  const layouts = JSON.parse(await readFile(new URL('../shared/layouts.json', import.meta.url)));
  const keys = layouts.languages.find(lang => lang.id === 'kk').rows.join('');
  for (const char of 'әіңғүұқөһабвгдеёжзийклмнопрстуфхцчшщъыьэюя') assert.ok(keys.includes(char), char);
  assert.deepEqual(layouts.languages.map(lang => lang.id), ['kk', 'ru', 'en', 'uk', 'de', 'tr', 'fr', 'es']);
});
test('clipboard deduplicates without losing pin or identity', () => {
  let clips = addClip([], 'Сәлем!', () => '1'); clips[0].pinned = true;
  clips = addClip(clips, 'Hello', () => '2');
  clips = addClip(clips, 'Сәлем!', () => '3');
  assert.equal(clips.length, 2); assert.deepEqual(clips[0], { id: '1', text: 'Сәлем!', pinned: true, inHistory: true });
});
test('history keeps exactly ten most recent texts and stores older favorites separately', () => {
  let clips = addClip([], 'favorite', () => 'favorite'); clips[0].pinned = true;
  for (let i = 0; i < 12; i++) clips = addClip(clips, `copy ${i}`, () => String(i));
  assert.deepEqual(clips.filter(clip => clip.inHistory).map(clip => clip.text), Array.from({ length: 10 }, (_, i) => `copy ${11 - i}`));
  assert.equal(clips.find(clip => clip.id === 'favorite').inHistory, false);
  assert.equal(clips.find(clip => clip.id === 'favorite').pinned, true);
  assert.equal(clips.length, 11);
  clips = addClip(clips, 'favorite', () => 'unused');
  assert.equal(clips[0].id, 'favorite'); assert.equal(clips[0].inHistory, true);
  assert.equal(clips.filter(clip => clip.inHistory).length, 10);
});
test('even ten pinned recent copies cannot block automatic history', () => {
  let clips = Array.from({ length: 10 }, (_, i) => ({ id: String(i), text: String(i), pinned: true, inHistory: true }));
  clips = addClip(clips, 'new', () => 'new');
  assert.equal(clips[0].text, 'new'); assert.equal(clips.filter(clip => clip.inHistory).length, 10);
  assert.equal(clips.filter(clip => clip.pinned).length, 10);
  assert.equal(clips.find(clip => clip.id === '9').inHistory, false);
});
test('old 100-entry storage migrates to ten recent entries plus separate favorites', () => {
  const clips = readClips(Array.from({ length: 100 }, (_, i) => ({ id: String(i), text: String(i), pinned: i === 99 })));
  assert.deepEqual(clips.filter(clip => clip.inHistory).map(clip => clip.id), Array.from({ length: 10 }, (_, i) => String(i)));
  assert.equal(clips.length, 11); assert.equal(clips.at(-1).id, '99'); assert.equal(clips.at(-1).inHistory, false);
});
test('invalid and oversized clips are rejected', () => {
  assert.throws(() => addClip([], '   ')); assert.throws(() => addClip([], 'a'.repeat(10001)));
  assert.throws(() => readClips([{ id: 'x', text: '<script>', pinned: 'false' }]));
  assert.throws(() => readClips([{ id: 'x', text: 'a', pinned: false }, { id: 'x', text: 'b', pinned: false }]));
});
test('clips round trip through storage without interpreting text as HTML', () => {
  const clips = addClip([], '<img src=x onerror=alert(1)>\nӘлем', () => 'id');
  assert.deepEqual(readClips(JSON.parse(JSON.stringify(clips))), clips);
});
test('typing replaces selection and keeps trailing text', () => {
  assert.deepEqual(insertText('Hello world', 6, 11, 'әлем'), { value: 'Hello әлем', cursor: 10 });
  assert.deepEqual(insertText('ab', 1, 1, 'қ'), { value: 'aқb', cursor: 2 });
});
test('delete removes a full emoji grapheme or selected range', () => {
  const value = 'Сәлем 👨‍👩‍👧‍👦';
  assert.deepEqual(deleteText(value, value.length, value.length), { value: 'Сәлем ', cursor: 6 });
  assert.deepEqual(deleteText('abcdef', 2, 5), { value: 'abf', cursor: 2 });
  assert.deepEqual(deleteText('', 0, 0), { value: '', cursor: 0 });
});
test('capitalization at sentence and newline boundaries', () => {
  for (const text of ['', 'Сәлем! ', 'Hello. ', '\n']) assert.equal(shouldCapitalize(text), true);
  for (const text of ['сәлем ', 'hello']) assert.equal(shouldCapitalize(text), false);
});
test('cursor movement preserves emoji graphemes and collapses selections', () => {
  const text = 'a👨‍👩‍👧‍👦b';
  assert.equal(moveCursor(text, 1, 1, 1), text.length - 1);
  assert.equal(moveCursor(text, text.length - 1, text.length - 1, -1), 1);
  assert.equal(moveCursor(text, 1, text.length, -1), 1);
  assert.equal(moveCursor(text, 1, text.length, 1), text.length);
});
