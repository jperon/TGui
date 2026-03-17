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
    
    if await dataViewsList.isHidden()
      await dataViewsToggle.click()
      await page.waitForTimeout 500
    
    await expect(dataViewsList).toBeVisible()
    await expect(page.locator('#new-data-view-btn')).toBeVisible()
  )

  test('should create a new data view', ({ page }) ->
    dataViewName = generateUniqueName('TestDataView')
    
    # Expand data views section
    dataViewsList = page.locator('#data-view-list')
    dataViewsToggle = page.locator('#data-views-toggle-btn')
    
    if await dataViewsList.isHidden()
      await dataViewsToggle.click()
      await page.waitForTimeout 500
    
    # Click new data view button
    await page.click '#new-data-view-btn'
    await page.waitForTimeout 1000
    
    # Fill in the data view form
    await page.fill '#dv-name', dataViewName
    
    # Select source space (assuming 'users' exists in test DB)
    await page.selectOption '#dv-source', 'users'
    await page.waitForTimeout 1000
    
    # Save the data view
    await page.click '#data-view-save-btn'
    await page.waitForTimeout 2000
    
    # Verify the data view was created in the sidebar
    createdItem = page.locator('#data-view-list').locator('li', { hasText: dataViewName })
    await expect(createdItem).toBeVisible()
  )

  test('should execute a data view and see results', ({ page }) ->
    # First create a data view if none exists
    dataViewsList = page.locator('#data-view-list')
    dataViewsToggle = page.locator('#data-views-toggle-btn')
    
    if await dataViewsList.isHidden()
      await dataViewsToggle.click()
      await page.waitForTimeout 500
    
    # Check if there are any existing data views
    existingItems = dataViewsList.locator('li')
    count = await existingItems.count()
    
    if count > 0
      # Click on the first data view to execute it
      await existingItems.first().click()
      await page.waitForTimeout 2000
      
      # Check that grid container is visible (shows data view results)
      gridContainer = page.locator('#grid-container')
      await expect(gridContainer).toBeVisible()
    else
      # Create a new data view first
      dataViewName = generateUniqueName('TestDataView')
      await page.click '#new-data-view-btn'
      await page.waitForTimeout 1000
      await page.fill '#dv-name', dataViewName
      await page.selectOption '#dv-source', 'users'
      await page.waitForTimeout 1000
      await page.click '#data-view-save-btn'
      await page.waitForTimeout 2000
      
      # Click on the created data view
      createdItem = dataViewsList.locator('li', { hasText: dataViewName })
      await createdItem.click()
      await page.waitForTimeout 2000
      
      # Verify grid is displayed
      gridContainer = page.locator('#grid-container')
      await expect(gridContainer).toBeVisible()
  )

  test('should edit a data view', ({ page }) ->
    dataViewsList = page.locator('#data-view-list')
    dataViewsToggle = page.locator('#data-views-toggle-btn')
    
    if await dataViewsList.isHidden()
      await dataViewsToggle.click()
      await page.waitForTimeout 500
    
    # Check if there are any data views
    existingItems = dataViewsList.locator('li')
    count = await existingItems.count()
    
    if count > 0
      # Click on first data view to select it
      await existingItems.first().click()
      await page.waitForTimeout 1000
      
      # Click configure button (renameSpaceBtn has title "Configurer la vue" for data views)
      await page.click '#rename-space-btn'
      await page.waitForTimeout 1000
      
      # Verify modal is open and has the edit title
      modalTitle = await page.locator('#data-view-modal-title').textContent()
      expect(modalTitle).toContain('Modifier')
      
      # Change the name
      newName = generateUniqueName('EditedDataView')
      await page.fill '#dv-name', newName
      await page.click '#data-view-save-btn'
      await page.waitForTimeout 2000
      
      # Verify the name was updated in the sidebar
      updatedItem = dataViewsList.locator('li', { hasText: newName })
      await expect(updatedItem).toBeVisible()
  )

  test('should delete a data view', ({ page }) ->
    dataViewsList = page.locator('#data-view-list')
    dataViewsToggle = page.locator('#data-views-toggle-btn')
    
    if await dataViewsList.isHidden()
      await dataViewsToggle.click()
      await page.waitForTimeout 500
    
    # First create a data view to delete
    dataViewName = generateUniqueName('DeleteMeDataView')
    await page.click '#new-data-view-btn'
    await page.waitForTimeout 1000
    await page.fill '#dv-name', dataViewName
    await page.selectOption '#dv-source', 'users'
    await page.waitForTimeout 1000
    await page.click '#data-view-save-btn'
    await page.waitForTimeout 2000
    
    # Verify it was created
    createdItem = dataViewsList.locator('li', { hasText: dataViewName })
    await expect(createdItem).toBeVisible()
    
    # Select the data view
    await createdItem.click()
    await page.waitForTimeout 1000
    
    # Click delete button (deleteSpaceBtn has title "Supprimer la vue" for data views)
    await page.click '#delete-space-btn'
    await page.waitForTimeout 1000
    
    # Handle the confirmation dialog
    dialog = page.locator('.tui-modal, .modal, [class*="confirm"], [class*="dialog"]')
    if await dialog.isVisible()
      # Look for confirm/delete button
      confirmBtn = page.locator('button[class*="danger"], button[class*="delete"], button:has-text("Supprimer"), button:has-text("Delete"), button[class*="confirm"]')
      await confirmBtn.click()
      await page.waitForTimeout 2000
    
    # Verify the data view was deleted
    deletedItem = dataViewsList.locator('li', { hasText: dataViewName })
    await expect(deletedItem).toHaveCount(0)
  )
)
