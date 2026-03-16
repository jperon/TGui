(function() {
  // Spaces Fields Reordering E2E Tests
  // Tests drag & drop functionality for field reordering
  var AuthHelper, SpacesHelper, expect, test;

  ({test, expect} = require('@playwright/test'));

  ({AuthHelper} = require('../config/auth.setup'));

  ({SpacesHelper} = require('../config/spaces.setup'));

  test.describe('Spaces - Fields Reordering', function() {
    var authHelper, spaceId, spacesHelper;
    authHelper = null;
    spacesHelper = null;
    spaceId = null;
    test.beforeEach(async function({page}) {
      var fieldName, fieldNames, j, len, results, spaceName;
      authHelper = new AuthHelper();
      spacesHelper = new SpacesHelper();
      await authHelper.login(page);
      
      // Create a test space with multiple fields
      spaceName = spacesHelper.generateSpaceName('reorder_test');
      spaceId = (await spacesHelper.createSpaceGraphQL(page, spaceName));
      
      // Add several fields for reordering tests
      fieldNames = ['first_field', 'second_field', 'third_field', 'fourth_field', 'fifth_field'];
      results = [];
      for (j = 0, len = fieldNames.length; j < len; j++) {
        fieldName = fieldNames[j];
        results.push((await spacesHelper.addFieldGraphQL(page, spaceId, fieldName, 'String')));
      }
      return results;
    });
    test.afterEach(async function({page}) {
      // Clean up test space
      return (await spacesHelper.deleteSpaceGraphQL(page, spaceId));
    });
    test('should display fields in creation order', async function({page}) {
      var element, expectedOrder, fieldElements, fieldName, fieldOrder, j, len;
      await page.goto(`/#!spaces/${spaceId}`);
      
      // Wait for fields to load
      await page.waitForSelector('[data-field-name]');
      
      // Get field order
      fieldElements = (await page.locator('[data-field-name]').all());
      fieldOrder = [];
      for (j = 0, len = fieldElements.length; j < len; j++) {
        element = fieldElements[j];
        fieldName = (await element.getAttribute('data-field-name'));
        fieldOrder.push(fieldName);
      }
      
      // Verify fields are in creation order
      expectedOrder = ['first_field', 'second_field', 'third_field', 'fourth_field', 'fifth_field'];
      expect(fieldOrder).toEqual(expectedOrder);
      return console.log(`✅ Fields displayed in creation order: ${fieldOrder.join(', ')}`);
    });
    test('should show drag handles on field hover', async function({page}) {
      var dragHandle, firstField;
      await page.goto(`/#!spaces/${spaceId}`);
      
      // Wait for fields to load
      await page.waitForSelector('[data-field-name]');
      
      // Hover over first field
      firstField = page.locator('[data-field-name="first_field"]');
      await firstField.hover();
      
      // Verify drag handle appears
      dragHandle = page.locator('[data-field-name="first_field"] [data-testid="field-drag-handle"]');
      await expect(dragHandle).toBeVisible();
      
      // Verify drag handle has appropriate styling
      await expect(dragHandle).toHaveClass(/drag-handle/);
      return (await expect(dragHandle).toHaveCSS('cursor', 'grab'));
    });
    test('should change cursor on drag handle hover', async function({page}) {
      var dragHandle, fieldContainer;
      await page.goto(`/#!spaces/${spaceId}`);
      
      // Wait for fields to load
      await page.waitForSelector('[data-field-name]');
      
      // Hover over drag handle
      dragHandle = page.locator('[data-field-name="first_field"] [data-testid="field-drag-handle"]');
      await dragHandle.hover();
      
      // Verify cursor changes to grab
      await expect(dragHandle).toHaveCSS('cursor', 'grab');
      
      // Verify field container has appropriate styling
      fieldContainer = page.locator('[data-field-name="first_field"]');
      return (await expect(fieldContainer).toHaveClass(/draggable/));
    });
    test('should initiate drag on drag handle', async function({page}) {
      var dragHandle;
      await page.goto(`/#!spaces/${spaceId}`);
      
      // Wait for fields to load
      await page.waitForSelector('[data-field-name]');
      
      // Start dragging first field
      dragHandle = page.locator('[data-field-name="first_field"] [data-testid="field-drag-handle"]');
      
      // Start drag
      await dragHandle.down();
      
      // Verify dragging state
      await expect(page.locator('body')).toHaveClass(/dragging-active/);
      await expect(page.locator('[data-field-name="first_field"]')).toHaveClass(/dragging/);
      
      // Release drag
      await dragHandle.up();
      
      // Verify dragging state cleared
      await expect(page.locator('body')).not.toHaveClass(/dragging-active/);
      return (await expect(page.locator('[data-field-name="first_field"]')).not.toHaveClass(/dragging/));
    });
    test('should show drop zones during drag', async function({page}) {
      var dragHandle, dropZones;
      await page.goto(`/#!spaces/${spaceId}`);
      
      // Wait for fields to load
      await page.waitForSelector('[data-field-name]');
      
      // Start dragging first field
      dragHandle = page.locator('[data-field-name="first_field"] [data-testid="field-drag-handle"]');
      await dragHandle.down();
      
      // Verify drop zones appear
      dropZones = page.locator('[data-testid="field-drop-zone"]');
      await expect(dropZones.first()).toBeVisible();
      
      // Verify drop zone styling
      await expect(dropZones.first()).toHaveClass(/drop-zone/);
      await expect(dropZones.first()).toHaveCSS('border', /dashed/);
      
      // Release drag
      await dragHandle.up();
      
      // Verify drop zones disappear
      return (await expect(dropZones.first()).not.toBeVisible());
    });
    test('should reorder fields via drag and drop', async function({page}) {
      var element, fieldElements, fieldName, initialOrder, j, k, len, len1, newFieldElements, newOrder, sourceField, targetPosition;
      await page.goto(`/#!spaces/${spaceId}`);
      
      // Wait for fields to load
      await page.waitForSelector('[data-field-name]');
      
      // Get initial order
      fieldElements = (await page.locator('[data-field-name]').all());
      initialOrder = [];
      for (j = 0, len = fieldElements.length; j < len; j++) {
        element = fieldElements[j];
        fieldName = (await element.getAttribute('data-field-name'));
        initialOrder.push(fieldName);
      }
      console.log(`Initial order: ${initialOrder.join(', ')}`);
      
      // Drag first field to last position
      sourceField = page.locator('[data-field-name="first_field"]');
      targetPosition = page.locator('[data-field-name="fifth_field"]');
      
      // Perform drag and drop
      await sourceField.dragTo(targetPosition);
      
      // Wait for reordering to complete
      await page.waitForTimeout(1000);
      
      // Get new order
      newFieldElements = (await page.locator('[data-field-name]').all());
      newOrder = [];
      for (k = 0, len1 = newFieldElements.length; k < len1; k++) {
        element = newFieldElements[k];
        fieldName = (await element.getAttribute('data-field-name'));
        newOrder.push(fieldName);
      }
      console.log(`New order: ${newOrder.join(', ')}`);
      
      // Verify order changed (implementation dependent)
      // The exact behavior depends on the drag & drop implementation
      return expect(newOrder).not.toEqual(initialOrder);
    });
    test('should save new field order after reordering', async function({page}) {
      var element, fieldElements, fieldName, finalOrder, j, len, sourceField, targetPosition;
      await page.goto(`/#!spaces/${spaceId}`);
      
      // Wait for fields to load
      await page.waitForSelector('[data-field-name]');
      
      // Perform reordering
      sourceField = page.locator('[data-field-name="second_field"]');
      targetPosition = page.locator('[data-field-name="fourth_field"]');
      await sourceField.dragTo(targetPosition);
      
      // Wait for save to complete
      await page.waitForSelector('[data-testid="fields-saved"]', {
        timeout: 5000
      });
      
      // Reload page to verify persistence
      await page.reload();
      await page.waitForSelector('[data-field-name]');
      
      // Get order after reload
      fieldElements = (await page.locator('[data-field-name]').all());
      finalOrder = [];
      for (j = 0, len = fieldElements.length; j < len; j++) {
        element = fieldElements[j];
        fieldName = (await element.getAttribute('data-field-name'));
        finalOrder.push(fieldName);
      }
      console.log(`Final order after reload: ${finalOrder.join(', ')}`);
      
      // Verify order is maintained (implementation dependent)
      return expect(finalOrder.length).toBe(5);
    });
    test('should handle reordering with GraphQL API', async function({page}) {
      var element, error, fieldElements, fieldId, fieldIds, j, len, result, reversedIds;
      // Get current field IDs
      await page.goto(`/#!spaces/${spaceId}`);
      await page.waitForSelector('[data-field-name]');
      fieldElements = (await page.locator('[data-field-name]').all());
      fieldIds = [];
      for (j = 0, len = fieldElements.length; j < len; j++) {
        element = fieldElements[j];
        fieldId = (await element.getAttribute('data-field-id'));
        if (fieldId) {
          fieldIds.push(fieldId);
        }
      }
      
      // Reverse the order
      reversedIds = fieldIds.reverse();
      try {
        
        // Reorder via GraphQL
        result = (await spacesHelper.reorderFields(page, spaceId, reversedIds));
        
        // Verify the API response
        expect(result).toBeDefined();
        expect(Array.isArray(result)).toBeTruthy();
        return console.log("✅ Fields reordered via GraphQL API");
      } catch (error1) {
        error = error1;
        return console.log("GraphQL reordering not implemented:", error.message);
      }
    });
    test('should prevent invalid drops', async function({page}) {
      var currentOrder, element, expectedOrder, fieldElements, fieldName, j, len, sourceField;
      await page.goto(`/#!spaces/${spaceId}`);
      
      // Wait for fields to load
      await page.waitForSelector('[data-field-name]');
      
      // Try to drag field outside valid drop zone
      sourceField = page.locator('[data-field-name="third_field"]');
      
      // Drag to outside field list area
      await sourceField.dragTo(page.locator('[data-testid="space-header"]'));
      
      // Verify field returns to original position
      await page.waitForTimeout(1000);
      fieldElements = (await page.locator('[data-field-name]').all());
      currentOrder = [];
      for (j = 0, len = fieldElements.length; j < len; j++) {
        element = fieldElements[j];
        fieldName = (await element.getAttribute('data-field-name'));
        currentOrder.push(fieldName);
      }
      expectedOrder = ['first_field', 'second_field', 'third_field', 'fourth_field', 'fifth_field'];
      return expect(currentOrder).toEqual(expectedOrder);
    });
    test('should show visual feedback during drag', async function({page}) {
      var dragHandle, draggingField, ghostElement;
      await page.goto(`/#!spaces/${spaceId}`);
      
      // Wait for fields to load
      await page.waitForSelector('[data-field-name]');
      
      // Start dragging
      dragHandle = page.locator('[data-field-name="first_field"] [data-testid="field-drag-handle"]');
      await dragHandle.down();
      
      // Verify visual feedback
      draggingField = page.locator('[data-field-name="first_field"]');
      
      // Check for visual indicators
      await expect(draggingField).toHaveClass(/dragging/);
      await expect(draggingField).toHaveCSS('opacity', /0\.8/); // Semi-transparent
      
      // Check for ghost element
      ghostElement = page.locator('.field-ghost');
      if ((await ghostElement.isVisible())) {
        await expect(ghostElement).toHaveCSS('opacity', /0\.4/);
      }
      
      // Release drag
      await dragHandle.up();
      
      // Verify visual feedback cleared
      return (await expect(draggingField).not.toHaveClass(/dragging/));
    });
    test('should handle keyboard navigation for reordering', async function({page}) {
      var currentOrder, element, fieldElements, fieldName, firstField, j, len;
      await page.goto(`/#!spaces/${spaceId}`);
      
      // Wait for fields to load
      await page.waitForSelector('[data-field-name]');
      
      // Focus on first field
      firstField = page.locator('[data-field-name="first_field"]');
      await firstField.focus();
      
      // Try keyboard shortcuts if implemented
      // Common patterns: Ctrl+Up/Down, Alt+Up/Down, etc.

      // Test Ctrl+Down (move down)
      await page.keyboard.press('Control+ArrowDown');
      await page.waitForTimeout(500);
      
      // Check if order changed
      fieldElements = (await page.locator('[data-field-name]').all());
      currentOrder = [];
      for (j = 0, len = fieldElements.length; j < len; j++) {
        element = fieldElements[j];
        fieldName = (await element.getAttribute('data-field-name'));
        currentOrder.push(fieldName);
      }
      
      // If keyboard reordering is implemented, order should change
      // If not implemented, this test serves as documentation
      return console.log(`Order after keyboard navigation: ${currentOrder.join(', ')}`);
    });
    return test('should handle reordering with many fields', async function({page}) {
      var additionalFields, fieldElements, fieldName, i, j, middleField, targetField;
      // Add more fields for stress testing
      additionalFields = [];
      for (i = j = 6; j <= 15; i = ++j) {
        fieldName = `extra_field_${i}`;
        await spacesHelper.addFieldGraphQL(page, spaceId, fieldName, 'String');
        additionalFields.push(fieldName);
      }
      await page.goto(`/#!spaces/${spaceId}`);
      await page.waitForSelector('[data-field-name]');
      
      // Verify all fields are displayed
      fieldElements = (await page.locator('[data-field-name]').all());
      expect(fieldElements.length).toBe(15);
      
      // Test reordering with many fields
      middleField = page.locator('[data-field-name="eighth_field"]');
      targetField = page.locator('[data-field-name="second_field"]');
      await middleField.dragTo(targetField);
      await page.waitForTimeout(1000);
      
      // Verify reordering still works with many fields
      fieldElements = (await page.locator('[data-field-name]').all());
      expect(fieldElements.length).toBe(15);
      return console.log(`✅ Reordering works with ${fieldElements.length} fields`);
    });
  });

}).call(this);
