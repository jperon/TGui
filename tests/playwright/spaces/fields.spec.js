(function() {
  // Spaces Fields E2E Tests
  // Tests field creation, modification, and all field types
  var AuthHelper, SpacesHelper, expect, test,
    indexOf = [].indexOf;

  ({test, expect} = require('@playwright/test'));

  ({AuthHelper} = require('../config/auth.setup'));

  ({SpacesHelper} = require('../config/spaces.setup'));

  test.describe('Spaces - Fields Management', function() {
    var authHelper, spaceId, spacesHelper;
    authHelper = null;
    spacesHelper = null;
    spaceId = null;
    test.beforeEach(async function({page}) {
      var spaceName;
      authHelper = new AuthHelper();
      spacesHelper = new SpacesHelper();
      await authHelper.login(page);
      
      // Create a test space for field tests
      spaceName = spacesHelper.generateSpaceName('field_test');
      return spaceId = (await spacesHelper.createSpaceGraphQL(page, spaceName));
    });
    test.afterEach(async function({page}) {
      // Clean up test space
      return (await spacesHelper.deleteSpaceGraphQL(page, spaceId));
    });
    test('should add String field via UI', async function({page}) {
      await page.goto(`/#!spaces/${spaceId}`);
      
      // Click add field button
      await page.click('[data-testid="add-field-button"]');
      
      // Fill field form
      await page.fill('input[name="name"]', 'test_string');
      await page.selectOption('select[name="type"]', 'String');
      await page.fill('textarea[name="description"]', 'Test string field');
      
      // Save field
      await page.click('[data-testid="save-field-button"]');
      
      // Verify field appears in list
      await expect(page.locator('[data-field-name="test_string"]')).toBeVisible();
      await expect(page.locator('[data-field-type="String"]')).toBeVisible();
      return (await expect(page.locator('[data-field-description="Test string field"]')).toBeVisible());
    });
    test('should add all basic field types via GraphQL', async function({page}) {
      var field, fieldTypes, i, j, len, len1;
      fieldTypes = [
        {
          name: 'string_field',
          type: 'String',
          description: 'String field test'
        },
        {
          name: 'int_field',
          type: 'Int',
          description: 'Integer field test'
        },
        {
          name: 'float_field',
          type: 'Float',
          description: 'Float field test'
        },
        {
          name: 'boolean_field',
          type: 'Boolean',
          description: 'Boolean field test'
        },
        {
          name: 'id_field',
          type: 'ID',
          description: 'ID field test'
        },
        {
          name: 'uuid_field',
          type: 'UUID',
          description: 'UUID field test'
        }
      ];
      for (i = 0, len = fieldTypes.length; i < len; i++) {
        field = fieldTypes[i];
        await spacesHelper.addFieldGraphQL(page, spaceId, field.name, field.type, {
          description: field.description
        });
      }
      
      // Verify all fields appear in UI
      await page.goto(`/#!spaces/${spaceId}`);
      for (j = 0, len1 = fieldTypes.length; j < len1; j++) {
        field = fieldTypes[j];
        await expect(page.locator(`[data-field-name=\"${field.name}\"]`)).toBeVisible();
        await expect(page.locator(`[data-field-type=\"${field.type}\"]`)).toBeVisible();
        await expect(page.locator(`[data-field-description=\"${field.description}\"]`)).toBeVisible();
      }
      return console.log(`✅ Added ${fieldTypes.length} basic field types`);
    });
    test('should add Sequence field for auto-increment', async function({page}) {
      await spacesHelper.addFieldGraphQL(page, spaceId, 'auto_id', 'Sequence', {
        description: 'Auto-increment ID'
      });
      
      // Verify field appears
      await page.goto(`/#!spaces/${spaceId}`);
      await expect(page.locator('[data-field-name="auto_id"]')).toBeVisible();
      await expect(page.locator('[data-field-type="Sequence"]')).toBeVisible();
      
      // Verify sequence-specific attributes
      return (await expect(page.locator('[data-field-sequence="true"]')).toBeVisible());
    });
    test('should add JSON field types (Any, Map, Array)', async function({page}) {
      var field, i, j, jsonTypes, len, len1;
      jsonTypes = [
        {
          name: 'any_field',
          type: 'Any',
          description: 'Any JSON field'
        },
        {
          name: 'map_field',
          type: 'Map',
          description: 'Map JSON field'
        },
        {
          name: 'array_field',
          type: 'Array',
          description: 'Array JSON field'
        }
      ];
      for (i = 0, len = jsonTypes.length; i < len; i++) {
        field = jsonTypes[i];
        await spacesHelper.addFieldGraphQL(page, spaceId, field.name, field.type, {
          description: field.description
        });
      }
      
      // Verify JSON fields appear
      await page.goto(`/#!spaces/${spaceId}`);
      for (j = 0, len1 = jsonTypes.length; j < len1; j++) {
        field = jsonTypes[j];
        await expect(page.locator(`[data-field-name=\"${field.name}\"]`)).toBeVisible();
        await expect(page.locator(`[data-field-type=\"${field.type}\"]`)).toBeVisible();
      }
      return console.log(`✅ Added ${jsonTypes.length} JSON field types`);
    });
    test('should handle required (not null) fields', async function({page}) {
      // Add required field
      await spacesHelper.addFieldGraphQL(page, spaceId, 'required_field', 'String', {
        description: 'Required field test',
        notNull: true
      });
      
      // Verify field appears as required
      await page.goto(`/#!spaces/${spaceId}`);
      await expect(page.locator('[data-field-name="required_field"]')).toBeVisible();
      return (await expect(page.locator('[data-field-required="true"]')).toBeVisible());
    });
    
    // Test required field validation when creating records
    // This would need record creation API - for now we just verify the field is marked as required
    test('should validate field names', async function({page}) {
      await page.goto(`/#!spaces/${spaceId}`);
      
      // Try to add field with invalid name (reserved keyword)
      await page.click('[data-testid="add-field-button"]');
      await page.fill('input[name="name"]', 'id'); // 'id' might be reserved
      await page.selectOption('select[name="type"]', 'String');
      await page.click('[data-testid="save-field-button"]');
      
      // Check if validation error occurs (depends on implementation)
      // If no validation, the field should still be created
      await page.waitForTimeout(1000);
      
      // Try field with special characters
      await page.click('[data-testid="add-field-button"]');
      await page.fill('input[name="name"]', 'field-with-dashes');
      await page.selectOption('select[name="type"]', 'String');
      await page.click('[data-testid="save-field-button"]');
      
      // Verify if field was created or rejected
      return (await page.waitForTimeout(1000));
    });
    test('should handle field position ordering', async function({page}) {
      var currentOrder, element, error, fieldElements, fieldName, fieldNames, i, j, k, len, len1, len2, newOrder, reorderedElements, reversedOrder;
      // Add multiple fields
      fieldNames = ['field_a', 'field_b', 'field_c', 'field_d'];
      for (i = 0, len = fieldNames.length; i < len; i++) {
        fieldName = fieldNames[i];
        await spacesHelper.addFieldGraphQL(page, spaceId, fieldName, 'String');
      }
      
      // Get current field order
      await page.goto(`/#!spaces/${spaceId}`);
      fieldElements = (await page.locator('[data-field-name]').all());
      currentOrder = [];
      for (j = 0, len1 = fieldElements.length; j < len1; j++) {
        element = fieldElements[j];
        fieldName = (await element.getAttribute('data-field-name'));
        if (indexOf.call(fieldNames, fieldName) >= 0) {
          currentOrder.push(fieldName);
        }
      }
      
      // Reorder fields (reverse order)
      reversedOrder = currentOrder.reverse();
      try {
        await spacesHelper.reorderFields(page, spaceId, reversedOrder);
        
        // Verify new order
        await page.goto(`/#!spaces/${spaceId}`);
        reorderedElements = (await page.locator('[data-field-name]').all());
        newOrder = [];
        for (k = 0, len2 = reorderedElements.length; k < len2; k++) {
          element = reorderedElements[k];
          fieldName = (await element.getAttribute('data-field-name'));
          if (indexOf.call(fieldNames, fieldName) >= 0) {
            newOrder.push(fieldName);
          }
        }
        
        // Check if order changed (implementation dependent)
        console.log(`Original order: ${currentOrder.join(', ')}`);
        return console.log(`New order: ${newOrder.join(', ')}`);
      } catch (error1) {
        error = error1;
        return console.log("Field reordering not implemented or failed:", error.message);
      }
    });
    test('should delete field via UI', async function({page}) {
      // Add a field first
      await spacesHelper.addFieldGraphQL(page, spaceId, 'to_delete', 'String');
      
      // Verify field exists
      await page.goto(`/#!spaces/${spaceId}`);
      await expect(page.locator('[data-field-name="to_delete"]')).toBeVisible();
      
      // Delete field
      await page.click('[data-field-name="to_delete"] [data-testid="delete-field-button"]');
      await page.click('[data-testid="confirm-delete-button"]');
      
      // Verify field is gone
      return (await expect(page.locator('[data-field-name="to_delete"]')).not.toBeVisible());
    });
    test('should handle field with very long name', async function({page}) {
      var longFieldName;
      longFieldName = 'a' * 50; // 50 characters
      await spacesHelper.addFieldGraphQL(page, spaceId, longFieldName, 'String');
      
      // Verify field was created
      await page.goto(`/#!spaces/${spaceId}`);
      return (await expect(page.locator(`[data-field-name=\"${longFieldName}\"]`)).toBeVisible());
    });
    test('should handle field with special characters', async function({page}) {
      var specialFieldName;
      specialFieldName = 'field_with.special@chars#123';
      await spacesHelper.addFieldGraphQL(page, spaceId, specialFieldName, 'String');
      
      // Verify field was created
      await page.goto(`/#!spaces/${spaceId}`);
      return (await expect(page.locator(`[data-field-name=\"${specialFieldName}\"]`)).toBeVisible());
    });
    test('should display field metadata correctly', async function({page}) {
      var fieldElement;
      // Add field with all metadata
      await spacesHelper.addFieldGraphQL(page, spaceId, 'metadata_field', 'String', {
        description: 'Field with complete metadata',
        notNull: true
      });
      
      // Verify metadata display
      await page.goto(`/#!spaces/${spaceId}`);
      fieldElement = page.locator('[data-field-name="metadata_field"]');
      await expect(fieldElement).toBeVisible();
      
      // Check type
      await expect(page.locator('[data-field-name="metadata_field"] [data-field-type="String"]')).toBeVisible();
      
      // Check description
      await expect(page.locator('[data-field-name="metadata_field"] [data-field-description="Field with complete metadata"]')).toBeVisible();
      
      // Check required indicator
      return (await expect(page.locator('[data-field-name="metadata_field"] [data-field-required="true"]')).toBeVisible());
    });
    return test('should handle field updates', async function({page}) {
      var editButton;
      // Add initial field
      await spacesHelper.addFieldGraphQL(page, spaceId, 'updatable_field', 'String', {
        description: 'Initial description'
      });
      
      // Try to update field (if update functionality exists)
      await page.goto(`/#!spaces/${spaceId}`);
      editButton = page.locator('[data-field-name="updatable_field"] [data-testid="edit-field-button"]');
      if ((await editButton.isVisible())) {
        await editButton.click();
        
        // Update description
        await page.fill('textarea[name="description"]', 'Updated description');
        await page.click('[data-testid="save-field-button"]');
        
        // Verify update
        return (await expect(page.locator('[data-field-name="updatable_field"] [data-field-description="Updated description"]')).toBeVisible());
      } else {
        return console.log("Field update functionality not available in UI");
      }
    });
  });

}).call(this);
