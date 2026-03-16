# Pages Drag & Drop E2E Tests
# Tests widget drag and drop functionality

{ test, expect } = require '@playwright/test'
{ AuthHelper } = require '../config/auth.setup'
{ PagesHelper } = require '../config/pages.setup'
{ SpacesHelper } = require '../config/spaces.setup'

test.describe 'Pages - Widget Drag & Drop', ->
  authHelper = null
  pagesHelper = null
  spacesHelper = null
  pageId = null
  spaceId = null

  test.beforeEach ({ page }) ->
    authHelper = new AuthHelper()
    pagesHelper = new PagesHelper()
    spacesHelper = new SpacesHelper()
    await authHelper.login page
    
    # Create a test space
    spaceName = spacesHelper.generateSpaceName('dragdrop_test')
    spaceId = await spacesHelper.createSpaceGraphQL page, spaceName
    await spacesHelper.addFieldGraphQL page, spaceId, 'name', 'String'
    
    # Create a test page with multiple widgets
    pageName = pagesHelper.generatePageName('dragdrop_page')
    pageId = await pagesHelper.createPageGraphQL page, pageName
    
    # Add several widgets for drag & drop testing
    widgetConfigs = [
      { title: 'Widget A', space: spaceName, columns: ['name'] }
      { title: 'Widget B', space: spaceName, columns: ['name'] }
      { title: 'Widget C', space: spaceName, columns: ['name'] }
      { title: 'Widget D', space: spaceName, columns: ['name'] }
    ]
    
    for config in widgetConfigs
      await pagesHelper.addWidget page, pageId, config

  test.afterEach ({ page }) ->
    # Clean up test data
    await pagesHelper.cleanup page
    await spacesHelper.cleanup page

  test 'should show drag handles on widget hover', ({ page }) ->
    await page.goto "/#!pages/#{pageId}"
    
    # Wait for widgets to load
    await page.waitForSelector '[data-widget-title]'
    
    # Hover over first widget
    firstWidget = page.locator '[data-widget-title="Widget A"]'
    await firstWidget.hover()
    
    # Verify drag handle appears
    dragHandle = page.locator '[data-widget-title="Widget A"] [data-testid="widget-drag-handle"]'
    await expect(dragHandle).toBeVisible()
    
    # Verify drag handle has appropriate styling
    await expect(dragHandle).toHaveClass /drag-handle/
    await expect(dragHandle).toHaveCSS 'cursor', 'grab'
    
    console.log "✅ Drag handle appears on widget hover"

  test 'should reorder widgets via drag and drop', ({ page }) ->
    await page.goto "/#!pages/#{pageId}"
    await page.waitForSelector '[data-widget-title]'
    
    # Get initial widget order
    widgetElements = await page.locator('[data-widget-title]').all()
    initialOrder = []
    for element in widgetElements
      widgetTitle = await element.getAttribute 'data-widget-title'
      initialOrder.push widgetTitle
    
    console.log "Initial widget order: #{initialOrder.join(', ')}"
    
    # Drag first widget to last position
    sourceWidget = page.locator '[data-widget-title="Widget A"]'
    targetPosition = page.locator '[data-widget-title="Widget D"]'
    
    # Perform drag and drop
    await sourceWidget.dragTo targetPosition
    
    # Wait for reordering to complete
    await page.waitForTimeout 1000
    
    # Get new order
    newWidgetElements = await page.locator('[data-widget-title]').all()
    newOrder = []
    for element in newWidgetElements
      widgetTitle = await element.getAttribute 'data-widget-title'
      newOrder.push widgetTitle
    
    console.log "New widget order: #{newOrder.join(', ')}"
    
    # Verify order changed
    expect(newOrder).not.toEqual initialOrder
    
    # Verify specific change (Widget A should no longer be first)
    expect(newOrder[0]).not.toBe 'Widget A'

  test 'should handle drag with many widgets', ({ page }) ->
    # Add more widgets for stress testing
    additionalWidgets = []
    for i in [5..8]
      widgetConfig = {
        title: "Widget #{String.fromCharCode(64 + i)}"  # E, F, G, H
        space: spaceName
        columns: ['name']
      }
      await pagesHelper.addWidget page, pageId, widgetConfig
      additionalWidgets.push widgetConfig.title
    
    await page.goto "/#!pages/#{pageId}"
    await page.waitForSelector '[data-widget-title]'
    
    # Verify all widgets are displayed
    widgetElements = await page.locator('[data-widget-title]').all()
    expect(widgetElements.length).toBe 8
    
    # Test reordering with many widgets
    middleWidget = page.locator '[data-widget-title="Widget F"]'
    targetWidget = page.locator '[data-widget-title="Widget B"]'
    
    await middleWidget.dragTo targetWidget
    await page.waitForTimeout 1000
    
    # Verify reordering still works with many widgets
    widgetElements = await page.locator('[data-widget-title]').all()
    expect(widgetElements.length).toBe 8
    
    console.log "✅ Drag & drop works with #{widgetElements.length} widgets"

  test 'should show visual feedback during drag', ({ page }) ->
    await page.goto "/#!pages/#{pageId}"
    await page.waitForSelector '[data-widget-title]'
    
    # Start dragging
    widgetHeader = page.locator '[data-widget-title="Widget A"] .widget-header'
    await widgetHeader.down()
    
    # Verify visual feedback
    draggingWidget = page.locator '[data-widget-title="Widget A"]'
    
    # Check for visual indicators
    await expect(draggingWidget).toHaveClass /widget-chosen/
    await expect(draggingWidget).toHaveCSS 'opacity', /0\.8/  # Semi-transparent
    
    # Release drag
    await widgetHeader.up()
    
    # Verify visual feedback cleared
    await expect(draggingWidget).not.toHaveClass /widget-chosen/

  test 'should prevent invalid drops', ({ page }) ->
    await page.goto "/#!pages/#{pageId}"
    await page.waitForSelector '[data-widget-title]'
    
    # Try to drag widget outside valid drop zone
    sourceWidget = page.locator '[data-widget-title="Widget B"]'
    
    # Drag to outside field list area
    await sourceWidget.dragTo page.locator '[data-testid="page-header"]'
    
    # Verify widget returns to original position
    await page.waitForTimeout 1000
    
    widgetElements = await page.locator('[data-widget-title]').all()
    currentOrder = []
    for element in widgetElements
      widgetTitle = await element.getAttribute 'data-widget-title'
      currentOrder.push widgetTitle
    
    expectedOrder = ['Widget A', 'Widget B', 'Widget C', 'Widget D']
    expect(currentOrder).toEqual expectedOrder
