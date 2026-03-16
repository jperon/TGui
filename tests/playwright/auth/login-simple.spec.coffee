# Simple login test for Playwright
{ test, expect } = require '@playwright/test'

test.describe('Authentication - Simple Login', ->
  test('should load login page', ({ page }) ->
    await page.goto '/login'
    
    # Check if login page loads
    title = await page.title()
    console.log "Page title: #{title}"
    
    expect(title).toBeTruthy()
    
    # Check for login form elements
    await expect(page.locator('input[name="username"]')).toBeVisible()
    await expect(page.locator('input[name="password"]')).toBeVisible()
    await expect(page.locator('button[type="submit"]')).toBeVisible()
  )

  test('should show error with invalid credentials', ({ page }) ->
    await page.goto '/login'
    
    # Try invalid login
    await page.fill 'input[name="username"]', 'invalid'
    await page.fill 'input[name="password"]', 'invalid'
    await page.click 'button[type="submit"]'
    
    # Should stay on login page or show error
    await page.waitForTimeout 1000
    
    currentUrl = page.url()
    console.log "Current URL after invalid login: #{currentUrl}"
    
    # Either shows error or stays on login page
    expect(currentUrl).toMatch /login/
  )
)
