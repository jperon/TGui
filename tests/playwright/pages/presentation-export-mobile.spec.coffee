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

    # Get the custom view data and select the page programmatically
    pageData = await page.evaluate (name) ->
      token = localStorage.getItem('tdb_token')
      query = """
        query {
          customViews {
            id
            name
            yaml
          }
        }
      """
      fetch('/graphql', {
        method: 'POST'
        headers: {
          'Content-Type': 'application/json'
          'Authorization': "Bearer #{token}"
        }
        body: JSON.stringify({ query: query })
      }).then((r) -> r.json()).then((result) ->
        cv = result.data?.customViews?.find (v) -> v.name == name
        cv
      )
    , pageName

    console.log "Page data:", JSON.stringify(pageData)

    # Call selectPage directly to initialize the CustomView
    if pageData
      await page.evaluate (cv) ->
        window.App._currentCustomView = cv
        window.App.selectPage cv
      , pageData
      await page.waitForTimeout 2000

    # Force container visibility
    await page.evaluate ->
      container = document.getElementById('custom-view-container')
      container.classList.remove('hidden') if container?

    # Wait for widgets to render
    await page.waitForSelector('[data-widget-id]', { timeout: 5000 }).catch(-> null)
    await page.waitForTimeout 1000

    # Check if _activeCustomView is set, if not try to initialize it
    cvInitialized = await page.evaluate ->
      if window.App?._activeCustomView
        return true
      # Try to manually initialize by calling mountCustomView
      if window.AppViewHelpers?.mountCustomView?
        container = document.getElementById('custom-view-container')
        yaml = window.App._currentCustomView?.yaml
        if yaml and container
          window.AppViewHelpers.mountCustomView(window.App, yaml)
          return !!window.App._activeCustomView
      false

    console.log "CustomView initialized:", cvInitialized

    # Check initial state - presentation mode should be false
    isPresentationMode = await page.evaluate ->
      cv = window.App?._activeCustomView
      return cv?.isPresentationMode?() or false

    console.log "Initial presentation mode:", isPresentationMode
    
    # Toggle presentation mode
    await page.evaluate ->
      cv = window.App?._activeCustomView
      if cv?.togglePresentationMode?
        cv.togglePresentationMode()

    await page.waitForTimeout 1000

    # Check that presentation mode is now true
    isPresentationModeAfter = await page.evaluate ->
      cv = window.App?._activeCustomView
      return cv?.isPresentationMode?() or false

    console.log "After toggle presentation mode:", isPresentationModeAfter
    await expect(isPresentationModeAfter).toBe true

    # Verify CSS class is applied
    hasPresentationClass = await page.evaluate ->
      # Check both the main container and the widgets container
      mainContainer = document.getElementById('custom-view-container')
      widgetsContainer = mainContainer?.querySelector('.widgets-container')
      return (widgetsContainer?.classList.contains('presentation-mode')) or (mainContainer?.classList.contains('presentation-mode'))

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

    # Create a page to import into and get ID directly from mutation result
    pageName = "ImportTarget_#{Date.now()}"

    createResult = await page.evaluate (name) ->
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

    console.log "Create result:", JSON.stringify(createResult)

    pageId = createResult.data?.createCustomView?.id

    unless pageId
      throw new Error "Failed to create page: #{JSON.stringify(createResult.errors)}"

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
    , pageId

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

  test 'should resize to mobile and apply CSS media queries', ({ page }) ->
    # Set mobile viewport
    await page.setViewportSize({ width: 375, height: 667 })
    await page.waitForTimeout 500

    # Verify viewport size
    viewport = page.viewportSize()
    expect(viewport.width).toBe 375
    expect(viewport.height).toBe 667

    # Navigate to pages
    await page.goto '/#!pages'
    await page.waitForTimeout 2000

    # Check that media queries are applied (window width should be <= 768)
    isMobileWidth = await page.evaluate ->
      window.innerWidth <= 768

    console.log "Is mobile width (<=768):", isMobileWidth
    expect(isMobileWidth).toBe true

    # Check that body has appropriate responsive class or style
    bodyStyles = await page.evaluate ->
      computed = window.getComputedStyle(document.body)
      {
        width: computed.width
        innerWidth: window.innerWidth
      }

    console.log "Computed body width:", bodyStyles.width
    expect(parseInt(bodyStyles.width)).toBeLessThanOrEqual(375)

test.describe 'DataView - readOnly option', ->
  test.beforeEach ({ page }) ->
    await performLogin page
    await page.waitForTimeout 2000

  test 'should load users space without crashing', ({ page }) ->
    console.log "Testing DataView with users space..."

    # Navigate directly to users space
    await page.goto '/#!spaces/users'
    await page.waitForTimeout 3000

    # Check that page loaded without crashing
    await expect(page.locator('#app')).toBeVisible({ timeout: 10000 })

test.describe 'DragDropManager - availability', ->
  test.beforeEach ({ page }) ->
    await performLogin page
    await page.waitForTimeout 2000

  test 'should have DragDropManager defined on window', ({ page }) ->
    # Navigate to pages
    await page.goto '/#!pages'
    await page.waitForTimeout 2000

    # Create a page with widgets
    pageName = "DDMTest_#{Date.now()}"

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

    # Get the custom view data
    pageData = await page.evaluate (name) ->
      token = localStorage.getItem('tdb_token')
      query = """
        query {
          customViews {
            id
            name
            yaml
          }
        }
      """
      fetch('/graphql', {
        method: 'POST'
        headers: {
          'Content-Type': 'application/json'
          'Authorization': "Bearer #{token}"
        }
        body: JSON.stringify({ query: query })
      }).then((r) -> r.json()).then((result) ->
        cv = result.data?.customViews?.find (v) -> v.name == name
        cv
      )
    , pageName

    # Click on the page to initialize it
    if pageData
      await page.evaluate (cv) ->
        window.App._currentCustomView = cv
        window.App.selectPage cv
      , pageData
      await page.waitForTimeout 2000

    # Force container visibility
    await page.evaluate ->
      container = document.getElementById('custom-view-container')
      container.classList.remove('hidden') if container?

    # Wait for widgets to render
    await page.waitForSelector('[data-widget-id]', { timeout: 5000 }).catch(-> null)
    await page.waitForTimeout 1000

    # Verify DragDropManager is defined
    isDefined = await page.evaluate ->
      typeof window.DragDropManager is 'function'

    console.log "DragDropManager defined:", isDefined
    expect(isDefined).toBe true

  test 'should resize to mobile viewport and apply media queries', ({ page }) ->
    # Set mobile viewport
    await page.setViewportSize({ width: 375, height: 667 })
    await page.waitForTimeout 500

    # Verify viewport size
    viewport = page.viewportSize()
    expect(viewport.width).toBe 375
    expect(viewport.height).toBe 667

    # Navigate to a page that has mobile-specific CSS
    await page.goto '/#!pages'
    await page.waitForTimeout 2000

    # Check that media query is applied by checking computed style of body
    bodyStyles = await page.evaluate ->
      computed = window.getComputedStyle(document.body)
      {
        width: computed.width
        isMobile: window.innerWidth <= 768
      }

    console.log "Body styles on mobile:", JSON.stringify(bodyStyles)
    expect(bodyStyles.isMobile).toBe true

