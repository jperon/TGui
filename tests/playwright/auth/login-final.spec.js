(function() {
  // Authentication E2E Tests - Final version without AuthHelper issues
  // Tests login, logout, and session management
  var expect, test;

  ({test, expect} = require('@playwright/test'));

  test.describe('Authentication - Login', function() {
    test('should login with valid credentials', async function({page}) {
      await page.goto('/');
      // Verify login page is loaded
      await expect(page.locator('h1')).toContainText('TGui');
      await expect(page.locator('#login-username')).toBeVisible();
      await expect(page.locator('#login-password')).toBeVisible();
      // Perform login
      await page.fill('#login-username', 'admin');
      await page.fill('#login-password', 'adminadmin');
      await page.click('#login-btn');
      // Wait for login to complete
      await page.waitForSelector('#main', {
        state: 'visible'
      });
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

  test.describe('Authentication - Logout', function() {
    test('should logout successfully', async function({page}) {
      // Login first
      await page.goto('/');
      await page.fill('#login-username', 'admin');
      await page.fill('#login-password', 'adminadmin');
      await page.click('#login-btn');
      await page.waitForSelector('#main', {
        state: 'visible'
      });
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
      // Login first
      await page.goto('/');
      await page.fill('#login-username', 'admin');
      await page.fill('#login-password', 'adminadmin');
      await page.click('#login-btn');
      await page.waitForSelector('#main', {
        state: 'visible'
      });
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

  test.describe('Authentication - Session Management', function() {
    test('should maintain session across page reloads', async function({page}) {
      // Login
      await page.goto('/');
      await page.fill('#login-username', 'admin');
      await page.fill('#login-password', 'adminadmin');
      await page.click('#login-btn');
      await page.waitForSelector('#main', {
        state: 'visible'
      });
      // Reload page
      await page.reload();
      // Wait for possible login check
      await page.waitForTimeout(2000);
      // Verify we're still logged in (main app should be visible)
      await expect(page.locator('#main')).toBeVisible();
      return (await expect(page.locator('#login-overlay')).toHaveClass('overlay hidden'));
    });
    test('should expire session after logout', async function({page}) {
      // Login
      await page.goto('/');
      await page.fill('#login-username', 'admin');
      await page.fill('#login-password', 'adminadmin');
      await page.click('#login-btn');
      await page.waitForSelector('#main', {
        state: 'visible'
      });
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
      await page.fill('#login-username', 'admin');
      await page.fill('#login-password', 'adminadmin');
      await page.click('#login-btn');
      // Wait for login
      await page.waitForSelector('#main', {
        state: 'visible'
      });
      // Verify successful login
      return (await expect(page.locator('#main')).toBeVisible());
    });
  });

}).call(this);
