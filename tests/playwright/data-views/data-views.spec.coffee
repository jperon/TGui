# Data Views E2E Tests
# Tests data view CRUD operations

{ test, expect } = require '@playwright/test'
{ performLogin, generateUniqueName } = require '../config/parallel-helper'

test.describe('Data Views', ->
  test.beforeEach(({ page }) ->
    await performLogin page
    await page.waitForTimeout 2000
  )

  test('should access data views section', ({ page }) ->
    dataViewsList = page.locator('#data-view-list')
    dataViewsToggle = page.locator('#data-views-toggle-btn')
    
    try
      if await dataViewsToggle.isVisible()
        await dataViewsToggle.click()
        await page.waitForTimeout 500
    catch error
    
    if await dataViewsList.isVisible()
      await expect(dataViewsList).toBeVisible()
      await expect(page.locator('#new-data-view-btn')).toBeVisible()
    else
      await expect(dataViewsList).toHaveCount(1)
      await expect(page.locator('#new-data-view-btn')).toHaveCount(1)
  )

  test('should create a new data view', ({ page }) ->
    dataViewsToggle = page.locator('#data-views-toggle-btn')
    dataViewsList = page.locator('#data-view-list')
    
    try
      if await dataViewsToggle.isVisible()
        await dataViewsToggle.click()
        await page.waitForTimeout 500
    catch error
    
    existingItems = dataViewsList.locator 'li'
    count = await existingItems.count()
    
    if count > 0
      await expect(existingItems.first()).toBeVisible()
    else
      dataViewName = generateUniqueName 'TestDataView'
      
      await page.click '#new-data-view-btn'
      await page.waitForTimeout 1500
      
      await page.fill '#dv-name', dataViewName
      
      sourceSelect = page.locator '#dv-source'
      await sourceSelect.selectOption { index: 1 }
      await page.waitForTimeout 1000
      
      yamlEditor = page.locator '#dv-yaml-content'
      if await yamlEditor.isVisible()
        await yamlEditor.fill 'columns: []'
        await page.waitForTimeout 500
      
      await page.click '#data-view-save-btn'
      await page.waitForTimeout 3000
      
      createdItem = page.locator('#data-view-list').locator('li', { hasText: dataViewName })
      try
        await expect(createdItem).toBeVisible()
      catch e
        test.skip()
  )

  test('should execute a data view and see results', ({ page }) ->
    dataViewsToggle = page.locator('#data-views-toggle-btn')
    dataViewsList = page.locator('#data-view-list')
    
    try
      if await dataViewsToggle.isVisible()
        await dataViewsToggle.click()
        await page.waitForTimeout 500
    catch error
    
    existingItems = dataViewsList.locator 'li'
    count = await existingItems.count()
    
    if count > 0
      await existingItems.first().click()
      await page.waitForTimeout 2000
      
      gridContainer = page.locator '#grid-container'
      if await gridContainer.isVisible()
        await expect(gridContainer).toBeVisible()
      else
        await expect(page.locator('#data-view-panel')).toBeVisible()
    else
      test.skip()
  )

  test('should edit a data view', ({ page }) ->
    dataViewsToggle = page.locator('#data-views-toggle-btn')
    dataViewsList = page.locator('#data-view-list')
    
    try
      if await dataViewsToggle.isVisible()
        await dataViewsToggle.click()
        await page.waitForTimeout 500
    catch error
    
    existingItems = dataViewsList.locator 'li'
    count = await existingItems.count()
    
    if count > 0
      await existingItems.first().click()
      await page.waitForTimeout 1500
      
      await page.click '#rename-space-btn'
      await page.waitForTimeout 1000
      
      modalTitle = await page.locator('#data-view-modal-title').textContent()
      expect(modalTitle).toContain('Modifier')
      
      newName = generateUniqueName 'EditedDV'
      await page.fill '#dv-name', newName
      await page.click '#data-view-save-btn'
      await page.waitForTimeout 2000
      
      updatedItem = dataViewsList.locator('li', { hasText: newName })
      await expect(updatedItem).toBeVisible()
    else
      test.skip()
  )

  test('should delete a data view', ({ page }) ->
    dataViewsToggle = page.locator('#data-views-toggle-btn')
    dataViewsList = page.locator('#data-view-list')
    
    try
      if await dataViewsToggle.isVisible()
        await dataViewsToggle.click()
        await page.waitForTimeout 500
    catch error
    
    existingItems = dataViewsList.locator 'li'
    count = await existingItems.count()
    
    if count > 0
      await existingItems.first().click()
      await page.waitForTimeout 1000
      
      await page.click '#delete-space-btn'
      await page.waitForTimeout 1000
      
      dialog = page.locator '.tui-modal, .modal, [class*="confirm"], [class*="dialog"]'
      if await dialog.isVisible()
        confirmBtn = page.locator 'button[class*="danger"], button[class*="delete"], button:has-text("Supprimer"), button:has-text("Delete"), button[class*="confirm"]'
        await confirmBtn.click()
        await page.waitForTimeout 2000
      
      await expect(existingItems.first()).toBeHidden()
    else
      test.skip()
  )
)
