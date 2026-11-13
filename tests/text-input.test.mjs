import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { currentWord, distance, suggestWords, correctionEdit, enabledLanguageIDs, emojiWithTone } from '../preview/text-input.js';

const layouts = JSON.parse(await readFile(new URL('../shared/layouts.json', import.meta.url)));
const lexicons = JSON.parse(await readFile(new URL('../shared/lexicon.json', import.meta.url)));
const emoji = JSON.parse(await readFile(new URL('../shared/emoji.json', import.meta.url)));
const language = id => layouts.languages.find(lang => lang.id === id);

test('word replacement excludes selections, mid-word edits, email, handles, URLs and IDs', () => {
  assert.equal(currentWord('Сәлем, превет'), 'превет');
  assert.equal(currentWord("I don't"), "don't");
  for (const before of ['mail@превет', 'https://превет', 'test.превет', '@превет', '#превет', 'id123превет', 'some_name']) assert.equal(currentWord(before), null, before);
  assert.equal(currentWord('прев', 'ет'), null);
  assert.equal(currentWord('превет', '', true), null);
});
test('common typo correction preserves case and only corrects the word being typed', () => {
  const edit = correctionEdit('Ну, Превет', 10, 10, ' ', language('ru'), lexicons.ru, [], 'Превет');
  assert.equal(edit.value, 'Ну, Привет ');
  assert.equal(edit.cursor, edit.value.length);
  assert.equal(correctionEdit('превет', 6, 6, ' ', language('ru'), lexicons.ru, [], null), null, 'pasted words must stay unchanged');
  assert.equal(correctionEdit('ПРЕВЕТ', 6, 6, ' ', language('ru'), lexicons.ru, [], 'ПРЕВЕТ'), null, 'preserve acronyms');
  assert.equal(correctionEdit('превет', 6, 6, ' ', language('ru'), lexicons.ru, ['Превет'], 'превет'), null, 'respect personal dictionary');
});
test('Kazakh correction and completion remain in Kazakh', () => {
  assert.equal(correctionEdit('салем', 5, 5, ' ', language('kk'), lexicons.kk, [], 'салем').value, 'сәлем ');
  assert.ok(suggestWords('қаз', language('kk'), lexicons.kk).includes('қазақ'));
  assert.deepEqual(suggestWords('қаз', language('en'), lexicons.en), []);
  assert.ok(suggestWords('he', language('en'), lexicons.en).includes('hello'));
});
test('distance handles adjacent transpositions and Unicode letters', () => {
  assert.equal(distance('teh', 'the'), 1);
  assert.equal(distance('салем', 'сәлем'), 1);
  assert.equal(distance('', 'abc'), 3);
});
test('enabled language migration preserves at least one available language', () => {
  assert.deepEqual(enabledLanguageIDs(undefined, layouts.languages), ['kk', 'ru', 'en']);
  assert.deepEqual(enabledLanguageIDs(['de', 'de', 'not-installed'], layouts.languages), ['de']);
  assert.deepEqual(enabledLanguageIDs([], layouts.languages), ['kk']);
  assert.deepEqual(enabledLanguageIDs(['gone'], layouts.languages), ['kk']);
});
test('complete bundled emoji catalog preserves sequences, modifiers and localized search names', () => {
  const entries = emoji.categories.flatMap(category => category.entries);
  const sequences = entries.flatMap(entry => [entry.text, ...entry.variants]);
  assert.equal(emoji.categories.length, 9);
  assert.equal(sequences.length, 3781);
  assert.equal(new Set(sequences).size, 3781);
  const thumbsUp = entries.find(entry => entry.text === '👍');
  assert.equal(emojiWithTone(thumbsUp, '🏽'), '👍🏽');
  assert.equal(emojiWithTone(thumbsUp, ''), '👍');
  assert.equal(emojiWithTone(entries.find(entry => entry.text === '❤️'), '🏽'), '❤️');
  assert.ok(entries.some(entry => entry.keywords.includes('сердце')));
  assert.ok(entries.some(entry => entry.keywords.includes('жүрек')));
  assert.ok(sequences.includes('👨‍👩‍👧‍👦'));
  assert.ok(sequences.includes('🇰🇿'));
});
