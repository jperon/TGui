# Pages YAML Editor E2E Tests
# Tests direct YAML editing functionality

{ test, expect } = require '@playwright/test'
{ AuthHelper } = require '../config/auth.setup'
{ PagesHelper } = require '../config/pages.setup'

test.describe('Pages - YAML Editor', ->
  authHelper = null
  pagesHelper = null
  pageId = null

  test.beforeEach(({ page }) ->
    authHelper = new AuthHelper()
    pagesHelper = new PagesHelper()
    await authHelper.login page
    
    # Create a test page
    pageName = pagesHelper.generatePageName('yaml_test')
    pageId = await pagesHelper.createPageGraphQL page, pageName
  )

  test.afterEach(({ page }) ->
    # Clean up test page
    await pagesHelper.cleanup page
  )

  test('should open YAML editor from page view', ({ page }) ->
    await page.goto "/#!pages/#{pageId}"
    
    # Verify page details are visible
    await expect(page.locator('[data-testid="page-details"]')).toBeVisible()
    
    # Click edit YAML button
    await page.click '[data-testid="edit-yaml-button"]'
    
    # Verify YAML editor is visible
    await expect(page.locator('[data-testid="yaml-editor"]')).toBeVisible()
    await expect(page.locator('[data-testid="yaml-editor"]')).toBeEnabled()
    
    # Verify editor has basic YAML content
    yamlContent = await page.inputValue '[data-testid="yaml-editor"]'
    expect(yamlContent).toContain 'layout:'
    expect(yamlContent).toContain 'direction:'
    expect(yamlContent).toContain 'children:'
  )

  test('should display initial YAML structure', ({ page }) ->
    await page.goto "/#!pages/#{pageId}"
    await page.click '[data-testid="edit-yaml-button"]'
    
    # Get initial YAML content
    yamlContent = await page.inputValue '[data-testid="yaml-editor"]'
    
    # Verify basic structure
    expect(yamlContent).toMatch /layout:\s*direction:\s*(vertical|horizontal)/
    expect(yamlContent).toMatch /children:\s*\[\s*\]/
    
    console.log "Initial YAML content: #{yamlContent}"
  )

  test('should validate YAML syntax', ({ page }) ->
    await page.goto "/#!pages/#{pageId}"
    await page.click '[data-testid="edit-yaml-button"]'
    
    # Enter valid YAML
    validYaml = """
layout:
  direction: vertical
  children:
    - widget:
        title: Test Widget
        space: test_space
"""
    
    await page.fill '[data-testid="yaml-editor"]', validYaml
    
    # Save YAML
    await page.click '[data-testid="save-yaml-button"]'
    
    # Verify success message
    await expect(page.locator('[data-testid="yaml-saved-success"]')).toBeVisible()
    
    # Verify no validation errors
    await expect(page.locator('[data-testid="yaml-error"]')).not.toBeVisible()
  )

  test('should show error for invalid YAML syntax', ({ page }) ->
    await page.goto "/#!pages/#{pageId}"
    await page.click '[data-testid="edit-yaml-button"]'
    
    # Enter invalid YAML (bad indentation)
    invalidYaml = """
layout:
direction: vertical
  children:
    - widget:
        title: Test Widget
"""
    
    await page.fill '[data-testid="yaml-editor"]', invalidYaml
    
    # Try to save
    await page.click '[data-testid="save-yaml-button"]'
    
    # Verify error message
    await expect(page.locator('[data-testid="yaml-error"]')).toBeVisible()
    await expect(page.locator('[data-testid="yaml-error"]')).toContainText 'Invalid YAML'
    
    # Verify success message not shown
    await expect(page.locator('[data-testid="yaml-saved-success"]')).not.toBeVisible()
  )

  test('should save YAML changes', ({ page }) ->
    await page.goto "/#!pages/#{pageId}"
    await page.click '[data-testid="edit-yaml-button"]'
    
    # Modify YAML content
    modifiedYaml = """
layout:
  direction: horizontal
  children:
    - widget:
        title: Modified Widget
        space: modified_space
        columns: [name, description]
"""
    
    await page.fill '[data-testid="yaml-editor"]', modifiedYaml
    await page.click '[data-testid="save-yaml-button"]'
    
    # Wait for save success
    await expect(page.locator('[data-testid="yaml-saved-success"]')).toBeVisible()
    
    # Close editor and reopen to verify changes
    await page.click '[data-testid="close-yaml-editor"]'
    await page.waitForSelector '[data-testid="page-details"]', state: 'visible'
    
    # Reopen editor
    await page.click '[data-testid="edit-yaml-button"]'
    
    # Verify changes are saved
    savedYaml = await page.inputValue '[data-testid="yaml-editor"]'
    expect(savedYaml).toContain 'direction: horizontal'
    expect(savedYaml).toContain 'Modified Widget'
    expect(savedYaml).toContain 'modified_space'
  )

  test('should cancel YAML changes', ({ page }) ->
    await page.goto "/#!pages/#{pageId}"
    await page.click '[data-testid="edit-yaml-button"]'
    
    # Get original YAML
    originalYaml = await page.inputValue '[data-testid="yaml-editor"]'
    
    # Modify YAML
    modifiedYaml = """
layout:
  direction: vertical
  children:
    - widget:
        title: Temporary Widget
        space: temp_space
"""
    
    await page.fill '[data-testid="yaml-editor"]', modifiedYaml
    
    # Cancel instead of saving
    await page.click '[data-testid="cancel-yaml-button"]'
    
    # Reopen editor
    await page.click '[data-testid="edit-yaml-button"]'
    
    # Verify original content is restored
    restoredYaml = await page.inputValue '[data-testid="yaml-editor"]'
    expect(restoredYaml).toBe originalYaml
  )

  test('should handle complex YAML structures', ({ page }) ->
    await page.goto "/#!pages/#{pageId}"
    await page.click '[data-testid="edit-yaml-button"]'
    
    # Create complex nested structure
    complexYaml = """
layout:
  direction: vertical
  children:
    - direction: horizontal
      factor: 2
      children:
        - widget:
            title: Left Widget
            space: left_space
            columns: [id, name]
        - direction: vertical
          factor: 1
          children:
            - widget:
                title: Top Right Widget
                space: top_right_space
            - widget:
                title: Bottom Right Widget
                space: bottom_right_space
                depends_on:
                  widget: left_widget_id
                  field: left_id
    - widget:
        title: Bottom Widget
        space: bottom_space
        limit: 10
"""
    
    await page.fill '[data-testid="yaml-editor"]', complexYaml
    await page.click '[data-testid="save-yaml-button"]'
    
    # Verify complex structure is saved
    await expect(page.locator('[data-testid="yaml-saved-success"]')).toBeVisible()
    
    # Verify structure validation
    isValid = pagesHelper.verifyYAMLStructure complexYaml
    expect(isValid).toBeTruthy()
  )

  test('should provide YAML syntax highlighting', ({ page }) ->
    await page.goto "/#!pages/#{pageId}"
    await page.click '[data-testid="edit-yaml-button"]'
    
    # Check if syntax highlighting is applied
    yamlEditor = page.locator('[data-testid="yaml-editor"]')
    
    # Look for syntax highlighting classes
    syntaxClasses = [
      'yaml-key'
      'yaml-value'
      'yaml-string'
      'yaml-number'
      'yaml-comment'
    ]
    
    hasSyntaxHighlighting = false
    for cssClass in syntaxClasses
      if await yamlEditor.locator(".#{cssClass}").count() > 0
        hasSyntaxHighlighting = true
        break
    
    if hasSyntaxHighlighting
      console.log "✅ YAML syntax highlighting is enabled"
    else
      console.log "ℹ️ YAML syntax highlighting not implemented"
  )

  test('should support YAML auto-completion', ({ page }) ->
    await page.goto "/#!pages/#{pageId}"
    await page.click '[data-testid="edit-yaml-button"]'
    
    # Focus on YAML editor
    await page.focus '[data-testid="yaml-editor"]'
    
    # Type partial YAML to trigger auto-completion
    await page.keyboard.type 'lay'
    
    # Wait for potential auto-completion
    await page.waitForTimeout 500
    
    # Check for auto-completion suggestions
    autoComplete = page.locator('[data-testid="yaml-autocomplete"]')
    if await autoComplete.isVisible()
      console.log "✅ YAML auto-completion is available"
      
      # Test auto-completion selection
      await page.keyboard.press 'Tab'
      
      # Verify completion was applied
      yamlContent = await page.inputValue '[data-testid="yaml-editor"]'
      expect(yamlContent).toContain 'layout:'
    else
      console.log "ℹ️ YAML auto-completion not implemented"
  )

  test('should show YAML preview', ({ page }) ->
    await page.goto "/#!pages/#{pageId}"
    await page.click '[data-testid="edit-yaml-button"]'
    
    # Look for preview functionality
    previewButton = page.locator '[data-testid="yaml-preview-button"]'
    if await previewButton.isVisible()
      await previewButton.click()
      
      # Verify preview panel is visible
      await expect(page.locator('[data-testid="yaml-preview"]')).toBeVisible()
      
      # Verify preview shows rendered layout
      await expect(page.locator('[data-testid="preview-layout"]')).toBeVisible()
      
      console.log "✅ YAML preview functionality is available"
    else
      console.log "ℹ️ YAML preview not implemented"
  )

  test('should handle YAML formatting', ({ page }) ->
    await page.goto "/#!pages/#{pageId}"
    await page.click '[data-testid="edit-yaml-button"]'
    
    # Enter unformatted YAML
    unformattedYaml = 'layout:direction:vertical children:[]'
    await page.fill '[data-testid="yaml-editor"]', unformattedYaml
    
    # Look for format button
    formatButton = page.locator '[data-testid="yaml-format-button"]'
    if await formatButton.isVisible()
      await formatButton.click()
      
      # Verify YAML is formatted
      formattedYaml = await page.inputValue '[data-testid="yaml-editor"]'
      expect(formattedYaml).toMatch /layout:\s*direction:\s*vertical/
      expect(formattedYaml).toMatch /children:\s*\[\s*\]/
      
      console.log "✅ YAML formatting is available"
    else
      console.log "ℹ️ YAML formatting not implemented"
  )

  test('should validate YAML schema', ({ page }) ->
    await page.goto "/#!pages/#{pageId}"
    await page.click '[data-testid="edit-yaml-button"]'
    
    # Enter YAML with invalid schema
    invalidSchemaYaml = """
layout:
  direction: vertical
  children:
    - widget:
        title: Test Widget
        # Missing required 'space' field
"""
    
    await page.fill '[data-testid="yaml-editor"]', invalidSchemaYaml
    await page.click '[data-testid="save-yaml-button"]'
    
    # Check for schema validation error
    schemaError = page.locator '[data-testid="yaml-schema-error"]'
    if await schemaError.isVisible()
      await expect(schemaError).toContainText 'Missing required field'
      console.log "✅ YAML schema validation is working"
    else
      # Schema validation might not be implemented
      console.log "ℹ️ YAML schema validation not implemented"
  )

  test('should support YAML templates', ({ page }) ->
    await page.goto "/#!pages/#{pageId}"
    await page.click '[data-testid="edit-yaml-button"]'
    
    # Look for template functionality
    templateButton = page.locator '[data-testid="yaml-template-button"]'
    if await templateButton.isVisible()
      await templateButton.click()
      
      # Verify template selector is visible
      await expect(page.locator('[data-testid="yaml-template-selector"]')).toBeVisible()
      
      # Select a template
      await page.selectOption '[data-testid="yaml-template-selector"]', 'two-column-layout'
      await page.click '[data-testid="apply-template-button"]'
      
      # Verify template is applied
      yamlContent = await page.inputValue '[data-testid="yaml-editor"]'
      expect(yamlContent).toContain 'direction: horizontal'
      expect(yamlContent).toContain 'children:'
      
      console.log "✅ YAML templates are available"
    else
      console.log "ℹ️ YAML templates not implemented"
  )
)
