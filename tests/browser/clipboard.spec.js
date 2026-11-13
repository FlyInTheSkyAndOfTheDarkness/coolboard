import { test, expect } from '@playwright/test';

async function copyEvent(page, text) {
  await page.evaluate(value => {
    const data = new DataTransfer(); data.setData('text/plain', value);
    document.querySelector('#editor').dispatchEvent(new ClipboardEvent('copy', { clipboardData: data, bubbles: true, cancelable: true }));
  }, text);
}
async function open(page) { await page.goto('/'); await page.getByRole('button', { name: 'Буфер обмена', exact: true }).click(); }

test('copying automatically records the last ten texts with no save-button click', async ({ page }) => {
  await open(page);
  for (let i = 0; i < 12; i++) await copyEvent(page, `copy ${i}`);
  await expect(page.locator('.clip-text').first()).toHaveText('copy 11');
  await expect(page.locator('.clip')).toHaveCount(10); await expect(page.locator('.clip-text').last()).toHaveText('copy 2');
  await expect(page.locator('#history-count')).toHaveText('10/10');
  await copyEvent(page, 'copy 5'); await expect(page.locator('.clip-text').first()).toHaveText('copy 5'); await expect(page.locator('.clip')).toHaveCount(10);
});

test('older pinned copies live separately and never block the ten newest', async ({ page }) => {
  await open(page); await copyEvent(page, 'favorite');
  await page.getByRole('button', { name: 'Закрепить', exact: true }).click();
  for (let i = 0; i < 12; i++) await copyEvent(page, `new ${i}`);
  await expect(page.locator('.clip-text').first()).toHaveText('new 11'); await expect(page.locator('.clip')).toHaveCount(10);
  await page.getByRole('button', { name: 'Закреплённые', exact: true }).click();
  await expect(page.locator('.clip')).toHaveCount(1); await expect(page.locator('.clip-text')).toHaveText('favorite');
  await page.getByRole('button', { name: 'Последние 10', exact: true }).click(); await expect(page.locator('.clip')).toHaveCount(10);
});

test('external current clipboard is picked up on opening and is not resurrected after deletion', async ({ page }) => {
  await page.addInitScript(() => {
    Object.defineProperty(navigator, 'clipboard', { configurable: true, value: { readText: async () => 'external clipboard' } });
    Object.defineProperty(navigator, 'permissions', { configurable: true, value: { query: async () => ({ state: 'granted' }) } });
  });
  await open(page); await expect(page.locator('.clip-text')).toHaveText('external clipboard');
  await page.getByRole('button', { name: 'Удалить фрагмент', exact: true }).click();
  await page.reload(); await page.getByRole('button', { name: 'Буфер обмена', exact: true }).click();
  await expect(page.locator('#clipboard-status')).toContainText('чтение буфера разрешено'); await expect(page.locator('.clip')).toHaveCount(0);
});

test('disabling automatic history stops new copies and clearing leaves favorites separate', async ({ page }) => {
  await open(page); await copyEvent(page, 'favorite'); await page.getByRole('button', { name: 'Закрепить', exact: true }).click();
  await copyEvent(page, 'another');
  await page.getByRole('button', { name: 'Настройки', exact: true }).click();
  await page.getByRole('switch', { name: 'Автосохранение последних 10 копирований' }).uncheck();
  await page.getByRole('button', { name: 'Очистить историю копирований', exact: true }).click();
  await copyEvent(page, 'disabled copy'); await page.getByRole('button', { name: 'Буфер обмена', exact: true }).click();
  await expect(page.locator('.clip')).toHaveCount(0); await page.getByRole('button', { name: 'Закреплённые', exact: true }).click();
  await expect(page.locator('.clip-text')).toHaveText('favorite');
});

test('legacy hundred-entry history migrates and deletes obsolete unpinned storage', async ({ page }) => {
  await page.addInitScript(() => localStorage.setItem('coolboard.clips', JSON.stringify(Array.from({ length: 100 }, (_, i) => ({ id: String(i), text: `legacy ${i}`, pinned: i === 99 })))));
  await open(page); await expect(page.locator('.clip')).toHaveCount(10);
  expect(await page.evaluate(() => JSON.parse(localStorage.getItem('coolboard.clips')).length)).toBe(11);
  await page.getByRole('button', { name: 'Закреплённые', exact: true }).click(); await expect(page.locator('.clip-text')).toHaveText('legacy 99');
});
