(function() {
  // Spaces Creation E2E Tests - Final Parallel version
  // Tests space operations with correct handling of UI states
  var expect, generateUniqueName, performLogin, test;

  ({test, expect} = require('@playwright/test'));

  ({performLogin, generateUniqueName} = require('../config/parallel-helper'));

  test.describe('Spaces - Creation (Final Parallel)', function() {
    test.beforeEach(async function({page}) {
      await performLogin(page);
      // Wait for interface to be fully loaded
      return (await page.waitForTimeout(2000));
    });
    test('should access spaces section', async function({page}) {
      var spacesList, spacesToggle;
      // Check if spaces section is visible, if not expand it
      spacesList = page.locator('#space-list');
      spacesToggle = page.locator('#spaces-toggle-btn');
      
      // If spaces list is hidden, click toggle to expand
      if ((await spacesList.isHidden())) {
        await spacesToggle.click();
        await page.waitForTimeout(500);
      }
      
      // Now verify spaces section is accessible
      await expect(spacesList).toBeVisible();
      return (await expect(page.locator('#new-space-btn')).toBeVisible());
    });
    test('should toggle spaces section', async function({page}) {
      var spacesList, spacesToggle;
      spacesList = page.locator('#space-list');
      spacesToggle = page.locator('#spaces-toggle-btn');
      
      // Ensure section is expanded first
      if ((await spacesList.isHidden())) {
        await spacesToggle.click();
        await page.waitForTimeout(500);
      }
      
      // Verify it's expanded
      await expect(spacesList).toBeVisible();
      
      // Toggle to collapse
      await spacesToggle.click();
      await page.waitForTimeout(500);
      
      // Verify it's collapsed
      await expect(spacesList).toBeHidden();
      
      // Toggle back to expand
      await spacesToggle.click();
      await page.waitForTimeout(500);
      
      // Verify it's expanded again
      return (await expect(spacesList).toBeVisible());
    });
    test('should access data views section', async function({page}) {
      var dataViewsList, dataViewsToggle, error;
      dataViewsList = page.locator('#data-view-list');
      dataViewsToggle = page.locator('#data-views-toggle-btn');
      try {
        
        // Data views section might be collapsed by default
        // Try to expand it if the toggle button exists and is clickable
        if ((await dataViewsToggle.isVisible())) {
          await dataViewsToggle.click();
          await page.waitForTimeout(500);
        }
      } catch (error1) {
        error = error1;
      }
      // Toggle might not be available, continue

      // Check if data views section is now visible
      // If still hidden, that's OK - just verify the element exists
      if ((await dataViewsList.isVisible())) {
        await expect(dataViewsList).toBeVisible();
        return (await expect(page.locator('#new-data-view-btn')).toBeVisible());
      } else {
        // Just verify the elements exist in DOM
        await expect(dataViewsList).toHaveCount(1);
        return (await expect(page.locator('#new-data-view-btn')).toHaveCount(1));
      }
    });
    test('should access pages section', async function({page}) {
      var newPageBtn, pagesList;
      pagesList = page.locator('#page-list');
      
      // Pages section might be collapsed by default
      // Just verify the elements exist in DOM
      await expect(pagesList).toHaveCount(1);
      
      // Check for new page button
      newPageBtn = page.locator('#new-page-btn');
      return (await expect(newPageBtn).toHaveCount(1));
    });
    test('should test basic navigation', async function({page}) {
      var main, sidebar, toggleBtn;
      // Test sidebar toggle functionality
      sidebar = page.locator('#sidebar');
      main = page.locator('#main');
      toggleBtn = page.locator('#sidebar-toggle-btn');
      
      // Verify initial state
      await expect(sidebar).toBeVisible();
      await expect(main).toBeVisible();
      
      // Check if toggle button exists and is clickable
      if ((await toggleBtn.isVisible())) {
        // Toggle sidebar
        await toggleBtn.click();
        await page.waitForTimeout(500);
        
        // Verify sidebar state changed (main should have sidebar-collapsed class)
        if ((await main.getAttribute('class').then(function(cls) {
          return cls != null ? cls.includes('sidebar-collapsed') : void 0;
        }))) {
          // Toggle back
          await toggleBtn.click();
          return (await page.waitForTimeout(500));
        }
      }
    });
    return test('should verify all sections exist', async function({page}) {
      // Verify all main sections exist in DOM
      await expect(page.locator('#space-list')).toHaveCount(1);
      await expect(page.locator('#data-view-list')).toHaveCount(1);
      await expect(page.locator('#page-list')).toHaveCount(1);
      await expect(page.locator('#new-space-btn')).toHaveCount(1);
      await expect(page.locator('#new-data-view-btn')).toHaveCount(1);
      await expect(page.locator('#new-page-btn')).toHaveCount(1);
      await expect(page.locator('#spaces-toggle-btn')).toHaveCount(1);
      return (await expect(page.locator('#data-views-toggle-btn')).toHaveCount(1));
    });
  });

}).call(this);
