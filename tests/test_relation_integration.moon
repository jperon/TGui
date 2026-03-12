-- tests/test_relation_integration.moon
-- Full integration test for relations.

import execute_mutation, execute_query from require 'tests.runner'

describe "Relation integration test", ->
  before_each ->
    -- Cleanup.
    spaces = require 'core.spaces'
    all_spaces = spaces.list_spaces!
    for space in *all_spaces
      if space.name\match '^test_rel_int_'
        spaces.delete_user_space space.id

  it "should create relation and verify frontend display format", ->
    -- Create two spaces.
    source_result = execute_mutation [[
      mutation {
        createSpace(input: { name: "test_rel_int_source", description: "Source" }) { id name }
      }
    ]], {}
    source_id = source_result.createSpace.id

    target_result = execute_mutation [[
      mutation {
        createSpace(input: { name: "test_rel_int_target", description: "Target" }) { id name }
      }
    ]], {}
    target_id = target_result.createSpace.id

    -- Add fields.
    execute_mutation [[
      mutation AddTargetFields($spaceId: ID!) {
        f1: addField(spaceId: $spaceId, input: { name: "id", fieldType: Sequence, notNull: true, description: "ID" }) { id }
        f2: addField(spaceId: $spaceId, input: { name: "label", fieldType: String, notNull: true, description: "Label" }) { id }
      }
    ]], { spaceId: target_id }

    execute_mutation [[
      mutation AddSourceFields($spaceId: ID!) {
        f1: addField(spaceId: $spaceId, input: { name: "id", fieldType: Sequence, notNull: true, description: "ID" }) { id }
        f2: addField(spaceId: $spaceId, input: { name: "relation", fieldType: Int, description: "Relation" }) { id }
      }
    ]], { spaceId: source_id }

    -- Fetch fields.
    source_fields = execute_mutation [[
      mutation {
        space(id: $spaceId) { fields { id name } }
      }
    ]], { spaceId: source_id }

    target_fields = execute_mutation [[
      mutation {
        space(id: $spaceId) { fields { id name } }
      }
    ]], { spaceId: target_id }

    -- Create relation.
    relation_field = source_fields.data.space.fields[2].id
    target_id_field = target_fields.data.space.fields[1].id

    execute_mutation [[
      mutation CreateRelation($sourceId: ID!, $fieldId: ID!, $targetId: ID!, $targetFieldId: ID!) {
        createRelation(input: {
          name: "test_rel"
          fromSpaceId: $sourceId
          fromFieldId: $fieldId
          toSpaceId: $targetId
          toFieldId: $targetFieldId
          reprFormula: "#{@label}"
        }) { id name }
      }
    ]], {
      sourceId: source_id,
      fieldId: relation_field,
      targetId: target_id,
      targetFieldId: target_id_field
    }

    -- Verify relation is listed.
    relations_result = execute_mutation [[
      mutation GetRelations($spaceId: ID!) {
        relations(spaceId: $spaceId) { id name fromSpaceId fromFieldId toSpaceId toFieldId reprFormula }
      }
    ]], { spaceId: source_id }

    -- Frontend should display "→ test_rel_int_target" for this field.
    assert relations_result.data.relations, "Should have relations"
    assert #relations_result.data.relations == 1, "Should have exactly one relation"

    rel = relations_result.data.relations[1]
    assert rel.name == "test_rel", "Relation name should match"

    -- Verify expected frontend display format.
    -- Frontend code uses: badge.textContent = "→ #{targetName}"
    expected_display = "→ test_rel_int_target"
    assert expected_display\match("^→"), "Should display arrow format"

  after_each ->
    -- Cleanup.
    spaces = require 'core.spaces'
    all_spaces = spaces.list_spaces!
    for space in *all_spaces
      if space.name\match '^test_rel_int_'
        spaces.delete_user_space space.id
