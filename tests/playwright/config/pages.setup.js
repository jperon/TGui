(function() {
  // Pages helper utilities for Playwright tests
  // Provides Page/Custom View creation, widget management, and YAML handling
  var PagesHelper;

  PagesHelper = class PagesHelper {
    constructor() {
      this.createdPages = [];
      this.randomSuffix = Math.floor(Math.random() * 1000000);
    }

    // Generate unique test page name
    generatePageName(baseName = 'test_page') {
      return `${baseName}_${this.randomSuffix}`;
    }

    // Create a new Page via UI
    async createPage({page, name, description = 'Test page created by E2E tests'}) {
      var pageId;
      await page.goto('/#!pages');
      
      // Click "Create Page" button
      await page.click('[data-testid="create-page-button"]');
      
      // Fill page creation form
      await page.fill('input[name="name"]', name);
      await page.fill('textarea[name="description"]', description);
      
      // Submit form
      await page.click('[data-testid="save-page-button"]');
      
      // Wait for success and redirect
      await page.waitForSelector('[data-testid="page-created-success"]');
      
      // Get Page ID from page content
      pageId = (await page.evaluate(function() {
        var ref;
        return (ref = document.querySelector('[data-page-id]')) != null ? ref.getAttribute('data-page-id') : void 0;
      }));
      this.createdPages.push({
        id: pageId,
        name
      });
      console.log(`✅ Created page: ${name} (ID: ${pageId})`);
      return pageId;
    }

    // Create a new Page via GraphQL API
    async createPageGraphQL({page, name, description = 'Test page'}) {
      var AuthHelper, auth, pageId, query, result, variables, yamlContent;
      query = `mutation CreateCustomView($name: String!, $description: String!, $yaml: String!) {
  createCustomView(name: $name, description: $description, yaml: $yaml) {
    id
    name
    description
    yaml
  }
}`;
      
      // Basic YAML structure for new page
      yamlContent = `layout:
  direction: vertical
  children: []`;
      variables = {
        name,
        description,
        yaml: yamlContent
      };
      ({AuthHelper} = require('./auth.setup'));
      auth = new AuthHelper();
      result = (await auth.makeGraphQLRequest(page, query, variables));
      pageId = result.createCustomView.id;
      this.createdPages.push({
        id: pageId,
        name
      });
      console.log(`✅ Created page via GraphQL: ${name} (ID: ${pageId})`);
      return pageId;
    }

    // Add widget to page via UI
    async addWidget({page, pageId, widgetConfig}) {
      var column, i, len, ref;
      await page.goto(`/#!pages/${pageId}`);
      
      // Click "Add Widget" button
      await page.click('[data-testid="add-widget-button"]');
      
      // Fill widget configuration form
      await page.fill('input[name="title"]', widgetConfig.title);
      await page.selectOption('select[name="space"]', widgetConfig.space);
      if (widgetConfig.columns && widgetConfig.columns.length > 0) {
        ref = widgetConfig.columns;
        // Add columns
        for (i = 0, len = ref.length; i < len; i++) {
          column = ref[i];
          await page.click('[data-testid="add-column-button"]');
          await page.selectOption('select[name="column"]', column);
        }
      }
      
      // Submit form
      await page.click('[data-testid="save-widget-button"]');
      
      // Wait for widget to appear in page
      await page.waitForSelector(`[data-widget-title=\"${widgetConfig.title}\"]`);
      return console.log(`✅ Added widget: ${widgetConfig.title} to page ${pageId}`);
    }

    // Add widget to page via GraphQL API
    async addWidgetGraphQL({page, pageId, widgetConfig}) {
      var AuthHelper, auth, query, result, variables;
      query = `mutation AddWidgetToView($viewId: ID!, $widget: WidgetInput!) {
  addWidgetToView(viewId: $viewId, widget: $widget) {
    id
    yaml
  }
}`;
      variables = {
        viewId: pageId,
        widget: widgetConfig
      };
      ({AuthHelper} = require('./auth.setup'));
      auth = new AuthHelper();
      result = (await auth.makeGraphQLRequest(page, query, variables));
      console.log(`✅ Added widget via GraphQL: ${widgetConfig.title} to page ${pageId}`);
      return result.addWidgetToView;
    }

    // Get page YAML content
    async getPageYAML({page, pageId}) {
      var yamlContent;
      await page.goto(`/#!pages/${pageId}`);
      
      // Click "Edit YAML" button
      await page.click('[data-testid="edit-yaml-button"]');
      
      // Get YAML content from editor
      yamlContent = (await page.inputValue('[data-testid="yaml-editor"]'));
      console.log(`📄 Retrieved YAML for page ${pageId}`);
      return yamlContent;
    }

    // Get page YAML via GraphQL API
    async getPageYAMLGraphQL({page, pageId}) {
      var AuthHelper, auth, query, result, variables;
      query = `query GetCustomView($id: ID!) {
  customView(id: $id) {
    id
    name
    yaml
  }
}`;
      variables = {
        id: pageId
      };
      ({AuthHelper} = require('./auth.setup'));
      auth = new AuthHelper();
      result = (await auth.makeGraphQLRequest(page, query, variables));
      console.log(`📄 Retrieved YAML via GraphQL for page ${pageId}`);
      return result.customView.yaml;
    }

    // Update page YAML content
    async updatePageYAML({page, pageId, yamlContent}) {
      await page.goto(`/#!pages/${pageId}`);
      
      // Click "Edit YAML" button
      await page.click('[data-testid="edit-yaml-button"]');
      
      // Update YAML content
      await page.fill('[data-testid="yaml-editor"]', yamlContent);
      
      // Save changes
      await page.click('[data-testid="save-yaml-button"]');
      
      // Wait for success message
      await page.waitForSelector('[data-testid="yaml-saved-success"]');
      return console.log(`✅ Updated YAML for page ${pageId}`);
    }

    // Update page YAML via GraphQL API
    async updatePageYAMLGraphQL({page, pageId, yamlContent}) {
      var AuthHelper, auth, query, result, variables;
      query = `mutation UpdateCustomView($id: ID!, $input: UpdateCustomViewInput!) {
  updateCustomView(id: $id, input: $input) {
    id
    name
    yaml
  }
}`;
      variables = {
        id: pageId,
        input: {
          yaml: yamlContent
        }
      };
      ({AuthHelper} = require('./auth.setup'));
      auth = new AuthHelper();
      result = (await auth.makeGraphQLRequest(page, query, variables));
      console.log(`✅ Updated YAML via GraphQL for page ${pageId}`);
      return result.updateCustomView;
    }

    // Reorder widgets in page
    async reorderWidgets({page, pageId, widgetPositions}) {
      var AuthHelper, auth, query, result, variables;
      query = `mutation ReorderWidgets($pageId: ID!, $widgetPositions: [WidgetPosition!]!) {
  reorderWidgets(pageId: $pageId, widgetPositions: $widgetPositions) {
    id
    yaml
  }
}`;
      variables = {pageId, widgetPositions};
      ({AuthHelper} = require('./auth.setup'));
      auth = new AuthHelper();
      result = (await auth.makeGraphQLRequest(page, query, variables));
      console.log(`✅ Reordered widgets in page ${pageId}`);
      return result.reorderWidgets;
    }

    // Get widget positions from page DOM
    async getWidgetPositions({page, pageId}) {
      var positions;
      await page.goto(`/#!pages/${pageId}`);
      positions = (await page.evaluate(function() {
        var widgets;
        widgets = document.querySelectorAll('[data-widget-id]');
        return Array.from(widgets).map(function(widget, index) {
          return {
            widgetId: widget.getAttribute('data-widget-id'),
            index: index + 1
          };
        });
      }));
      console.log(`📍 Retrieved ${positions.length} widget positions from page ${pageId}`);
      return positions;
    }

    // Verify widget exists in page
    async verifyWidgetExists({page, pageId, widgetTitle}) {
      var error;
      await page.goto(`/#!pages/${pageId}`);
      try {
        await page.waitForSelector(`[data-widget-title=\"${widgetTitle}\"]`, {
          timeout: 5000
        });
        console.log(`✅ Verified widget exists: ${widgetTitle}`);
        return true;
      } catch (error1) {
        error = error1;
        console.log(`❌ Widget not found: ${widgetTitle}`);
        return false;
      }
    }

    // Verify YAML structure is valid
    verifyYAMLStructure({yamlContent}) {
      var error, hasChildren, hasDirection, hasLayout, isValid, lines;
      try {
        // Basic YAML structure validation
        lines = yamlContent.split('\n');
        hasLayout = lines.some(function(line) {
          return line.trim().startsWith('layout:');
        });
        hasDirection = lines.some(function(line) {
          return line.trim().startsWith('direction:');
        });
        hasChildren = lines.some(function(line) {
          return line.trim().startsWith('children:');
        });
        isValid = hasLayout && hasDirection && hasChildren;
        console.log(`🔍 YAML structure validation: ${isValid ? '✅ Valid' : '❌ Invalid'}`);
        return isValid;
      } catch (error1) {
        error = error1;
        console.log("❌ YAML validation error:", error.message);
        return false;
      }
    }

    // Delete page
    async deletePage({page, pageId}) {
      await page.goto(`/#!pages/${pageId}`);
      
      // Click delete button
      await page.click('[data-testid="delete-page-button"]');
      
      // Confirm deletion in modal
      await page.click('[data-testid="confirm-delete-button"]');
      
      // Wait for success message
      await page.waitForSelector('[data-testid="page-deleted-success"]');
      
      // Remove from created pages tracking
      this.createdPages = this.createdPages.filter(function(p) {
        return p.id !== pageId;
      });
      return console.log(`✅ Deleted page: ${pageId}`);
    }

    // Delete page via GraphQL API
    async deletePageGraphQL({page, pageId}) {
      var AuthHelper, auth, query, variables;
      query = `mutation DeleteCustomView($id: ID!) {
  deleteCustomView(id: $id)
}`;
      variables = {
        id: pageId
      };
      ({AuthHelper} = require('./auth.setup'));
      auth = new AuthHelper();
      await auth.makeGraphQLRequest(page, query, variables);
      
      // Remove from created pages tracking
      this.createdPages = this.createdPages.filter(function(p) {
        return p.id !== pageId;
      });
      return console.log(`✅ Deleted page via GraphQL: ${pageId}`);
    }

    // Clean up all created pages
    async cleanup({page}) {
      var error, i, len, pageData, ref;
      console.log(`🧹 Cleaning up ${this.createdPages.length} test pages...`);
      ref = this.createdPages;
      for (i = 0, len = ref.length; i < len; i++) {
        pageData = ref[i];
        try {
          await this.deletePageGraphQL(page, pageData.id);
        } catch (error1) {
          error = error1;
          console.warn(`⚠️ Failed to delete page ${pageData.name}: ${error.message}`);
        }
      }
      this.createdPages = [];
      return console.log("✅ All test pages cleaned up");
    }

  };

  module.exports = {PagesHelper};

}).call(this);
