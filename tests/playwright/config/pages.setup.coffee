# Pages helper utilities for Playwright tests
# Provides Page/Custom View creation, widget management, and YAML handling

class PagesHelper
  constructor: ->
    @createdPages = []
    @randomSuffix = Math.floor(Math.random() * 1000000)

  # Generate unique test page name
  generatePageName: (baseName = 'test_page') ->
    "#{baseName}_#{@randomSuffix}"

  # Create a new Page via UI
  createPage: ({page, name, description = 'Test page created by E2E tests'}) ->
    await page.goto '/#!pages'
    
    # Click "Create Page" button
    await page.click '[data-testid="create-page-button"]'
    
    # Fill page creation form
    await page.fill 'input[name="name"]', name
    await page.fill 'textarea[name="description"]', description
    
    # Submit form
    await page.click '[data-testid="save-page-button"]'
    
    # Wait for success and redirect
    await page.waitForSelector '[data-testid="page-created-success"]'
    
    # Get Page ID from page content
    pageId = await page.evaluate -> 
      document.querySelector('[data-page-id]')?.getAttribute('data-page-id')
    
    @createdPages.push { id: pageId, name }
    
    console.log "✅ Created page: #{name} (ID: #{pageId})"
    return pageId

  # Create a new Page via GraphQL API
  createPageGraphQL: ({page, name, description = 'Test page'}) ->
    query = """
      mutation CreateCustomView($name: String!, $description: String!, $yaml: String!) {
        createCustomView(name: $name, description: $description, yaml: $yaml) {
          id
          name
          description
          yaml
        }
      }
    """
    
    # Basic YAML structure for new page
    yamlContent = """
layout:
  direction: vertical
  children: []
"""
    
    variables = { name, description, yaml: yamlContent }
    { AuthHelper } = require './auth.setup'
    auth = new AuthHelper()
    
    result = await auth.makeGraphQLRequest page, query, variables
    pageId = result.createCustomView.id
    
    @createdPages.push { id: pageId, name }
    
    console.log "✅ Created page via GraphQL: #{name} (ID: #{pageId})"
    return pageId

  # Add widget to page via UI
  addWidget: ({page, pageId, widgetConfig}) ->
    await page.goto "/#!pages/#{pageId}"
    
    # Click "Add Widget" button
    await page.click '[data-testid="add-widget-button"]'
    
    # Fill widget configuration form
    await page.fill 'input[name="title"]', widgetConfig.title
    await page.selectOption 'select[name="space"]', widgetConfig.space
    
    if widgetConfig.columns and widgetConfig.columns.length > 0
      # Add columns
      for column in widgetConfig.columns
        await page.click '[data-testid="add-column-button"]'
        await page.selectOption 'select[name="column"]', column
    
    # Submit form
    await page.click '[data-testid="save-widget-button"]'
    
    # Wait for widget to appear in page
    await page.waitForSelector "[data-widget-title=\"#{widgetConfig.title}\"]"
    
    console.log "✅ Added widget: #{widgetConfig.title} to page #{pageId}"

  # Add widget to page via GraphQL API
  addWidgetGraphQL: ({page, pageId, widgetConfig}) ->
    query = """
      mutation AddWidgetToView($viewId: ID!, $widget: WidgetInput!) {
        addWidgetToView(viewId: $viewId, widget: $widget) {
          id
          yaml
        }
      }
    """
    
    variables = 
      viewId: pageId
      widget: widgetConfig
    
    { AuthHelper } = require './auth.setup'
    auth = new AuthHelper()
    
    result = await auth.makeGraphQLRequest page, query, variables
    
    console.log "✅ Added widget via GraphQL: #{widgetConfig.title} to page #{pageId}"
    return result.addWidgetToView

  # Get page YAML content
  getPageYAML: ({page, pageId}) ->
    await page.goto "/#!pages/#{pageId}"
    
    # Click "Edit YAML" button
    await page.click '[data-testid="edit-yaml-button"]'
    
    # Get YAML content from editor
    yamlContent = await page.inputValue '[data-testid="yaml-editor"]'
    
    console.log "📄 Retrieved YAML for page #{pageId}"
    return yamlContent

  # Get page YAML via GraphQL API
  getPageYAMLGraphQL: ({page, pageId}) ->
    query = """
      query GetCustomView($id: ID!) {
        customView(id: $id) {
          id
          name
          yaml
        }
      }
    """
    
    variables = { id: pageId }
    { AuthHelper } = require './auth.setup'
    auth = new AuthHelper()
    
    result = await auth.makeGraphQLRequest page, query, variables
    
    console.log "📄 Retrieved YAML via GraphQL for page #{pageId}"
    return result.customView.yaml

  # Update page YAML content
  updatePageYAML: ({page, pageId, yamlContent}) ->
    await page.goto "/#!pages/#{pageId}"
    
    # Click "Edit YAML" button
    await page.click '[data-testid="edit-yaml-button"]'
    
    # Update YAML content
    await page.fill '[data-testid="yaml-editor"]', yamlContent
    
    # Save changes
    await page.click '[data-testid="save-yaml-button"]'
    
    # Wait for success message
    await page.waitForSelector '[data-testid="yaml-saved-success"]'
    
    console.log "✅ Updated YAML for page #{pageId}"

  # Update page YAML via GraphQL API
  updatePageYAMLGraphQL: ({page, pageId, yamlContent}) ->
    query = """
      mutation UpdateCustomView($id: ID!, $input: UpdateCustomViewInput!) {
        updateCustomView(id: $id, input: $input) {
          id
          name
          yaml
        }
      }
    """
    
    variables = 
      id: pageId
      input: { yaml: yamlContent }
    
    { AuthHelper } = require './auth.setup'
    auth = new AuthHelper()
    
    result = await auth.makeGraphQLRequest page, query, variables
    
    console.log "✅ Updated YAML via GraphQL for page #{pageId}"
    return result.updateCustomView

  # Reorder widgets in page
  reorderWidgets: ({page, pageId, widgetPositions}) ->
    query = """
      mutation ReorderWidgets($pageId: ID!, $widgetPositions: [WidgetPosition!]!) {
        reorderWidgets(pageId: $pageId, widgetPositions: $widgetPositions) {
          id
          yaml
        }
      }
    """
    
    variables = { pageId, widgetPositions }
    { AuthHelper } = require './auth.setup'
    auth = new AuthHelper()
    
    result = await auth.makeGraphQLRequest page, query, variables
    
    console.log "✅ Reordered widgets in page #{pageId}"
    return result.reorderWidgets

  # Get widget positions from page DOM
  getWidgetPositions: ({page, pageId}) ->
    await page.goto "/#!pages/#{pageId}"
    
    positions = await page.evaluate ->
      widgets = document.querySelectorAll '[data-widget-id]'
      Array.from(widgets).map (widget, index) ->
        {
          widgetId: widget.getAttribute('data-widget-id')
          index: index + 1
        }
    
    console.log "📍 Retrieved #{positions.length} widget positions from page #{pageId}"
    return positions

  # Verify widget exists in page
  verifyWidgetExists: ({page, pageId, widgetTitle}) ->
    await page.goto "/#!pages/#{pageId}"
    
    try
      await page.waitForSelector "[data-widget-title=\"#{widgetTitle}\"]", timeout: 5000
      console.log "✅ Verified widget exists: #{widgetTitle}"
      return true
    catch error
      console.log "❌ Widget not found: #{widgetTitle}"
      return false

  # Verify YAML structure is valid
  verifyYAMLStructure: ({yamlContent}) ->
    try
      # Basic YAML structure validation
      lines = yamlContent.split('\n')
      hasLayout = lines.some (line) -> line.trim().startsWith('layout:')
      hasDirection = lines.some (line) -> line.trim().startsWith('direction:')
      hasChildren = lines.some (line) -> line.trim().startsWith('children:')
      
      isValid = hasLayout and hasDirection and hasChildren
      
      console.log "🔍 YAML structure validation: #{if isValid then '✅ Valid' else '❌ Invalid'}"
      return isValid
    catch error
      console.log "❌ YAML validation error:", error.message
      return false

  # Delete page
  deletePage: ({page, pageId}) ->
    await page.goto "/#!pages/#{pageId}"
    
    # Click delete button
    await page.click '[data-testid="delete-page-button"]'
    
    # Confirm deletion in modal
    await page.click '[data-testid="confirm-delete-button"]'
    
    # Wait for success message
    await page.waitForSelector '[data-testid="page-deleted-success"]'
    
    # Remove from created pages tracking
    @createdPages = @createdPages.filter (p) -> p.id != pageId
    
    console.log "✅ Deleted page: #{pageId}"

  # Delete page via GraphQL API
  deletePageGraphQL: ({page, pageId}) ->
    query = """
      mutation DeleteCustomView($id: ID!) {
        deleteCustomView(id: $id)
      }
    """
    
    variables = { id: pageId }
    { AuthHelper } = require './auth.setup'
    auth = new AuthHelper()
    
    await auth.makeGraphQLRequest page, query, variables
    
    # Remove from created pages tracking
    @createdPages = @createdPages.filter (p) -> p.id != pageId
    
    console.log "✅ Deleted page via GraphQL: #{pageId}"

  # Clean up all created pages
  cleanup: ({page}) ->
    console.log "🧹 Cleaning up #{@createdPages.length} test pages..."
    
    for pageData in @createdPages
      try
        await @deletePageGraphQL page, pageData.id
      catch error
        console.warn "⚠️ Failed to delete page #{pageData.name}: #{error.message}"
    
    @createdPages = []
    console.log "✅ All test pages cleaned up"

module.exports = { PagesHelper }
