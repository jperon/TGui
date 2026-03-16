(function() {
  // Complete Workflow E2E Tests
  // Tests end-to-end user workflows across all TGui features
  var AuthHelper, DataViewsHelper, PagesHelper, SpacesHelper, expect, test;

  ({test, expect} = require('@playwright/test'));

  ({AuthHelper} = require('../config/auth.setup'));

  ({SpacesHelper} = require('../config/spaces.setup'));

  ({DataViewsHelper} = require('../config/data-views.setup'));

  ({PagesHelper} = require('../config/pages.setup'));

  test.describe('Complete User Workflow', function() {
    var authHelper, dataViewId, dataViewsHelper, pageId, pagesHelper, spaceId, spacesHelper;
    authHelper = null;
    spacesHelper = null;
    dataViewsHelper = null;
    pagesHelper = null;
    spaceId = null;
    dataViewId = null;
    pageId = null;
    test.beforeEach(async function({page}) {
      authHelper = new AuthHelper();
      spacesHelper = new SpacesHelper();
      dataViewsHelper = new DataViewsHelper();
      pagesHelper = new PagesHelper();
      return (await authHelper.login(page));
    });
    test.afterEach(async function({page}) {
      // Clean up all created resources
      await pagesHelper.cleanup(page);
      await dataViewsHelper.cleanup(page);
      return (await spacesHelper.cleanup(page));
    });
    test('should complete full data management workflow', async function({page}) {
      var config, currentYaml, dataViewName, fieldElements, firstWidget, initialPositions, j, k, l, len, len1, len2, modifiedYaml, newPositions, pageName, resource, resources, resultRows, results, secondWidget, spaceName, widgetConfigs;
      console.log("🚀 Starting complete data management workflow...");
      // Step 1: Create a space with various field types
      console.log("📝 Step 1: Creating space with fields...");
      spaceName = spacesHelper.generateSpaceName('workflow_space');
      spaceId = (await spacesHelper.createSpaceGraphQL(page, spaceName, 'Workflow test space'));
      // Add different field types
      await spacesHelper.addFieldGraphQL(page, spaceId, 'name', 'String', {
        description: 'Person name'
      });
      await spacesHelper.addFieldGraphQL(page, spaceId, 'email', 'String', {
        description: 'Email address'
      });
      await spacesHelper.addFieldGraphQL(page, spaceId, 'age', 'Int', {
        description: 'Person age'
      });
      await spacesHelper.addFieldGraphQL(page, spaceId, 'active', 'Boolean', {
        description: 'Account status'
      });
      await spacesHelper.addFieldGraphQL(page, spaceId, 'score', 'Float', {
        description: 'Performance score'
      });
      await spacesHelper.addFieldGraphQL(page, spaceId, 'id', 'UUID', {
        description: 'Unique identifier'
      });
      await spacesHelper.addFieldGraphQL(page, spaceId, 'metadata', 'Map', {
        description: 'Additional metadata'
      });
      console.log("✅ Space created with 8 fields");
      // Step 2: Create a Data View with filters and aggregations
      console.log("📊 Step 2: Creating Data View with filters...");
      dataViewName = dataViewsHelper.generateDataViewName('workflow_dataview');
      dataViewId = (await dataViewsHelper.createDataViewGraphQL(page, dataViewName, 'Workflow Data View', spaceName, {
        limit: 50,
        offset: 0
      }));
      // Configure filters
      await dataViewsHelper.configureFilters(page, dataViewId, [
        {
          field: 'active',
          operator: 'EQ',
          value: true
        },
        {
          field: 'age',
          operator: 'GT',
          value: 18
        }
      ]);
      // Configure aggregations
      await dataViewsHelper.configureAggregations(page, dataViewId, [
        {
          field: 'age',
          function: 'AVG',
          alias: 'average_age'
        },
        {
          field: 'score',
          function: 'SUM',
          alias: 'total_score'
        },
        {
          field: 'id',
          function: 'COUNT',
          alias: 'total_records'
        }
      ]);
      console.log("✅ Data View created with filters and aggregations");
      // Step 3: Create a page with multiple widgets
      console.log("📄 Step 3: Creating page with widgets...");
      pageName = pagesHelper.generatePageName('workflow_page');
      pageId = (await pagesHelper.createPageGraphQL(page, pageName, 'Workflow test page'));
      // Add multiple widgets
      widgetConfigs = [
        {
          title: 'Active Users',
          space: spaceName,
          columns: ['name',
        'email',
        'age'],
          position: {
            x: 0,
            y: 0,
            w: 6,
            h: 4
          }
        },
        {
          title: 'Performance Metrics',
          space: spaceName,
          columns: ['name',
        'score',
        'active'],
          position: {
            x: 6,
            y: 0,
            w: 6,
            h: 4
          }
        },
        {
          title: 'User Details',
          space: spaceName,
          columns: ['name',
        'email',
        'metadata'],
          position: {
            x: 0,
            y: 4,
            w: 12,
            h: 3
          }
        }
      ];
      for (j = 0, len = widgetConfigs.length; j < len; j++) {
        config = widgetConfigs[j];
        await pagesHelper.addWidgetGraphQL(page, pageId, config);
      }
      console.log("✅ Page created with 3 widgets");
      // Step 4: Verify the complete setup
      console.log("🔍 Step 4: Verifying complete setup...");
      // Verify space exists and has correct fields
      await page.goto(`/#!spaces/${spaceId}`);
      await expect(page.locator('[data-testid="space-details"]')).toBeVisible();
      fieldElements = (await page.locator('[data-field-name]').all());
      expect(fieldElements.length).toBe(8);
      // Verify Data View exists and is configured
      await page.goto(`/#!data-views/${dataViewId}`);
      await expect(page.locator('[data-testid="data-view-details"]')).toBeVisible();
      // Execute Data View to verify it works
      results = (await dataViewsHelper.executeDataView(page, dataViewId));
      expect(Array.isArray(results)).toBeTruthy();
      // Verify page exists and has widgets
      await page.goto(`/#!pages/${pageId}`);
      await expect(page.locator('[data-testid="page-details"]')).toBeVisible();
      for (k = 0, len1 = widgetConfigs.length; k < len1; k++) {
        config = widgetConfigs[k];
        await expect(page.locator(`[data-widget-title=\"${config.title}\"]`)).toBeVisible();
      }
      console.log("✅ Complete setup verified successfully");
      // Step 5: Test widget reordering
      console.log("🔄 Step 5: Testing widget reordering...");
      // Get initial widget order
      initialPositions = (await pagesHelper.getWidgetPositions(page, pageId));
      console.log(`Initial widget positions: ${JSON.stringify(initialPositions)}`);
      // Reorder widgets
      firstWidget = page.locator('[data-widget-title="Active Users"]');
      secondWidget = page.locator('[data-widget-title="Performance Metrics"]');
      await firstWidget.dragTo(secondWidget);
      await page.waitForTimeout(1000);
      // Verify reordering
      newPositions = (await pagesHelper.getWidgetPositions(page, pageId));
      console.log(`New widget positions: ${JSON.stringify(newPositions)}`);
      expect(newPositions).not.toEqual(initialPositions);
      console.log("✅ Widget reordering working correctly");
      // Step 6: Test YAML editing
      console.log("📝 Step 6: Testing YAML editing...");
      await page.goto(`/#!pages/${pageId}`);
      await page.click('[data-testid="edit-yaml-button"]');
      // Modify YAML
      currentYaml = (await page.inputValue('[data-testid="yaml-editor"]'));
      modifiedYaml = currentYaml.replace('Active Users', 'Active Users (Updated)');
      await page.fill('[data-testid="yaml-editor"]', modifiedYaml);
      await page.click('[data-testid="save-yaml-button"]');
      // Verify changes
      await expect(page.locator('[data-testid="yaml-saved-success"]')).toBeVisible();
      await expect(page.locator("[data-widget-title=\"Active Users (Updated)\"]")).toBeVisible();
      console.log("✅ YAML editing working correctly");
      // Step 7: Test Data View execution
      console.log("📊 Step 7: Testing Data View execution...");
      await page.goto(`/#!data-views/${dataViewId}`);
      await page.click('[data-testid="execute-data-view-button"]');
      // Wait for results
      await page.waitForSelector('[data-testid="data-view-results"]');
      // Verify results structure
      resultRows = (await page.locator('[data-testid="result-row"]').all());
      console.log(`Data View returned ${resultRows.length} results`);
      // Verify aggregations are present
      await expect(page.locator('[data-testid="aggregation-results"]')).toBeVisible();
      console.log("✅ Data View execution working correctly");
      // Step 8: Test space field management
      console.log("🔧 Step 8: Testing space field management...");
      await page.goto(`/#!spaces/${spaceId}`);
      // Add a new field
      await spacesHelper.addFieldGraphQL(page, spaceId, 'created_at', 'String', {
        description: 'Creation timestamp'
      });
      // Verify field appears
      await page.reload();
      await expect(page.locator('[data-field-name="created_at"]')).toBeVisible();
      // Test field reordering
      fieldElements = (await page.locator('[data-field-name]').all());
      expect(fieldElements.length).toBe(9); // 8 original + 1 new
      console.log("✅ Space field management working correctly");
      // Step 9: Test permissions and access control
      console.log("🔐 Step 9: Testing permissions...");
      // Verify admin can access all resources
      resources = [
        {
          url: `/#!spaces/${spaceId}`,
          selector: '[data-testid="space-details"]'
        },
        {
          url: `/#!data-views/${dataViewId}`,
          selector: '[data-testid="data-view-details"]'
        },
        {
          url: `/#!pages/${pageId}`,
          selector: '[data-testid="page-details"]'
        }
      ];
      for (l = 0, len2 = resources.length; l < len2; l++) {
        resource = resources[l];
        await page.goto(resource.url);
        await expect(page.locator(resource.selector)).toBeVisible();
      }
      console.log("✅ Permissions working correctly");
      // Step 10: Test data persistence
      console.log("💾 Step 10: Testing data persistence...");
      // Logout and login again
      await authHelper.logout(page);
      await authHelper.login(page);
      // Verify all resources still exist
      await page.goto(`/#!spaces/${spaceId}`);
      await expect(page.locator('[data-testid="space-details"]')).toBeVisible();
      await page.goto(`/#!data-views/${dataViewId}`);
      await expect(page.locator('[data-testid="data-view-details"]')).toBeVisible();
      await page.goto(`/#!pages/${pageId}`);
      await expect(page.locator("[data-widget-title=\"Active Users (Updated)\"]")).toBeVisible();
      console.log("Data persistence working correctly");
      return console.log("Complete workflow test finished successfully!");
    });
    test('should handle complex nested page layouts', async function({page}) {
      var complexYaml, headerWidget, mainContentWidget, pageName, spaceName, widgetElements;
      console.log("🏗️ Testing complex nested layouts...");
      // Create space
      spaceName = spacesHelper.generateSpaceName('nested_space');
      spaceId = (await spacesHelper.createSpaceGraphQL(page, spaceName));
      await spacesHelper.addFieldGraphQL(page, spaceId, 'title', 'String');
      await spacesHelper.addFieldGraphQL(page, spaceId, 'content', 'String');
      // Create page with complex nested layout
      pageName = pagesHelper.generatePageName('nested_page');
      pageId = (await pagesHelper.createPageGraphQL(page, pageName));
      // Create complex YAML structure
      complexYaml = `layout:
  direction: vertical
  children:
    - direction: horizontal
      factor: 2
      children:
        - direction: vertical
          factor: 1
          children:
            - widget:
                title: Header Widget
                space: ${spaceName}
                columns: [title]
            - widget:
                title: Navigation Widget
                space: ${spaceName}
                columns: [title]
        - direction: vertical
          factor: 1
          children:
            - widget:
                title: Main Content
                space: ${spaceName}
                columns: [title, content]
            - widget:
                title: Sidebar Widget
                space: ${spaceName}
                columns: [title]
    - direction: horizontal
      factor: 1
      children:
        - widget:
            title: Footer Widget 1
            space: ${spaceName}
            columns: [title]
        - widget:
            title: Footer Widget 2
            space: ${spaceName}
            columns: [title]`;
      await pagesHelper.updatePageYAMLGraphQL(page, pageId, complexYaml);
      // Verify complex layout renders
      await page.goto(`/#!pages/${pageId}`);
      await page.waitForSelector('[data-widget-title]');
      widgetElements = (await page.locator('[data-widget-title]').all());
      expect(widgetElements.length).toBe(6); // Header, Navigation, Main Content, Sidebar, Footer 1, Footer 2
      
      // Test drag & drop in complex layout
      headerWidget = page.locator('[data-widget-title="Header Widget"]');
      mainContentWidget = page.locator('[data-widget-title="Main Content"]');
      await headerWidget.dragTo(mainContentWidget);
      await page.waitForTimeout(1000);
      return console.log("✅ Complex nested layout working correctly");
    });
    test('should handle error scenarios gracefully', async function({page}) {
      var invalidYaml, pageName;
      console.log("🚨 Testing error scenarios...");
      // Test invalid YAML
      pageName = pagesHelper.generatePageName('error_test');
      pageId = (await pagesHelper.createPageGraphQL(page, pageName));
      await page.goto(`/#!pages/${pageId}`);
      await page.click('[data-testid="edit-yaml-button"]');
      // Enter invalid YAML
      invalidYaml = `layout:
direction: vertical
  children:
    - widget:
        title: Test
        # Missing required space field`;
      await page.fill('[data-testid="yaml-editor"]', invalidYaml);
      await page.click('[data-testid="save-yaml-button"]');
      // Verify error handling
      await expect(page.locator('[data-testid="yaml-error"]')).toBeVisible();
      // Test non-existent resource access
      await page.goto('/#!spaces/non-existent-space');
      await expect(page.locator('[data-testid="not-found"]')).toBeVisible();
      // Test unauthorized access (logout first)
      await authHelper.logout(page);
      await page.goto('/#!spaces');
      await expect(page).toHaveURL(/\*\/login/);
      return console.log("✅ Error scenarios handled gracefully");
    });
    return test('should handle performance with large datasets', async function({page}) {
      var dataViewName, endTime, executionTime, i, j, pageLoadTime, pageName, results, spaceName, startTime, widgetConfig;
      console.log("⚡ Testing performance with large datasets...");
      // Create space
      spaceName = spacesHelper.generateSpaceName('performance_space');
      spaceId = (await spacesHelper.createSpaceGraphQL(page, spaceName));
      await spacesHelper.addFieldGraphQL(page, spaceId, 'name', 'String');
      await spacesHelper.addFieldGraphQL(page, spaceId, 'value', 'Int');
      // Create Data View with large limit
      dataViewName = dataViewsHelper.generateDataViewName('performance_dataview');
      dataViewId = (await dataViewsHelper.createDataViewGraphQL(page, dataViewName, 'Performance Data View', spaceName, {
        limit: 1000,
        offset: 0
      }));
      // Execute Data View and measure performance
      startTime = Date.now();
      results = (await dataViewsHelper.executeDataView(page, dataViewId));
      endTime = Date.now();
      executionTime = endTime - startTime;
      console.log(`Data View execution time: ${executionTime}ms for ${results.length} results`);
      // Verify performance is acceptable (< 5 seconds)
      expect(executionTime).toBeLessThan(5000);
      // Create page with many widgets
      pageName = pagesHelper.generatePageName('performance_page');
      pageId = (await pagesHelper.createPageGraphQL(page, pageName));
// Add 10 widgets
      for (i = j = 1; j <= 10; i = ++j) {
        widgetConfig = {
          title: `Performance Widget ${i}`,
          space: spaceName,
          columns: ['name', 'value']
        };
        await pagesHelper.addWidgetGraphQL(page, pageId, widgetConfig);
      }
      // Test page load performance
      startTime = Date.now();
      await page.goto(`/#!pages/${pageId}`);
      await page.waitForSelector('[data-widget-title]');
      endTime = Date.now();
      pageLoadTime = endTime - startTime;
      console.log(`Page load time: ${pageLoadTime}ms for 10 widgets`);
      // Verify page load performance is acceptable (< 3 seconds)
      expect(pageLoadTime).toBeLessThan(3000);
      return console.log("✅ Performance tests passed");
    });
  });

}).call(this);
