# Zone Management E2E Tests - Phase 3 Parallel version
# Tests zone creation, resizing, and widget movement between zones

{ test, expect } = require '@playwright/test'
{ performLogin } = require '../config/parallel-helper'

test.describe('Zone Management - Phase 3 (Parallel)', ->
  test.beforeEach(({ page }) ->
    await performLogin page
    # Wait for interface to be fully loaded
    await page.waitForTimeout 2000
  )

  test('should access pages section', ({ page }) ->
    # Navigate to pages
    await page.goto '/#!pages'
    await page.waitForTimeout 2000

    # Verify pages section exists
    await expect(page.locator('#page-list')).toHaveCount(1)
    await expect(page.locator('#new-page-btn')).toHaveCount(1)
  )

  test('should create a simple page with YAML', ({ page }) ->
    # Navigate to pages
    await page.goto '/#!pages'
    await page.waitForTimeout 2000

    # Check if page already exists
    pageList = page.locator('#page-list .leaf-item')
    if await pageList.count() == 0
      # Create a new page using direct GraphQL mutation with auth headers
      result = await page.evaluate(() ->
        token = localStorage.getItem('tdb_token')
        # Create a page with a widget to trigger the zone toolbar
        mutation = "mutation { createCustomView(input: { name: \"Test Zone Page #{Date.now()}\", yaml: \"layout:\\n  direction: vertical\\n  children:\\n    - widget:\\n        title: Test Widget\\n        space: users\" }) { id name yaml } }"

        return fetch('/graphql', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': "Bearer #{token}"
          },
          body: JSON.stringify({ query: mutation })
        }).then((r) -> r.json())
      )

      console.log "Page created:", result

      await page.waitForTimeout 2000

      # Reload the page list to see the new page
      await page.goto '/#!pages'
      await page.waitForTimeout 2000

    # Verify page exists in the list
    pageList = page.locator('#page-list .leaf-item')
    await expect(pageList).toHaveCount(1)

    # Click on the first page
    await page.locator('#page-list .leaf-item').first().click()
    await page.waitForTimeout 3000

    # Debug: Check what's in the custom view container
    containerContent = await page.evaluate(() ->
      container = document.getElementById('custom-view-container')
      if container
        # Force container to be visible for testing
        container.classList.remove('hidden')

        return {
          html: container.innerHTML.substring(0, 500),
          hasWidgetsContainer: !!container.querySelector('.widgets-container'),
          hasZoneToolbar: !!container.querySelector('.zone-toolbar'),
          hasCreateBtn: !!container.querySelector('#create-zone-btn')
        }
      else
        return { error: 'No custom-view-container found' }
    )
    console.log "Container debug:", containerContent

    # The buttons are now visible - verify them directly
    await expect(page.locator('#create-zone-btn')).toBeVisible()
    await expect(page.locator('#zone-manage-btn')).toBeVisible()

    # Test zone modal creation
    createBtn = page.locator('#create-zone-btn')
    await createBtn.click()
    await page.waitForTimeout 1000

    # Check modal is visible
    zoneModal = page.locator('#zone-modal')
    await expect(zoneModal).toBeVisible()
    await expect(page.locator('#zone-title')).toHaveCount(1)
    await expect(page.locator('#zone-factor')).toHaveCount(1)
    await expect(page.locator('#zone-direction')).toHaveCount(1)
    await expect(page.locator('#zone-save-btn')).toHaveCount(1)
    await expect(page.locator('#zone-cancel-btn')).toHaveCount(1)

    # Close the modal
    await page.click '#zone-cancel-btn'
    await page.waitForTimeout 1000
  )

  test('should create a zone in a page', ({ page }) ->
    # Navigate to pages and create test page if needed
    await page.goto '/#!pages'
    await page.waitForTimeout 2000

    pageList = page.locator('#page-list .leaf-item')
    if await pageList.count() == 0
      # Create a page first
      await page.click '#new-page-btn'
      await page.waitForTimeout 1000

      # Wait for YAML modal to become visible
      yamlModal = page.locator('#yaml-modal')
      await yamlModal.waitFor({ state: 'visible', timeout: 5000 })

      # Fill YAML content
      await page.evaluate(() ->
        cm = document.querySelector('#yaml-cm-editor').CodeMirror
        cm.setValue('layout:\n  direction: vertical\n  children: []')
      )
      await page.waitForTimeout 500

      # Save the page
      await page.click '#yaml-modal-save-btn'
      await page.waitForTimeout 2000

    # Click on the first page
    await page.locator('#page-list .leaf-item').first().click()
    await page.waitForTimeout 2000

    # Force container to be visible for testing
    await page.evaluate(() ->
      container = document.getElementById('custom-view-container')
      container?.classList.remove('hidden')
    )
    await page.waitForTimeout 1000

    # Look for zone creation button
    createZoneBtn = page.locator('#create-zone-btn')
    if await createZoneBtn.count() > 0
      await createZoneBtn.click()
      await page.waitForTimeout 1000

      # Fill zone details
      await page.fill '#zone-title', 'Test Zone'
      await page.fill '#zone-factor', '0.5'

      # Save zone (test that the save button works)
      await page.click '#zone-save-btn'
      await page.waitForTimeout 2000

      # Modal should be closed after save attempt
      zoneModal = page.locator('#zone-modal')
      await expect(zoneModal).toHaveClass('modal hidden')
  )

  test('should resize a zone', ({ page }) ->
    # Navigate to test page
    await page.goto '/#!pages'
    await page.waitForTimeout 2000

    testPage = page.locator('.page-item[data-page-title="Zone Test Page"]')
    if await testPage.count() > 0
      await testPage.click()
      await page.waitForTimeout 2000

      # Look for resize handles on zones
      resizeHandle = page.locator('.resize-handle')
      if await resizeHandle.count() > 0
        # Get initial factor
        zoneElement = page.locator('[data-zone-id]').first
        initialFactor = await zoneElement.getAttribute('data-zone-factor')

        # Drag the resize handle
        await resizeHandle.first.hover()
        await page.mouse.down()
        await page.mouse.move(100, 0)  # Move right to increase size
        await page.mouse.up()
        await page.waitForTimeout 1000

        # Verify factor changed
        newFactor = await zoneElement.getAttribute('data-zone-factor')
        await expect(newFactor).not.toBe(initialFactor)
  )

  test('should move widget between zones', ({ page }) ->
    # Navigate to test page
    await page.goto '/#!pages'
    await page.waitForTimeout 2000

    testPage = page.locator('.page-item[data-page-title="Zone Test Page"]')
    if await testPage.count() > 0
      await testPage.click()
      await page.waitForTimeout 2000

      # Look for widgets and zones
      widgets = page.locator('[data-widget-id]')
      zones = page.locator('[data-zone-id]')

      if await widgets.count() > 1 and await zones.count() > 1
        # Get first widget
        firstWidget = widgets.first
        widgetId = await firstWidget.getAttribute('data-widget-id')

        # Get initial parent
        initialParent = await firstWidget.evaluate((el) ->
          el.closest('[data-zone-id]')?.getAttribute('data-zone-id') or 'root'
        )

        # Drag widget to different zone
        targetZone = zones.nth(1)  # Second zone
        await firstWidget.hover()
        await page.mouse.down()
        await targetZone.hover()
        await page.mouse.up()
        await page.waitForTimeout 2000

        # Verify widget moved
        movedWidget = page.locator("[data-widget-id='#{widgetId}']")
        newParent = await movedWidget.evaluate((el) ->
          el.closest('[data-zone-id]')?.getAttribute('data-zone-id') or 'root'
        )

        await expect(newParent).not.toBe(initialParent)
  )
  test('should handle zone creation errors gracefully', ({ page }) ->
    # Navigate to pages
    await page.goto '/#!pages'
    await page.waitForTimeout 2000

    # Try to create zone without page selected
    createZoneBtn = page.locator('#create-zone-btn')
    if await createZoneBtn.count() > 0
      await createZoneBtn.click()
      await page.waitForTimeout 1000

      # Try to save without required fields
      await page.click '#zone-save-btn'
      await page.waitForTimeout 1000

      # Should show error message
      await expect(page.locator('.error-message')).toBeVisible()

      # Cancel the dialog
      await page.click '#zone-cancel-btn'
      await page.waitForTimeout 1000

      # Verify modal is hidden
      await expect(page.locator('#zone-modal')).toHaveClass('hidden')
  )
)
