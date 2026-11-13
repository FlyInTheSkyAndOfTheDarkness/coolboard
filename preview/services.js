export async function fetchJSON(url, signal) {
  const response = await fetch(url, { signal: signal || AbortSignal.timeout(20000), credentials: 'omit' });
  if (!response.ok) throw new Error(`Сервис недоступен (${response.status}).`);
  const text = await response.text();
  if (text.length > 2_000_000) throw new Error('Слишком большой ответ сервиса.');
  return JSON.parse(text);
}
export function translationURL(text, from, to) {
  if (!text.trim()) throw new Error('Введи текст для перевода.');
  if (new TextEncoder().encode(text).length > 500) throw new Error('За один запрос можно перевести до 500 байт текста.');
  const url = new URL('https://api.mymemory.translated.net/get'); url.search = new URLSearchParams({ q: text, langpair: `${from}|${to}` }); return url;
}
export async function translate(text, from, to, signal) {
  const url = translationURL(text, from, to);
  if (from === to) return text;
  const data = await fetchJSON(url, signal);
  if (Number(data.responseStatus) !== 200 || data.quotaFinished || typeof data.responseData?.translatedText !== 'string') throw new Error(data.responseDetails || 'Перевод недоступен или исчерпан лимит сервиса.');
  return data.responseData.translatedText;
}
export async function searchWikipedia(query, language, signal) {
  if (!query.trim()) throw new Error('Введи запрос.');
  const lang = ['kk', 'ru', 'en', 'uk', 'de', 'tr', 'fr', 'es'].includes(language) ? language : 'en';
  const url = new URL(`https://${lang}.wikipedia.org/w/api.php`);
  url.search = new URLSearchParams({ action: 'query', list: 'search', srsearch: query.slice(0, 150), srlimit: '8', format: 'json', origin: '*' });
  const data = await fetchJSON(url, signal);
  return (data.query?.search || []).filter(item => Number.isInteger(item.pageid) && typeof item.title === 'string').map(item => ({ title: item.title, url: `https://${lang}.wikipedia.org/?curid=${item.pageid}` }));
}
export function parseGIFs(data) {
  return Object.values(data.query?.pages || {}).flatMap(page => {
    const image = page.imageinfo?.[0];
    if (!image || image.mime !== 'image/gif' || !Number.isFinite(image.size) || image.size > 3_000_000) return [];
    try {
      const url = new URL(image.url), source = new URL(image.descriptionurl), thumb = new URL(image.thumburl || image.url);
      if (url.protocol !== 'https:' || url.hostname !== 'upload.wikimedia.org' || source.protocol !== 'https:' || source.hostname !== 'commons.wikimedia.org' || thumb.protocol !== 'https:' || thumb.hostname !== 'upload.wikimedia.org') return [];
      return [{ title: String(page.title).replace(/^File:/, ''), url: url.href, source: source.href, thumbnail: thumb.href, size: image.size }];
    } catch { return []; }
  });
}
export async function searchGIFs(query, signal) {
  if (!query.trim()) throw new Error('Введи запрос для GIF.');
  const url = new URL('https://commons.wikimedia.org/w/api.php');
  url.search = new URLSearchParams({ action: 'query', generator: 'search', gsrsearch: `${query.slice(0, 100)} filemime:image/gif`, gsrnamespace: '6', gsrlimit: '12', prop: 'imageinfo', iiprop: 'url|mime|size', iiurlwidth: '160', format: 'json', origin: '*' });
  return parseGIFs(await fetchJSON(url, signal));
}

export async function imageBlob(url) {
  const address = new URL(url);
  if (address.protocol !== 'https:' || address.hostname !== 'upload.wikimedia.org') throw new Error('Неподдерживаемый адрес картинки.');
  const response = await fetch(address, { credentials: 'omit', signal: AbortSignal.timeout(20000) });
  if (!response.ok || Number(response.headers.get('content-length')) > 3_000_000) throw new Error('Не удалось загрузить GIF до 3 МБ.');
  const reader = response.body.getReader(); const chunks = []; let size = 0;
  try {
    while (true) { const { value, done } = await reader.read(); if (done) break; size += value.byteLength; if (size > 3_000_000) { await reader.cancel(); throw new Error('GIF больше 3 МБ.'); } chunks.push(value); }
  } finally { reader.releaseLock(); }
  const blob = new Blob(chunks, { type: 'image/gif' });
  const signature = await blob.slice(0, 6).text();
  if (!['GIF87a', 'GIF89a'].includes(signature)) throw new Error('Сервис вернул файл другого типа.');
  return blob;
}
