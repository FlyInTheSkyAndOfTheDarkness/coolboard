import { test, expect } from '@playwright/test';

test.beforeEach(async ({ page }) => { await page.goto('/'); await expect(page.getByRole('button', { name: 'Сменить язык' })).toBeVisible(); });

test('Kazakh typing, selection replacement and all three languages', async ({ page }) => {
  const editor = page.getByRole('textbox', { name: 'Тестовый текст' });
  await page.getByRole('button', { name: 'Ә', exact: true }).click();
  await page.getByRole('button', { name: 'ң', exact: true }).click();
  await expect(editor).toHaveValue('Әң');
  await page.getByRole('button', { name: 'Сменить язык' }).click();
  await expect(page.getByRole('button', { name: 'Сменить язык' })).toHaveText('РУС');
  await page.getByRole('button', { name: 'Сменить язык' }).click();
  await page.getByRole('button', { name: 'q', exact: true }).click();
  await expect(editor).toHaveValue('Әңq');
  await editor.evaluate(el => el.setSelectionRange(0, 2));
  await page.getByRole('button', { name: 'w', exact: true }).click();
  await expect(editor).toHaveValue('wq');
});

test('save, pin, paste, delete and restore snippets', async ({ page }) => {
  await page.getByRole('button', { name: 'Буфер обмена', exact: true }).click();
  const snippet = page.getByRole('textbox', { name: 'Новый фрагмент' });
  await snippet.fill('Сәлем, әлем!'); await page.getByRole('button', { name: 'Сохранить фрагмент', exact: true }).click();
  await page.getByRole('button', { name: 'Закрепить', exact: true }).click();
  await snippet.fill('Удалить меня'); await page.getByRole('button', { name: 'Сохранить фрагмент', exact: true }).click();
  await page.getByRole('button', { name: 'Настройки', exact: true }).click();
  await page.getByRole('button', { name: 'Удалить незакреплённые фрагменты' }).click();
  await page.reload();
  await page.getByRole('button', { name: 'Буфер обмена', exact: true }).click();
  await expect(page.locator('.clip')).toHaveCount(1);
  await page.getByRole('button', { name: 'Сәлем, әлем!', exact: true }).click();
  await expect(page.getByRole('textbox', { name: 'Тестовый текст' })).toHaveValue('Сәлем, әлем!');
});

test('preferences persist and mobile page has no horizontal overflow', async ({ page }) => {
  await page.setViewportSize({ width: 375, height: 812 });
  await page.getByRole('button', { name: 'Настройки', exact: true }).click();
  await page.getByRole('button', { name: 'Бумага', exact: true }).click();
  await page.getByRole('switch', { name: 'Цифры отдельным рядом' }).check();
  await page.reload();
  await expect(page.locator('.phone')).toHaveAttribute('data-theme', 'paper');
  await expect(page.getByRole('button', { name: '1', exact: true })).toBeVisible();
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
});

test('clipboard denial gives a usable fallback and snippets are rendered as text', async ({ page }) => {
  await page.evaluate(() => Object.defineProperty(navigator, 'clipboard', { value: { readText: async () => { throw new Error('denied'); } }, configurable: true }));
  await page.getByRole('button', { name: 'Буфер обмена', exact: true }).click();
  await page.getByRole('button', { name: 'Разрешить чтение буфера', exact: true }).click();
  await expect(page.locator('#clipboard-status')).toContainText('не разрешил чтение');
  await page.getByRole('textbox', { name: 'Новый фрагмент' }).fill('<img src=x onerror=alert(1)>');
  await page.getByRole('button', { name: 'Сохранить фрагмент', exact: true }).click();
  await expect(page.locator('.clip-text')).toHaveText('<img src=x onerror=alert(1)>');
  await expect(page.locator('.clip img')).toHaveCount(0);
});

test('holding backspace stops deleting on release', async ({ page }) => {
  const editor = page.getByRole('textbox', { name: 'Тестовый текст' });
  await editor.fill('abcdefghijklmnopqrst');
  await editor.evaluate(el => el.setSelectionRange(el.value.length, el.value.length));
  const del = page.getByRole('button', { name: 'Удалить символ', exact: true });
  await del.hover(); await page.mouse.down(); await page.waitForTimeout(700); await page.mouse.up();
  const text = await editor.inputValue();
  expect(text.length).toBeLessThan(18);
  await page.waitForTimeout(250); await expect(editor).toHaveValue(text);
});

test('manual shift, double space and caps lock', async ({ page }) => {
  await page.getByRole('button', { name: 'Сменить язык' }).click();
  await page.getByRole('button', { name: 'Сменить язык' }).click();
  const editor = page.getByRole('textbox', { name: 'Тестовый текст' });
  // Shift can turn off automatic capitalization at the beginning of a sentence.
  await page.getByRole('button', { name: 'Shift', exact: true }).click();
  await page.getByRole('button', { name: 'q', exact: true }).click();
  await page.getByRole('button', { name: 'Пробел', exact: true }).click();
  await page.getByRole('button', { name: 'Пробел', exact: true }).click();
  await expect(editor).toHaveValue('q. ');
  await page.getByRole('button', { name: 'Shift', exact: true }).dblclick();
  await page.getByRole('button', { name: 'A', exact: true }).click();
  await page.getByRole('button', { name: 'B', exact: true }).click();
  await expect(editor).toHaveValue('q. AB');
});
