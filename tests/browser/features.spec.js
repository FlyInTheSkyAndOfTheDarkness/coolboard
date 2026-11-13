import { test, expect } from '@playwright/test';

test.beforeEach(async ({ page }) => { await page.goto('/'); await expect(page.getByRole('button', { name: 'Сменить язык' })).toBeVisible(); });

test('T9 corrects typed words, backspace undoes, and disabling T9 preserves typing', async ({ page }) => {
  const editor = page.getByRole('textbox', { name: 'Тестовый текст' });
  await page.getByRole('button', { name: 'Сменить язык' }).click();
  await editor.pressSequentially('превет');
  await page.getByRole('button', { name: 'Пробел', exact: true }).click();
  await expect(editor).toHaveValue('привет ');
  await expect(page.getByRole('button', { name: 'Отменить автокоррекцию' })).toBeVisible();
  await page.getByRole('button', { name: 'Удалить символ', exact: true }).click();
  await expect(editor).toHaveValue('превет');
  await page.getByRole('button', { name: 'Т9: автокоррекция', exact: true }).click();
  await expect(page.getByRole('button', { name: 'Т9: автокоррекция', exact: true })).toHaveAttribute('aria-pressed', 'false');
  await page.getByRole('button', { name: 'Очистить текст ↗' }).click();
  await editor.pressSequentially('превет');
  await page.getByRole('button', { name: 'Пробел', exact: true }).click();
  await expect(editor).toHaveValue('превет ');
  await page.reload();
  await expect(page.getByRole('button', { name: 'Т9: автокоррекция', exact: true })).toHaveAttribute('aria-pressed', 'false');
});

test('suggestions insert a full word and personal dictionary prevents correction', async ({ page }) => {
  const editor = page.getByRole('textbox', { name: 'Тестовый текст' });
  await page.getByRole('button', { name: 'Сменить язык' }).click();
  await editor.pressSequentially('превет');
  await page.getByRole('button', { name: 'Подсказка: привет', exact: true }).click();
  await expect(editor).toHaveValue('привет ');
  await page.getByRole('button', { name: 'Очистить текст ↗' }).click();
  await editor.pressSequentially('превет');
  await page.getByRole('button', { name: 'Запомнить слово' }).click();
  await page.getByRole('button', { name: 'Пробел', exact: true }).click();
  await expect(editor).toHaveValue('превет ');
  await page.reload();
  await editor.pressSequentially('превет');
  await page.getByRole('button', { name: 'Пробел', exact: true }).click();
  await expect(editor).toHaveValue('превет ');
});

test('languages can be added and removed and the final language is protected', async ({ page }) => {
  await page.getByRole('button', { name: 'Настройки', exact: true }).click();
  await page.getByRole('switch', { name: 'Қазақша', exact: true }).uncheck();
  await page.getByRole('switch', { name: 'Русский', exact: true }).uncheck();
  await expect(page.getByRole('switch', { name: 'English', exact: true })).toBeDisabled();
  await page.getByRole('switch', { name: 'Deutsch', exact: true }).check();
  await page.getByRole('button', { name: 'Клавиатура', exact: true }).click();
  await page.getByRole('button', { name: 'Сменить язык' }).click();
  await expect(page.getByRole('button', { name: 'Сменить язык' })).toHaveText('DEU');
  await expect(page.getByRole('button', { name: 'Ü', exact: true })).toBeVisible();
  await page.reload();
  await expect(page.getByRole('button', { name: 'Сменить язык' })).toHaveText('DEU');
});

test('emoji search, skin tones, recents, insertion and whole-grapheme deletion', async ({ page }) => {
  await page.setViewportSize({ width: 375, height: 812 });
  const editor = page.getByRole('textbox', { name: 'Тестовый текст' });
  await page.getByRole('button', { name: 'Эмодзи', exact: true }).click();
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
  await page.getByRole('searchbox', { name: 'Поиск эмодзи' }).fill('thumbs up');
  await page.getByRole('combobox', { name: 'Оттенок кожи' }).selectOption('🏽');
  await page.getByRole('button', { name: 'thumbs up', exact: true }).click();
  await expect(editor).toHaveValue('👍🏽');
  await page.getByRole('button', { name: 'Недавние', exact: true }).click();
  await expect(page.locator('#emoji-grid button')).toHaveCount(1);
  await page.getByRole('button', { name: 'Удалить эмодзи', exact: true }).click();
  await expect(editor).toHaveValue('');
  await page.reload();
  await page.getByRole('button', { name: 'Эмодзи', exact: true }).click();
  await expect(page.getByRole('combobox', { name: 'Оттенок кожи' })).toHaveValue('🏽');
  await page.getByRole('button', { name: 'Недавние', exact: true }).click();
  await expect(page.locator('#emoji-grid button')).toHaveText('👍🏽');
  await page.getByRole('searchbox', { name: 'Поиск эмодзи' }).fill('сердце');
  expect(await page.locator('#emoji-grid button').count()).toBeGreaterThan(10);
  await page.getByRole('searchbox', { name: 'Поиск эмодзи' }).fill('жүрек');
  expect(await page.locator('#emoji-grid button').count()).toBeGreaterThan(10);
});

test('suggestions can be disabled independently and email text is unchanged', async ({ page }) => {
  await page.getByRole('button', { name: 'Настройки', exact: true }).click();
  await page.getByRole('switch', { name: 'Подсказки слов' }).uncheck();
  await page.getByRole('button', { name: 'Клавиатура', exact: true }).click();
  await expect(page.locator('.prediction-bar')).toHaveCount(0);
  await expect(page.getByRole('button', { name: 'Т9: автокоррекция', exact: true })).toHaveAttribute('aria-pressed', 'true');
  await page.getByRole('button', { name: 'Сменить язык' }).click();
  const editor = page.getByRole('textbox', { name: 'Тестовый текст' });
  await editor.pressSequentially('mail@превет');
  await page.getByRole('button', { name: 'Пробел', exact: true }).click();
  await expect(editor).toHaveValue('mail@превет ');
});

test('spacebar drag moves the cursor without inserting text and ordinary tap inserts a space', async ({ page }) => {
  const editor = page.getByRole('textbox', { name: 'Тестовый текст' });
  await editor.fill('abcdef');
  await editor.evaluate(el => el.setSelectionRange(3, 3));
  const space = page.getByRole('button', { name: 'Пробел', exact: true });
  await space.scrollIntoViewIfNeeded();
  const bounds = await space.boundingBox();
  const x = bounds.x + bounds.width / 2, y = bounds.y + bounds.height / 2;
  await page.mouse.move(x, y); await page.mouse.down();
  await page.mouse.move(x + 25, y, { steps: 5 }); await page.mouse.up();
  await expect(editor).toHaveValue('abcdef');
  await expect.poll(() => editor.evaluate(el => el.selectionStart)).toBe(5);
  await space.click();
  await expect(editor).toHaveValue('abcde f');
});
