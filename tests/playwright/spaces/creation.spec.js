(function() {
  // Spaces Creation E2E Tests
  // Tests space creation, listing, and basic CRUD operations
  var AuthHelper, SpacesHelper, expect, test;

  ({test, expect} = require('@playwright/test'));

  ({AuthHelper} = require('../config/auth.setup'));

  ({SpacesHelper} = require('../config/spaces.setup'));

  test.describe('Spaces - Creation', function() {
    var authHelper, spacesHelper;
    authHelper = null;
    spacesHelper = null;
    test.beforeEach(async function({page}) {
      authHelper = new AuthHelper();
      spacesHelper = new SpacesHelper();
      return (await authHelper.login(page));
    });
    test.afterEach(async function({page}) {
      // Clean up any created spaces
      return (await spacesHelper.cleanup(page));
    });
    test('should create space with valid data via UI', async function({page}) {
      var description, spaceId, spaceName;
      spaceName = spacesHelper.generateSpaceName();
      description = 'Test space created via UI';
      
      // Go to spaces page
      await page.goto('/#!spaces');
      
      // Verify spaces list is loaded
      await expect(page.locator('[data-testid="spaces-list"]')).toBeVisible();
      await expect(page.locator('[data-testid="create-space-button"]')).toBeVisible();
      
      // Create space
      spaceId = (await spacesHelper.createSpace(page, spaceName, description));
      
      // Verify space appears in list
      await page.goto('/#!spaces');
      await expect(page.locator(`[data-space-name=\"${spaceName}\"]`)).toBeVisible();
      await expect(page.locator(`[data-space-name=\"${spaceName}\"]`)).toContainText(spaceName);
      
      // Verify space details
      await page.goto(`/#!spaces/${spaceId}`);
      await expect(page.locator('[data-testid="space-details"]')).toBeVisible();
      await expect(page.locator('[data-testid="space-name"]')).toContainText(spaceName);
      return (await expect(page.locator('[data-testid="space-description"]')).toContainText(description));
    });
    test('should create space with valid data via GraphQL', async function({page}) {
      var description, spaceId, spaceName;
      spaceName = spacesHelper.generateSpaceName();
      description = 'Test space created via GraphQL';
      
      // Create space via GraphQL
      spaceId = (await spacesHelper.createSpaceGraphQL(page, spaceName, description));
      
      // Verify space was created
      expect(spaceId).toBeTruthy();
      
      // Verify space appears in UI
      await page.goto('/#!spaces');
      await expect(page.locator(`[data-space-name=\"${spaceName}\"]`)).toBeVisible();
      
      // Verify space details in UI
      await page.goto(`/#!spaces/${spaceId}`);
      await expect(page.locator('[data-testid="space-name"]')).toContainText(spaceName);
      return (await expect(page.locator('[data-testid="space-description"]')).toContainText(description));
    });
    test('should validate required fields on space creation', async function({page}) {
      var spaceId, spaceName;
      await page.goto('/#!spaces');
      
      // Click create space button
      await page.click('[data-testid="create-space-button"]');
      
      // Try to submit without name
      await page.click('[data-testid="save-space-button"]');
      
      // Verify validation error
      await expect(page.locator('input[name="name"]:invalid')).toBeVisible();
      
      // Fill name and try again
      spaceName = spacesHelper.generateSpaceName();
      await page.fill('input[name="name"]', spaceName);
      await page.click('[data-testid="save-space-button"]');
      
      // Verify successful creation
      await expect(page.locator('[data-testid="space-created-success"]')).toBeVisible();
      
      // Clean up
      spaceId = (await page.evaluate(function() {
        var ref;
        return (ref = document.querySelector('[data-space-id]')) != null ? ref.getAttribute('data-space-id') : void 0;
      }));
      return (await spacesHelper.deleteSpaceGraphQL(page, spaceId));
    });
    test('should handle duplicate space names gracefully', async function({page}) {
      var error, firstSpaceId, spaceName;
      spaceName = spacesHelper.generateSpaceName();
      
      // Create first space
      firstSpaceId = (await spacesHelper.createSpaceGraphQL(page, spaceName));
      try {
        
        // Try to create duplicate
        await spacesHelper.createSpaceGraphQL(page, spaceName);
        expect(false).toBeTruthy(); // Should not reach here
      } catch (error1) {
        error = error1;
        expect(error.message).toContain('already exists');
      }
      
      // Verify first space still exists
      await page.goto('/#!spaces');
      await expect(page.locator(`[data-space-name=\"${spaceName}\"]`)).toBeVisible();
      
      // Clean up
      return (await spacesHelper.deleteSpaceGraphQL(page, firstSpaceId));
    });
    test('should list spaces correctly', async function({page}) {
      var i, j, k, len, len1, len2, results, spaceElements, spaceId, spaceIds, spaceName, spaceNames;
      // Create multiple spaces
      spaceNames = [spacesHelper.generateSpaceName('space_a'), spacesHelper.generateSpaceName('space_b'), spacesHelper.generateSpaceName('space_c')];
      spaceIds = [];
      for (i = 0, len = spaceNames.length; i < len; i++) {
        spaceName = spaceNames[i];
        spaceId = (await spacesHelper.createSpaceGraphQL(page, spaceName));
        spaceIds.push(spaceId);
      }
      
      // Verify all spaces appear in list
      await page.goto('/#!spaces');
      for (j = 0, len1 = spaceNames.length; j < len1; j++) {
        spaceName = spaceNames[j];
        await expect(page.locator(`[data-space-name=\"${spaceName}\"]`)).toBeVisible();
      }
      
      // Verify spaces count
      spaceElements = (await page.locator('[data-space-name]').count());
      expect(spaceElements).toBeGreaterThanOrEqual(spaceNames.length);

      // Clean up
      results = [];
      for (k = 0, len2 = spaceIds.length; k < len2; k++) {
        spaceId = spaceIds[k];
        results.push((await spacesHelper.deleteSpaceGraphQL(page, spaceId)));
      }
      return results;
    });
    test('should search and filter spaces', async function({page}) {
      var otherId, otherName, searchBox, searchableId, searchableName;
      // Create spaces with different names
      searchableName = spacesHelper.generateSpaceName('searchable_space');
      otherName = spacesHelper.generateSpaceName('other_space');
      searchableId = (await spacesHelper.createSpaceGraphQL(page, searchableName));
      otherId = (await spacesHelper.createSpaceGraphQL(page, otherName));
      
      // Test search functionality
      await page.goto('/#!spaces');
      
      // Use search box if available
      searchBox = page.locator('[data-testid="spaces-search"]');
      if ((await searchBox.isVisible())) {
        await searchBox.fill(searchableName);
        
        // Verify only matching space appears
        await expect(page.locator(`[data-space-name=\"${searchableName}\"]`)).toBeVisible();
        await expect(page.locator(`[data-space-name=\"${otherName}\"]`)).not.toBeVisible();
        
        // Clear search
        await searchBox.fill('');
        
        // Verify both spaces appear again
        await expect(page.locator(`[data-space-name=\"${searchableName}\"]`)).toBeVisible();
        await expect(page.locator(`[data-space-name=\"${otherName}\"]`)).toBeVisible();
      }
      
      // Clean up
      await spacesHelper.deleteSpaceGraphQL(page, searchableId);
      return (await spacesHelper.deleteSpaceGraphQL(page, otherId));
    });
    test('should handle space deletion via UI', async function({page}) {
      var spaceId, spaceName;
      spaceName = spacesHelper.generateSpaceName();
      spaceId = (await spacesHelper.createSpaceGraphQL(page, spaceName));
      
      // Verify space exists
      await page.goto('/#!spaces');
      await expect(page.locator(`[data-space-name=\"${spaceName}\"]`)).toBeVisible();
      
      // Delete space via UI
      await spacesHelper.deleteSpace(page, spaceId);
      
      // Verify space is gone
      await page.goto('/#!spaces');
      await expect(page.locator(`[data-space-name=\"${spaceName}\"]`)).not.toBeVisible();
      
      // Verify trying to access deleted space shows error
      await page.goto(`/#!spaces/${spaceId}`);
      return (await expect(page.locator('[data-testid="not-found"]')).toBeVisible());
    });
    test('should handle space deletion via GraphQL', async function({page}) {
      var spaceId, spaceName;
      spaceName = spacesHelper.generateSpaceName();
      spaceId = (await spacesHelper.createSpaceGraphQL(page, spaceName));
      
      // Verify space exists
      await page.goto('/#!spaces');
      await expect(page.locator(`[data-space-name=\"${spaceName}\"]`)).toBeVisible();
      
      // Delete space via GraphQL
      await spacesHelper.deleteSpaceGraphQL(page, spaceId);
      
      // Verify space is gone from UI
      await page.goto('/#!spaces');
      return (await expect(page.locator(`[data-space-name=\"${spaceName}\"]`)).not.toBeVisible());
    });
    test('should handle special characters in space names', async function({page}) {
      var spaceId, specialName;
      // Test space name with special characters
      specialName = spacesHelper.generateSpaceName('test-space_with.special@chars');
      spaceId = (await spacesHelper.createSpaceGraphQL(page, specialName));
      
      // Verify space was created and is accessible
      await page.goto('/#!spaces');
      await expect(page.locator(`[data-space-name=\"${specialName}\"]`)).toBeVisible();
      await page.goto(`/#!spaces/${spaceId}`);
      await expect(page.locator('[data-testid="space-name"]')).toContainText(specialName);
      
      // Clean up
      return (await spacesHelper.deleteSpaceGraphQL(page, spaceId));
    });
    return test('should handle very long space names', async function({page}) {
      var longName, spaceId;
      // Test with long name
      longName = spacesHelper.generateSpaceName('a' * 100); // 100 characters
      spaceId = (await spacesHelper.createSpaceGraphQL(page, longName));
      
      // Verify space was created
      await page.goto('/#!spaces');
      await expect(page.locator(`[data-space-name=\"${longName}\"]`)).toBeVisible();
      
      // Clean up
      return (await spacesHelper.deleteSpaceGraphQL(page, spaceId));
    });
  });

}).call(this);
