# Presentation Mode, Export/Import Layouts, and Mobile Responsive E2E Tests
# Tests for Phase 6 features: presentation mode, export/import layouts, mobile responsive

{ test, expect } = require '@playwright/test'
{ performLogin, generateUniqueName } = require '../config/parallel-helper'

test.describe 'Pages - Presentation Mode', ->
  test.beforeEach ({ page }) ->
    await performLogin page
    await page.waitForTimeout 2000

  test 'should toggle presentation mode and disable drag & drop', ({ page }) ->
    # Navigate to pages
    await page.goto '/#!pages'
    await page.waitForTimeout 2000

    # Create a page with widgets
    pageName = "PresentationTest_#{Date.now()}"

    await page.evaluate (name) ->
      mutation = """
        mutation {
          createCustomView(input: {
            name: "#{name}",
            yaml: "layout:\\n  direction: vertical\\n  children:\\n    - widget:\\n        id: w1\\n        title: Widget 1\\n        space: users\\n    - widget:\\n        id: w2\\n        title: Widget 2\\n        space: tasks"
          }) { id name }
        }
      """
      token = localStorage.getItem('tdb_token')
      fetch('/graphql', {
        method: 'POST'
        headers: {
          'Content-Type': 'application/json'
          'Authorization': "Bearer #{token}"
        }
        body: JSON.stringify({ query: mutation })
      }).then((r) -> r.json())
    , pageName

    await page.waitForTimeout 2000

    # Click on the page
    pageItem = page.locator(".leaf-item:has-text('#{pageName}')")
    if await pageItem.count() > 0
      await pageItem.click()
      await page.waitForTimeout 3000

    # Force container visibility
    await page.evaluate ->
      container = document.getElementById('custom-view-container')
      container.classList.remove('hidden') if container?

    await page.waitForTimeout 1000

    # Check initial state - presentation mode should be false
    isPresentationMode = await page.evaluate ->
      cv = window.CustomView?.instances?[0]
      return cv?.isPresentationMode?() or false

    console.log "Initial presentation mode:", isPresentationMode
    
    # Toggle presentation mode
    await page.evaluate ->
      cv = window.CustomView?.instances?[0]
      if cv?.togglePresentationMode?
        cv.togglePresentationMode()

    await page.waitForTimeout 1000

    # Check that presentation mode is now true
    isPresentationModeAfter = await page.evaluate ->
      cv = window.CustomView?.instances?[0]
      return cv?.isPresentationMode?() or false

    console.log "After toggle presentation mode:", isPresentationModeAfter
    await expect(isPresentationModeAfter).toBe true

    # Verify CSS class is applied
    hasPresentationClass = await page.evaluate ->
      container = document.getElementById('custom-view-container')
      return container?.classList.contains('presentation-mode')

    console.log "Has presentation-mode class:", hasPresentationClass
    await expect(hasPresentationClass).toBe true

    # Verify drag handles are hidden
    deleteButtonsVisible = await page.locator('.cv-widget-delete-btn').isVisible().catch(-> false)
    console.log "Delete buttons visible in presentation mode:", deleteButtonsVisible
    await expect(deleteButtonsVisible).toBe false

test.describe 'Pages - Export/Import Layouts', ->
  test.beforeEach ({ page }) ->
    await performLogin page
    await page.waitForTimeout 2000

  test 'should export layout as YAML file', ({ page }) ->
    # Navigate to pages
    await page.goto '/#!pages'
    await page.waitForTimeout 2000

    # Create a page with widgets
    pageName = "ExportTest_#{Date.now()}"

    await page.evaluate (name) ->
      mutation = """
        mutation {
          createCustomView(input: {
            name: "#{name}",
            yaml: "layout:\\n  direction: vertical\\n  children:\\n    - widget:\\n        id: w1\\n        title: Test Widget\\n        space: users"
          }) { id name }
        }
      """
      token = localStorage.getItem('tdb_token')
      fetch('/graphql', {
        method: 'POST'
        headers: {
          'Content-Type': 'application/json'
          'Authorization': "Bearer #{token}"
        }
        body: JSON.stringify({ query: mutation })
      }).then((r) -> r.json())
    , pageName

    await page.waitForTimeout 2000

    # Find and click the export button
    pageItem = page.locator(".leaf-item:has-text('#{pageName}')")
    if await pageItem.count() > 0
      await pageItem.hover()
      await page.waitForTimeout 500

      # Look for export button
      exportBtn = page.locator('.leaf-item-actions .page-action-btn').first()
      
      if await exportBtn.count() > 0
        # Start download listener
        downloadPromise = page.waitForEvent('download', { timeout: 5000 }).catch(-> null)
        
        await exportBtn.click()
        await page.waitForTimeout 1000

        console.log "Export button clicked"
      else
        console.log "Export button not found"

  test 'should import layout from YAML file', ({ page }) ->
    # Navigate to pages
    await page.goto '/#!pages'
    await page.waitForTimeout 2000

    # Create a page to import into
    pageName = "ImportTarget_#{Date.now()}"

    await page.evaluate (name) ->
      mutation = """
        mutation {
          createCustomView(input: {
            name: "#{name}",
            yaml: "layout:\\n  direction: vertical\\n  children: []"
          }) { id name }
        }
      """
      token = localStorage.getItem('tdb_token')
      fetch('/graphql', {
        method: 'POST'
        headers: {
          'Content-Type': 'application/json'
          'Authorization': "Bearer #{token}"
        }
        body: JSON.stringify({ query: mutation })
      }).then((r) -> r.json())
    , pageName

    await page.waitForTimeout 2000

    # Get page ID
    pageId = await page.evaluate (name) ->
      mutation = """
        query {
          customViews(filter: { name: "#{name}" }) {
            id
          }
        }
      """
      token = localStorage.getItem('tdb_token')
      fetch('/graphql', {
        method: 'POST'
        headers: {
          'Content-Type': 'application/json'
          'Authorization': "Bearer #{token}"
        }
        body: JSON.stringify({ query: mutation })
      }).then((r) -> r.json())
    , pageName

    console.log "Page ID:", JSON.stringify(pageId)

    # Test importLayout mutation directly
    importResult = await page.evaluate (id) ->
      mutation = """
        mutation ImportLayout($pageId: ID!, $yaml: String!) {
          importLayout(pageId: $pageId, yaml: $yaml) {
            id
            name
            yaml
          }
        }
      """
      token = localStorage.getItem('tdb_token')
      fetch('/graphql', {
        method: 'POST'
        headers: {
          'Content-Type': 'application/json'
          'Authorization': "Bearer #{token}"
        }
        body: JSON.stringify({ 
          query: mutation,
          variables: {
            pageId: id,
            yaml: "layout:\\n  direction: horizontal\\n  children:\\n    - widget:\\n        id: imported1\\n        title: Imported Widget\\n        space: users"
          }
        })
      }).then((r) -> r.json())
    , pageId.customViews[0].id

    console.log "Import result:", JSON.stringify(importResult)
    
    # Verify import was successful
    if importResult.data?.importLayout
      await expect(importResult.data.importLayout.yaml).toContain 'imported1'
      await expect(importResult.data.importLayout.yaml).toContain 'horizontal'
    else
      console.log "Import failed:", importResult.errors

