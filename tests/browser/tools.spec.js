import { test, expect } from '@playwright/test';

test.beforeEach(async ({ page }) => { await page.goto('/'); await expect(page.getByRole('button', { name: 'Все инструменты', exact: true })).toBeVisible(); });
async function tool(page, name) { await page.getByRole('button', { name: 'Все инструменты', exact: true }).click(); await page.getByRole('button', { name, exact: true }).click(); }

test('glide types a whole word and provides alternatives', async ({ page }) => {
  await page.getByRole('button', { name: 'Сменить язык' }).click(); await page.getByRole('button', { name: 'Сменить язык' }).click();
  await page.locator('#keys-panel').scrollIntoViewIfNeeded();
  const points = await page.evaluate(() => [...'helo'].map(char => { const b = document.querySelector(`.letter-key[data-character="${char}"]`).getBoundingClientRect(); return { x: b.x + b.width / 2, y: b.y + b.height / 2 }; }));
  await page.mouse.move(points[0].x, points[0].y); await page.mouse.down();
  for (const point of points.slice(1)) await page.mouse.move(point.x, point.y, { steps: 8 });
  await page.mouse.up();
  await expect(page.getByRole('textbox', { name: 'Тестовый текст' })).toHaveValue('Hello ');
  await expect(page.getByRole('button', { name: 'Подсказка: hello', exact: true })).toBeVisible();
});

test('next word is inserted after a completed word', async ({ page }) => {
  await page.getByRole('button', { name: 'Сменить язык' }).click();
  const editor = page.getByRole('textbox', { name: 'Тестовый текст' }); await editor.fill('доброе ');
  await page.getByRole('button', { name: 'Подсказка: утро', exact: true }).click();
  await expect(editor).toHaveValue('доброе утро ');
});

test('online tools send no request until enabled and explicitly submitted', async ({ page }) => {
  let calls = 0;
  await page.route('https://api.mymemory.translated.net/**', route => { calls++; return route.fulfill({ json: { responseStatus: 200, responseData: { translatedText: 'Hello' } } }); });
  await tool(page, '⇄ Перевод');
  await page.getByRole('textbox', { name: 'Текст для перевода' }).fill('Сәлем');
  await page.getByRole('button', { name: 'Перевести', exact: true }).click();
  expect(calls).toBe(0);
  await page.getByRole('button', { name: 'Включить онлайн-функции', exact: true }).click();
  await page.getByRole('textbox', { name: 'Текст для перевода' }).fill('Сәлем');
  expect(calls).toBe(0);
  await page.getByRole('button', { name: 'Перевести', exact: true }).click();
  await page.getByRole('button', { name: 'Вставить перевод', exact: true }).click();
  await expect(page.getByRole('textbox', { name: 'Тестовый текст' })).toHaveValue('Hello'); expect(calls).toBe(1);
});

test('online errors and quota failures never insert error text', async ({ page }) => {
  await page.route('https://api.mymemory.translated.net/**', route => route.fulfill({ json: { responseStatus: 403, responseDetails: 'Daily quota exhausted', quotaFinished: true } }));
  await tool(page, '⇄ Перевод'); await page.getByRole('button', { name: 'Включить онлайн-функции' }).click();
  await page.getByRole('textbox', { name: 'Текст для перевода' }).fill('test');
  await page.getByRole('button', { name: 'Перевести', exact: true }).click();
  await expect(page.locator('.online-results')).toHaveText('Daily quota exhausted');
  await expect(page.getByRole('button', { name: 'Вставить перевод' })).toHaveCount(0);
  await expect(page.getByRole('textbox', { name: 'Тестовый текст' })).toHaveValue('');
});

test('one-handed mode persists and reset restores the keyboard width', async ({ page }) => {
  await page.setViewportSize({ width: 375, height: 812 });
  await tool(page, '⚙ Настройки');
  await page.getByRole('combobox', { name: 'Одной рукой', exact: true }).selectOption('right');
  await expect(page.locator('#keyboard')).toHaveAttribute('data-hand', 'right');
  await page.reload(); await expect(page.locator('#keyboard')).toHaveAttribute('data-hand', 'right');
  await page.getByRole('button', { name: 'Обычная ширина клавиатуры', exact: true }).click();
  await expect(page.locator('#keyboard')).toHaveAttribute('data-hand', 'off');
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
});

