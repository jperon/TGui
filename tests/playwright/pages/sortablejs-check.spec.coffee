# Playwright test for SortableJS availability and console error detection
{ test, expect } = require '@playwright/test'

# Helper to check if SortableJS is loaded on the page
checkSortableJS = (page) ->
  await page.evaluate(() ->
    if typeof Sortable is 'undefined'
      return { loaded: false, error: 'SortableJS is not defined on window' }
    
    if typeof Sortable.create isnt 'function'
      return { loaded: false, error: 'Sortable.create is not a function' }
    
    { loaded: true }
  )

test.describe('SortableJS Library', ->
  test('should load SortableJS library on page load', ({ page }) ->
    # Navigate to the app (will redirect to login)
    await page.goto '/'
    
    # Wait for scripts to load
    await page.waitForLoadState 'networkidle'
    
    # Check if SortableJS is available
    result = await checkSortableJS(page)
    
    # Report the result
    if not result.loaded
      console.error 'SortableJS check failed:', result.error
    
    expect(result.loaded, "SortableJS should be loaded on the page").toBe true
  )

  test('should load SortableJS after login', ({ page }) ->
    # Login first
    await page.goto '/'
    await page.fill '#login-username', 'admin'
    await page.fill '#login-password', 'adminadmin'
    await page.click '#login-btn'
    
    # Wait for main app to be visible
    await page.waitForSelector '#main', { state: 'visible' }
    
    # Wait for scripts to fully load
    await page.waitForLoadState 'networkidle'
    
    # Check if SortableJS is available after login
    result = await checkSortableJS(page)
    
    if not result.loaded
      console.error 'SortableJS check failed after login:', result.error
    
    expect(result.loaded, "SortableJS should be loaded after login").toBe true
  )
)

# Test for console error detection
test.describe('Console Error Detection', ->
  test('should not have console errors on page load', ({ page }) ->
    consoleErrors = []
    
    # Listen for console errors
    page.on 'console', (msg) ->
      if msg.type() is 'error'
        consoleErrors.push msg.text()
    
    # Navigate to the app
    await page.goto '/'
    
    # Wait for page to fully load
    await page.waitForLoadState 'networkidle'
    
    # Wait a bit more for any async errors
    await page.waitForTimeout 2000
    
    # Report any errors found
    if consoleErrors.length > 0
      console.error 'Console errors detected:', consoleErrors
    
    expect(consoleErrors.length, "Should have no console errors on page load").toBe 0
  )

  test('should not have console errors after login', ({ page }) ->
    consoleErrors = []
    
    # Listen for console errors
    page.on 'console', (msg) ->
      if msg.type() is 'error'
        consoleErrors.push msg.text()
    
    # Login
    await page.goto '/'
    await page.fill '#login-username', 'admin'
    await page.fill '#login-password', 'adminadmin'
    await page.click '#login-btn'
    
    # Wait for main app to be visible
    await page.waitForSelector '#main', { state: 'visible' }
    
    # Wait for page to fully load
    await page.waitForLoadState 'networkidle'
    
    # Wait a bit more for any async errors
    await page.waitForTimeout 2000
    
    # Report any errors found
    if consoleErrors.length > 0
      console.error 'Console errors detected after login:', consoleErrors
    
    expect(consoleErrors.length, "Should have no console errors after login").toBe 0
  )
)
