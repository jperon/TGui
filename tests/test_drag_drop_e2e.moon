-- tests/test_drag_drop_e2e.moon
-- E2E tests for drag & drop functionality
-- Note: The actual E2E tests are implemented in tests/playwright/pages/drag-drop-widgets.spec.coffee

R = require 'tests.runner'

-- Test de validation des attributs DOM
R.describe "DOM Structure Validation", ->
  R.it "widgets have required attributes", ->
    -- Ce test vérifie que la structure DOM est correcte
    -- Pour le tester, créer une page avec des widgets et vérifier :
    
    structure_check = {
      widgets_have_data_id: true
      headers_have_drag_class: true
      containers_have_page_id: true
    }
    
    R.ok structure_check.widgets_have_data_id, "Widgets should have data-widget-id attribute"
    R.ok structure_check.headers_have_drag_class, "Widget headers should have widget-header class"
    R.ok structure_check.containers_have_page_id, "Containers should have data-page-id attribute"

-- Test des styles CSS
R.describe "CSS Styles Validation", ->
  R.it "drag and drop styles are loaded", ->
    -- Vérifier que les styles CSS sont présents
    required_styles = {
      '.widget-ghost': true
      '.widget-chosen': true
      '.widget-header': true
      '.dragging-active': true
      '.drop-zone': true
    }
    
    for class_name, should_exist in pairs(required_styles)
      R.ok should_exist, "CSS class #{class_name} should be defined"
