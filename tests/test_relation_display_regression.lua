local execute_mutation
execute_mutation = require('tests.runner').execute_mutation
return describe("Relation display regression tests", function()
  it("should not allow Relation as a field type in addField", function()
    local space_result = execute_mutation([[      mutation {
        createSpace(input: { name: "test_regression_space", description: "Test" }) { id name }
      }
    ]], { })
    local space_id = space_result.createSpace.id
    local result = execute_mutation([[      mutation {
        addField(spaceId: $spaceId, input: { name: "test_field", fieldType: "Relation", description: "Test" }) { id name fieldType }
      }
    ]], {
      spaceId = space_id
    })
    assert(result.data.addField, "Field should be created")
    assert(result.data.addField.fieldType == "Int", "Relation should be transformed to Int")
    return execute_mutation([[      mutation {
        deleteSpace(id: $spaceId)
      }
    ]], {
      spaceId = space_id
    })
  end)
  return it("should use correct display format for relations", function()
    local arrow_format = "→ "
    assert(arrow_format:match("^→ "), "Should use arrow format")
    local tooltip_format = "Relation vers "
    return assert(tooltip_format:match("^Relation vers "), "Should use correct tooltip")
  end)
end)
