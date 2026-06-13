// @ts-check
const { defineConfig, devices } = require('@playwright/test');

/**
 * Configuration optimisée pour la parallélisation avec gestion des dépendances
 */
module.exports = defineConfig({
  testDir: './',
  testMatch: '**/*.spec.js',
  timeout: 30000,
  expect: {
    timeout: 10000
  },
  // Réinitialise la base de test à une baseline démo avant le run (isolation)
  globalSetup: require.resolve('./config/global-setup-simple.js'),

  fullyParallel: true,  // Activer la parallélisation complète

  retries: 1,  // Moins de retries en parallèle
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
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] }
    }
  ],
  // Workers parallèles : 2 workers = performance optimale
  workers: 2,
});
