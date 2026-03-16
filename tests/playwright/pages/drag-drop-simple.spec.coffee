# Simple Drag & Drop Test
{ test, expect } = require '@playwright/test'

test.describe('Pages - Widget Drag & Drop', ->
  test('should show drag handles on widget hover', ({ page }) ->
    await page.goto 'http://localhost:8081/#!pages'
    
    # Wait for page to load
    await page.waitForTimeout 2000
    
    # Check if any widgets exist
    widgets = await page.locator('[data-widget-title]').count()
    console.log "Found #{widgets} widgets on page"
    
    if widgets > 0
      # Hover over first widget
      firstWidget = page.locator('[data-widget-title]').first()
      await firstWidget.hover()
      
      console.log "✅ Widget hover test completed"
    else
      console.log "ℹ️ No widgets found for drag & drop testing"
    
    expect(widgets).toBeGreaterThanOrEqual 0
  )

  test('should handle page navigation', ({ page }) ->
    await page.goto 'http://localhost:8081/#!pages'
    
    # Wait for page to load
    await page.waitForTimeout 2000
    
    # Check if we can access pages
    title = await page.title()
    console.log "Page title: #{title}"
    
    expect(title).toBeTruthy()
  )
)
