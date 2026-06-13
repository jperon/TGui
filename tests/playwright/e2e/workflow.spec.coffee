# Workflow E2E Tests
# Complete workflow: space -> view -> page

{ test, expect } = require '@playwright/test'
{ performLogin, generateUniqueName } = require '../config/parallel-helper'

test.describe('Complete Workflow', ->
  test.beforeEach(({ page }) ->
    await performLogin page
    await page.waitForTimeout 2000
  )

  test('should login and navigate to spaces section', ({ page }) ->
    await expect(page.locator('#main')).toBeVisible()
    
    spacesList = page.locator('#space-list')
    spacesToggle = page.locator('#spaces-toggle-btn')
    
    if await spacesList.isHidden()
      await spacesToggle.click()
      await page.waitForTimeout 500
    
    await expect(spacesList).toBeVisible()
    await expect(page.locator('#new-space-btn')).toBeVisible()
  )

  test.skip('should create a new space with fields', ({ page }) ->
    spaceName = generateUniqueName 'TestSpace'
    fieldName = 'test_field'
    
    spacesList = page.locator('#space-list')
    spacesToggle = page.locator('#spaces-toggle-btn')
    
    if await spacesList.isHidden()
      await spacesToggle.click()
      await page.waitForTimeout 500
    
    await page.click '#new-space-btn'
    await page.waitForSelector '.tdb-modal-input'
    await page.fill '.tdb-modal-input', spaceName
    await page.click '.tdb-modal-actions .btn-primary'
    await page.waitForTimeout 2000
    
    createdSpace = page.locator('#space-list').locator('li', { hasText: spaceName })
    await expect(createdSpace).toBeVisible()
    
    await createdSpace.click()
    await page.waitForTimeout 1000
    
    await page.click '#fields-btn'
    await page.waitForTimeout 500
    
    await page.fill '#field-name', fieldName
    await page.selectOption '#field-type', 'String'
    await page.waitForTimeout 500
    
    addFieldBtn = page.locator('#field-add-btn')
    if await addFieldBtn.count() > 0
      await addFieldBtn.click()
    else
      saveFieldBtn = page.locator('#field-add-btn')
      await saveFieldBtn.click()
    
    await page.waitForTimeout 2000
    
    fieldsList = page.locator('#fields-list')
    createdField = fieldsList.locator('li', { hasText: fieldName })
    await expect(createdField).toBeVisible()
  )

  test('should create a data view from that space', ({ page }) ->
    spaceName = generateUniqueName 'DVSourceSpace'
    dataViewName = generateUniqueName 'TestDataView'
    fieldName = 'dv_field'
    
    spacesList = page.locator('#space-list')
    spacesToggle = page.locator('#spaces-toggle-btn')
    
    if await spacesList.isHidden()
      await spacesToggle.click()
      await page.waitForTimeout 500
    
    await page.click '#new-space-btn'
    await page.waitForSelector '.tdb-modal-input'
    await page.fill '.tdb-modal-input', spaceName
    await page.click '.tdb-modal-actions .btn-primary'
    await page.waitForTimeout 2000
    
    createdSpace = page.locator('#space-list').locator('li', { hasText: spaceName })
    await expect(createdSpace).toBeVisible()

    spaceId = await createdSpace.getAttribute('data-id')
    
    await createdSpace.click()
    await page.waitForTimeout 1000
    
    await page.click '#fields-btn'
    await page.waitForTimeout 500
    
    await page.fill '#field-name', fieldName
    await page.selectOption '#field-type', 'String'
    await page.waitForTimeout 500
    
    addFieldBtn = page.locator('#field-add-btn')
    if await addFieldBtn.count() > 0
      await addFieldBtn.click()
    else
      saveFieldBtn = page.locator('#field-add-btn')
      await saveFieldBtn.click()
    
    await page.waitForTimeout 2000
    
    dataViewsToggle = page.locator('#data-views-toggle-btn')
    dataViewsList = page.locator('#data-view-list')
    
    if await dataViewsList.isHidden()
      await dataViewsToggle.click()
      await page.waitForTimeout 500
    
    await page.click '#new-data-view-btn'
    await page.waitForTimeout 2000
    
    await page.fill '#dv-name', dataViewName
    
    # Debug: print the spaceId being used
    console.log 'Space ID to select:', spaceId
    
    sourceSelect = page.locator('#dv-source')
    await sourceSelect.selectOption { label: spaceName }
    await page.waitForTimeout 1500
    
    # Debug: print what's selected
    selectedValue = await sourceSelect.inputValue()
    console.log 'Selected value:', selectedValue
    
    await page.waitForTimeout 500
    
    await page.click '#data-view-save-btn'
    await page.waitForTimeout 5000
    
    createdDV = dataViewsList.locator('li', { hasText: dataViewName })
    await expect(createdDV).toBeVisible()
  )

  test('should create a page with a widget using that data view', ({ page }) ->
    spaceName = generateUniqueName 'WidgetSpace'
    dataViewName = generateUniqueName 'WidgetDV'
    pageName = generateUniqueName 'WidgetPage'
    fieldName = 'widget_field'
    
    spacesList = page.locator('#space-list')
    spacesToggle = page.locator('#spaces-toggle-btn')
    
    if await spacesList.isHidden()
      await spacesToggle.click()
      await page.waitForTimeout 500
    
    await page.click '#new-space-btn'
    await page.waitForSelector '.tdb-modal-input'
    await page.fill '.tdb-modal-input', spaceName
    await page.click '.tdb-modal-actions .btn-primary'
    await page.waitForTimeout 2000
    
    createdSpace = page.locator('#space-list').locator('li', { hasText: spaceName })
    await expect(createdSpace).toBeVisible()

    spaceId = await createdSpace.getAttribute('data-id')
    
    await createdSpace.click()
    await page.waitForTimeout 1000
    
    await page.click '#fields-btn'
    await page.waitForTimeout 500
    
    await page.fill '#field-name', fieldName
    await page.selectOption '#field-type', 'String'
    await page.waitForTimeout 500
    
    addFieldBtn = page.locator('#field-add-btn')
    if await addFieldBtn.count() > 0
      await addFieldBtn.click()
    else
      saveFieldBtn = page.locator('#field-add-btn')
      await saveFieldBtn.click()
    
    await page.waitForTimeout 2000
    
    dataViewsToggle = page.locator('#data-views-toggle-btn')
    dataViewsList = page.locator('#data-view-list')
    
    if await dataViewsList.isHidden()
      await dataViewsToggle.click()
      await page.waitForTimeout 500
    
    await page.click '#new-data-view-btn'
    await page.waitForTimeout 2000
    
    await page.fill '#dv-name', dataViewName
    sourceSelect = page.locator('#dv-source')
    await sourceSelect.selectOption { label: spaceName }
    await page.waitForTimeout 1500
    
    await page.click '#data-view-save-btn'
    await page.waitForTimeout 2000
    
    createdDV = dataViewsList.locator('li', { hasText: dataViewName })
    await expect(createdDV).toBeVisible()
    
    await page.goto '/#!pages'
    await page.waitForTimeout 2000
    
    result = await page.evaluate(({name, dvName}) ->
      mutation = """
        mutation {
          createCustomView(input: {
            name: "#{name}",
            yaml: "layout:\\n  direction: vertical\\n  children:\\n    - widget:\\n        id: w1\\n        title: Test Widget\\n        dataView: #{dvName}\\n        position: 1"
          }) { id name yaml }
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
    , {name: pageName, dvName: dataViewName})

    console.log "Created page:", result

    # Recharge pour refléter la création via l'API
    await page.reload()
    await page.waitForSelector '#main', { state: 'visible' }
    await page.waitForTimeout 1000

    pageItem = page.locator(".leaf-item", { hasText: pageName }).first()
    await expect(pageItem).toBeVisible()
  )

  test('should verify the page displays the widget with data', ({ page }) ->
    spaceName = generateUniqueName 'VerifySpace'
    dataViewName = generateUniqueName 'VerifyDV'
    pageName = generateUniqueName 'VerifyPage'
    fieldName = 'verify_field'
    
    spacesList = page.locator('#space-list')
    spacesToggle = page.locator('#spaces-toggle-btn')
    
    if await spacesList.isHidden()
      await spacesToggle.click()
      await page.waitForTimeout 500
    
    await page.click '#new-space-btn'
    await page.waitForSelector '.tdb-modal-input'
    await page.fill '.tdb-modal-input', spaceName
    await page.click '.tdb-modal-actions .btn-primary'
    await page.waitForTimeout 2000
    
    createdSpace = page.locator('#space-list').locator('li', { hasText: spaceName })
    await expect(createdSpace).toBeVisible()

    spaceId = await createdSpace.getAttribute('data-id')
    
    await createdSpace.click()
    await page.waitForTimeout 1000
    
    await page.click '#fields-btn'
    await page.waitForTimeout 500
    
    await page.fill '#field-name', fieldName
    await page.selectOption '#field-type', 'String'
    await page.waitForTimeout 500
    
    addFieldBtn = page.locator('#field-add-btn')
    if await addFieldBtn.count() > 0
      await addFieldBtn.click()
    else
      saveFieldBtn = page.locator('#field-add-btn')
      await saveFieldBtn.click()
    
    await page.waitForTimeout 2000
    
    dataViewsToggle = page.locator('#data-views-toggle-btn')
    dataViewsList = page.locator('#data-view-list')
    
    if await dataViewsList.isHidden()
      await dataViewsToggle.click()
      await page.waitForTimeout 500
    
    await page.click '#new-data-view-btn'
    await page.waitForTimeout 2000
    
    await page.fill '#dv-name', dataViewName
    sourceSelect = page.locator('#dv-source')
    await sourceSelect.selectOption { label: spaceName }
    await page.waitForTimeout 1500
    
    await page.click '#data-view-save-btn'
    await page.waitForTimeout 2000
    
    await page.goto '/#!pages'
    await page.waitForTimeout 2000
    
    result = await page.evaluate(({name, dvName, field}) ->
      mutation = """
        mutation {
          createCustomView(input: {
            name: "#{name}",
            yaml: "layout:\\n  direction: vertical\\n  children:\\n    - widget:\\n        id: w1\\n        title: Verification Widget\\n        dataView: #{dvName}\\n        position: 1"
          }) { id name yaml }
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
    , {name: pageName, dvName: dataViewName, field: fieldName})

    console.log "Created page:", result

    # Recharge pour refléter la création via l'API, puis ouvre la page
    await page.reload()
    await page.waitForSelector '#main', { state: 'visible' }
    await page.waitForTimeout 1000

    pageItem = page.locator(".leaf-item", { hasText: pageName }).first()
    await expect(pageItem).toBeVisible()

    await pageItem.click()
    await page.waitForTimeout 3000

    widgets = page.locator('[data-widget-id], .widget, [class*="widget"]')
    widgetCount = await widgets.count()
    
    console.log "Widget count:", widgetCount
    await expect(widgetCount).toBeGreaterThan 0
  )
)
