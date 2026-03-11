local execute_mutation, execute_query
do
  local _obj_0 = require('tests.runner')
  execute_mutation, execute_query = _obj_0.execute_mutation, _obj_0.execute_query
end
return describe("Relation integration test", function()
  before_each(function()
    local spaces = require('core.spaces')
    local all_spaces = spaces.list_spaces()
    for _index_0 = 1, #all_spaces do
      local space = all_spaces[_index_0]
      if space.name:match('^test_rel_int_') then
        spaces.delete_user_space(space.id)
      end
    end
  end)
  it("should create relation and verify frontend display format", function()
    local source_result = execute_mutation([[      mutation {
        createSpace(input: { name: "test_rel_int_source", description: "Source" }) { id name }
      }
    ]], { })
    local source_id = source_result.createSpace.id
    local target_result = execute_mutation([[      mutation {
        createSpace(input: { name: "test_rel_int_target", description: "Target" }) { id name }
      }
    ]], { })
    local target_id = target_result.createSpace.id
    execute_mutation([[      mutation AddTargetFields($spaceId: ID!) {
        f1: addField(spaceId: $spaceId, input: { name: "id", fieldType: Sequence, notNull: true, description: "ID" }) { id }
        f2: addField(spaceId: $spaceId, input: { name: "label", fieldType: String, notNull: true, description: "Label" }) { id }
      }
    ]], {
      spaceId = target_id
    })
    execute_mutation([[      mutation AddSourceFields($spaceId: ID!) {
        f1: addField(spaceId: $spaceId, input: { name: "id", fieldType: Sequence, notNull: true, description: "ID" }) { id }
        f2: addField(spaceId: $spaceId, input: { name: "relation", fieldType: Int, description: "Relation" }) { id }
      }
    ]], {
      spaceId = source_id
    })
    local source_fields = execute_mutation([[      mutation {
        space(id: $spaceId) { fields { id name } }
      }
    ]], {
      spaceId = source_id
    })
    local target_fields = execute_mutation([[      mutation {
        space(id: $spaceId) { fields { id name } }
      }
    ]], {
      spaceId = target_id
    })
    local relation_field = source_fields.data.space.fields[2].id
    local target_id_field = target_fields.data.space.fields[1].id
    execute_mutation([[      mutation CreateRelation($sourceId: ID!, $fieldId: ID!, $targetId: ID!, $targetFieldId: ID!) {
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
      sourceId = source_id,
      fieldId = relation_field,
      targetId = target_id,
      targetFieldId = target_id_field
    })
    local relations_result = execute_mutation([[      mutation GetRelations($spaceId: ID!) {
        relations(spaceId: $spaceId) { id name fromSpaceId fromFieldId toSpaceId toFieldId reprFormula }
      }
    ]], {
      spaceId = source_id
    })
    assert(relations_result.data.relations, "Should have relations")
    assert(#relations_result.data.relations == 1, "Should have exactly one relation")
    local rel = relations_result.data.relations[1]
    assert(rel.name == "test_rel", "Relation name should match")
    local expected_display = "→ test_rel_int_target"
    return assert(expected_display:match("^→"), "Should display arrow format")
  end)
  return after_each(function()
    local spaces = require('core.spaces')
    local all_spaces = spaces.list_spaces()
    for _index_0 = 1, #all_spaces do
      local space = all_spaces[_index_0]
      if space.name:match('^test_rel_int_') then
        spaces.delete_user_space(space.id)
      end
    end
  end)
end)
