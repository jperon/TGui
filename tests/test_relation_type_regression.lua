local execute_mutation
execute_mutation = require('tests.runner').execute_mutation
return describe("Regression: Relation type should not exist", function()
  it("should reject Relation field type in addField", function()
    local space_result = execute_mutation([[      mutation {
        createSpace(input: { name: "test_relation_regression", description: "Test space" }) { id name }
      }
    ]], { })
    local space_id = space_result.createSpace.id
    local result = execute_mutation([[      mutation {
        addField(spaceId: $spaceId, input: { name: "bad_field", fieldType: "Relation", description: "Should fail" }) { id }
      }
    ]], {
      spaceId = space_id
    })
    assert(result.errors, "Should have errors")
    return assert(result.errors[1].message:match("Type de champ invalide"), "Should mention invalid type")
  end)
  it("should work with Int field type + createRelation", function()
    local source_result = execute_mutation([[      mutation {
        createSpace(input: { name: "test_source", description: "Source" }) { id name }
      }
    ]], { })
    local source_id = source_result.createSpace.id
    local target_result = execute_mutation([[      mutation {
        createSpace(input: { name: "test_target", description: "Target" }) { id name }
      }
    ]], { })
    local target_id = target_result.createSpace.id
    local field_result = execute_mutation([[      mutation {
        addField(spaceId: $spaceId, input: { name: "relation_field", fieldType: Int, description: "Relation field" }) { id name }
      }
    ]], {
      spaceId = source_id
    })
    assert(field_result.data.addField, "Should create Int field")
    local field_id = field_result.data.addField.id
    local relation_result = execute_mutation([[      mutation {
        createRelation(input: {
          name: "test_relation"
          fromSpaceId: $sourceId
          fromFieldId: $fieldId
          toSpaceId: $targetId
          toFieldId: "id"
          reprFormula: "#{@name}"
        }) { id name }
      }
    ]], {
      sourceId = source_id,
      fieldId = field_id,
      targetId = target_id
    })
    return assert(relation_result.data.createRelation, "Should create relation")
  end)
  return after_each(function()
    local spaces = require('core.spaces')
    local all_spaces = spaces.list_spaces()
    for _index_0 = 1, #all_spaces do
      local space = all_spaces[_index_0]
      if space.name:match('^test_relation_regression' or space.name:match('^test_source' or space.name:match('^test_target'))) then
        spaces.delete_user_space(space.id)
      end
    end
  end)
end)