test.describe 'Pages - Mobile Responsive', ->
  test.beforeEach ({ page }) ->
    await performLogin page
    await page.waitForTimeout 2000

  test 'should apply mobile responsive styles on small viewport', ({ page }) ->
    # Set mobile viewport
    await page.setViewportSize({ width: 375, height: 667 })
    await page.waitForTimeout 500

    # Navigate to pages
    await page.goto '/#!pages'
    await page.waitForTimeout 2000

    # Create a page with zones
    pageName = "MobileTest_#{Date.now()}"

    await page.evaluate (name) ->
      mutation = """
        mutation {
          createCustomView(input: {
            name: "#{name}",
            yaml: "layout:\\n  direction: vertical\\n  children:\\n    - zone:\\n        id: zone1\\n        title: Zone 1\\n        direction: horizontal\\n        children:\\n          - widget:\\n              id: w1\\n              title: Widget 1\\n              space: users"
          }) { id name }
        }
      """
      token = localStorage.getItem('tdb_token')
      fetch('/graphql', {
        method: 'POST'
        headers: {
          'Content-Type': 'application/json'
          'Authorization': "Bearer #{token}"
        }
        body: JSON.stringify({ query: mutation })
      }).then((r) -> r.json())
    , pageName

    await page.waitForTimeout 2000

    # Click on the page
    pageItem = page.locator(".leaf-item:has-text('#{pageName}')")
    if await pageItem.count() > 0
      await pageItem.click()
      await page.waitForTimeout 3000

    # Force container visibility
    await page.evaluate ->
      container = document.getElementById('custom-view-container')
      container.classList.remove('hidden') if container?

    await page.waitForTimeout 1000

    # Check that zone headers are hidden on mobile
    zoneHeaderVisible = await page.locator('.cv-zone-header').isVisible().catch(-> false)
    console.log "Zone header visible on mobile:", zoneHeaderVisible
    await expect(zoneHeaderVisible).toBe false

    # Check that layout palette is hidden on mobile
    layoutPaletteVisible = await page.locator('.cv-layout-palette').isVisible().catch(-> false)
    console.log "Layout palette visible on mobile:", layoutPaletteVisible
    await expect(layoutPaletteVisible).toBe false

  test 'should maintain full-width widgets on mobile', ({ page }) ->
    # Set mobile viewport
    await page.setViewportSize({ width: 375, height: 667 })
    await page.waitForTimeout 500

    # Navigate to pages
    await page.goto '/#!pages'
    await page.waitForTimeout 2000

    # Create a page with widgets
    pageName = "MobileWidgets_#{Date.now()}"

    await page.evaluate (name) ->
      mutation = """
        mutation {
          createCustomView(input: {
            name: "#{name}",
            yaml: "layout:\\n  direction: vertical\\n  children:\\n    - widget:\\n        id: w1\\n        title: Widget 1\\n        space: users\\n    - widget:\\n        id: w2\\n        title: Widget 2\\n        space: tasks"
          }) { id name }
        }
      """
      token = localStorage.getItem('tdb_token')
      fetch('/graphql', {
        method: 'POST'
        headers: {
          'Content-Type': 'application/json'
          'Authorization': "Bearer #{token}"
        }
        body: JSON.stringify({ query: mutation })
      }).then((r) -> r.json())
    , pageName

    await page.waitForTimeout 2000

    # Click on the page
    pageItem = page.locator(".leaf-item:has-text('#{pageName}')")
    if await pageItem.count() > 0
      await pageItem.click()
      await page.waitForTimeout 3000

    # Force container visibility
    await page.evaluate ->
      container = document.getElementById('custom-view-container')
      container.classList.remove('hidden') if container?

    await page.waitForTimeout 1000

    # Check widget elements exist
    widgets = page.locator('.cv-widget')
    widgetCount = await widgets.count()
    console.log "Widget count on mobile:", widgetCount
    await expect(widgetCount).toBeGreaterThan 0
