# Authentication E2E Tests
# Tests login, logout, and session management

{ test, expect } = require '@playwright/test'
{ AuthHelper } = require '../config/auth.setup'

test.describe('Authentication - Login', ->
  authHelper = null

  test.beforeEach ->
    authHelper = new AuthHelper()

  test('should login with valid credentials', ({ page }) ->
    await page.goto '/login'

    # Verify login page is loaded
    await expect(page.locator('h1')).toContainText 'Login'
    await expect(page.locator('input[name="username"]')).toBeVisible()
    await expect(page.locator('input[name="password"]')).toBeVisible()

    # Perform login
    token = await authHelper.login page, 'admin', 'adminadmin'

    # Verify successful login
    expect(token).toBeTruthy()
    expect(authHelper.isAuthenticated page).toBeTruthy()

    # Verify we're redirected to main app
    await expect(page).toHaveURL /\*\/\#\!/

    # Verify main app elements are visible
    await expect(page.locator('[data-testid="main-app"]')).toBeVisible()
    await expect(page.locator('[data-testid="sidebar"]')).toBeVisible()
  )

  test('should fail login with invalid credentials', ({ page }) ->
    await page.goto '/login'

    # Try to login with invalid credentials
    await page.fill 'input[name="username"]', 'invalid'
    await page.fill 'input[name="password"]', 'invalid'
    await page.click 'button[type="submit"]'

    # Verify login failed
    await expect(page.locator('[data-testid="login-error"]')).toBeVisible()
    await expect(page.locator('[data-testid="login-error"]')).toContainText 'Invalid credentials'

    # Verify we're still on login page
    await expect(page).toHaveURL /\*\/login/
  )

  test('should fail login with missing username', ({ page }) ->
    await page.goto '/login'

    # Try to login with missing username
    await page.fill 'input[name="password"]', 'adminadmin'
    await page.click 'button[type="submit"]'

    # Verify validation error
    await expect(page.locator('input[name="username"]:invalid')).toBeVisible()
  )

  test('should fail login with missing password', ({ page }) ->
    await page.goto '/login'

    # Try to login with missing password
    await page.fill 'input[name="username"]', 'admin'
    await page.click 'button[type="submit"]'

    # Verify validation error
    await expect(page.locator('input[name="password"]:invalid')).toBeVisible()
  )
)

test.describe('Authentication - Logout', ->
  authHelper = null

  test.beforeEach(({ page }) ->
    authHelper = new AuthHelper()
    await authHelper.login page
  )

  test('should logout successfully', ({ page }) ->
    # Verify we're logged in
    expect(authHelper.isAuthenticated page).toBeTruthy()

    # Perform logout
    await authHelper.logout page

    # Verify logout success
    expect(authHelper.isAuthenticated page).toBeFalsy()
    await expect(page).toHaveURL /\/login/

    # Verify login page is shown again
    await expect(page.locator('h1')).toContainText 'Login'
  )

  test('should clear authentication token on logout', ({ page }) ->
    # Verify token exists before logout
    expect(authHelper.token).toBeTruthy()

    # Perform logout
    await authHelper.logout page

    # Verify token is cleared
    expect(authHelper.token).toBeNull()
    expect(authHelper.currentUser).toBeNull()
  )
)

test.describe('Authentication - Session Management', ->
  authHelper = null

  test('should maintain session across page reloads', ({ page }) ->
    # Login
    await authHelper.login page

    # Reload page
    await page.reload()

    # Verify we're still logged in
    expect(authHelper.isAuthenticated page).toBeTruthy()
    await expect(page).toHaveURL /\/#!\//
  )

  test('should expire session after logout', ({ page }) ->
    # Login
    await authHelper.login page

    # Logout
    await authHelper.logout page

    # Try to access protected page directly
    await page.goto '/#!spaces'

    # Verify we're redirected to login
    await expect(page).toHaveURL /\/login/
  )

  test('should handle multiple login attempts', ({ page }) ->
    # First login attempt with wrong password
    await page.goto '/login'
    await page.fill 'input[name="username"]', 'admin'
    await page.fill 'input[name="password"]', 'wrong'
    await page.click 'button[type="submit"]'

    # Verify error message
    await expect(page.locator('[data-testid="login-error"]')).toBeVisible()

    # Second login attempt with correct credentials
    await page.fill 'input[name="password"]', 'adminadmin'
    await page.click 'button[type="submit"]'

    # Verify successful login
    expect(authHelper.isAuthenticated page).toBeTruthy()
    await expect(page).toHaveURL /\*\/\#\!/
  )
)
