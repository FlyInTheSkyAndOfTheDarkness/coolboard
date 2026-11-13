import { addClip, readClips, insertText, deleteText, moveCursor, shouldCapitalize } from './core.js';
import { currentWord, suggestWords, correctionEdit, enabledLanguageIDs, emojiWithTone } from './text-input.js';
import { rankGlide, nextWords, deleteWord } from './glide.js';
import { installTools } from './tools.js';
import { installClipboardCapture } from './clipboard.js';

const $ = selector => document.querySelector(selector);
const [layouts, lexicons, emojiCatalog, predictionPack, seeds] = await Promise.all(['layouts', 'lexicon', 'emoji', 'prediction', 'predictive-seeds'].map(name => fetch(`/shared/${name}.json`).then(response => { if (!response.ok) throw new Error('Не удалось загрузить данные клавиатуры'); return response.json(); })));
const defaults = { theme: 'gboard', language: 'kk', enabledLanguages: ['kk', 'ru', 'en'], size: 'normal', numberRow: false, autoCap: true, doubleSpace: true, autocorrect: true, predictions: true, emojiTone: '', glide: true, nextWord: true, multilingual: true, haptics: false, online: false, oneHanded: 'off', autoClipboard: true };
const themes = { gboard: ['Gboard · светлая', '#ffffff'], graphite: ['Графит', '#414844'], paper: ['Бумага', '#dae1d1'], ocean: ['Океан', '#304a5e'], rose: ['Роза', '#795768'], photo: ['Фотофон', '#526078'] };
let prefs = { ...defaults }, clips = [], panel = 'keys', symbolPage = -1, shift = null, caps = false, lastShift = 0, lastSpace = 0, toastTimer;
let composingWord = null, undo = null, personalWords = {}, recentEmoji = [], emojiCategory = 'smileys';
let toolFeatures, glideChoice = null, trace = null, suppressLettersUntil = 0, historyMuted = false;
let clipboardCapture, clipSection = 'history';
const editHistory = [], redoHistory = [];
const allEmoji = emojiCatalog.categories.flatMap(category => category.entries);
const knownEmoji = new Set(allEmoji.flatMap(entry => [entry.text, ...entry.variants]));
const editor = $('#editor');
editor.placeholder = 'Сәлем! Как дела?\nHello, world.';
try {
  const saved = JSON.parse(localStorage.getItem('coolboard.preferences') || '{}');
  prefs = {
    theme: Object.hasOwn(themes, saved.theme) ? saved.theme : defaults.theme,
    language: layouts.languages.some(l => l.id === saved.language) ? saved.language : defaults.language,
    enabledLanguages: enabledLanguageIDs(saved.enabledLanguages, layouts.languages),
    size: ['compact', 'normal', 'large'].includes(saved.size) ? saved.size : defaults.size,
    numberRow: typeof saved.numberRow === 'boolean' ? saved.numberRow : defaults.numberRow,
    autoCap: typeof saved.autoCap === 'boolean' ? saved.autoCap : defaults.autoCap,
    doubleSpace: typeof saved.doubleSpace === 'boolean' ? saved.doubleSpace : defaults.doubleSpace,
    autocorrect: typeof saved.autocorrect === 'boolean' ? saved.autocorrect : true,
    predictions: typeof saved.predictions === 'boolean' ? saved.predictions : true,
    emojiTone: ['', '🏻', '🏼', '🏽', '🏾', '🏿'].includes(saved.emojiTone) ? saved.emojiTone : '',
    glide: saved.glide !== false, nextWord: saved.nextWord !== false, multilingual: saved.multilingual !== false,
    haptics: saved.haptics === true, online: saved.online === true,
    autoClipboard: saved.autoClipboard !== false,
    oneHanded: ['left', 'right', 'off'].includes(saved.oneHanded) ? saved.oneHanded : 'off'
  };
  if (!prefs.enabledLanguages.includes(prefs.language)) prefs.language = prefs.enabledLanguages[0];
  clips = readClips(JSON.parse(localStorage.getItem('coolboard.clips') || '[]'));
  const words = JSON.parse(localStorage.getItem('coolboard.words') || '{}');
  for (const lang of layouts.languages) personalWords[lang.id] = Array.isArray(words?.[lang.id]) ? words[lang.id].filter(word => typeof word === 'string' && word.length <= 64).slice(0, 500) : [];
  const recent = JSON.parse(localStorage.getItem('coolboard.emoji') || '[]');
  recentEmoji = Array.isArray(recent) ? [...new Set(recent)].filter(text => knownEmoji.has(text)).slice(0, 32) : [];
} catch { toast('Локальное хранилище недоступно или повреждено. Настройки работают в этой вкладке.'); }

