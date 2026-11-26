import { defineConfig } from '@playwright/test';

// Runs against the local Apache started by e2e/local-apache.sh, which uses the
// production vhost template. Never point this at the real server.
export default defineConfig({
  testDir: 'e2e',
  fullyParallel: false,
  workers: 1,
  timeout: 30000,
  use: {
    baseURL: 'https://localhost:16065/ui/',
    ignoreHTTPSErrors: true,
    locale: 'ru-RU',
    timezoneId: 'Europe/Berlin',
  },
  globalSetup: './e2e/global-setup.ts',
  globalTeardown: './e2e/global-teardown.ts',
});
