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
      // Tous les fichiers de spec SAUF apps : ils tournent en parallèle
      // (fullyParallel global + workers: 2).
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
      testIgnore: '**/apps/**'
    },
    {
      // La spec des applications exporte puis réinstalle TOUTE l'instance :
      // si un autre fichier crée ou supprime un espace entre l'export et
      // l'installation, le plan de la spec change (et l'installation
      // recréerait un espace supprimé par un autre test). On l'isole donc :
      // elle ne démarre qu'après la fin du projet `chromium`
      // (dependencies) et s'exécute en série (fullyParallel: false ; la spec
      // est de toute façon en test.describe.serial). `workers` n'étant pas
      // configurable par projet, c'est `fullyParallel: false` qui garantit le
      // série au sein de ce projet.
      name: 'chromium-apps',
      use: { ...devices['Desktop Chrome'] },
      testMatch: '**/apps/**/*.spec.js',
      dependencies: ['chromium'],
      fullyParallel: false
    }
  ],
  // Workers parallèles : 2 workers = performance optimale
  workers: 2,
});
