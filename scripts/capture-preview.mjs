import { chromium } from '@playwright/test';
import { mkdir } from 'node:fs/promises';

await mkdir('artifacts', { recursive: true });
const browser = await chromium.launch({ channel: 'chrome' });
try {
  const page = await browser.newPage({ viewport: { width: 1440, height: 1060 }, deviceScaleFactor: 1 });
  const errors = [];
  page.on('pageerror', error => errors.push(error.message));
  await page.goto('http://localhost:4173');
  await page.getByRole('button', { name: 'Сменить язык' }).waitFor();
  await page.screenshot({ path: 'artifacts/preview-desktop.png', fullPage: true });
  await page.setViewportSize({ width: 375, height: 812 });
  await page.screenshot({ path: 'artifacts/preview-mobile.png', fullPage: true });
  await page.getByRole('button', { name: 'Эмодзи', exact: true }).click();
  await page.screenshot({ path: 'artifacts/preview-emoji.png', fullPage: true });
  await page.getByRole('button', { name: 'Настройки', exact: true }).click();
  await page.screenshot({ path: 'artifacts/preview-settings.png', fullPage: true });
  await page.getByRole('button', { name: 'Все инструменты', exact: true }).click();
  await page.screenshot({ path: 'artifacts/preview-tools.png', fullPage: true });
  await page.getByRole('button', { name: '▧ Стикеры', exact: true }).click();
  await page.screenshot({ path: 'artifacts/preview-stickers.png', fullPage: true });
  await page.getByRole('button', { name: 'Буфер обмена', exact: true }).click();
  await page.screenshot({ path: 'artifacts/preview-clipboard.png', fullPage: true });
  if (errors.length) throw new Error(errors.join('\n'));
  console.log('Desktop and mobile previews saved. No browser runtime errors.');
} finally { await browser.close(); }
