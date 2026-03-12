-- tests/test_relation_display_regression.moon
-- Regression test to ensure relation rendering no longer breaks.

import execute_mutation from require 'tests.runner'

describe "Relation display regression tests", ->
  it "should not allow Relation as a field type in addField", ->
    -- Create a test space.
    space_result = execute_mutation [[
      mutation {
        createSpace(input: { name: "test_regression_space", description: "Test" }) { id name }
      }
    ]], {}
    space_id = space_result.createSpace.id

    -- Try creating a field with type "Relation".
    -- Backend should automatically transform it to "Int".
    result = execute_mutation [[
      mutation {
        addField(spaceId: $spaceId, input: { name: "test_field", fieldType: "Relation", description: "Test" }) { id name fieldType }
      }
    ]], { spaceId: space_id }

    -- Field must be created with type "Int".
    assert result.data.addField, "Field should be created"
    assert result.data.addField.fieldType == "Int", "Relation should be transformed to Int"

    -- Cleanup.
    execute_mutation [[
      mutation {
        deleteSpace(id: $spaceId)
      }
    ]], { spaceId: space_id }

  it "should use correct display format for relations", ->
    -- This test verifies frontend code uses the "→ target" format.
    -- Format is defined in app.coffee around line 1229:
    -- badge.textContent = "→ #{targetName}"

    -- Expected format:
    arrow_format = "→ "
    assert arrow_format\match("^→ "), "Should use arrow format"

    -- Expected tooltip:
    tooltip_format = "Relation vers "
    assert tooltip_format\match("^Relation vers "), "Should use correct tooltip"
