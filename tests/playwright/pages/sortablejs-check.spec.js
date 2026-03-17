(function() {
  // Playwright test for SortableJS availability and console error detection
  var checkSortableJS, expect, test;

  ({test, expect} = require('@playwright/test'));

  // Helper to check if SortableJS is loaded on the page
  checkSortableJS = async function(page) {
    return (await page.evaluate(function() {
      if (typeof Sortable === 'undefined') {
        return {
          loaded: false,
          error: 'SortableJS is not defined on window'
        };
      }
      if (typeof Sortable.create !== 'function') {
        return {
          loaded: false,
          error: 'Sortable.create is not a function'
        };
      }
      return {
        loaded: true
      };
    }));
  };

  test.describe('SortableJS Library', function() {
    test('should load SortableJS library on page load', async function({page}) {
      var result;
      // Navigate to the app (will redirect to login)
      await page.goto('/');
      
      // Wait for scripts to load
      await page.waitForLoadState('networkidle');
      
      // Check if SortableJS is available
      result = (await checkSortableJS(page));
      
      // Report the result
      if (!result.loaded) {
        console.error('SortableJS check failed:', result.error);
      }
      return expect(result.loaded, "SortableJS should be loaded on the page").toBe(true);
    });
    return test('should load SortableJS after login', async function({page}) {
      var result;
      // Login first
      await page.goto('/');
      await page.fill('#login-username', 'admin');
      await page.fill('#login-password', 'adminadmin');
      await page.click('#login-btn');
      
      // Wait for main app to be visible
      await page.waitForSelector('#main', {
        state: 'visible'
      });
      
      // Wait for scripts to fully load
      await page.waitForLoadState('networkidle');
      
      // Check if SortableJS is available after login
      result = (await checkSortableJS(page));
      if (!result.loaded) {
        console.error('SortableJS check failed after login:', result.error);
      }
      return expect(result.loaded, "SortableJS should be loaded after login").toBe(true);
    });
  });

  // Test for console error detection
  test.describe('Console Error Detection', function() {
    test('should not have console errors on page load', async function({page}) {
      var consoleErrors;
      consoleErrors = [];
      
      // Listen for console errors
      page.on('console', function(msg) {
        if (msg.type() === 'error') {
          return consoleErrors.push(msg.text());
        }
      });
      
      // Navigate to the app
      await page.goto('/');
      
      // Wait for page to fully load
      await page.waitForLoadState('networkidle');
      
      // Wait a bit more for any async errors
      await page.waitForTimeout(2000);
      
      // Report any errors found
      if (consoleErrors.length > 0) {
        console.error('Console errors detected:', consoleErrors);
      }
      return expect(consoleErrors.length, "Should have no console errors on page load").toBe(0);
    });
    return test('should not have console errors after login', async function({page}) {
      var consoleErrors;
      consoleErrors = [];
      
      // Listen for console errors
      page.on('console', function(msg) {
        if (msg.type() === 'error') {
          return consoleErrors.push(msg.text());
        }
      });
      
      // Login
      await page.goto('/');
      await page.fill('#login-username', 'admin');
      await page.fill('#login-password', 'adminadmin');
      await page.click('#login-btn');
      
      // Wait for main app to be visible
      await page.waitForSelector('#main', {
        state: 'visible'
      });
      
      // Wait for page to fully load
      await page.waitForLoadState('networkidle');
      
      // Wait a bit more for any async errors
      await page.waitForTimeout(2000);
      
      // Report any errors found
      if (consoleErrors.length > 0) {
        console.error('Console errors detected after login:', consoleErrors);
      }
      return expect(consoleErrors.length, "Should have no console errors after login").toBe(0);
    });
  });

}).call(this);
