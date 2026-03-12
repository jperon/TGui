-- tests/test_relation_field.moon
-- Ensures Relation type is not used directly and UI follows the correct mutation flow.

import execute_mutation, execute_query from require 'tests.runner'

describe "Relation field creation", ->
  before_each ->
    -- Cleanup test spaces.
    spaces = require 'core.spaces'
    all_spaces = spaces.list_spaces!
    for space in *all_spaces
      if space.name\match '^test_relation_'
        spaces.delete_user_space space.id

  it "should reject 'Relation' as a field type", ->
    -- Create a test space.
    space_result = execute_mutation [[
      mutation {
        createSpace(input: { name: "test_relation_space", description: "Test space" }) { id name }
      }
    ]], {}
    space_id = space_result.createSpace.id

    -- Try creating a field with type "Relation" (must fail).
    result = execute_mutation [[
      mutation AddInvalidField($spaceId: ID!) {
        addField(spaceId: $spaceId, input: { name: "test_field", fieldType: "Relation", description: "Test field" }) { id }
      }
    ]], { spaceId: space_id }

    -- Verify it fails with "invalid field type".
    assert result.errors, "Should have errors when using Relation type"
    error_message = result.errors[1].message
    assert error_message\match("Type de champ invalide"), "Error should mention invalid field type"
    assert error_message\match("Relation"), "Error should mention Relation type"

  it "should create relation field using correct approach", ->
    -- Create two test spaces.
    source_result = execute_mutation [[
      mutation {
        createSpace(input: { name: "test_relation_source", description: "Source space" }) { id name }
      }
    ]], {}
    source_space_id = source_result.createSpace.id

    target_result = execute_mutation [[
      mutation {
        createSpace(input: { name: "test_relation_target", description: "Target space" }) { id name }
      }
    ]], {}
    target_space_id = target_result.createSpace.id

    -- 1) Create an Int field in the source space.
    field_result = execute_mutation [[
      mutation AddIntField($spaceId: ID!) {
        addField(spaceId: $spaceId, input: { name: "relation_field", fieldType: Int, description: "Relation field" }) { id name }
      }
    ]], { spaceId: source_space_id }

    assert field_result.data.addField, "Should create Int field successfully"
    field_id = field_result.data.addField.id

    -- 2) Create relation with createRelation.
    relation_result = execute_mutation [[
      mutation CreateRelation($sourceSpaceId: ID!, $fieldId: ID!, $targetSpaceId: ID!) {
        createRelation(input: {
          name: "test_relation"
          fromSpaceId: $sourceSpaceId
          fromFieldId: $fieldId
          toSpaceId: $targetSpaceId
          toFieldId: "id"  # Use default ID field
          reprFormula: "#{@name}"
        }) { id name }
      }
    ]], {
      sourceSpaceId: source_space_id,
      fieldId: field_id,
      targetSpaceId: target_space_id
    }

    assert relation_result.data.createRelation, "Should create relation successfully"
    assert relation_result.data.createRelation.name == "test_relation", "Relation should have correct name"

  after_each ->
    -- Cleanup test spaces.
    spaces = require 'core.spaces'
    all_spaces = spaces.list_spaces!
    for space in *all_spaces
      if space.name\match '^test_relation_'
        spaces.delete_user_space space.id
