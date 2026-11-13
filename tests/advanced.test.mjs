import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { rankGlide, resample, nextWords, deleteWord } from '../preview/glide.js';
import { translationURL, parseGIFs } from '../preview/services.js';

const seeds = JSON.parse(await readFile(new URL('../shared/predictive-seeds.json', import.meta.url)));
const vocabulary = JSON.parse(await readFile(new URL('../shared/prediction.json', import.meta.url)));
const keys = {};
['qwertyuiop', 'asdfghjkl', 'zxcvbnm'].forEach((row, y) => [...row].forEach((char, x) => { keys[char] = { x: (x + y * .4) * 30, y: y * 45 }; }));

test('offline word packs cover every configured language with a real Kazakh vocabulary', () => {
  assert.equal(Object.keys(vocabulary.languages).length, 8);
  assert.ok(vocabulary.languages.kk.length > 4000);
  assert.ok(Object.values(vocabulary.languages).every(words => words.length >= 4000 && new Set(words).size === words.length));
  assert.equal(vocabulary.license, 'CC-BY-SA-4.0');
});
test('glide decoder recognizes a traced word and preserves repeated letters', () => {
  const trace = resample([keys.h, keys.e, keys.l, keys.o], 50);
  const result = rankGlide(trace, keys, ['help', 'hello', 'held', 'home', 'world']);
  assert.equal(result[0], 'hello');
  assert.equal(rankGlide(trace, keys, vocabulary.languages.en)[0], 'hello');
});
test('glide rejects a stationary tap, empty paths and words not available on the layout', () => {
  assert.deepEqual(rankGlide([keys.h, keys.h], keys, ['hello']), []);
  assert.deepEqual(rankGlide([], keys, ['hello']), []);
  assert.deepEqual(rankGlide([keys.h, keys.o], keys, ['сәлем']), []);
});
test('next-word predictions use language-specific context and support personal ranking', () => {
  assert.equal(nextWords('доброе ', 'ru', seeds)[0], 'утро');
  assert.equal(nextWords('how ', 'en', seeds)[0], 'are');
  assert.equal(nextWords('қайырлы ', 'kk', seeds)[0], 'таң');
  assert.deepEqual(nextWords('hello', 'en', seeds), []);
  assert.equal(nextWords('hello ', 'en', seeds, { en: { hello: { friend: 5 } } })[0], 'friend');
});
test('word deletion keeps preceding content and respects selected ranges', () => {
  assert.deepEqual(deleteWord('сәлем әлем ', 11, 11), { value: 'сәлем ', cursor: 6 });
  assert.deepEqual(deleteWord('abc def', 1, 3), { value: 'a def', cursor: 1 });
  assert.deepEqual(deleteWord('hello 👨‍👩‍👧‍👦 ', 18, 18), { value: 'hello ', cursor: 6 });
});
test('translation requests encode text and enforce the provider byte limit', () => {
  const url = translationURL('Сәлем & hello?', 'kk', 'en');
  assert.equal(url.searchParams.get('q'), 'Сәлем & hello?'); assert.equal(url.searchParams.get('langpair'), 'kk|en');
  assert.throws(() => translationURL('ә'.repeat(251), 'kk', 'en'), /500/);
  assert.throws(() => translationURL(' ', 'ru', 'en'));
});
test('GIF parser accepts only bounded HTTPS images from the provider', () => {
  const file = { title: 'File:Cat.gif', imageinfo: [{ mime: 'image/gif', size: 1000, url: 'https://upload.wikimedia.org/cat.gif', descriptionurl: 'https://commons.wikimedia.org/wiki/File:Cat.gif', thumburl: 'https://upload.wikimedia.org/cat-small.gif' }] };
  assert.equal(parseGIFs({ query: { pages: { 1: file } } })[0].title, 'Cat.gif');
  for (const patch of [{ size: 3_000_001 }, { url: 'javascript:alert(1)' }, { mime: 'text/html' }, { thumburl: 'https://evil.example/a.gif' }]) {
    assert.deepEqual(parseGIFs({ query: { pages: { 1: { ...file, imageinfo: [{ ...file.imageinfo[0], ...patch }] } } } }), []);
  }
});
