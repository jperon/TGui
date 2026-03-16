// @ts-check
const { defineConfig, devices } = require('@playwright/test');

/**
 * @see https://playwright.dev/docs/test-configuration
 */
module.exports = defineConfig({
  testDir: './',
  testMatch: '**/*.spec.js',
  timeout: 30000,
  expect: {
    timeout: 10000
  },
  fullyParallel: false,
    
  retries: 2,
  reporter: [
    ['list']
  ],
  use: {
    baseURL: 'http://localhost:8081',
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
    video: 'retain-on-failure'
  },
  projects: [
    { name: 'chromium', use: { ...devices['Desktop Chrome'] } }
  ],
  workers: process.env.CI ? 1 : undefined,
});