test('text emoticons insert, delete word works, and undo restores the previous edit', async ({ page }) => {
  const editor = page.getByRole('textbox', { name: 'Тестовый текст' });
  await tool(page, '▧ Стикеры'); await page.getByRole('button', { name: 'ʕ•ᴥ•ʔ', exact: true }).click();
  await expect(editor).toHaveValue('ʕ•ᴥ•ʔ');
  await page.getByRole('button', { name: 'Клавиатура', exact: true }).click();
  await editor.fill('hello world'); await editor.evaluate(el => el.setSelectionRange(11, 11));
  await tool(page, '⌫ Слово'); await expect(editor).toHaveValue('hello ');
  await page.getByRole('button', { name: '↶ Отмена', exact: true }).click(); await expect(editor).toHaveValue('hello world');
});

test('GIF search returns real provider results and inserts an explicitly selected source link', async ({ page }) => {
  await page.route('https://commons.wikimedia.org/w/api.php**', route => route.fulfill({ json: { query: { pages: { 1: { title: 'File:Cat.gif', imageinfo: [{ mime: 'image/gif', size: 1000, url: 'https://upload.wikimedia.org/cat.gif', thumburl: 'https://upload.wikimedia.org/small.gif', descriptionurl: 'https://commons.wikimedia.org/wiki/File:Cat.gif' }] } } } } }));
  await page.route('https://upload.wikimedia.org/**', route => route.fulfill({ body: Buffer.from('R0lGODlhAQABAIAAAP///////yH5BAEAAAAALAAAAAABAAEAAAICRAEAOw==', 'base64'), contentType: 'image/gif' }));
  await tool(page, 'GIF'); await page.getByRole('button', { name: 'Включить онлайн-функции' }).click();
  await page.getByRole('textbox', { name: 'Поисковый запрос' }).fill('cat'); await page.getByRole('button', { name: 'Найти', exact: true }).click();
  await expect(page.getByRole('img', { name: 'Cat.gif', exact: true })).toBeVisible();
  const editor = page.getByRole('textbox', { name: 'Тестовый текст' }); await expect(editor).toHaveValue('');
  await page.getByRole('button', { name: 'Вставить ссылку', exact: true }).click();
  await expect(editor).toHaveValue('https://commons.wikimedia.org/wiki/File:Cat.gif');
});

test('custom GIF import persists and remains removable', async ({ page }) => {
  await tool(page, '▧ Стикеры');
  await page.getByLabel('Добавить свой GIF или стикер').setInputFiles({ name: 'my.gif', mimeType: 'image/gif', buffer: Buffer.from('R0lGODlhAQABAIAAAP///////yH5BAEAAAAALAAAAAABAAEAAAICRAEAOw==', 'base64') });
  await expect(page.getByRole('img', { name: 'my.gif' })).toBeVisible();
  await page.reload(); await tool(page, '▧ Стикеры');
  await expect(page.getByRole('img', { name: 'my.gif' })).toBeVisible();
  await page.getByRole('button', { name: 'Удалить', exact: true }).click(); await expect(page.getByRole('img', { name: 'my.gif' })).toHaveCount(0);
});

test('voice recognition starts explicitly, inserts transcript and stops on navigation', async ({ page }) => {
  await page.evaluate(() => {
    window.voiceStarts = 0; window.voiceStops = 0;
    window.SpeechRecognition = class {
      start() { window.voiceStarts++; queueMicrotask(() => this.onresult?.({ results: [[{ transcript: 'Сәлем әлем' }]] })); }
      stop() { window.voiceStops++; this.onend?.(); }
      abort() { window.voiceStops++; this.onend?.(); }
    };
  });
  await tool(page, '🎙 Голос'); expect(await page.evaluate(() => window.voiceStarts)).toBe(0);
  await page.getByRole('button', { name: 'Начать запись', exact: true }).click();
  await expect(page.getByRole('textbox', { name: 'Распознанный текст' })).toHaveValue('Сәлем әлем');
  await page.getByRole('button', { name: 'Вставить распознанный текст', exact: true }).click();
  await expect(page.getByRole('textbox', { name: 'Тестовый текст' })).toHaveValue('Сәлем әлем');
  expect(await page.evaluate(() => window.voiceStops)).toBeGreaterThan(0);
});
