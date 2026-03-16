# Permissions E2E Tests - Parallel-ready version
# Tests user/group permissions and admin panel access

{ test, expect } = require '@playwright/test'
{ performLogin } = require '../config/parallel-helper'

test.describe('Permissions - Admin Panel (Parallel)', ->
  test.beforeEach(({ page }) ->
    await performLogin page
    # Wait for interface to be fully loaded
    await page.waitForTimeout 2000
  )

  test('should access admin panel as admin', ({ page }) ->
    # Try to access admin section
    adminToggle = page.locator('#admin-toggle-btn')
    adminSection = page.locator('#admin-sidebar-section')

    # If admin section is collapsed, expand it
    adminClasses = await adminSection.getAttribute('class')
    if adminClasses?.includes('collapsed')
      await adminToggle.click()
      await page.waitForTimeout 500

    # Verify admin section is accessible
    await expect(adminSection).not.toHaveClass('hidden')

    # Verify admin navigation items exist
    await expect(page.locator('#admin-nav-users')).toHaveCount(1)
    await expect(page.locator('#admin-nav-groups')).toHaveCount(1)
    await expect(page.locator('#admin-nav-snapshot')).toHaveCount(1)
  )

  test('should access users management', ({ page }) ->
    # Expand admin section if needed
    adminToggle = page.locator('#admin-toggle-btn')
    adminSection = page.locator('#admin-sidebar-section')

    adminClasses = await adminSection.getAttribute('class')
    if adminClasses?.includes('collapsed')
      await adminToggle.click()
      await page.waitForTimeout 500

    # Click on users management
    await page.click '#admin-nav-users'
    await page.waitForTimeout 500

    # Verify users section is visible
    await expect(page.locator('#admin-users-section')).toBeVisible()
    await expect(page.locator('#admin-create-user-btn')).toBeVisible()
    await expect(page.locator('#admin-users-list')).toHaveCount(1)
  )

  test('should access groups management', ({ page }) ->
    # Expand admin section if needed
    adminToggle = page.locator('#admin-toggle-btn')
    adminSection = page.locator('#admin-sidebar-section')

    adminClasses = await adminSection.getAttribute('class')
    if adminClasses?.includes('collapsed')
      await adminToggle.click()
      await page.waitForTimeout 500

    # Click on groups management
    await page.click '#admin-nav-groups'
    await page.waitForTimeout 500

    # Verify groups section is visible
    await expect(page.locator('#admin-groups-section')).toBeVisible()
    await expect(page.locator('#admin-create-group-btn')).toBeVisible()
  )

  test('should access snapshot management', ({ page }) ->
    # Expand admin section if needed
    adminToggle = page.locator('#admin-toggle-btn')
    adminSection = page.locator('#admin-sidebar-section')

    adminClasses = await adminSection.getAttribute('class')
    if adminClasses?.includes('collapsed')
      await adminToggle.click()
      await page.waitForTimeout 500

    # Click on snapshot management
    await page.click '#admin-nav-snapshot'
    await page.waitForTimeout 500

    # Verify snapshot functionality exists
    await expect(page.locator('#snapshot-import-result')).toHaveCount(1)
  )

  test('should toggle admin section', ({ page }) ->
    adminToggle = page.locator('#admin-toggle-btn')
    adminSection = page.locator('#admin-sidebar-section')

    # Verify initial state (likely collapsed)
    initialClasses = await adminSection.getAttribute('class')
    initialCollapsed = initialClasses?.includes('collapsed')

    # Toggle admin section
    await adminToggle.click()
    await page.waitForTimeout 500

    # Verify state changed
    newClasses = await adminSection.getAttribute('class')
    newCollapsed = newClasses?.includes('collapsed')
    await expect(newCollapsed).not.toBe(initialCollapsed)

    # Toggle back
    await adminToggle.click()
    await page.waitForTimeout 500

    # Verify back to original state
    finalClasses = await adminSection.getAttribute('class')
    finalCollapsed = finalClasses?.includes('collapsed')
    await expect(finalCollapsed).toBe(initialCollapsed)
  )

  test('should verify admin elements exist', ({ page }) ->
    # Verify all admin elements exist in DOM
    await expect(page.locator('#admin-sidebar-section')).toHaveCount(1)
    await expect(page.locator('#admin-toggle-btn')).toHaveCount(1)
    await expect(page.locator('#admin-panel')).toHaveCount(1)
    await expect(page.locator('#admin-users-section')).toHaveCount(1)
    await expect(page.locator('#admin-groups-section')).toHaveCount(1)
    await expect(page.locator('#admin-nav-users')).toHaveCount(1)
    await expect(page.locator('#admin-nav-groups')).toHaveCount(1)
    await expect(page.locator('#admin-nav-snapshot')).toHaveCount(1)
    await expect(page.locator('#admin-create-user-btn')).toHaveCount(1)
    await expect(page.locator('#admin-create-group-btn')).toHaveCount(1)
  )
)
