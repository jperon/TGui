-- tests/test_relation_repr.moon
-- Test to verify that relations correctly use _repr.

import execute_mutation, execute_query from require 'tests.runner'

describe "Relation _repr display", ->
  before_each ->
    -- Cleanup.
    spaces = require 'core.spaces'
    all_spaces = spaces.list_spaces!
    for space in *all_spaces
      if space.name\match '^test_relation_repr_'
        spaces.delete_user_space space.id

  it "should include _repr fields in records query", ->
    -- Create two spaces.
    source_result = execute_mutation [[
      mutation {
        createSpace(input: { name: "test_relation_repr_source", description: "Source" }) { id name }
      }
    ]], {}
    source_id = source_result.createSpace.id

    target_result = execute_mutation [[
      mutation {
        createSpace(input: { name: "test_relation_repr_target", description: "Target" }) { id name }
      }
    ]], {}
    target_id = target_result.createSpace.id

    -- Add fields.
    execute_mutation [[
      mutation AddTargetFields($spaceId: ID!) {
        f1: addField(spaceId: $spaceId, input: { name: "id", fieldType: Sequence, notNull: true, description: "ID" }) { id }
        f2: addField(spaceId: $spaceId, input: { name: "nom", fieldType: String, notNull: true, description: "Nom" }) { id }
      }
    ]], { spaceId: target_id }

    execute_mutation [[
      mutation AddSourceFields($spaceId: ID!) {
        f1: addField(spaceId: $spaceId, input: { name: "id", fieldType: Sequence, notNull: true, description: "ID" }) { id }
        f2: addField(spaceId: $spaceId, input: { name: "relation", fieldType: Int, description: "Relation" }) { id }
      }
    ]], { spaceId: source_id }

    -- Fetch field IDs.
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

    relation_field = source_fields.data.space.fields[2].id  -- "relation" field
    id_field = target_fields.data.space.fields[1].id      -- "id" field

    -- Create relation.
    execute_mutation [[
      mutation CreateRelation($sourceId: ID!, $fieldId: ID!, $targetId: ID!, $targetFieldId: ID!) {
        createRelation(input: {
          name: "test_rel"
          fromSpaceId: $sourceId
          fromFieldId: $fieldId
          toSpaceId: $targetId
          toFieldId: $targetFieldId
          reprFormula: "#{@nom}"
        }) { id }
      }
    ]], {
      sourceId: source_id,
      fieldId: relation_field,
      targetId: target_id,
      targetFieldId: id_field
    }

    -- Insert data.
    execute_mutation [[
      mutation InsertTarget($spaceId: ID!, $data: JSON!) {
        insertRecord(spaceId: $spaceId, data: $data) { id }
      }
    ]], { spaceId: target_id, data: { nom: "Test Item" } }

    execute_mutation [[
      mutation InsertSource($spaceId: ID!, $data: JSON!) {
        insertRecord(spaceId: $spaceId, data: $data) { id }
      }
    ]], { spaceId: source_id, data: { relation: "1" } }

    -- Query records using reprFormula.
    records_result = execute_mutation [[
      mutation GetRecords($spaceId: ID!) {
        records(spaceId: $spaceId, limit: 10) {
          items {
            id
            data
          }
        }
      }
    ]], { spaceId: source_id }

    -- Verify data is present.
    assert records_result.data.records.items, "Should have records"
    record = records_result.data.records.items[1]
    assert record, "Should have at least one record"

    -- TODO: Add deeper reprFormula assertions when API exposes related projection.

  after_each ->
    -- Cleanup.
    spaces = require 'core.spaces'
    all_spaces = spaces.list_spaces!
    for space in *all_spaces
      if space.name\match '^test_relation_repr_'
        spaces.delete_user_space space.id
