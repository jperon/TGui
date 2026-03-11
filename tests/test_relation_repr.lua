local execute_mutation, execute_query
do
  local _obj_0 = require('tests.runner')
  execute_mutation, execute_query = _obj_0.execute_mutation, _obj_0.execute_query
end
return describe("Relation _repr display", function()
  before_each(function()
    local spaces = require('core.spaces')
    local all_spaces = spaces.list_spaces()
    for _index_0 = 1, #all_spaces do
      local space = all_spaces[_index_0]
      if space.name:match('^test_relation_repr_') then
        spaces.delete_user_space(space.id)
      end
    end
  end)
  it("should include _repr fields in records query", function()
    local source_result = execute_mutation([[      mutation {
        createSpace(input: { name: "test_relation_repr_source", description: "Source" }) { id name }
      }
    ]], { })
    local source_id = source_result.createSpace.id
    local target_result = execute_mutation([[      mutation {
        createSpace(input: { name: "test_relation_repr_target", description: "Target" }) { id name }
      }
    ]], { })
    local target_id = target_result.createSpace.id
    execute_mutation([[      mutation AddTargetFields($spaceId: ID!) {
        f1: addField(spaceId: $spaceId, input: { name: "id", fieldType: Sequence, notNull: true, description: "ID" }) { id }
        f2: addField(spaceId: $spaceId, input: { name: "nom", fieldType: String, notNull: true, description: "Nom" }) { id }
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
    local id_field = target_fields.data.space.fields[1].id
    execute_mutation([[      mutation CreateRelation($sourceId: ID!, $fieldId: ID!, $targetId: ID!, $targetFieldId: ID!) {
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
      sourceId = source_id,
      fieldId = relation_field,
      targetId = target_id,
      targetFieldId = id_field
    })
    execute_mutation([[      mutation InsertTarget($spaceId: ID!, $data: JSON!) {
        insertRecord(spaceId: $spaceId, data: $data) { id }
      }
    ]], {
      spaceId = target_id,
      data = {
        nom = "Test Item"
      }
    })
    execute_mutation([[      mutation InsertSource($spaceId: ID!, $data: JSON!) {
        insertRecord(spaceId: $spaceId, data: $data) { id }
      }
    ]], {
      spaceId = source_id,
      data = {
        relation = "1"
      }
    })
    local records_result = execute_mutation([[      mutation GetRecords($spaceId: ID!) {
        records(spaceId: $spaceId, limit: 10) {
          items {
            id
            data
          }
        }
      }
    ]], {
      spaceId = source_id
    })
    assert(records_result.data.records.items, "Should have records")
    local record = records_result.data.records.items[1]
    return assert(record, "Should have at least one record")
  end)
  return after_each(function()
    local spaces = require('core.spaces')
    local all_spaces = spaces.list_spaces()
    for _index_0 = 1, #all_spaces do
      local space = all_spaces[_index_0]
      if space.name:match('^test_relation_repr_') then
        spaces.delete_user_space(space.id)
      end
    end
  end)
end)
