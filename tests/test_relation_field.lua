local execute_mutation, execute_query
do
  local _obj_0 = require('tests.runner')
  execute_mutation, execute_query = _obj_0.execute_mutation, _obj_0.execute_query
end
return describe("Relation field creation", function()
  before_each(function()
    local spaces = require('core.spaces')
    local all_spaces = spaces.list_spaces()
    for _index_0 = 1, #all_spaces do
      local space = all_spaces[_index_0]
      if space.name:match('^test_relation_') then
        spaces.delete_user_space(space.id)
      end
    end
  end)
  it("should reject 'Relation' as a field type", function()
    local space_result = execute_mutation([[      mutation {
        createSpace(input: { name: "test_relation_space", description: "Test space" }) { id name }
      }
    ]], { })
    local space_id = space_result.createSpace.id
    local result = execute_mutation([[      mutation AddInvalidField($spaceId: ID!) {
        addField(spaceId: $spaceId, input: { name: "test_field", fieldType: "Relation", description: "Test field" }) { id }
      }
    ]], {
      spaceId = space_id
    })
    assert(result.errors, "Should have errors when using Relation type")
    local error_message = result.errors[1].message
    assert(error_message:match("Type de champ invalide"), "Error should mention invalid field type")
    return assert(error_message:match("Relation"), "Error should mention Relation type")
  end)
  it("should create relation field using correct approach", function()
    local source_result = execute_mutation([[      mutation {
        createSpace(input: { name: "test_relation_source", description: "Source space" }) { id name }
      }
    ]], { })
    local source_space_id = source_result.createSpace.id
    local target_result = execute_mutation([[      mutation {
        createSpace(input: { name: "test_relation_target", description: "Target space" }) { id name }
      }
    ]], { })
    local target_space_id = target_result.createSpace.id
    local field_result = execute_mutation([[      mutation AddIntField($spaceId: ID!) {
        addField(spaceId: $spaceId, input: { name: "relation_field", fieldType: Int, description: "Relation field" }) { id name }
      }
    ]], {
      spaceId = source_space_id
    })
    assert(field_result.data.addField, "Should create Int field successfully")
    local field_id = field_result.data.addField.id
    local relation_result = execute_mutation([[      mutation CreateRelation($sourceSpaceId: ID!, $fieldId: ID!, $targetSpaceId: ID!) {
        createRelation(input: {
          name: "test_relation"
          fromSpaceId: $sourceSpaceId
          fromFieldId: $fieldId
          toSpaceId: $targetSpaceId
          toFieldId: "id"  # Utiliser l'ID par défaut
          reprFormula: "#{@name}"
        }) { id name }
      }
    ]], {
      sourceSpaceId = source_space_id,
      fieldId = field_id,
      targetSpaceId = target_space_id
    })
    assert(relation_result.data.createRelation, "Should create relation successfully")
    return assert(relation_result.data.createRelation.name == "test_relation", "Relation should have correct name")
  end)
  return after_each(function()
    local spaces = require('core.spaces')
    local all_spaces = spaces.list_spaces()
    for _index_0 = 1, #all_spaces do
      local space = all_spaces[_index_0]
      if space.name:match('^test_relation_') then
        spaces.delete_user_space(space.id)
      end
    end
  end)
end)
