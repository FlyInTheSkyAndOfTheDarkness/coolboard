import { defineConfig } from '@playwright/test';

export default defineConfig({
  testDir: './tests/browser',
  timeout: 20000,
  fullyParallel: true,
  workers: 2,
  reporter: 'list',
  use: { baseURL: 'http://localhost:4173', browserName: 'chromium', channel: 'chrome', screenshot: 'only-on-failure' },
  webServer: { command: 'node scripts/preview-server.mjs', url: 'http://localhost:4173', reuseExistingServer: true }
});
