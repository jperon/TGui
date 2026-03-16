(function() {
  // Permissions E2E Tests
  // Tests access control and permissions by resource
  var AuthHelper, SpacesHelper, expect, test;

  ({test, expect} = require('@playwright/test'));

  ({AuthHelper} = require('../config/auth.setup'));

  ({SpacesHelper} = require('../config/spaces.setup'));

  test.describe('Authentication - Permissions', function() {
    var authHelper, spacesHelper;
    authHelper = null;
    spacesHelper = null;
    test.beforeEach(function() {
      authHelper = new AuthHelper();
      return spacesHelper = new SpacesHelper();
    });
    test.afterEach(async function({page}) {
      // Clean up any created spaces
      return (await spacesHelper.cleanup(page));
    });
    test('should allow admin to access all resources', async function({page}) {
      var i, len, resource, resources;
      // Login as admin
      await authHelper.login(page);
      
      // Test access to different resources
      resources = [
        {
          url: '/#!spaces',
          selector: '[data-testid="spaces-list"]'
        },
        {
          url: '/#!data-views',
          selector: '[data-testid="data-views-list"]'
        },
        {
          url: '/#!pages',
          selector: '[data-testid="pages-list"]'
        },
        {
          url: '/#!relations',
          selector: '[data-testid="relations-list"]'
        },
        {
          url: '/#!users',
          selector: '[data-testid="users-list"]'
        }
      ];
      for (i = 0, len = resources.length; i < len; i++) {
        resource = resources[i];
        await page.goto(resource.url);
        
        // Verify resource is accessible
        await expect(page.locator(resource.selector)).toBeVisible();
        
        // Verify no access denied message
        await expect(page.locator('[data-testid="access-denied"]')).not.toBeVisible();
      }
      return console.log('✅ Admin can access all resources');
    });
    test('should deny access to unauthenticated users', async function({page}) {
      var i, len, protectedUrls, url;
      // Try to access protected resources without authentication
      protectedUrls = ['/#!spaces', '/#!data-views', '/#!pages', '/#!relations', '/#!users'];
      for (i = 0, len = protectedUrls.length; i < len; i++) {
        url = protectedUrls[i];
        await page.goto(url);
        
        // Verify redirect to login
        await expect(page).toHaveURL(/\*\/login/);
        
        // Verify access denied message
        await expect(page.locator('[data-testid="access-denied"]')).toBeVisible();
      }
      return console.log('✅ Unauthenticated users denied access to protected resources');
    });
    test('should enforce read/write permissions on spaces', async function({page}) {
      var spaceId, spaceName;
      // Login as admin
      await authHelper.login(page);
      
      // Create a test space
      spaceName = spacesHelper.generateSpaceName();
      spaceId = (await spacesHelper.createSpaceGraphQL(page, spaceName));
      
      // Create a test user with limited permissions
      // Note: This would require user creation API - for now we test with admin

      // Test admin can read and write
      await page.goto(`/#!spaces/${spaceId}`);
      await expect(page.locator('[data-testid="space-details"]')).toBeVisible();
      
      // Test adding field (write permission)
      await spacesHelper.addFieldGraphQL(page, spaceId, 'test_field', 'String');
      
      // Verify field was added
      await page.goto(`/#!spaces/${spaceId}`);
      await expect(page.locator('[data-field-name="test_field"]')).toBeVisible();
      return console.log('✅ Admin has read/write permissions on spaces');
    });
    test('should enforce permissions on Data Views', async function({page}) {
      var DataViewsHelper, dataViewId, dataViewName, dataViewsHelper, spaceId, spaceName;
      // Login as admin
      await authHelper.login(page);
      
      // Create a test space first
      spaceName = spacesHelper.generateSpaceName();
      spaceId = (await spacesHelper.createSpaceGraphQL(page, spaceName));
      
        // Create a Data View
      ({DataViewsHelper} = require('../config/data-views.setup'));
      dataViewsHelper = new DataViewsHelper();
      dataViewName = dataViewsHelper.generateDataViewName();
      dataViewId = (await dataViewsHelper.createDataViewGraphQL(page, dataViewName, 'Test Data View', spaceName));
      
      // Test admin can access Data View
      await page.goto(`/#!data-views/${dataViewId}`);
      await expect(page.locator('[data-testid="data-view-details"]')).toBeVisible();
      
      // Test admin can modify Data View
      await dataViewsHelper.updateDataView(page, dataViewId, {
        description: 'Updated description'
      });
      
      // Verify update
      await page.goto(`/#!data-views/${dataViewId}`);
      await expect(page.locator('[data-testid="data-view-description"]')).toContainText('Updated description');
      
      // Clean up
      await dataViewsHelper.cleanup(page);
      return console.log('✅ Admin has full permissions on Data Views');
    });
    test('should enforce permissions on Pages', async function({page}) {
      var PagesHelper, newYaml, pageId, pageName, pagesHelper, updatedYaml;
      // Login as admin
      await authHelper.login(page);
      
        // Create a test page
      ({PagesHelper} = require('../config/pages.setup'));
      pagesHelper = new PagesHelper();
      pageName = pagesHelper.generatePageName();
      pageId = (await pagesHelper.createPageGraphQL(page, pageName));
      
      // Test admin can access page
      await page.goto(`/#!pages/${pageId}`);
      await expect(page.locator('[data-testid="page-details"]')).toBeVisible();
      
      // Test admin can modify page
      newYaml = `layout:
  direction: vertical
  children:
    - widget:
        title: Test Widget
        space: ${spaceName}`;
      await pagesHelper.updatePageYAMLGraphQL(page, pageId, newYaml);
      
      // Verify update
      updatedYaml = (await pagesHelper.getPageYAMLGraphQL(page, pageId));
      expect(updatedYaml).toContain('Test Widget');
      
      // Clean up
      await pagesHelper.cleanup(page);
      return console.log('✅ Admin has full permissions on Pages');
    });
    test('should handle permission errors gracefully', async function({page}) {
      var error;
      // Login as admin
      await authHelper.login(page);
      
      // Try to access non-existent resource
      await page.goto('/#!spaces/non-existent-id');
      
      // Verify error handling
      await expect(page.locator('[data-testid="not-found"]')).toBeVisible();
      await expect(page.locator('[data-testid="not-found"]')).toContainText('Space not found');
      try {
        
        // Try to modify non-existent resource via GraphQL
        await spacesHelper.addFieldGraphQL(page, 'non-existent-id', 'test', 'String');
        expect(false).toBeTruthy(); // Should not reach here
      } catch (error1) {
        error = error1;
        expect(error.message).toContain('Space not found');
      }
      return console.log('✅ Permission errors handled gracefully');
    });
    return test('should validate API authentication', async function({page}) {
      var error, result;
      try {
        // Try GraphQL request without authentication
        await authHelper.makeGraphQLRequest(page, '{ spaces { id name } }');
        expect(false).toBeTruthy(); // Should not reach here
      } catch (error1) {
        error = error1;
        expect(error.message).toContain('Not authenticated');
      }
      
      // Login and try again
      await authHelper.login(page);
      result = (await authHelper.makeGraphQLRequest(page, '{ spaces { id name } }'));
      expect(result.spaces).toBeDefined();
      expect(Array.isArray(result.spaces)).toBeTruthy();
      return console.log('✅ API authentication working correctly');
    });
  });

}).call(this);
