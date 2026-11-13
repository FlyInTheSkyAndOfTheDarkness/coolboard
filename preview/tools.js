import { translate, searchWikipedia, searchGIFs, imageBlob } from './services.js';

const phrases = ['Сәлем!', 'Рақмет!', 'Керемет!', 'Привет!', 'Спасибо!', 'Обнимаю', 'OK!', 'Супер!'];
const faces = ['¯\\_(ツ)_/¯', '(╯°□°)╯︵ ┻━┻', '(づ｡◕‿‿◕｡)づ', 'ಠ_ಠ', 'ʕ•ᴥ•ʔ', '(•̀ᴗ•́)و', '♡', ':-)', ':-D'];
const element = (tag, text, className) => { const node = document.createElement(tag); if (text != null) node.textContent = text; if (className) node.className = className; return node; };

export function installTools(api) {
  const panel = element('div', null, 'panel'); panel.id = 'tools-panel'; panel.hidden = true;
  document.querySelector('.home-indicator').before(panel);
  let active = 'tools', request, speech, media = [], background = '';
  try { media = JSON.parse(localStorage.getItem('coolboard.media') || '[]').filter(item => item && /^data:image\/(png|jpeg|gif);base64,/.test(item.data) && item.data.length < 4_000_000).slice(0, 12); background = localStorage.getItem('coolboard.background') || ''; } catch { media = []; }
  const button = (text, action, label) => {
    const node = element('button', text, 'tool-button'); node.type = 'button'; if (label) node.ariaLabel = label;
    node.onpointerdown = event => event.preventDefault(); node.onclick = action; return node;
  };
  const saveMedia = () => { try { localStorage.setItem('coolboard.media', JSON.stringify(media)); } catch { api.toast('Хранилище заполнено: картинки доступны только в этой вкладке.'); } };
  function header(title) { const row = element('div', null, 'tools-title'); row.append(button('‹', () => api.setPanel('keys'), 'К клавиатуре'), element('strong', title)); panel.append(row); }
  function message(text) { panel.append(element('p', text, 'tools-note')); }
  function consent() {
    if (api.prefs().online) return true;
    message('Запрос отправляется MyMemory или Wikimedia только по нажатию.');
    panel.append(button('Включить онлайн-функции', () => { api.prefs().online = true; api.save(); api.apply(); show(active); })); return false;
  }
  function show(name) {
    request?.abort(); request = undefined; speech?.abort(); speech = undefined;
    active = name; panel.replaceChildren();
    if (name === 'tools') {
      header('Все инструменты');
      const grid = element('div', null, 'tool-grid');
      for (const [label, action] of [
        ['〰 Свайп', () => { api.prefs().glide = !api.prefs().glide; api.save(); api.apply(); api.toast(`Свайп-набор ${api.prefs().glide ? 'включён' : 'выключен'}.`); }],
        ['⇄ Перевод', () => api.setPanel('translate')], ['GIF', () => api.setPanel('gifs')], ['▧ Стикеры', () => api.setPanel('stickers')],
        ['⌕ Поиск', () => api.setPanel('web')], ['🎙 Голос', () => api.setPanel('voice')], ['▤ Буфер', () => api.setPanel('clips')],
        ['← Курсор', () => api.move(-1)], ['Курсор →', () => api.move(1)], ['⌫ Слово', api.deleteWord], ['↶ Отмена', api.undoEdit],
        ['⚙ Настройки', () => api.setPanel('settings')]
      ]) grid.append(button(label, action));
      panel.append(grid);
      const hand = element('div', null, 'hand-options');
      for (const [value, title] of [['off', 'Обычно'], ['left', 'Слева'], ['right', 'Справа']]) hand.append(button(title, () => { api.prefs().oneHanded = value; api.save(); api.apply(); }));
      panel.append(element('p', 'Режим одной руки', 'tools-note'), hand);
    } else if (name === 'voice') voice();
    else if (name === 'stickers') stickers();
    else online(name);
  }
  function online(name) {
    header(name === 'translate' ? 'Перевод · MyMemory' : name === 'gifs' ? 'GIF · Wikimedia' : 'Поиск · Wikipedia');
    consent();
    const form = element('form', null, 'tools-form');
    const query = element('textarea'); query.ariaLabel = name === 'translate' ? 'Текст для перевода' : 'Поисковый запрос'; query.placeholder = name === 'translate' ? 'Что перевести?' : 'Что найти?'; query.maxLength = 1000;
    form.append(query);
    const target = element('select'); target.ariaLabel = 'Язык перевода';
    if (name === 'translate') { for (const lang of api.layouts().languages) { const option = element('option', lang.name); option.value = lang.id; target.append(option); } target.value = api.language().id === 'en' ? 'ru' : 'en'; form.append(target); }
    const result = element('div', null, 'online-results'); result.setAttribute('aria-live', 'polite');
    const submit = element('button', name === 'translate' ? 'Перевести' : 'Найти', 'tool-button'); submit.type = 'submit';
    form.append(button('Из выделенного', () => { query.value = api.selected(); }), submit);
    form.onsubmit = async event => {
      event.preventDefault(); result.replaceChildren();
      if (!api.prefs().online) { result.append(element('p', 'Сначала включи онлайн-функции.', 'tools-note')); return; }
      request?.abort(); const operation = new AbortController(); request = operation;
      submit.disabled = true; result.textContent = 'Загрузка…';
      const timer = setTimeout(() => operation.abort(), 20000);
      try {
        const data = name === 'translate' ? await translate(query.value, api.language().id, target.value, operation.signal) : name === 'gifs' ? await searchGIFs(query.value, operation.signal) : await searchWikipedia(query.value, api.language().id, operation.signal);
        if (operation.signal.aborted || request !== operation) return;
        result.replaceChildren();
        if (name === 'translate') { result.append(element('p', data), button('Вставить перевод', () => { api.insert(data); api.setPanel('keys'); })); }
        else {
          if (!data.length) result.append(element('p', 'Ничего не найдено. Попробуй другой запрос.', 'tools-note'));
          for (const item of data) {
            const row = element('div', null, 'online-item');
            if (name === 'gifs') {
              const img = element('img'); img.src = item.thumbnail; img.alt = item.title; img.loading = 'lazy'; img.referrerPolicy = 'no-referrer'; row.append(img);
              row.append(button('Скачать GIF', async () => {
                try { const blob = await imageBlob(item.url); download(blob, 'coolboard.gif'); api.toast('GIF скачан. Прикрепи его в чате.'); } catch (error) { api.toast(error.message); }
              }));
            }
            row.append(element('span', item.title), button('Вставить ссылку', () => api.insert(item.source || item.url)));
            const source = element('a', 'Источник'); source.href = item.source || item.url; source.target = '_blank'; source.rel = 'noopener noreferrer'; row.append(source); result.append(row);
          }
        }
      } catch (error) { if (request === operation) result.textContent = error.name === 'AbortError' ? 'Запрос остановлен или истёк тайм-аут.' : error.message; }
      finally { clearTimeout(timer); if (request === operation) submit.disabled = false; }
    };
    panel.append(form, result);
    if (name === 'web') {
      const google = element('a', 'Открыть поиск Google ↗', 'tool-button'); google.href = 'https://www.google.com/'; google.target = '_blank'; google.rel = 'noopener noreferrer';
      google.onclick = () => { google.href = `https://www.google.com/search?${new URLSearchParams({ q: query.value })}`; }; panel.append(google);
    }
  }
  function download(blob, name) { const url = URL.createObjectURL(blob); const anchor = element('a'); anchor.href = url; anchor.download = name; anchor.click(); setTimeout(() => URL.revokeObjectURL(url), 1000); }
  async function sticker(phrase) {
    const canvas = element('canvas'); canvas.width = 560; canvas.height = 240;
    const context = canvas.getContext('2d'); context.fillStyle = '#2d6ee6'; context.beginPath(); context.roundRect(8, 8, 544, 224, 60); context.fill();
    context.fillStyle = 'white'; context.font = 'bold 52px sans-serif'; context.textAlign = 'center'; context.textBaseline = 'middle'; context.fillText(phrase, 280, 120, 520);
    const blob = await new Promise(resolve => canvas.toBlob(resolve, 'image/png'));
    try { await navigator.clipboard.write([new ClipboardItem({ 'image/png': blob })]); api.toast('Стикер скопирован. Вставь его в чате.'); }
    catch { download(blob, 'coolboard-sticker.png'); api.toast('Стикер скачан. Можно прикрепить его в чате.'); }
  }
  function stickers() {
    header('Стикеры и текстовые смайлики');
    const grid = element('div', null, 'sticker-grid'); for (const phrase of phrases) grid.append(button(phrase, () => sticker(phrase))); panel.append(grid);
    const text = element('div', null, 'kaomoji-grid'); for (const face of faces) text.append(button(face, () => api.insert(face))); panel.append(text);
    const input = element('input'); input.type = 'file'; input.accept = 'image/png,image/jpeg,image/gif'; input.ariaLabel = 'Добавить свой GIF или стикер';
    input.onchange = () => {
      const file = input.files[0];
      if (!file || !['image/png', 'image/jpeg', 'image/gif'].includes(file.type) || file.size > 3_000_000 || media.length >= 12) { api.toast('Выбери PNG, JPEG или GIF до 3 МБ. В библиотеке до 12 файлов.'); return; }
      const reader = new FileReader(); reader.onload = () => {
        if (media.reduce((sum, item) => sum + item.data.length, 0) + String(reader.result).length > 6_000_000) { api.toast('Библиотека заполнена (6 МБ). Удали файл.'); return; }
        media.unshift({ id: crypto.randomUUID(), name: file.name, data: reader.result }); saveMedia(); stickersRefresh();
      }; reader.readAsDataURL(file);
    };
    panel.append(input);
    const own = element('div'); panel.append(own);
    function stickersRefresh() {
      own.replaceChildren();
      for (const item of media) {
        const row = element('div', null, 'online-item'), img = element('img'); img.src = item.data; img.alt = item.name;
        row.append(img, element('span', item.name), button('Вставить в тест', () => { const preview = element('img'); preview.src = item.data; preview.alt = item.name; document.querySelector('#media-output').replaceChildren(preview); api.toast('Картинка показана отдельно: в текстовое поле изображение вставить нельзя.'); }), button('Удалить', () => { media = media.filter(other => other.id !== item.id); saveMedia(); stickersRefresh(); })); own.append(row);
      }
    }
    stickersRefresh();
  }
  function voice() {
    header('Голосовой ввод');
    const Recognition = window.SpeechRecognition || window.webkitSpeechRecognition;
    message('Браузер может отправлять речь своему провайдеру распознавания. Запись начинается по нажатию и требует разрешения микрофона. На iPhone запись находится в приложении CoolBoard.');
    const output = element('textarea'); output.ariaLabel = 'Распознанный текст';
    const status = element('p', Recognition ? 'Готов к записи.' : 'Этот браузер не поддерживает распознавание речи.', 'tools-note');
    const start = button('Начать запись', () => {
      if (!Recognition) return;
      if (speech) { speech.stop(); return; }
      const recognizer = new Recognition(); speech = recognizer;
      recognizer.lang = api.language().locale; recognizer.continuous = true; recognizer.interimResults = true;
      recognizer.onresult = event => { if (speech === recognizer) output.value = Array.from(event.results).map(result => result[0].transcript).join(' '); };
      recognizer.onerror = event => { status.textContent = `Распознавание остановлено: ${event.error}.`; };
      recognizer.onend = () => { if (speech === recognizer) { speech = undefined; start.textContent = 'Начать запись'; } };
      try { recognizer.start(); start.textContent = 'Остановить запись'; status.textContent = 'Слушаю…'; } catch (error) { speech = undefined; status.textContent = error.message; }
    }); start.disabled = !Recognition;
    panel.append(start, status, output, button('Вставить распознанный текст', () => { speech?.stop(); if (output.value.trim()) { api.insert(output.value); api.setPanel('keys'); } }));
  }
  const photo = document.querySelector('#photo-background');
  photo.onchange = () => {
    const file = photo.files[0]; if (!file || !['image/png', 'image/jpeg', 'image/webp'].includes(file.type) || file.size > 5_000_000) { api.toast('Выбери фото PNG, JPEG или WebP до 5 МБ.'); return; }
    const image = new Image(), url = URL.createObjectURL(file);
    image.onload = () => {
      const canvas = element('canvas'); canvas.width = 700; canvas.height = 500; canvas.getContext('2d').drawImage(image, 0, 0, 700, 500); background = canvas.toDataURL('image/jpeg', .7);
      URL.revokeObjectURL(url);
      try { localStorage.setItem('coolboard.background', background); } catch { api.toast('Фотофон работает только в этой вкладке: хранилище заполнено.'); }
      api.prefs().theme = 'photo'; api.save(); api.apply();
    }; image.onerror = () => { URL.revokeObjectURL(url); api.toast('Не удалось прочитать фото.'); }; image.src = url;
  };
  const fullWidth = button('↔', () => { api.prefs().oneHanded = 'off'; api.save(); api.apply(); }, 'Обычная ширина клавиатуры'); fullWidth.id = 'restore-width'; document.querySelector('#keyboard').append(fullWidth);
  function apply() {
    const keyboard = document.querySelector('#keyboard'), prefs = api.prefs(); keyboard.dataset.hand = prefs.oneHanded; fullWidth.hidden = prefs.oneHanded === 'off';
    keyboard.style.setProperty('--photo-background', prefs.theme === 'photo' && /^data:image\/jpeg;base64,/.test(background) ? `url("${background}")` : 'none');
  }
  document.addEventListener('visibilitychange', () => { if (document.hidden) { speech?.abort(); speech = undefined; request?.abort(); } });
  return { show, apply, close() { request?.abort(); speech?.abort(); speech = undefined; } };
}
