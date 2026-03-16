# Simple test to verify Playwright setup works
{ test, expect } = require '@playwright/test'

test.describe('Simple Test', ->
  test('should load page', ({ page }) ->
    await page.goto 'http://localhost:8081'
    
    # Just check if page loads without error
    title = await page.title()
    console.log "Page title: #{title}"
    
    expect(title).toBeTruthy()
  )
)
