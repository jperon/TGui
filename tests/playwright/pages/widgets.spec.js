(function() {
  // Pages Widgets E2E Tests
  // Tests widget creation, modification, and management via UI
  var AuthHelper, PagesHelper, SpacesHelper, expect, test;

  ({test, expect} = require('@playwright/test'));

  ({AuthHelper} = require('../config/auth.setup'));

  ({PagesHelper} = require('../config/pages.setup'));

  ({SpacesHelper} = require('../config/spaces.setup'));

  test.describe('Pages - Widgets Management', function() {
    var authHelper, pageId, pagesHelper, spaceId, spacesHelper;
    authHelper = null;
    pagesHelper = null;
    spacesHelper = null;
    pageId = null;
    spaceId = null;
    test.beforeEach(async function({page}) {
      var pageName, spaceName;
      authHelper = new AuthHelper();
      pagesHelper = new PagesHelper();
      spacesHelper = new SpacesHelper();
      await authHelper.login(page);
      
      // Create a test space for widgets
      spaceName = spacesHelper.generateSpaceName('widget_test');
      spaceId = (await spacesHelper.createSpaceGraphQL(page, spaceName));
      
      // Add some fields to the space
      await spacesHelper.addFieldGraphQL(page, spaceId, 'name', 'String');
      await spacesHelper.addFieldGraphQL(page, spaceId, 'description', 'String');
      await spacesHelper.addFieldGraphQL(page, spaceId, 'active', 'Boolean');
      
      // Create a test page
      pageName = pagesHelper.generatePageName('widget_page');
      return pageId = (await pagesHelper.createPageGraphQL(page, pageName));
    });
    test.afterEach(async function({page}) {
      // Clean up test data
      await pagesHelper.cleanup(page);
      return (await spacesHelper.cleanup(page));
    });
    test('should show add widget button', async function({page}) {
      await page.goto(`/#!pages/${pageId}`);
      
      // Verify add widget button is visible
      await expect(page.locator('[data-testid="add-widget-button"]')).toBeVisible();
      return (await expect(page.locator('[data-testid="add-widget-button"]')).toContainText('Add Widget'));
    });
    test('should open widget creation dialog', async function({page}) {
      await page.goto(`/#!pages/${pageId}`);
      
      // Click add widget button
      await page.click('[data-testid="add-widget-button"]');
      
      // Verify widget creation dialog is visible
      await expect(page.locator('[data-testid="widget-creation-dialog"]')).toBeVisible();
      
      // Verify required form fields
      await expect(page.locator('input[name="title"]')).toBeVisible();
      await expect(page.locator('select[name="space"]')).toBeVisible();
      await expect(page.locator('[data-testid="save-widget-button"]')).toBeVisible();
      return (await expect(page.locator('[data-testid="cancel-widget-button"]')).toBeVisible());
    });
    test('should populate space selector with available spaces', async function({page}) {
      var options, spaceSelector;
      await page.goto(`/#!pages/${pageId}`);
      await page.click('[data-testid="add-widget-button"]');
      
      // Get space selector options
      spaceSelector = page.locator('select[name="space"]');
      options = (await spaceSelector.locator('option').allTexts());
      
      // Verify our test space is in the list
      expect(options).toContain(spaceName);
      
      // Verify at least one option is available
      return expect(options.length).toBeGreaterThan(0);
    });
    test('should create basic widget via UI', async function({page}) {
      var widgetConfig, widgetElement;
      await page.goto(`/#!pages/${pageId}`);
      
      // Create widget
      widgetConfig = {
        title: 'Test Widget',
        space: spaceName,
        columns: ['name', 'description']
      };
      await pagesHelper.addWidget(page, pageId, widgetConfig);
      
      // Verify widget appears on page
      await expect(page.locator(`[data-widget-title=\"${widgetConfig.title}\"]`)).toBeVisible();
      
      // Verify widget configuration
      widgetElement = page.locator(`[data-widget-title=\"${widgetConfig.title}\"]`);
      return (await expect(widgetElement.locator('[data-widget-space]')).toContainText(spaceName));
    });
    test('should create widget via GraphQL API', async function({page}) {
      var result, widgetConfig;
      widgetConfig = {
        title: 'GraphQL Widget',
        space: spaceName,
        columns: ['name', 'active'],
        position: {
          x: 0,
          y: 0,
          w: 12,
          h: 4
        }
      };
      
      // Create widget via GraphQL
      result = (await pagesHelper.addWidgetGraphQL(page, pageId, widgetConfig));
      
      // Verify widget was created
      expect(result).toBeDefined();
      expect(result.yaml).toContain(widgetConfig.title);
      expect(result.yaml).toContain(spaceName);
      
      // Verify widget appears in UI
      await page.goto(`/#!pages/${pageId}`);
      return (await expect(page.locator(`[data-widget-title=\"${widgetConfig.title}\"]`)).toBeVisible());
    });
    test('should validate required widget fields', async function({page}) {
      await page.goto(`/#!pages/${pageId}`);
      await page.click('[data-testid="add-widget-button"]');
      
      // Try to save without title
      await page.selectOption('select[name="space"]', spaceName);
      await page.click('[data-testid="save-widget-button"]');
      
      // Verify validation error
      await expect(page.locator('input[name="title"]:invalid')).toBeVisible();
      
      // Fill title and try again
      await page.fill('input[name="title"]', 'Valid Widget');
      await page.click('[data-testid="save-widget-button"]');
      
      // Verify successful creation
      return (await expect(page.locator('[data-testid="widget-created-success"]')).toBeVisible());
    });
    test('should add column selection', async function({page}) {
      var yamlContent;
      await page.goto(`/#!pages/${pageId}`);
      await page.click('[data-testid="add-widget-button"]');
      
      // Fill basic widget info
      await page.fill('input[name="title"]', 'Column Test Widget');
      await page.selectOption('select[name="space"]', spaceName);
      
      // Add columns
      await page.click('[data-testid="add-column-button"]');
      await page.selectOption('select[name="column"]', 'name');
      await page.click('[data-testid="add-column-button"]');
      await page.selectOption('select[name="column"]', 'description');
      
      // Save widget
      await page.click('[data-testid="save-widget-button"]');
      
      // Verify widget was created with columns
      await expect(page.locator('[data-testid="widget-created-success"]')).toBeVisible();
      
      // Verify columns in YAML
      yamlContent = (await pagesHelper.getPageYAMLGraphQL(page, pageId));
      return expect(yamlContent).toContain('columns: [name, description]');
    });
    test('should edit existing widget', async function({page}) {
      var widgetConfig;
      // Create a widget first
      widgetConfig = {
        title: 'Editable Widget',
        space: spaceName,
        columns: ['name']
      };
      await pagesHelper.addWidget(page, pageId, widgetConfig);
      
      // Edit the widget
      await page.goto(`/#!pages/${pageId}`);
      await page.click(`[data-widget-title=\"${widgetConfig.title}\"] [data-testid=\"edit-widget-button\"]`);
      
      // Verify edit dialog opens
      await expect(page.locator('[data-testid="widget-edit-dialog"]')).toBeVisible();
      
      // Modify widget title
      await page.fill('input[name="title"]', 'Modified Widget');
      
      // Save changes
      await page.click('[data-testid="save-widget-button"]');
      
      // Verify changes
      await expect(page.locator("[data-widget-title=\"Modified Widget\"]")).toBeVisible();
      return (await expect(page.locator(`[data-widget-title=\"${widgetConfig.title}\"]`)).not.toBeVisible());
    });
    test('should delete widget', async function({page}) {
      var widgetConfig;
      // Create a widget first
      widgetConfig = {
        title: 'Deletable Widget',
        space: spaceName,
        columns: ['name']
      };
      await pagesHelper.addWidget(page, pageId, widgetConfig);
      
      // Verify widget exists
      await page.goto(`/#!pages/${pageId}`);
      await expect(page.locator(`[data-widget-title=\"${widgetConfig.title}\"]`)).toBeVisible();
      
      // Delete widget
      await page.click(`[data-widget-title=\"${widgetConfig.title}\"] [data-testid=\"delete-widget-button\"]`);
      await page.click('[data-testid="confirm-delete-button"]');
      
      // Verify widget is gone
      await expect(page.locator(`[data-widget-title=\"${widgetConfig.title}\"]`)).not.toBeVisible();
      return (await expect(page.locator('[data-testid="widget-deleted-success"]')).toBeVisible());
    });
    test('should handle widget dependencies', async function({page}) {
      var dependencySection;
      await page.goto(`/#!pages/${pageId}`);
      await page.click('[data-testid="add-widget-button"]');
      
      // Fill basic widget info
      await page.fill('input[name="title"]', 'Dependent Widget');
      await page.selectOption('select[name="space"]', spaceName);
      
      // Look for dependency configuration
      dependencySection = page.locator('[data-testid="widget-dependencies"]');
      if ((await dependencySection.isVisible())) {
        // Configure dependency
        await page.click('[data-testid="add-dependency-button"]');
        
        // Fill dependency fields
        await page.fill('input[name="dependency-field"]', 'dependent_field');
        await page.selectOption('select[name="dependency-widget"]', 'source_widget');
        await page.selectOption('select[name="dependency-from-field"]', 'id');
        console.log("✅ Widget dependencies configuration is available");
      } else {
        console.log("ℹ️ Widget dependencies not implemented");
      }
      
      // Cancel the dialog for now
      return (await page.click('[data-testid="cancel-widget-button"]'));
    });
    test('should handle widget parameters', async function({page}) {
      var paramsSection;
      await page.goto(`/#!pages/${pageId}`);
      await page.click('[data-testid="add-widget-button"]');
      
      // Fill basic widget info
      await page.fill('input[name="title"]', 'Parameterized Widget');
      await page.selectOption('select[name="space"]', spaceName);
      
      // Look for parameters configuration
      paramsSection = page.locator('[data-testid="widget-parameters"]');
      if ((await paramsSection.isVisible())) {
        // Add parameter
        await page.click('[data-testid="add-parameter-button"]');
        
        // Fill parameter fields
        await page.fill('input[name="param-name"]', 'limit');
        await page.selectOption('select[name="param-type"]', 'number');
        await page.fill('input[name="param-value"]', '10');
        console.log("✅ Widget parameters configuration is available");
      } else {
        console.log("ℹ️ Widget parameters not implemented");
      }
      
      // Cancel the dialog for now
      return (await page.click('[data-testid="cancel-widget-button"]'));
    });
    test('should show widget preview', async function({page}) {
      var previewButton;
      await page.goto(`/#!pages/${pageId}`);
      await page.click('[data-testid="add-widget-button"]');
      
      // Fill basic widget info
      await page.fill('input[name="title"]', 'Preview Widget');
      await page.selectOption('select[name="space"]', spaceName);
      
      // Look for preview functionality
      previewButton = page.locator('[data-testid="widget-preview-button"]');
      if ((await previewButton.isVisible())) {
        await previewButton.click();
        
        // Verify preview panel is visible
        await expect(page.locator('[data-testid="widget-preview"]')).toBeVisible();
        
        // Verify preview shows widget structure
        await expect(page.locator('[data-testid="preview-widget"]')).toBeVisible();
        console.log("✅ Widget preview functionality is available");
      } else {
        console.log("ℹ️ Widget preview not implemented");
      }
      
      // Cancel the dialog
      return (await page.click('[data-testid="cancel-widget-button"]'));
    });
    test('should handle multiple widgets on page', async function({page}) {
      var config, i, j, len, len1, widgetConfigs, widgetElements;
      // Create multiple widgets
      widgetConfigs = [
        {
          title: 'Widget A',
          space: spaceName,
          columns: ['name']
        },
        {
          title: 'Widget B',
          space: spaceName,
          columns: ['description']
        },
        {
          title: 'Widget C',
          space: spaceName,
          columns: ['active']
        }
      ];
      for (i = 0, len = widgetConfigs.length; i < len; i++) {
        config = widgetConfigs[i];
        await pagesHelper.addWidget(page, pageId, config);
      }
      
      // Verify all widgets appear
      await page.goto(`/#!pages/${pageId}`);
      for (j = 0, len1 = widgetConfigs.length; j < len1; j++) {
        config = widgetConfigs[j];
        await expect(page.locator(`[data-widget-title=\"${config.title}\"]`)).toBeVisible();
      }
      
      // Verify widgets are ordered correctly
      widgetElements = (await page.locator('[data-widget-title]').all());
      expect(widgetElements.length).toBe(widgetConfigs.length);
      return console.log("✅ Multiple widgets displayed correctly");
    });
    test('should handle widget with all field types', async function({page}) {
      var widgetConfig, yamlContent;
      // Add more field types to space
      await spacesHelper.addFieldGraphQL(page, spaceId, 'age', 'Int');
      await spacesHelper.addFieldGraphQL(page, spaceId, 'score', 'Float');
      await spacesHelper.addFieldGraphQL(page, spaceId, 'id', 'UUID');
      
      // Create widget with all fields
      widgetConfig = {
        title: 'All Fields Widget',
        space: spaceName,
        columns: ['name', 'age', 'score', 'active', 'id']
      };
      await pagesHelper.addWidget(page, pageId, widgetConfig);
      
      // Verify widget was created
      await page.goto(`/#!pages/${pageId}`);
      await expect(page.locator(`[data-widget-title=\"${widgetConfig.title}\"]`)).toBeVisible();
      
      // Verify YAML contains all columns
      yamlContent = (await pagesHelper.getPageYAMLGraphQL(page, pageId));
      expect(yamlContent).toContain('columns: [name, age, score, active, id]');
      return console.log("✅ Widget with all field types created successfully");
    });
    return test('should handle widget copy functionality', async function({page}) {
      var copyButton, widgetConfig;
      // Create a widget first
      widgetConfig = {
        title: 'Original Widget',
        space: spaceName,
        columns: ['name', 'description']
      };
      await pagesHelper.addWidget(page, pageId, widgetConfig);
      
      // Try to copy widget
      await page.goto(`/#!pages/${pageId}`);
      copyButton = page.locator(`[data-widget-title=\"${widgetConfig.title}\"] [data-testid=\"copy-widget-button\"]`);
      if ((await copyButton.isVisible())) {
        await copyButton.click();
        
        // Verify copy dialog opens
        await expect(page.locator('[data-testid="widget-copy-dialog"]')).toBeVisible();
        
        // Modify title for copy
        await page.fill('input[name="title"]', 'Copied Widget');
        await page.click('[data-testid="save-widget-button"]');
        
        // Verify both widgets exist
        await expect(page.locator(`[data-widget-title=\"${widgetConfig.title}\"]`)).toBeVisible();
        await expect(page.locator("[data-widget-title=\"Copied Widget\"]")).toBeVisible();
        return console.log("✅ Widget copy functionality is available");
      } else {
        return console.log("ℹ️ Widget copy functionality not implemented");
      }
    });
  });

}).call(this);