function toast(message) {
  $('#toast').textContent = message; $('#toast').classList.add('visible');
  clearTimeout(toastTimer); toastTimer = setTimeout(() => $('#toast').classList.remove('visible'), 4500);
}
function persist() {
  try { localStorage.setItem('coolboard.preferences', JSON.stringify(prefs)); localStorage.setItem('coolboard.clips', JSON.stringify(clips)); localStorage.setItem('coolboard.words', JSON.stringify(personalWords)); localStorage.setItem('coolboard.emoji', JSON.stringify(recentEmoji)); }
  catch { toast('Не удалось сохранить на устройстве: хранилище заполнено или отключено.'); }
}
function language() { return layouts.languages.find(item => item.id === prefs.language); }
function activeWord() { return currentWord(editor.value.slice(0, editor.selectionStart), editor.value.slice(editor.selectionEnd), editor.selectionStart !== editor.selectionEnd); }
function canUndo() { return undo && editor.value === undo.value && editor.selectionStart === undo.cursor && editor.selectionEnd === undo.cursor; }
function undoCorrection(keepDelimiter = true) {
  if (!canUndo()) { undo = null; return; }
  const start = undo.cursor - undo.replacement.length - undo.delimiter.length;
  updateEditor(insertText(editor.value, start, undo.cursor, undo.original + (keepDelimiter ? undo.delimiter : '')));
  undo = null; composingWord = null; lastSpace = 0; renderKeys();
}
function updateEditor(result) {
  if (!historyMuted && editor.value !== result.value) { editHistory.push({ value: editor.value, cursor: editor.selectionStart }); if (editHistory.length > 60) editHistory.shift(); redoHistory.length = 0; }
  editor.value = result.value; editor.focus({ preventScroll: true }); editor.setSelectionRange(result.cursor, result.cursor);
  $('#character-count').textContent = `${[...new Intl.Segmenter().segment(editor.value)].length} символов`;
}
function insert(text, isSpace = false) {
  glideChoice = null;
  lastShift = 0;
  const start = editor.selectionStart, end = editor.selectionEnd;
  const before = editor.value.slice(0, start);
  const otherLanguageWord = prefs.multilingual && composingWord && prefs.enabledLanguages.some(id => id !== prefs.language && predictionPack.languages[id]?.includes(composingWord.toLocaleLowerCase()));
  const correction = prefs.autocorrect && !otherLanguageWord ? correctionEdit(editor.value, start, end, text, language(), lexicons[prefs.language], personalWords[prefs.language] || [], composingWord) : null;
  undo = null;
  if (correction) {
    updateEditor(correction); undo = correction; lastSpace = isSpace ? Date.now() : 0;
  } else if (isSpace && prefs.doubleSpace && start === end && Date.now() - lastSpace < 400 && /[\p{L}\p{N}] $/u.test(before)) {
    updateEditor(insertText(editor.value, start - 1, end, '. ')); lastSpace = 0;
  } else { updateEditor(insertText(editor.value, start, end, text)); lastSpace = isSpace ? Date.now() : 0; }
  shift = null;
  composingWord = null;
  renderKeys();
}
function typeCharacter(text) {
  if (performance.now() < suppressLettersUntil) return;
  if (prefs.haptics) navigator.vibrate?.(5);
  const previous = activeWord(), owned = composingWord;
  insert(text);
  if (/^[\p{L}\p{M}]$/u.test(text) && (previous === null || previous === owned)) composingWord = activeWord();
}
function erase() {
  lastShift = 0;
  if (canUndo()) { undoCorrection(false); return; }
  const owned = composingWord === activeWord();
  undo = null;
  updateEditor(deleteText(editor.value, editor.selectionStart, editor.selectionEnd)); lastSpace = 0; shift = null;
  composingWord = owned ? activeWord() : null; renderKeys();
}
function key(title, action, options = {}) {
  const button = document.createElement('button'); button.type = 'button'; button.className = `key ${options.className || ''}`;
  button.textContent = title; button.ariaLabel = options.label || title;
  if (options.flex) button.style.flex = options.flex;
  // Preserve the editor selection when a virtual key is pressed.
  button.addEventListener('pointerdown', event => { event.preventDefault(); });
  button.addEventListener('click', action);
  return button;
}
function renderKeys() {
  const area = $('#keys-panel'); area.replaceChildren();
  if (!canUndo()) undo = null;
  const validGlide = glideChoice && glideChoice.value === editor.value && glideChoice.cursor === editor.selectionStart && editor.selectionEnd === editor.selectionStart;
  if (!validGlide) glideChoice = null;
  if (prefs.predictions || canUndo() || validGlide) {
    const bar = document.createElement('div'); bar.className = 'prediction-bar';
    if (validGlide) {
      glideChoice.options.forEach(word => bar.append(key(word, () => {
        if (!glideChoice || glideChoice.value !== editor.value) return;
        const previous = glideChoice;
        updateEditor(insertText(editor.value, previous.cursor - previous.word.length - 1, previous.cursor, word + ' '));
        glideChoice = { ...previous, word, value: editor.value, cursor: editor.selectionStart }; renderKeys();
      }, { label: `Подсказка: ${word}` })));
    } else if (canUndo()) {
      const cancel = key(`↶ Вернуть «${undo.original}»`, () => undoCorrection(), { label: 'Отменить автокоррекцию' }); bar.append(cancel);
    } else {
      const word = activeWord();
      let guesses = word ? suggestWords(word, language(), lexicons[prefs.language], personalWords[prefs.language] || []) : prefs.nextWord ? nextWords(editor.value.slice(0, editor.selectionStart), prefs.language, seeds) : [];
      if (word) {
        for (const id of prefs.multilingual ? [prefs.language, ...prefs.enabledLanguages.filter(id => id !== prefs.language)] : [prefs.language]) {
          guesses.push(...(predictionPack.languages[id] || []).filter(item => item.startsWith(word.toLocaleLowerCase()) && item !== word.toLocaleLowerCase()).slice(0, 3));
        }
        guesses = [...new Set(guesses)].slice(0, 3);
      }
      if (!guesses.length) { const hint = document.createElement('span'); hint.textContent = word || 'CoolBoard'; bar.append(hint); }
      guesses.forEach(suggestion => bar.append(key(suggestion, () => {
        if (activeWord() !== word) return;
        updateEditor(insertText(editor.value, editor.selectionStart - (word?.length || 0), editor.selectionEnd, suggestion + ' '));
        undo = null; composingWord = null; renderKeys();
      }, { label: `Подсказка: ${suggestion}` })));
      if (word) bar.append(key('＋', () => {
        const words = personalWords[prefs.language] || [];
        personalWords[prefs.language] = [word, ...words.filter(item => item !== word)].slice(0, 500);
        persist(); renderKeys(); toast(`«${word}» добавлено в твой словарь.`);
      }, { label: 'Запомнить слово', className: 'learn-word' }));
    }
    area.append(bar);
  }
  const lang = language();
  const mainRow = ['kk', 'fr', 'es'].includes(lang.id) ? lang.rows[1] : lang.rows[0];
  const baseCount = symbolPage < 0 ? [...mainRow].length : 10;
  const upper = caps || (shift ?? (prefs.autoCap && shouldCapitalize(editor.value.slice(0, editor.selectionStart))));
  const rows = symbolPage < 0 ? [...lang.rows] : [...layouts.symbols[symbolPage]];
  if (prefs.numberRow && symbolPage < 0) rows.unshift('1234567890');
  rows.forEach((row, index) => {
    const div = document.createElement('div'); div.className = 'key-row';
    div.style.setProperty('--row-columns', Math.max(baseCount, [...row].length));
    if (index === rows.length - 1) {
      div.append(key(symbolPage < 0 ? (caps ? '⇪' : '⇧') : (symbolPage === 0 ? '#+=' : '123'), () => {
        if (symbolPage >= 0) symbolPage = symbolPage === 0 ? 1 : 0;
        else if (Date.now() - lastShift < 300) { caps = !caps; shift = null; lastShift = 0; }
        else { shift = !upper; caps = false; lastShift = Date.now(); }
        renderKeys();
      }, { className: `special ${upper && symbolPage < 0 ? 'accent' : ''}`, flex: '1.45', label: symbolPage < 0 ? 'Shift' : 'Другие символы' }));
    }
    [...row].forEach((char, charIndex) => {
      const display = symbolPage < 0 && upper ? char.toLocaleUpperCase(lang.locale) : char;
      const letter = key(display, () => typeCharacter(display), { className: `letter-key ${lang.id === 'kk' && row === lang.rows[0] && symbolPage < 0 ? 'kazakh' : ''}` });
      letter.dataset.character = char;
      if (symbolPage < 0 && /^\p{L}$/u.test(char)) attachGlide(letter);
      if (symbolPage < 0 && row === mainRow && !prefs.numberRow && charIndex < 10) {
        const hint = String((charIndex + 1) % 10); const small = document.createElement('small'); small.className = 'key-hint'; small.textContent = hint; letter.append(small);
        letter.title = `Удерживай / правая кнопка: ${hint}`;
        letter.oncontextmenu = event => { event.preventDefault(); insert(hint); };
      }
      div.append(letter);
    });
    if (index === rows.length - 1) {
      const del = key('⌫', () => {}, { className: 'special', flex: '1.45', label: 'Удалить символ' });
      let delay, repeat;
      const stop = () => { clearTimeout(delay); clearInterval(repeat); document.removeEventListener('pointerup', stop); document.removeEventListener('pointercancel', stop); window.removeEventListener('blur', stop); };
      del.addEventListener('pointerdown', () => {
        erase();
        delay = setTimeout(() => { repeat = setInterval(erase, 75); }, 400);
        document.addEventListener('pointerup', stop); document.addEventListener('pointercancel', stop); window.addEventListener('blur', stop);
      });
      del.addEventListener('click', event => { if (event.detail === 0) erase(); });
      div.append(del);
    }
    area.append(div);
  });
  const bottom = document.createElement('div'); bottom.className = 'key-row';
  bottom.append(key(symbolPage < 0 ? '123' : 'АБВ', () => { symbolPage = symbolPage < 0 ? 0 : -1; renderKeys(); }, { className: 'special', flex: '1.3', label: 'Буквы и символы' }));
  bottom.append(key('⚙', () => setPanel('settings'), { className: 'special', flex: '.9', label: 'Настройки клавиатуры' }));
  const languageKey = key(lang.title, () => { prefs.language = prefs.enabledLanguages[(prefs.enabledLanguages.indexOf(lang.id) + 1) % prefs.enabledLanguages.length]; shift = null; caps = false; symbolPage = -1; composingWord = null; undo = null; persist(); renderKeys(); }, { className: 'special', flex: '1.3', label: 'Сменить язык' });
  languageKey.addEventListener('contextmenu', event => { event.preventDefault(); setPanel('settings'); $('.language-settings').scrollIntoView({ block: 'nearest' }); });
  bottom.append(key('😀', () => setPanel('emoji'), { className: 'special emoji-font', flex: '.9', label: 'Открыть эмодзи' }));
  let spaceDragging = false;
  const spaceKey = key(lang.name, () => { if (!spaceDragging) insert(' ', true); }, { className: 'space', flex: '5.8', label: 'Пробел' });
  spaceKey.title = 'Свайп по пробелу двигает курсор';
  let startX = 0, consumed = 0;
  spaceKey.addEventListener('pointerdown', event => { spaceDragging = false; startX = event.clientX; consumed = 0; spaceKey.setPointerCapture(event.pointerId); });
  spaceKey.addEventListener('pointermove', event => {
    if (!spaceKey.hasPointerCapture(event.pointerId)) return;
    const steps = Math.trunc((event.clientX - startX - consumed) / 12);
    if (!steps) return;
    spaceDragging = true; consumed += steps * 12;
    let cursor = editor.selectionStart;
    for (let index = 0; index < Math.abs(steps); index++) cursor = moveCursor(editor.value, cursor, cursor, Math.sign(steps));
    editor.setSelectionRange(cursor, cursor); composingWord = null; undo = null; lastSpace = 0;
  });
  spaceKey.addEventListener('pointerup', () => { if (spaceDragging) { editor.focus({ preventScroll: true }); setTimeout(renderKeys, 0); } });
  bottom.append(spaceKey);
  bottom.append(key('.', () => insert('.'), { className: 'special', flex: '.8' }));
  bottom.append(key('↵', () => insert('\n'), { className: 'accent return', flex: '1.6', label: 'Новая строка' }));
  area.append(bottom);
  const dock = document.createElement('div'); dock.className = 'keyboard-dock';
  const globe = document.createElement('span'); globe.textContent = '🌐'; globe.className = 'dock-globe'; globe.title = 'На iPhone: переключение системной клавиатуры';
  languageKey.className = 'dock-language';
  const brand = document.createElement('span'); brand.className = 'dock-brand'; brand.textContent = 'CoolBoard';
  dock.append(globe, languageKey, brand); area.append(dock);
}
function setPanel(next) {
  if (next !== panel) toolFeatures?.close();
  panel = next;
  for (const name of ['keys', 'clips', 'settings', 'emoji']) $(`#${name}-panel`).hidden = name !== next;
  if ($('#tools-panel')) $('#tools-panel').hidden = ['keys', 'clips', 'settings', 'emoji'].includes(next);
  document.querySelectorAll('[data-panel]').forEach(button => { button.classList.toggle('active', button.dataset.panel === next); button.setAttribute('aria-pressed', String(button.dataset.panel === next)); });
  if (next === 'clips') renderClips();
  if (next === 'emoji') renderEmoji();
  if (!['keys', 'clips', 'settings', 'emoji'].includes(next)) toolFeatures?.show(next);
}
function saveClip(text, { quiet = false } = {}) {
  try { clips = addClip(clips, text); persist(); renderClips(); if (!quiet) toast('Текст сохранён в истории.'); return true; }
  catch (error) { if (!quiet) toast(error.message); return false; }
}
function renderClips() {
  $('#clip-count').textContent = clips.filter(clip => clip.inHistory).length;
  $('#history-count').textContent = `${clips.filter(clip => clip.inHistory).length}/10`;
  const list = $('#clips-list'); list.replaceChildren();
  const search = $('#clip-search').value.toLocaleLowerCase();
  const filtered = clips.filter(clip => (clipSection === 'favorites' ? clip.pinned : clip.inHistory) && clip.text.toLocaleLowerCase().includes(search));
  document.querySelectorAll('[data-clip-section]').forEach(button => button.setAttribute('aria-pressed', String(button.dataset.clipSection === clipSection)));
  if (!filtered.length) {
    const empty = document.createElement('div'); empty.className = 'empty-clips';
    empty.textContent = search ? 'Ничего не найдено.' : clipSection === 'favorites' ? 'Закреплённые фразы хранятся отдельно от последних 10 копирований.' : 'Скопируй текст — он попадёт сюда автоматически. Здесь остаются последние 10 разных текстов.'; list.append(empty);
  }
  filtered.forEach(clip => {
    const item = document.createElement('div'); item.className = 'clip';
    const text = document.createElement('button'); text.className = 'clip-text'; text.textContent = clip.text; text.title = 'Вставить фрагмент';
    text.addEventListener('pointerdown', event => event.preventDefault()); text.onclick = () => { insert(clip.text); setPanel('keys'); };
    const pin = document.createElement('button'); pin.className = `clip-action ${clip.pinned ? 'pinned' : ''}`; pin.textContent = clip.pinned ? '★' : '☆'; pin.ariaLabel = clip.pinned ? 'Открепить' : 'Закрепить'; pin.onclick = () => {
      if (!clip.pinned && clips.filter(item => item.pinned).length >= 100) { toast('Можно закрепить до 100 фраз.'); return; }
      clip.pinned = !clip.pinned; clips = clips.filter(item => item.inHistory || item.pinned); persist(); renderClips();
    };
    const remove = document.createElement('button'); remove.className = 'clip-action'; remove.textContent = '×'; remove.ariaLabel = 'Удалить фрагмент'; remove.onclick = () => { clipboardCapture?.invalidate(); clips = clips.filter(item => item.id !== clip.id); persist(); renderClips(); };
    item.append(text, pin, remove); list.append(item);
  });
}
function applyPreferences() {
  $('.phone').dataset.theme = prefs.theme;
  $('.phone').style.setProperty('--key-height', { compact: '36px', normal: '43px', large: '51px' }[prefs.size]);
  $('#key-size').value = prefs.size;
  $('#number-row').checked = prefs.numberRow; $('#auto-cap').checked = prefs.autoCap; $('#double-space').checked = prefs.doubleSpace;
  $('#autocorrect').checked = prefs.autocorrect; $('#predictions').checked = prefs.predictions;
  $('#auto-clipboard').checked = prefs.autoClipboard;
  for (const [selector, property] of [['#glide', 'glide'], ['#next-word', 'nextWord'], ['#multilingual', 'multilingual'], ['#haptics', 'haptics'], ['#online-services', 'online']]) $(selector).checked = prefs[property];
  $('#one-handed').value = prefs.oneHanded;
  $('#quick-t9').setAttribute('aria-pressed', String(prefs.autocorrect)); $('#quick-t9').classList.toggle('active', prefs.autocorrect);
  $('.workspace-caption span:last-child').textContent = prefs.enabledLanguages.map(id => layouts.languages.find(lang => lang.id === id).title).join(' / ');
  document.querySelectorAll('[data-theme-choice]').forEach(button => button.setAttribute('aria-pressed', String(button.dataset.themeChoice === prefs.theme)));
  renderKeys();
  renderLanguages();
  toolFeatures?.apply();
  clipboardCapture?.resume(); void clipboardCapture?.scan();
}
function renderLanguages() {
  const list = $('#language-options'); list.replaceChildren();
  for (const lang of layouts.languages) {
    const row = document.createElement('label'); row.className = 'setting-row';
    const text = document.createElement('span'); text.textContent = lang.name;
    const toggle = document.createElement('input'); toggle.type = 'checkbox'; toggle.setAttribute('role', 'switch'); toggle.ariaLabel = lang.name;
    toggle.checked = prefs.enabledLanguages.includes(lang.id); toggle.disabled = toggle.checked && prefs.enabledLanguages.length === 1;
    toggle.onchange = () => {
      prefs.enabledLanguages = enabledLanguageIDs(toggle.checked ? [...prefs.enabledLanguages, lang.id] : prefs.enabledLanguages.filter(id => id !== lang.id), layouts.languages);
      if (!prefs.enabledLanguages.includes(prefs.language)) prefs.language = prefs.enabledLanguages[0];
      composingWord = null; undo = null; caps = false; shift = null; symbolPage = -1; persist(); applyPreferences();
    };
    row.append(text, toggle); list.append(row);
  }
}
function insertEmoji(text) {
  composingWord = null; undo = null; insert(text);
  recentEmoji = [text, ...recentEmoji.filter(item => item !== text)].slice(0, 32); persist();
  if (emojiCategory === 'recent') renderEmoji();
}
function renderEmoji() {
  $('#emoji-tone').value = prefs.emojiTone;
  const tabs = $('#emoji-categories'); tabs.replaceChildren();
  const categories = [{ id: 'recent', icon: '🕘', title: 'Недавние' }, ...emojiCatalog.categories];
  categories.forEach(category => {
    const button = document.createElement('button'); button.className = 'emoji-category emoji-font'; button.textContent = category.icon; button.ariaLabel = category.title; button.setAttribute('aria-pressed', String(category.id === emojiCategory));
    button.onclick = () => { emojiCategory = category.id; $('#emoji-search').value = ''; renderEmoji(); }; tabs.append(button);
  });
  const query = $('#emoji-search').value.trim().toLocaleLowerCase();
  const entries = query ? allEmoji.filter(entry => `${entry.name} ${entry.keywords} ${entry.text}`.toLocaleLowerCase().includes(query))
    : emojiCategory === 'recent' ? recentEmoji.map(text => ({ text, name: text, keywords: '', variants: [] }))
    : emojiCatalog.categories.find(category => category.id === emojiCategory).entries;
  const grid = $('#emoji-grid'); grid.replaceChildren(); $('#emoji-variants').hidden = true;
  for (const entry of entries) {
    const button = document.createElement('button'); const text = emojiWithTone(entry, prefs.emojiTone);
    button.type = 'button'; button.className = 'emoji-key emoji-font'; button.textContent = text; button.ariaLabel = entry.name; button.title = entry.keywords || entry.name;
    button.onpointerdown = event => event.preventDefault(); button.onclick = () => insertEmoji(text);
    button.oncontextmenu = event => {
      event.preventDefault();
      const variants = $('#emoji-variants'); variants.replaceChildren(); variants.hidden = false;
      for (const variant of [entry.text, ...entry.variants]) {
        const option = document.createElement('button'); option.className = 'emoji-key emoji-font'; option.textContent = variant; option.ariaLabel = variant;
        option.onpointerdown = event => event.preventDefault(); option.onclick = () => { insertEmoji(variant); variants.hidden = true; }; variants.append(option);
      }
    };
    grid.append(button);
  }
  if (!entries.length) { const empty = document.createElement('p'); empty.className = 'empty-emojis'; empty.textContent = query ? 'Ничего не найдено.' : 'Здесь появятся недавно использованные эмодзи.'; grid.append(empty); }
}
for (const [id, [name, color]] of Object.entries(themes)) {
  const button = document.createElement('button'); button.className = 'theme-option'; button.style.background = color; button.ariaLabel = name; button.title = name; button.dataset.themeChoice = id;
  button.onclick = () => { prefs.theme = id; persist(); applyPreferences(); }; $('#theme-picker').append(button);
}
for (const [selector, property] of [['#number-row', 'numberRow'], ['#auto-cap', 'autoCap'], ['#double-space', 'doubleSpace'], ['#key-size', 'size'], ['#autocorrect', 'autocorrect'], ['#predictions', 'predictions'], ['#glide', 'glide'], ['#next-word', 'nextWord'], ['#multilingual', 'multilingual'], ['#haptics', 'haptics'], ['#online-services', 'online'], ['#one-handed', 'oneHanded'], ['#auto-clipboard', 'autoClipboard']]) {
  $(selector).onchange = event => { prefs[property] = event.target.type === 'checkbox' ? event.target.checked : event.target.value; if (property === 'autoClipboard') clipboardCapture?.invalidate(); persist(); applyPreferences(); };
}
$('#quick-t9').onpointerdown = event => event.preventDefault();
$('#quick-t9').onclick = () => { prefs.autocorrect = !prefs.autocorrect; persist(); applyPreferences(); };
$('#emoji-search').oninput = renderEmoji;
$('#emoji-tone').onchange = event => { prefs.emojiTone = event.target.value; persist(); renderEmoji(); };
$('#emoji-back').onclick = () => setPanel('keys');
$('#emoji-delete').onpointerdown = event => event.preventDefault(); $('#emoji-delete').onclick = erase;
document.querySelectorAll('[data-panel]').forEach(button => { button.addEventListener('pointerdown', event => event.preventDefault()); button.onclick = () => setPanel(button.dataset.panel); });
$('#clip-search').oninput = renderClips;
document.querySelectorAll('[data-clip-section]').forEach(button => { button.onclick = () => { clipSection = button.dataset.clipSection; renderClips(); }; });
$('#snippet-form').onsubmit = event => { event.preventDefault(); saveClip($('#snippet-text').value); $('#snippet-text').value = ''; };
$('#capture-clipboard').onclick = () => { void clipboardCapture.scan({ requestAccess: true }); };
$('#save-selection').addEventListener('pointerdown', event => event.preventDefault());
$('#save-selection').onclick = () => { const text = editor.value.slice(editor.selectionStart, editor.selectionEnd); if (!text) toast('Сначала выдели текст в тестовой зоне.'); else saveClip(text); };
$('#clear-text').onclick = () => { composingWord = null; undo = null; glideChoice = null; updateEditor({ value: '', cursor: 0 }); renderKeys(); };
$('#clear-clips').onclick = () => { clips = clips.filter(clip => clip.pinned); persist(); renderClips(); toast('Незакреплённые фрагменты удалены.'); };
$('#clear-history').onclick = () => { clipboardCapture.invalidate(); clips = clips.filter(clip => clip.pinned).map(clip => ({ ...clip, inHistory: false })); persist(); renderClips(); };
for (const [selector, offset] of [['#cursor-left', -1], ['#cursor-right', 1]]) {
  $(selector).addEventListener('pointerdown', event => event.preventDefault());
  $(selector).onclick = () => { const cursor = moveCursor(editor.value, editor.selectionStart, editor.selectionEnd, offset); editor.focus({ preventScroll: true }); editor.setSelectionRange(cursor, cursor); lastSpace = 0; undo = null; composingWord = null; renderKeys(); };
}
editor.addEventListener('beforeinput', event => {
  if (event.isComposing) return;
  if (event.inputType === 'insertText' && event.data && prefs.autocorrect && correctionEdit(editor.value, editor.selectionStart, editor.selectionEnd, event.data, language(), lexicons[prefs.language], personalWords[prefs.language] || [], composingWord)) {
    event.preventDefault(); insert(event.data, event.data === ' ');
  } else if (event.inputType === 'deleteContentBackward' && canUndo()) { event.preventDefault(); undoCorrection(false); }
});
editor.addEventListener('input', event => {
  glideChoice = null;
  undo = null;
  composingWord = !event.isComposing && event.inputType === 'insertText' && /^[\p{L}\p{M}]$/u.test(event.data || '') ? activeWord() : null;
  $('#character-count').textContent = `${[...new Intl.Segmenter().segment(editor.value)].length} символов`; renderKeys();
});
editor.addEventListener('click', () => { composingWord = null; renderKeys(); });
function undoEdit() {
  const previous = editHistory.pop(); if (!previous) { toast('Больше нечего отменять.'); return; }
  redoHistory.push({ value: editor.value, cursor: editor.selectionStart }); historyMuted = true;
  updateEditor(previous); historyMuted = false; undo = null; glideChoice = null; composingWord = null; renderKeys();
}
function move(offset) {
  const cursor = moveCursor(editor.value, editor.selectionStart, editor.selectionEnd, offset);
  editor.focus({ preventScroll: true }); editor.setSelectionRange(cursor, cursor); undo = null; composingWord = null; glideChoice = null; renderKeys();
}
function attachGlide(letter) {
  letter.addEventListener('pointerdown', event => {
    if (!prefs.glide || event.button !== 0) return;
    const centers = {};
    document.querySelectorAll('.letter-key').forEach(button => { const bounds = button.getBoundingClientRect(); if (/^\p{L}$/u.test(button.dataset.character)) centers[button.dataset.character] = { x: bounds.x + bounds.width / 2, y: bounds.y + bounds.height / 2 }; });
    trace = { id: event.pointerId, points: [{ x: event.clientX, y: event.clientY }], centers, value: editor.value, start: editor.selectionStart, end: editor.selectionEnd, dragged: false };
    letter.setPointerCapture(event.pointerId);
  });
  letter.addEventListener('pointermove', event => {
    if (!trace || trace.id !== event.pointerId || !letter.hasPointerCapture(event.pointerId)) return;
    const point = { x: event.clientX, y: event.clientY }, first = trace.points[0];
    if (Math.hypot(point.x - first.x, point.y - first.y) > 12) trace.dragged = true;
    if (trace.points.length < 256) trace.points.push(point);
    if (trace.dragged) { suppressLettersUntil = performance.now() + 120; $('#glide-line').setAttribute('d', trace.points.map((p, index) => `${index ? 'L' : 'M'}${p.x},${p.y}`).join(' ')); }
  });
  letter.addEventListener('pointerup', () => {
    const gesture = trace; trace = null; $('#glide-line').setAttribute('d', '');
    if (!gesture?.dragged) return;
    suppressLettersUntil = performance.now() + 120;
    if (gesture.value !== editor.value || gesture.start !== editor.selectionStart || gesture.end !== editor.selectionEnd || gesture.start !== gesture.end) return;
    const words = [...(personalWords[prefs.language] || []), ...(predictionPack.languages[prefs.language] || [])];
    const options = rankGlide(gesture.points, gesture.centers, words);
    if (!options.length) { toast('Жест не распознан. Попробуй ещё раз.'); return; }
    const upper = caps || (shift ?? (prefs.autoCap && shouldCapitalize(editor.value.slice(0, editor.selectionStart))));
    const word = caps ? options[0].toLocaleUpperCase(language().locale) : upper ? options[0][0].toLocaleUpperCase(language().locale) + options[0].slice(1) : options[0];
    insert(word + ' '); glideChoice = { options, word, value: editor.value, cursor: editor.selectionStart }; renderKeys();
  });
  letter.addEventListener('pointercancel', () => { trace = null; $('#glide-line').setAttribute('d', ''); });
}
toolFeatures = installTools({
  prefs: () => prefs, language, layouts: () => layouts, save: persist, apply: applyPreferences, toast, setPanel, undoEdit, move,
  insert: text => { composingWord = null; undo = null; insert(text); }, selected: () => editor.value.slice(editor.selectionStart, editor.selectionEnd),
  deleteWord: () => { updateEditor(deleteWord(editor.value, editor.selectionStart, editor.selectionEnd)); undo = null; glideChoice = null; composingWord = null; renderKeys(); }
});
clipboardCapture = installClipboardCapture({ enabled: () => prefs.autoClipboard,
  save: text => saveClip(text, { quiet: true }),
  status: (message, retry) => { if ($('#clipboard-status').textContent !== message) $('#clipboard-status').textContent = message; $('#capture-clipboard').hidden = !retry; }
});
persist(); applyPreferences(); renderClips(); setPanel('keys');
