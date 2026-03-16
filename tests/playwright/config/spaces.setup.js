(function() {
  // Spaces helper utilities for Playwright tests
  // Provides space creation, field management, and cleanup
  var SpacesHelper;

  SpacesHelper = class SpacesHelper {
    constructor() {
      this.createdSpaces = [];
      this.randomSuffix = Math.floor(Math.random() * 1000000);
    }

    // Generate unique test space name
    generateSpaceName(baseName = 'test_space') {
      return `${baseName}_${this.randomSuffix}`;
    }

    // Create a new space via UI
    async createSpace({page, name, description = 'Test space created by E2E tests'}) {
      var spaceId;
      await page.goto('/#!spaces');
      
      // Click "Create Space" button
      await page.click('[data-testid="create-space-button"]');
      
      // Fill space creation form
      await page.fill('input[name="name"]', name);
      await page.fill('textarea[name="description"]', description);
      
      // Submit form
      await page.click('[data-testid="save-space-button"]');
      
      // Wait for success and redirect
      await page.waitForSelector('[data-testid="space-created-success"]');
      
      // Get space ID from URL or page content
      spaceId = (await page.evaluate(function() {
        var ref;
        return (ref = document.querySelector('[data-space-id]')) != null ? ref.getAttribute('data-space-id') : void 0;
      }));
      this.createdSpaces.push({
        id: spaceId,
        name
      });
      console.log(`✅ Created space: ${name} (ID: ${spaceId})`);
      return spaceId;
    }

    // Create a new space via GraphQL API
    async createSpaceGraphQL({page, name, description = 'Test space'}) {
      var AuthHelper, auth, query, result, spaceId, variables;
      query = `mutation CreateSpace($name: String!, $description: String!) {
  createSpace(name: $name, description: $description) {
    id
    name
    description
  }
}`;
      variables = {name, description};
      ({AuthHelper} = require('./auth.setup'));
      auth = new AuthHelper();
      result = (await auth.makeGraphQLRequest(page, query, variables));
      spaceId = result.createSpace.id;
      this.createdSpaces.push({
        id: spaceId,
        name
      });
      console.log(`✅ Created space via GraphQL: ${name} (ID: ${spaceId})`);
      return spaceId;
    }

    // Add field to existing space
    async addField({page, spaceId, fieldName, fieldType, description = ''}) {
      await page.goto(`/#!spaces/${spaceId}`);
      
      // Click "Add Field" button
      await page.click('[data-testid="add-field-button"]');
      
      // Fill field creation form
      await page.fill('input[name="name"]', fieldName);
      await page.selectOption('select[name="type"]', fieldType);
      if (description) {
        await page.fill('textarea[name="description"]', description);
      }
      
      // Submit form
      await page.click('[data-testid="save-field-button"]');
      
      // Wait for field to appear in list
      await page.waitForSelector(`[data-field-name=\"${fieldName}\"]`);
      return console.log(`✅ Added field: ${fieldName} (${fieldType}) to space ${spaceId}`);
    }

    // Add field via GraphQL API
    async addFieldGraphQL({page, spaceId, fieldName, fieldType, options = {}}) {
      var AuthHelper, auth, query, result, variables;
      query = `mutation AddField($spaceId: ID!, $input: FieldInput!) {
  addField(spaceId: $spaceId, input: $input) {
    id
    name
    fieldType
    position
  }
}`;
      variables = {
        spaceId: spaceId,
        input: {
          name: fieldName,
          fieldType: fieldType,
          description: options.description || '',
          notNull: options.notNull || false
        }
      };
      ({AuthHelper} = require('./auth.setup'));
      auth = new AuthHelper();
      result = (await auth.makeGraphQLRequest(page, query, variables));
      console.log(`✅ Added field via GraphQL: ${fieldName} (${fieldType}) to space ${spaceId}`);
      return result.addField;
    }

    // Reorder fields in space
    async reorderFields({page, spaceId, fieldIds}) {
      var AuthHelper, auth, query, result, variables;
      query = `mutation ReorderFields($spaceId: ID!, $fieldIds: [ID!]!) {
  reorderFields(spaceId: $spaceId, fieldIds: $fieldIds) {
    id
    name
    position
  }
}`;
      variables = {spaceId, fieldIds};
      ({AuthHelper} = require('./auth.setup'));
      auth = new AuthHelper();
      result = (await auth.makeGraphQLRequest(page, query, variables));
      console.log(`✅ Reordered fields in space ${spaceId}`);
      return result.reorderFields;
    }

    // Delete space
    async deleteSpace({page, spaceId}) {
      await page.goto(`/#!spaces/${spaceId}`);
      
      // Click delete button
      await page.click('[data-testid="delete-space-button"]');
      
      // Confirm deletion in modal
      await page.click('[data-testid="confirm-delete-button"]');
      
      // Wait for success message
      await page.waitForSelector('[data-testid="space-deleted-success"]');
      
      // Remove from created spaces tracking
      this.createdSpaces = this.createdSpaces.filter(function(space) {
        return space.id !== spaceId;
      });
      return console.log(`✅ Deleted space: ${spaceId}`);
    }

    // Delete space via GraphQL API
    async deleteSpaceGraphQL({page, spaceId}) {
      var AuthHelper, auth, query, variables;
      query = `mutation DeleteSpace($spaceId: ID!) {
  deleteSpace(spaceId: $spaceId)
}`;
      variables = {spaceId};
      ({AuthHelper} = require('./auth.setup'));
      auth = new AuthHelper();
      await auth.makeGraphQLRequest(page, query, variables);
      
      // Remove from created spaces tracking
      this.createdSpaces = this.createdSpaces.filter(function(space) {
        return space.id !== spaceId;
      });
      return console.log(`✅ Deleted space via GraphQL: ${spaceId}`);
    }

    // Clean up all created spaces
    async cleanup({page}) {
      var error, i, len, ref, space;
      console.log(`🧹 Cleaning up ${this.createdSpaces.length} test spaces...`);
      ref = this.createdSpaces;
      for (i = 0, len = ref.length; i < len; i++) {
        space = ref[i];
        try {
          await this.deleteSpaceGraphQL(page, space.id);
        } catch (error1) {
          error = error1;
          console.warn(`⚠️ Failed to delete space ${space.name}: ${error.message}`);
        }
      }
      this.createdSpaces = [];
      return console.log("✅ All test spaces cleaned up");
    }

  };

  module.exports = {SpacesHelper};

}).call(this);
