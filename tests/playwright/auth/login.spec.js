(function() {
  // Authentication E2E Tests
  // Tests login, logout, and session management
  var AuthHelper, expect, test;

  ({test, expect} = require('@playwright/test'));

  ({AuthHelper} = require('../config/auth.setup'));

  test.describe('Authentication - Login', function() {
    var authHelper;
    authHelper = null;
    test.beforeEach(function() {
      return authHelper = new AuthHelper();
    });
    test('should login with valid credentials', async function({page}) {
      var token;
      await page.goto('/login');
      // Verify login page is loaded
      await expect(page.locator('h1')).toContainText('Login');
      await expect(page.locator('input[name="username"]')).toBeVisible();
      await expect(page.locator('input[name="password"]')).toBeVisible();
      // Perform login
      token = (await authHelper.login(page, 'admin', 'adminadmin'));
      // Verify successful login
      expect(token).toBeTruthy();
      expect(authHelper.isAuthenticated(page)).toBeTruthy();
      // Verify we're redirected to main app
      await expect(page).toHaveURL(/\*\/\#\!/);
      // Verify main app elements are visible
      await expect(page.locator('[data-testid="main-app"]')).toBeVisible();
      return (await expect(page.locator('[data-testid="sidebar"]')).toBeVisible());
    });
    test('should fail login with invalid credentials', async function({page}) {
      await page.goto('/login');
      // Try to login with invalid credentials
      await page.fill('input[name="username"]', 'invalid');
      await page.fill('input[name="password"]', 'invalid');
      await page.click('button[type="submit"]');
      // Verify login failed
      await expect(page.locator('[data-testid="login-error"]')).toBeVisible();
      await expect(page.locator('[data-testid="login-error"]')).toContainText('Invalid credentials');
      // Verify we're still on login page
      return (await expect(page).toHaveURL(/\*\/login/));
    });
    test('should fail login with missing username', async function({page}) {
      await page.goto('/login');
      // Try to login with missing username
      await page.fill('input[name="password"]', 'adminadmin');
      await page.click('button[type="submit"]');
      // Verify validation error
      return (await expect(page.locator('input[name="username"]:invalid')).toBeVisible());
    });
    return test('should fail login with missing password', async function({page}) {
      await page.goto('/login');
      // Try to login with missing password
      await page.fill('input[name="username"]', 'admin');
      await page.click('button[type="submit"]');
      // Verify validation error
      return (await expect(page.locator('input[name="password"]:invalid')).toBeVisible());
    });
  });

  test.describe('Authentication - Logout', function() {
    var authHelper;
    authHelper = null;
    test.beforeEach(async function({page}) {
      authHelper = new AuthHelper();
      return (await authHelper.login(page));
    });
    test('should logout successfully', async function({page}) {
      // Verify we're logged in
      expect(authHelper.isAuthenticated(page)).toBeTruthy();
      // Perform logout
      await authHelper.logout(page);
      // Verify logout success
      expect(authHelper.isAuthenticated(page)).toBeFalsy();
      await expect(page).toHaveURL(/\/login/);
      // Verify login page is shown again
      return (await expect(page.locator('h1')).toContainText('Login'));
    });
    return test('should clear authentication token on logout', async function({page}) {
      // Verify token exists before logout
      expect(authHelper.token).toBeTruthy();
      // Perform logout
      await authHelper.logout(page);
      // Verify token is cleared
      expect(authHelper.token).toBeNull();
      return expect(authHelper.currentUser).toBeNull();
    });
  });

  test.describe('Authentication - Session Management', function() {
    var authHelper;
    authHelper = null;
    test('should maintain session across page reloads', async function({page}) {
      // Login
      await authHelper.login(page);
      // Reload page
      await page.reload();
      // Verify we're still logged in
      expect(authHelper.isAuthenticated(page)).toBeTruthy();
      return (await expect(page).toHaveURL(/\/#!\//));
    });
    test('should expire session after logout', async function({page}) {
      // Login
      await authHelper.login(page);
      // Logout
      await authHelper.logout(page);
      // Try to access protected page directly
      await page.goto('/#!spaces');
      // Verify we're redirected to login
      return (await expect(page).toHaveURL(/\/login/));
    });
    return test('should handle multiple login attempts', async function({page}) {
      // First login attempt with wrong password
      await page.goto('/login');
      await page.fill('input[name="username"]', 'admin');
      await page.fill('input[name="password"]', 'wrong');
      await page.click('button[type="submit"]');
      // Verify error message
      await expect(page.locator('[data-testid="login-error"]')).toBeVisible();
      // Second login attempt with correct credentials
      await page.fill('input[name="password"]', 'adminadmin');
      await page.click('button[type="submit"]');
      // Verify successful login
      expect(authHelper.isAuthenticated(page)).toBeTruthy();
      return (await expect(page).toHaveURL(/\*\/\#\!/));
    });
  });

}).call(this);
