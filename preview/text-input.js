export function currentWord(before, after = '', hasSelection = false) {
  if (hasSelection || /^[\p{L}\p{M}\p{N}'’]/u.test(after)) return null;
  const match = /[\p{L}\p{M}]+(?:['’][\p{L}\p{M}]+)*$/u.exec(before);
  if (!match || [...match[0]].length > 64) return null;
  if (/[\p{L}\p{N}@#/_\\.:'’\-]$/u.test(before.slice(0, match.index))) return null;
  return match[0];
}

export function preserveCase(suggestion, original, locale) {
  if (original === original.toLocaleUpperCase(locale)) return suggestion.toLocaleUpperCase(locale);
  if (original[0] === original[0].toLocaleUpperCase(locale)) return suggestion[0].toLocaleUpperCase(locale) + suggestion.slice(1);
  return suggestion;
}

export function distance(lhs, rhs) {
  const a = [...lhs], b = [...rhs];
  const rows = Array.from({ length: a.length + 1 }, () => Array(b.length + 1).fill(0));
  for (let i = 0; i <= a.length; i++) rows[i][0] = i;
  for (let j = 0; j <= b.length; j++) rows[0][j] = j;
  for (let i = 1; i <= a.length; i++) for (let j = 1; j <= b.length; j++) {
    rows[i][j] = Math.min(rows[i - 1][j] + 1, rows[i][j - 1] + 1, rows[i - 1][j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1));
    if (i > 1 && j > 1 && a[i - 1] === b[j - 2] && a[i - 2] === b[j - 1]) rows[i][j] = Math.min(rows[i][j], rows[i - 2][j - 2] + 1);
  }
  return rows[a.length][b.length];
}

export function suggestWords(word, language, lexicon, personal = []) {
  const lower = word.toLocaleLowerCase(language.locale);
  if (lower.length < 2) return [];
  const known = personal.some(item => item.toLocaleLowerCase(language.locale) === lower);
  const words = [...personal, ...(lexicon?.words || [])];
  const candidates = [];
  if (!known && lexicon?.corrections[lower]) candidates.push(lexicon.corrections[lower]);
  candidates.push(...words.filter(item => item.toLocaleLowerCase(language.locale).startsWith(lower) && item.toLocaleLowerCase(language.locale) !== lower));
  if (lower.length >= 3) candidates.push(...words.filter(item => Math.abs(item.length - lower.length) <= 1 && distance(lower, item.toLocaleLowerCase(language.locale)) === 1));
  return [...new Set(candidates.map(item => preserveCase(item, word, language.locale)))].filter(item => item !== word).slice(0, 3);
}

export function correctionEdit(value, start, end, delimiter, language, lexicon, personal, ownedWord) {
  if (![' ', '\n', '.', ',', '!', '?', ';', ':'].includes(delimiter)) return null;
  const word = currentWord(value.slice(0, start), value.slice(end), start !== end);
  if (!word || word !== ownedWord || word.length < 3 || word === word.toLocaleUpperCase(language.locale)) return null;
  const lower = word.toLocaleLowerCase(language.locale);
  if (personal.some(item => item.toLocaleLowerCase(language.locale) === lower)) return null;
  const candidate = lexicon?.corrections[lower];
  if (!candidate) return null;
  const replacement = preserveCase(candidate, word, language.locale);
  return {
    value: value.slice(0, start - word.length) + replacement + delimiter + value.slice(end),
    cursor: start - word.length + replacement.length + delimiter.length,
    original: word, replacement, delimiter
  };
}

export function enabledLanguageIDs(ids, languages) {
  const known = new Set(languages.map(language => language.id));
  const valid = Array.isArray(ids) ? [...new Set(ids)].filter(id => known.has(id)) : ['kk', 'ru', 'en'].filter(id => known.has(id));
  return valid.length ? valid : [languages[0].id];
}

export function emojiWithTone(entry, tone) {
  if (!tone) return entry.text;
  return entry.variants.find(variant => {
    const tones = [...variant].filter(char => /[\u{1F3FB}-\u{1F3FF}]/u.test(char));
    return tones.length && tones.every(char => char === tone);
  }) || entry.text;
}
