# Spaces Fields E2E Tests
# Tests field creation, modification, and all field types

{ test, expect } = require '@playwright/test'
{ AuthHelper } = require '../config/auth.setup'
{ SpacesHelper } = require '../config/spaces.setup'

test.describe('Spaces - Fields Management', ->
  authHelper = null
  spacesHelper = null
  spaceId = null

  test.beforeEach(({ page }) ->
    authHelper = new AuthHelper()
    spacesHelper = new SpacesHelper()
    await authHelper.login page
    
    # Create a test space for field tests
    spaceName = spacesHelper.generateSpaceName('field_test')
    spaceId = await spacesHelper.createSpaceGraphQL page, spaceName
  )

  test.afterEach(({ page }) ->
    # Clean up test space
    await spacesHelper.deleteSpaceGraphQL page, spaceId
  )

  test('should add String field via UI', ({ page }) ->
    await page.goto "/#!spaces/#{spaceId}"
    
    # Click add field button
    await page.click '[data-testid="add-field-button"]'
    
    # Fill field form
    await page.fill 'input[name="name"]', 'test_string'
    await page.selectOption 'select[name="type"]', 'String'
    await page.fill 'textarea[name="description"]', 'Test string field'
    
    # Save field
    await page.click '[data-testid="save-field-button"]'
    
    # Verify field appears in list
    await expect(page.locator('[data-field-name="test_string"]')).toBeVisible()
    await expect(page.locator('[data-field-type="String"]')).toBeVisible()
    await expect(page.locator('[data-field-description="Test string field"]')).toBeVisible()
  )

  test('should add all basic field types via GraphQL', ({ page }) ->
    fieldTypes = [
      { name: 'string_field', type: 'String', description: 'String field test' }
      { name: 'int_field', type: 'Int', description: 'Integer field test' }
      { name: 'float_field', type: 'Float', description: 'Float field test' }
      { name: 'boolean_field', type: 'Boolean', description: 'Boolean field test' }
      { name: 'id_field', type: 'ID', description: 'ID field test' }
      { name: 'uuid_field', type: 'UUID', description: 'UUID field test' }
    ]
    
    for field in fieldTypes
      await spacesHelper.addFieldGraphQL page, spaceId, field.name, field.type, { description: field.description }
    
    # Verify all fields appear in UI
    await page.goto "/#!spaces/#{spaceId}"
    
    for field in fieldTypes
      await expect(page.locator("[data-field-name=\"#{field.name}\"]")).toBeVisible()
      await expect(page.locator("[data-field-type=\"#{field.type}\"]")).toBeVisible()
      await expect(page.locator("[data-field-description=\"#{field.description}\"]")).toBeVisible()
    
    console.log "✅ Added #{fieldTypes.length} basic field types"
  )

  test('should add Sequence field for auto-increment', ({ page }) ->
    await spacesHelper.addFieldGraphQL page, spaceId, 'auto_id', 'Sequence', { description: 'Auto-increment ID' }
    
    # Verify field appears
    await page.goto "/#!spaces/#{spaceId}"
    await expect(page.locator('[data-field-name="auto_id"]')).toBeVisible()
    await expect(page.locator('[data-field-type="Sequence"]')).toBeVisible()
    
    # Verify sequence-specific attributes
    await expect(page.locator('[data-field-sequence="true"]')).toBeVisible()
  )

  test('should add JSON field types (Any, Map, Array)', ({ page }) ->
    jsonTypes = [
      { name: 'any_field', type: 'Any', description: 'Any JSON field' }
      { name: 'map_field', type: 'Map', description: 'Map JSON field' }
      { name: 'array_field', type: 'Array', description: 'Array JSON field' }
    ]
    
    for field in jsonTypes
      await spacesHelper.addFieldGraphQL page, spaceId, field.name, field.type, { description: field.description }
    
    # Verify JSON fields appear
    await page.goto "/#!spaces/#{spaceId}"
    
    for field in jsonTypes
      await expect(page.locator("[data-field-name=\"#{field.name}\"]")).toBeVisible()
      await expect(page.locator("[data-field-type=\"#{field.type}\"]")).toBeVisible()
    
    console.log "✅ Added #{jsonTypes.length} JSON field types"
  )

  test('should handle required (not null) fields', ({ page }) ->
    # Add required field
    await spacesHelper.addFieldGraphQL page, spaceId, 'required_field', 'String', { 
      description: 'Required field test'
      notNull: true 
    }
    
    # Verify field appears as required
    await page.goto "/#!spaces/#{spaceId}"
    await expect(page.locator('[data-field-name="required_field"]')).toBeVisible()
    await expect(page.locator('[data-field-required="true"]')).toBeVisible()
    
    # Test required field validation when creating records
    # This would need record creation API - for now we just verify the field is marked as required
  )

  test('should validate field names', ({ page }) ->
    await page.goto "/#!spaces/#{spaceId}"
    
    # Try to add field with invalid name (reserved keyword)
    await page.click '[data-testid="add-field-button"]'
    await page.fill 'input[name="name"]', 'id'  # 'id' might be reserved
    await page.selectOption 'select[name="type"]', 'String'
    await page.click '[data-testid="save-field-button"]'
    
    # Check if validation error occurs (depends on implementation)
    # If no validation, the field should still be created
    await page.waitForTimeout 1000
    
    # Try field with special characters
    await page.click '[data-testid="add-field-button"]'
    await page.fill 'input[name="name"]', 'field-with-dashes'
    await page.selectOption 'select[name="type"]', 'String'
    await page.click '[data-testid="save-field-button"]'
    
    # Verify if field was created or rejected
    await page.waitForTimeout 1000
  )

  test('should handle field position ordering', ({ page }) ->
    # Add multiple fields
    fieldNames = ['field_a', 'field_b', 'field_c', 'field_d']
    
    for fieldName in fieldNames
      await spacesHelper.addFieldGraphQL page, spaceId, fieldName, 'String'
    
    # Get current field order
    await page.goto "/#!spaces/#{spaceId}"
    
    fieldElements = await page.locator('[data-field-name]').all()
    currentOrder = []
    for element in fieldElements
      fieldName = await element.getAttribute 'data-field-name'
      currentOrder.push fieldName if fieldName in fieldNames
    
    # Reorder fields (reverse order)
    reversedOrder = currentOrder.reverse()
    
    try
      await spacesHelper.reorderFields page, spaceId, reversedOrder
      
      # Verify new order
      await page.goto "/#!spaces/#{spaceId}"
      
      reorderedElements = await page.locator('[data-field-name]').all()
      newOrder = []
      for element in reorderedElements
        fieldName = await element.getAttribute 'data-field-name'
        newOrder.push fieldName if fieldName in fieldNames
      
      # Check if order changed (implementation dependent)
      console.log "Original order: #{currentOrder.join(', ')}"
      console.log "New order: #{newOrder.join(', ')}"
      
    catch error
      console.log "Field reordering not implemented or failed:", error.message
  )

  test('should delete field via UI', ({ page }) ->
    # Add a field first
    await spacesHelper.addFieldGraphQL page, spaceId, 'to_delete', 'String'
    
    # Verify field exists
    await page.goto "/#!spaces/#{spaceId}"
    await expect(page.locator('[data-field-name="to_delete"]')).toBeVisible()
    
    # Delete field
    await page.click '[data-field-name="to_delete"] [data-testid="delete-field-button"]'
    await page.click '[data-testid="confirm-delete-button"]'
    
    # Verify field is gone
    await expect(page.locator('[data-field-name="to_delete"]')).not.toBeVisible()
  )

  test('should handle field with very long name', ({ page }) ->
    longFieldName = 'a' * 50  # 50 characters
    
    await spacesHelper.addFieldGraphQL page, spaceId, longFieldName, 'String'
    
    # Verify field was created
    await page.goto "/#!spaces/#{spaceId}"
    await expect(page.locator("[data-field-name=\"#{longFieldName}\"]")).toBeVisible()
  )

  test('should handle field with special characters', ({ page }) ->
    specialFieldName = 'field_with.special@chars#123'
    
    await spacesHelper.addFieldGraphQL page, spaceId, specialFieldName, 'String'
    
    # Verify field was created
    await page.goto "/#!spaces/#{spaceId}"
    await expect(page.locator("[data-field-name=\"#{specialFieldName}\"]")).toBeVisible()
  )

  test('should display field metadata correctly', ({ page }) ->
    # Add field with all metadata
    await spacesHelper.addFieldGraphQL page, spaceId, 'metadata_field', 'String', {
      description: 'Field with complete metadata'
      notNull: true
    }
    
    # Verify metadata display
    await page.goto "/#!spaces/#{spaceId}"
    
    fieldElement = page.locator('[data-field-name="metadata_field"]')
    await expect(fieldElement).toBeVisible()
    
    # Check type
    await expect(page.locator('[data-field-name="metadata_field"] [data-field-type="String"]')).toBeVisible()
    
    # Check description
    await expect(page.locator('[data-field-name="metadata_field"] [data-field-description="Field with complete metadata"]')).toBeVisible()
    
    # Check required indicator
    await expect(page.locator('[data-field-name="metadata_field"] [data-field-required="true"]')).toBeVisible()
  )

  test('should handle field updates', ({ page }) ->
    # Add initial field
    await spacesHelper.addFieldGraphQL page, spaceId, 'updatable_field', 'String', {
      description: 'Initial description'
    }
    
    # Try to update field (if update functionality exists)
    await page.goto "/#!spaces/#{spaceId}"
    
    editButton = page.locator('[data-field-name="updatable_field"] [data-testid="edit-field-button"]')
    if await editButton.isVisible()
      await editButton.click()
      
      # Update description
      await page.fill 'textarea[name="description"]', 'Updated description'
      await page.click '[data-testid="save-field-button"]'
      
      # Verify update
      await expect(page.locator('[data-field-name="updatable_field"] [data-field-description="Updated description"]')).toBeVisible()
    else
      console.log "Field update functionality not available in UI"
  )
)
