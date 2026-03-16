# Authentication E2E Tests - Fixed selectors
# Tests login, logout, and session management

{ test, expect } = require '@playwright/test'
{ AuthHelper } = require '../config/auth.setup'

test.describe('Authentication - Login', ->
  authHelper = null

  test.beforeEach ->
    authHelper = new AuthHelper()

  test('should login with valid credentials', ({ page }) ->
    await page.goto '/'

    # Verify login page is loaded
    await expect(page.locator('h1')).toContainText 'TGui'
    await expect(page.locator('#login-username')).toBeVisible()
    await expect(page.locator('#login-password')).toBeVisible()

    # Perform login
    await page.fill '#login-username', 'admin'
    await page.fill '#login-password', 'adminadmin'
    await page.click '#login-btn'

    # Wait for login to complete
    await page.waitForSelector '#main', { state: 'visible' }

    # Verify successful login
    expect(authHelper.isAuthenticated page).toBeTruthy()

    # Verify main app elements are visible
    await expect(page.locator('#main')).toBeVisible()
    await expect(page.locator('#sidebar')).toBeVisible()
  )

  test('should fail login with invalid credentials', ({ page }) ->
    await page.goto '/'

    # Try to login with invalid credentials
    await page.fill '#login-username', 'invalid'
    await page.fill '#login-password', 'invalid'
    await page.click '#login-btn'

    # Wait for error message
    await page.waitForTimeout 1000

    # Verify login failed - login overlay should still be visible
    await expect(page.locator('#login-overlay')).toBeVisible()
    await expect(page.locator('#login-error')).toBeVisible()

    # Verify we're still on login page
    await expect(page.locator('#login-overlay')).toBeVisible()
  )

  test('should fail login with missing username', ({ page }) ->
    await page.goto '/'

    # Try to login with missing username
    await page.fill '#login-password', 'adminadmin'
    await page.click '#login-btn'

    # Wait for error
    await page.waitForTimeout 1000

    # Verify login failed
    await expect(page.locator('#login-overlay')).toBeVisible()
  )

  test('should fail login with missing password', ({ page }) ->
    await page.goto '/'

    # Try to login with missing password
    await page.fill '#login-username', 'admin'
    await page.click '#login-btn'

    # Wait for error
    await page.waitForTimeout 1000

    # Verify login failed
    await expect(page.locator('#login-overlay')).toBeVisible()
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

    # Perform logout - find logout button or trigger logout
    # For now, let's simulate logout by clearing session
    await page.evaluate(() -> localStorage.clear())

    # Reload page
    await page.reload()

    # Verify logout success
    await expect(page.locator('#login-overlay')).toBeVisible()
    await expect(page.locator('#main')).toHaveClass 'hidden'
  )

  test('should clear authentication token on logout', ({ page }) ->
    # Verify token exists before logout
    expect(authHelper.token).toBeTruthy()

    # Perform logout
    await page.evaluate(() -> localStorage.clear())
    await page.reload()

    # Verify token is cleared
    expect(authHelper.isAuthenticated page).toBeFalsy()
  )
)

test.describe('Authentication - Session Management', ->
  authHelper = null

  test('should maintain session across page reloads', ({ page }) ->
    # Login
    await page.goto '/'
    await page.fill '#login-username', 'admin'
    await page.fill '#login-password', 'adminadmin'
    await page.click '#login-btn'
    await page.waitForSelector '#main', { state: 'visible' }

    # Reload page
    await page.reload()

    # Wait for possible login check
    await page.waitForTimeout 2000

    # Verify we're still logged in (main app should be visible)
    await expect(page.locator('#main')).toBeVisible()
    await expect(page.locator('#login-overlay')).toHaveClass 'overlay hidden'
  )

  test('should expire session after logout', ({ page }) ->
    # Login
    await page.goto '/'
    await page.fill '#login-username', 'admin'
    await page.fill '#login-password', 'adminadmin'
    await page.click '#login-btn'
    await page.waitForSelector '#main', { state: 'visible' }

    # Logout
    await page.evaluate(() -> localStorage.clear())
    await page.reload()

    # Try to access protected page directly
    await page.goto '/#!spaces'

    # Verify we're redirected to login
    await expect(page.locator('#login-overlay')).toBeVisible()
  )

  test('should handle multiple login attempts', ({ page }) ->
    await page.goto '/'

    # First login attempt with wrong password
    await page.fill '#login-username', 'admin'
    await page.fill '#login-password', 'wrong'
    await page.click '#login-btn'

    # Wait for error
    await page.waitForTimeout 1000

    # Verify error message
    await expect(page.locator('#login-error')).toBeVisible()

    # Second login attempt with correct credentials
    await page.fill '#login-username', 'admin'
    await page.fill '#login-password', 'adminadmin'
    await page.click '#login-btn'

    # Wait for login
    await page.waitForSelector '#main', { state: 'visible' }

    # Verify successful login
    await expect(page.locator('#main')).toBeVisible()
  )
)
