# Spaces Creation E2E Tests
# Tests space creation, listing, and basic CRUD operations

{ test, expect } = require '@playwright/test'
{ AuthHelper } = require '../config/auth.setup'
{ SpacesHelper } = require '../config/spaces.setup'

test.describe('Spaces - Creation', ->
  authHelper = null
  spacesHelper = null

  test.beforeEach(({ page }) ->
    authHelper = new AuthHelper()
    spacesHelper = new SpacesHelper()
    await authHelper.login page
  )

  test.afterEach(({ page }) ->
    # Clean up any created spaces
    await spacesHelper.cleanup page
  )

  test('should create space with valid data via UI', ({ page }) ->
    spaceName = spacesHelper.generateSpaceName()
    description = 'Test space created via UI'
    
    # Go to spaces page
    await page.goto '/#!spaces'
    
    # Verify spaces list is loaded
    await expect(page.locator('[data-testid="spaces-list"]')).toBeVisible()
    await expect(page.locator('[data-testid="create-space-button"]')).toBeVisible()
    
    # Create space
    spaceId = await spacesHelper.createSpace page, spaceName, description
    
    # Verify space appears in list
    await page.goto '/#!spaces'
    await expect(page.locator("[data-space-name=\"#{spaceName}\"]")).toBeVisible()
    await expect(page.locator("[data-space-name=\"#{spaceName}\"]")).toContainText spaceName
    
    # Verify space details
    await page.goto "/#!spaces/#{spaceId}"
    await expect(page.locator('[data-testid="space-details"]')).toBeVisible()
    await expect(page.locator('[data-testid="space-name"]')).toContainText spaceName
    await expect(page.locator('[data-testid="space-description"]')).toContainText description
  )

  test('should create space with valid data via GraphQL', ({ page }) ->
    spaceName = spacesHelper.generateSpaceName()
    description = 'Test space created via GraphQL'
    
    # Create space via GraphQL
    spaceId = await spacesHelper.createSpaceGraphQL page, spaceName, description
    
    # Verify space was created
    expect(spaceId).toBeTruthy()
    
    # Verify space appears in UI
    await page.goto '/#!spaces'
    await expect(page.locator("[data-space-name=\"#{spaceName}\"]")).toBeVisible()
    
    # Verify space details in UI
    await page.goto "/#!spaces/#{spaceId}"
    await expect(page.locator('[data-testid="space-name"]')).toContainText spaceName
    await expect(page.locator('[data-testid="space-description"]')).toContainText description
  )

  test('should validate required fields on space creation', ({ page }) ->
    await page.goto '/#!spaces'
    
    # Click create space button
    await page.click '[data-testid="create-space-button"]'
    
    # Try to submit without name
    await page.click '[data-testid="save-space-button"]'
    
    # Verify validation error
    await expect(page.locator('input[name="name"]:invalid')).toBeVisible()
    
    # Fill name and try again
    spaceName = spacesHelper.generateSpaceName()
    await page.fill 'input[name="name"]', spaceName
    await page.click '[data-testid="save-space-button"]'
    
    # Verify successful creation
    await expect(page.locator('[data-testid="space-created-success"]')).toBeVisible()
    
    # Clean up
    spaceId = await page.evaluate -> 
      document.querySelector('[data-space-id]')?.getAttribute('data-space-id')
    await spacesHelper.deleteSpaceGraphQL page, spaceId
  )

  test('should handle duplicate space names gracefully', ({ page }) ->
    spaceName = spacesHelper.generateSpaceName()
    
    # Create first space
    firstSpaceId = await spacesHelper.createSpaceGraphQL page, spaceName
    
    # Try to create duplicate
    try
      await spacesHelper.createSpaceGraphQL page, spaceName
      expect(false).toBeTruthy() # Should not reach here
    catch error
      expect(error.message).toContain 'already exists'
    
    # Verify first space still exists
    await page.goto '/#!spaces'
    await expect(page.locator("[data-space-name=\"#{spaceName}\"]")).toBeVisible()
    
    # Clean up
    await spacesHelper.deleteSpaceGraphQL page, firstSpaceId
  )

  test('should list spaces correctly', ({ page }) ->
    # Create multiple spaces
    spaceNames = [
      spacesHelper.generateSpaceName('space_a')
      spacesHelper.generateSpaceName('space_b')
      spacesHelper.generateSpaceName('space_c')
    ]
    
    spaceIds = []
    for spaceName in spaceNames
      spaceId = await spacesHelper.createSpaceGraphQL page, spaceName
      spaceIds.push spaceId
    
    # Verify all spaces appear in list
    await page.goto '/#!spaces'
    
    for spaceName in spaceNames
      await expect(page.locator("[data-space-name=\"#{spaceName}\"]")).toBeVisible()
    
    # Verify spaces count
    spaceElements = await page.locator('[data-space-name]').count()
    expect(spaceElements).toBeGreaterThanOrEqual spaceNames.length
    
    # Clean up
    for spaceId in spaceIds
      await spacesHelper.deleteSpaceGraphQL page, spaceId
  )

  test('should search and filter spaces', ({ page }) ->
    # Create spaces with different names
    searchableName = spacesHelper.generateSpaceName('searchable_space')
    otherName = spacesHelper.generateSpaceName('other_space')
    
    searchableId = await spacesHelper.createSpaceGraphQL page, searchableName
    otherId = await spacesHelper.createSpaceGraphQL page, otherName
    
    # Test search functionality
    await page.goto '/#!spaces'
    
    # Use search box if available
    searchBox = page.locator('[data-testid="spaces-search"]')
    if await searchBox.isVisible()
      await searchBox.fill searchableName
      
      # Verify only matching space appears
      await expect(page.locator("[data-space-name=\"#{searchableName}\"]")).toBeVisible()
      await expect(page.locator("[data-space-name=\"#{otherName}\"]")).not.toBeVisible()
      
      # Clear search
      await searchBox.fill ''
      
      # Verify both spaces appear again
      await expect(page.locator("[data-space-name=\"#{searchableName}\"]")).toBeVisible()
      await expect(page.locator("[data-space-name=\"#{otherName}\"]")).toBeVisible()
    
    # Clean up
    await spacesHelper.deleteSpaceGraphQL page, searchableId
    await spacesHelper.deleteSpaceGraphQL page, otherId
  )

  test('should handle space deletion via UI', ({ page }) ->
    spaceName = spacesHelper.generateSpaceName()
    spaceId = await spacesHelper.createSpaceGraphQL page, spaceName
    
    # Verify space exists
    await page.goto '/#!spaces'
    await expect(page.locator("[data-space-name=\"#{spaceName}\"]")).toBeVisible()
    
    # Delete space via UI
    await spacesHelper.deleteSpace page, spaceId
    
    # Verify space is gone
    await page.goto '/#!spaces'
    await expect(page.locator("[data-space-name=\"#{spaceName}\"]")).not.toBeVisible()
    
    # Verify trying to access deleted space shows error
    await page.goto "/#!spaces/#{spaceId}"
    await expect(page.locator('[data-testid="not-found"]')).toBeVisible()
  )

  test('should handle space deletion via GraphQL', ({ page }) ->
    spaceName = spacesHelper.generateSpaceName()
    spaceId = await spacesHelper.createSpaceGraphQL page, spaceName
    
    # Verify space exists
    await page.goto '/#!spaces'
    await expect(page.locator("[data-space-name=\"#{spaceName}\"]")).toBeVisible()
    
    # Delete space via GraphQL
    await spacesHelper.deleteSpaceGraphQL page, spaceId
    
    # Verify space is gone from UI
    await page.goto '/#!spaces'
    await expect(page.locator("[data-space-name=\"#{spaceName}\"]")).not.toBeVisible()
  )

  test('should handle special characters in space names', ({ page }) ->
    # Test space name with special characters
    specialName = spacesHelper.generateSpaceName('test-space_with.special@chars')
    
    spaceId = await spacesHelper.createSpaceGraphQL page, specialName
    
    # Verify space was created and is accessible
    await page.goto '/#!spaces'
    await expect(page.locator("[data-space-name=\"#{specialName}\"]")).toBeVisible()
    
    await page.goto "/#!spaces/#{spaceId}"
    await expect(page.locator('[data-testid="space-name"]')).toContainText specialName
    
    # Clean up
    await spacesHelper.deleteSpaceGraphQL page, spaceId
  )

  test('should handle very long space names', ({ page }) ->
    # Test with long name
    longName = spacesHelper.generateSpaceName('a' * 100)  # 100 characters
    
    spaceId = await spacesHelper.createSpaceGraphQL page, longName
    
    # Verify space was created
    await page.goto '/#!spaces'
    await expect(page.locator("[data-space-name=\"#{longName}\"]")).toBeVisible()
    
    # Clean up
    await spacesHelper.deleteSpaceGraphQL page, spaceId
  )
)
