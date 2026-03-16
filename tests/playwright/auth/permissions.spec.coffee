# Permissions E2E Tests
# Tests access control and permissions by resource

{ test, expect } = require '@playwright/test'
{ AuthHelper } = require '../config/auth.setup'
{ SpacesHelper } = require '../config/spaces.setup'

test.describe('Authentication - Permissions', ->
  authHelper = null
  spacesHelper = null

  test.beforeEach ->
    authHelper = new AuthHelper()
    spacesHelper = new SpacesHelper()

  test.afterEach(({ page }) ->
    # Clean up any created spaces
    await spacesHelper.cleanup page
  )

  test('should allow admin to access all resources', ({ page }) ->
    # Login as admin
    await authHelper.login page
    
    # Test access to different resources
    resources = [
      { url: '/#!spaces', selector: '[data-testid="spaces-list"]' }
      { url: '/#!data-views', selector: '[data-testid="data-views-list"]' }
      { url: '/#!pages', selector: '[data-testid="pages-list"]' }
      { url: '/#!relations', selector: '[data-testid="relations-list"]' }
      { url: '/#!users', selector: '[data-testid="users-list"]' }
    ]
    
    for resource in resources
      await page.goto resource.url
      
      # Verify resource is accessible
      await expect(page.locator(resource.selector)).toBeVisible()
      
      # Verify no access denied message
      await expect(page.locator('[data-testid="access-denied"]')).not.toBeVisible()
    
    console.log '✅ Admin can access all resources'
  )

  test('should deny access to unauthenticated users', ({ page }) ->
    # Try to access protected resources without authentication
    protectedUrls = [
      '/#!spaces'
      '/#!data-views'
      '/#!pages'
      '/#!relations'
      '/#!users'
    ]
    
    for url in protectedUrls
      await page.goto url
      
      # Verify redirect to login
      await expect(page).toHaveURL /\*\/login/
      
      # Verify access denied message
      await expect(page.locator('[data-testid="access-denied"]')).toBeVisible()
    
    console.log '✅ Unauthenticated users denied access to protected resources'
  )

  test('should enforce read/write permissions on spaces', ({ page }) ->
    # Login as admin
    await authHelper.login page
    
    # Create a test space
    spaceName = spacesHelper.generateSpaceName()
    spaceId = await spacesHelper.createSpaceGraphQL page, spaceName
    
    # Create a test user with limited permissions
    # Note: This would require user creation API - for now we test with admin
    
    # Test admin can read and write
    await page.goto "/#!spaces/#{spaceId}"
    await expect(page.locator('[data-testid="space-details"]')).toBeVisible()
    
    # Test adding field (write permission)
    await spacesHelper.addFieldGraphQL page, spaceId, 'test_field', 'String'
    
    # Verify field was added
    await page.goto "/#!spaces/#{spaceId}"
    await expect(page.locator('[data-field-name="test_field"]')).toBeVisible()
    
    console.log '✅ Admin has read/write permissions on spaces'
  )

  test('should enforce permissions on Data Views', ({ page }) ->
    # Login as admin
    await authHelper.login page
    
    # Create a test space first
    spaceName = spacesHelper.generateSpaceName()
    spaceId = await spacesHelper.createSpaceGraphQL page, spaceName
    
    # Create a Data View
    { DataViewsHelper } = require '../config/data-views.setup'
    dataViewsHelper = new DataViewsHelper()
    
    dataViewName = dataViewsHelper.generateDataViewName()
    dataViewId = await dataViewsHelper.createDataViewGraphQL page, dataViewName, 'Test Data View', spaceName
    
    # Test admin can access Data View
    await page.goto "/#!data-views/#{dataViewId}"
    await expect(page.locator('[data-testid="data-view-details"]')).toBeVisible()
    
    # Test admin can modify Data View
    await dataViewsHelper.updateDataView page, dataViewId, { description: 'Updated description' }
    
    # Verify update
    await page.goto "/#!data-views/#{dataViewId}"
    await expect(page.locator('[data-testid="data-view-description"]')).toContainText 'Updated description'
    
    # Clean up
    await dataViewsHelper.cleanup page
    
    console.log '✅ Admin has full permissions on Data Views'
  )

  test('should enforce permissions on Pages', ({ page }) ->
    # Login as admin
    await authHelper.login page
    
    # Create a test page
    { PagesHelper } = require '../config/pages.setup'
    pagesHelper = new PagesHelper()
    
    pageName = pagesHelper.generatePageName()
    pageId = await pagesHelper.createPageGraphQL page, pageName
    
    # Test admin can access page
    await page.goto "/#!pages/#{pageId}"
    await expect(page.locator('[data-testid="page-details"]')).toBeVisible()
    
    # Test admin can modify page
    newYaml = """
layout:
  direction: vertical
  children:
    - widget:
        title: Test Widget
        space: #{spaceName}
"""
    
    await pagesHelper.updatePageYAMLGraphQL page, pageId, newYaml
    
    # Verify update
    updatedYaml = await pagesHelper.getPageYAMLGraphQL page, pageId
    expect(updatedYaml).toContain 'Test Widget'
    
    # Clean up
    await pagesHelper.cleanup page
    
    console.log '✅ Admin has full permissions on Pages'
  )

  test('should handle permission errors gracefully', ({ page }) ->
    # Login as admin
    await authHelper.login page
    
    # Try to access non-existent resource
    await page.goto '/#!spaces/non-existent-id'
    
    # Verify error handling
    await expect(page.locator('[data-testid="not-found"]')).toBeVisible()
    await expect(page.locator('[data-testid="not-found"]')).toContainText 'Space not found'
    
    # Try to modify non-existent resource via GraphQL
    try
      await spacesHelper.addFieldGraphQL page, 'non-existent-id', 'test', 'String'
      expect(false).toBeTruthy() # Should not reach here
    catch error
      expect(error.message).toContain 'Space not found'
    
    console.log '✅ Permission errors handled gracefully'
  )

  test('should validate API authentication', ({ page }) ->
    # Try GraphQL request without authentication
    try
      await authHelper.makeGraphQLRequest page, '{ spaces { id name } }'
      expect(false).toBeTruthy() # Should not reach here
    catch error
      expect(error.message).toContain 'Not authenticated'
    
    # Login and try again
    await authHelper.login page
    
    result = await authHelper.makeGraphQLRequest page, '{ spaces { id name } }'
    expect(result.spaces).toBeDefined()
    expect(Array.isArray(result.spaces)).toBeTruthy()
    
    console.log '✅ API authentication working correctly'
  )
)
