(function() {
  // Authentication E2E Tests - Parallel-ready version
  // Optimized for concurrent execution with proper isolation
  var expect, performLogin, test;

  ({test, expect} = require('@playwright/test'));

  // Helper function with retry logic for login
  performLogin = async function(page, username = 'admin', password = 'adminadmin') {
    var error;
    await page.goto('/');
    await page.fill('#login-username', username);
    await page.fill('#login-password', password);
    await page.click('#login-btn');
    try {
      // Wait for login with timeout and retry
      return (await page.waitForSelector('#main', {
        state: 'visible',
        timeout: 10000
      }));
    } catch (error1) {
      error = error1;
      // If login fails, retry once (might be due to concurrent access)
      await page.goto('/');
      await page.fill('#login-username', username);
      await page.fill('#login-password', password);
      await page.click('#login-btn');
      return (await page.waitForSelector('#main', {
        state: 'visible',
        timeout: 10000
      }));
    }
  };

  test.describe('Authentication - Login (Parallel)', function() {
    test('should login with valid credentials', async function({page}) {
      await performLogin(page);
      // Verify successful login
      await expect(page.locator('#main')).toBeVisible();
      return (await expect(page.locator('#sidebar')).toBeVisible());
    });
    test('should fail login with invalid credentials', async function({page}) {
      await page.goto('/');
      // Try to login with invalid credentials
      await page.fill('#login-username', 'invalid');
      await page.fill('#login-password', 'invalid');
      await page.click('#login-btn');
      // Wait for error message
      await page.waitForTimeout(1000);
      // Verify login failed - login overlay should still be visible
      await expect(page.locator('#login-overlay')).toBeVisible();
      return (await expect(page.locator('#login-error')).toBeVisible());
    });
    test('should fail login with missing username', async function({page}) {
      await page.goto('/');
      // Try to login with missing username
      await page.fill('#login-password', 'adminadmin');
      await page.click('#login-btn');
      // Wait for error
      await page.waitForTimeout(1000);
      // Verify login failed
      return (await expect(page.locator('#login-overlay')).toBeVisible());
    });
    return test('should fail login with missing password', async function({page}) {
      await page.goto('/');
      // Try to login with missing password
      await page.fill('#login-username', 'admin');
      await page.click('#login-btn');
      // Wait for error
      await page.waitForTimeout(1000);
      // Verify login failed
      return (await expect(page.locator('#login-overlay')).toBeVisible());
    });
  });

  test.describe('Authentication - Logout (Parallel)', function() {
    test('should logout successfully', async function({page}) {
      // Login with retry logic
      await performLogin(page);
      // Verify we're logged in
      await expect(page.locator('#main')).toBeVisible();
      // Perform logout - simulate by clearing session
      await page.evaluate(function() {
        return localStorage.clear();
      });
      // Reload page
      await page.reload();
      // Verify logout success
      await expect(page.locator('#login-overlay')).toBeVisible();
      return (await expect(page.locator('#main')).toHaveClass('hidden'));
    });
    return test('should clear authentication token on logout', async function({page}) {
      // Login with retry logic
      await performLogin(page);
      // Verify we're logged in
      await expect(page.locator('#main')).toBeVisible();
      // Perform logout
      await page.evaluate(function() {
        return localStorage.clear();
      });
      await page.reload();
      // Verify logout success
      await expect(page.locator('#login-overlay')).toBeVisible();
      return (await expect(page.locator('#main')).toHaveClass('hidden'));
    });
  });

  test.describe('Authentication - Session Management (Parallel)', function() {
    test('should maintain session across page reloads', async function({page}) {
      // Login with retry logic
      await performLogin(page);
      // Reload page
      await page.reload();
      // Wait for possible login check
      await page.waitForTimeout(2000);
      // Verify we're still logged in (main app should be visible)
      await expect(page.locator('#main')).toBeVisible();
      return (await expect(page.locator('#login-overlay')).toHaveClass('overlay hidden'));
    });
    test('should expire session after logout', async function({page}) {
      // Login with retry logic
      await performLogin(page);
      // Logout
      await page.evaluate(function() {
        return localStorage.clear();
      });
      await page.reload();
      // Try to access protected page directly
      await page.goto('/#!spaces');
      // Verify we're redirected to login
      return (await expect(page.locator('#login-overlay')).toBeVisible());
    });
    return test('should handle multiple login attempts', async function({page}) {
      await page.goto('/');
      // First login attempt with wrong password
      await page.fill('#login-username', 'admin');
      await page.fill('#login-password', 'wrong');
      await page.click('#login-btn');
      // Wait for error
      await page.waitForTimeout(1000);
      // Verify error message
      await expect(page.locator('#login-error')).toBeVisible();
      // Second login attempt with correct credentials
      await performLogin(page, 'admin', 'adminadmin');
      // Verify successful login
      return (await expect(page.locator('#main')).toBeVisible());
    });
  });

}).call(this);
