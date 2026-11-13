export const MAX_CLIPS = 10;
export const MAX_FAVORITES = 100;
export const MAX_LENGTH = 10000;

export function addClip(clips, text, createID = () => crypto.randomUUID()) {
  if (typeof text !== 'string' || !text.trim()) throw new Error('В буфере нет текста.');
  if (text.length > MAX_LENGTH) throw new Error('Максимум 10 000 символов в одном фрагменте.');
  const existing = clips.find(clip => clip.text === text);
  return readClips([{ id: existing?.id || createID(), text, pinned: existing?.pinned || false, inHistory: true }, ...clips.filter(clip => clip.text !== text)]);
}

export function readClips(raw) {
  if (!Array.isArray(raw) || raw.length > MAX_CLIPS + MAX_FAVORITES + 1) throw new Error('Неверный формат библиотеки.');
  const ids = new Set(), texts = new Set(); let recent = 0, favorites = 0;
  return raw.map(clip => {
    if (!clip || typeof clip.id !== 'string' || !clip.id || ids.has(clip.id) || typeof clip.text !== 'string' || !clip.text.trim() || clip.text.length > MAX_LENGTH || typeof clip.pinned !== 'boolean') throw new Error('Неверный формат фрагмента.');
    ids.add(clip.id);
    if (clip.inHistory !== undefined && typeof clip.inHistory !== 'boolean') throw new Error('Неверный формат истории.');
    if (texts.has(clip.text)) return null;
    texts.add(clip.text);
    const pinned = clip.pinned && ++favorites <= MAX_FAVORITES;
    const inHistory = (clip.inHistory ?? true) && ++recent <= MAX_CLIPS;
    return inHistory || pinned ? { id: clip.id, text: clip.text, pinned, inHistory } : null;
  }).filter(Boolean);
}

export function insertText(value, start, end, text) {
  return { value: value.slice(0, start) + text + value.slice(end), cursor: start + text.length };
}

export function deleteText(value, start, end) {
  if (start !== end) return insertText(value, start, end, '');
  const segments = [...new Intl.Segmenter(undefined, { granularity: 'grapheme' }).segment(value.slice(0, start))];
  return insertText(value, segments.at(-1)?.index ?? 0, start, '');
}

export function moveCursor(value, start, end, direction) {
  if (start !== end) return direction < 0 ? start : end;
  const boundaries = [...new Intl.Segmenter().segment(value)].map(segment => segment.index);
  boundaries.push(value.length);
  return direction < 0 ? (boundaries.findLast(index => index < start) ?? 0) : (boundaries.find(index => index > end) ?? value.length);
}

export function shouldCapitalize(context) {
  return context.length === 0 || /[.!?\n][ \t]*$/u.test(context);
}
