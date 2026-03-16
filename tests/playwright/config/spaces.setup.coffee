# Spaces helper utilities for Playwright tests
# Provides space creation, field management, and cleanup

class SpacesHelper
  constructor: ->
    @createdSpaces = []
    @randomSuffix = Math.floor(Math.random() * 1000000)

  # Generate unique test space name
  generateSpaceName: (baseName = 'test_space') ->
    "#{baseName}_#{@randomSuffix}"

  # Create a new space via UI
  createSpace: ({page, name, description = 'Test space created by E2E tests'}) ->
    await page.goto '/#!spaces'
    
    # Click "Create Space" button
    await page.click '[data-testid="create-space-button"]'
    
    # Fill space creation form
    await page.fill 'input[name="name"]', name
    await page.fill 'textarea[name="description"]', description
    
    # Submit form
    await page.click '[data-testid="save-space-button"]'
    
    # Wait for success and redirect
    await page.waitForSelector '[data-testid="space-created-success"]'
    
    # Get space ID from URL or page content
    spaceId = await page.evaluate -> 
      document.querySelector('[data-space-id]')?.getAttribute('data-space-id')
    
    @createdSpaces.push { id: spaceId, name }
    
    console.log "✅ Created space: #{name} (ID: #{spaceId})"
    return spaceId

  # Create a new space via GraphQL API
  createSpaceGraphQL: ({page, name, description = 'Test space'}) ->
    query = """
      mutation CreateSpace($name: String!, $description: String!) {
        createSpace(name: $name, description: $description) {
          id
          name
          description
        }
      }
    """
    
    variables = { name, description }
    { AuthHelper } = require './auth.setup'
    auth = new AuthHelper()
    
    result = await auth.makeGraphQLRequest page, query, variables
    spaceId = result.createSpace.id
    
    @createdSpaces.push { id: spaceId, name }
    
    console.log "✅ Created space via GraphQL: #{name} (ID: #{spaceId})"
    return spaceId

  # Add field to existing space
  addField: ({page, spaceId, fieldName, fieldType, description = ''}) ->
    await page.goto "/#!spaces/#{spaceId}"
    
    # Click "Add Field" button
    await page.click '[data-testid="add-field-button"]'
    
    # Fill field creation form
    await page.fill 'input[name="name"]', fieldName
    await page.selectOption 'select[name="type"]', fieldType
    if description
      await page.fill 'textarea[name="description"]', description
    
    # Submit form
    await page.click '[data-testid="save-field-button"]'
    
    # Wait for field to appear in list
    await page.waitForSelector "[data-field-name=\"#{fieldName}\"]"
    
    console.log "✅ Added field: #{fieldName} (#{fieldType}) to space #{spaceId}"

  # Add field via GraphQL API
  addFieldGraphQL: ({page, spaceId, fieldName, fieldType, options = {}}) ->
    query = """
      mutation AddField($spaceId: ID!, $input: FieldInput!) {
        addField(spaceId: $spaceId, input: $input) {
          id
          name
          fieldType
          position
        }
      }
    """
    
    variables = 
      spaceId: spaceId
      input: 
        name: fieldName
        fieldType: fieldType
        description: options.description or ''
        notNull: options.notNull or false
    
    { AuthHelper } = require './auth.setup'
    auth = new AuthHelper()
    
    result = await auth.makeGraphQLRequest page, query, variables
    
    console.log "✅ Added field via GraphQL: #{fieldName} (#{fieldType}) to space #{spaceId}"
    return result.addField

  # Reorder fields in space
  reorderFields: ({page, spaceId, fieldIds}) ->
    query = """
      mutation ReorderFields($spaceId: ID!, $fieldIds: [ID!]!) {
        reorderFields(spaceId: $spaceId, fieldIds: $fieldIds) {
          id
          name
          position
        }
      }
    """
    
    variables = { spaceId, fieldIds }
    { AuthHelper } = require './auth.setup'
    auth = new AuthHelper()
    
    result = await auth.makeGraphQLRequest page, query, variables
    
    console.log "✅ Reordered fields in space #{spaceId}"
    return result.reorderFields

  # Delete space
  deleteSpace: ({page, spaceId}) ->
    await page.goto "/#!spaces/#{spaceId}"
    
    # Click delete button
    await page.click '[data-testid="delete-space-button"]'
    
    # Confirm deletion in modal
    await page.click '[data-testid="confirm-delete-button"]'
    
    # Wait for success message
    await page.waitForSelector '[data-testid="space-deleted-success"]'
    
    # Remove from created spaces tracking
    @createdSpaces = @createdSpaces.filter (space) -> space.id != spaceId
    
    console.log "✅ Deleted space: #{spaceId}"

  # Delete space via GraphQL API
  deleteSpaceGraphQL: ({page, spaceId}) ->
    query = """
      mutation DeleteSpace($spaceId: ID!) {
        deleteSpace(spaceId: $spaceId)
      }
    """
    
    variables = { spaceId }
    { AuthHelper } = require './auth.setup'
    auth = new AuthHelper()
    
    await auth.makeGraphQLRequest page, query, variables
    
    # Remove from created spaces tracking
    @createdSpaces = @createdSpaces.filter (space) -> space.id != spaceId
    
    console.log "✅ Deleted space via GraphQL: #{spaceId}"

  # Clean up all created spaces
  cleanup: ({page}) ->
    console.log "🧹 Cleaning up #{@createdSpaces.length} test spaces..."
    
    for space in @createdSpaces
      try
        await @deleteSpaceGraphQL page, space.id
      catch error
        console.warn "⚠️ Failed to delete space #{space.name}: #{error.message}"
    
    @createdSpaces = []
    console.log "✅ All test spaces cleaned up"

module.exports = { SpacesHelper }
