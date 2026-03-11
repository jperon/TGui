-- tests/test_relation_type_regression.moon
-- Test spécifique pour empêcher la régression du type Relation

import execute_mutation from require 'tests.runner'

describe "Regression: Relation type should not exist", ->
  it "should reject Relation field type in addField", ->
    -- Créer un espace de test
    space_result = execute_mutation [[
      mutation {
        createSpace(input: { name: "test_relation_regression", description: "Test space" }) { id name }
      }
    ]], {}
    space_id = space_result.createSpace.id

    -- Essayer de créer un champ avec le type "Relation"
    result = execute_mutation [[
      mutation {
        addField(spaceId: $spaceId, input: { name: "bad_field", fieldType: "Relation", description: "Should fail" }) { id }
      }
    ]], { spaceId: space_id }

    -- Doit échouer
    assert result.errors, "Should have errors"
    assert result.errors[1].message\match("Type de champ invalide"), "Should mention invalid type"

  it "should work with Int field type + createRelation", ->
    -- Créer deux espaces
    source_result = execute_mutation [[
      mutation {
        createSpace(input: { name: "test_source", description: "Source" }) { id name }
      }
    ]], {}
    source_id = source_result.createSpace.id

    target_result = execute_mutation [[
      mutation {
        createSpace(input: { name: "test_target", description: "Target" }) { id name }
      }
    ]], {}
    target_id = target_result.createSpace.id

    -- 1. Créer un champ Int (correct)
    field_result = execute_mutation [[
      mutation {
        addField(spaceId: $spaceId, input: { name: "relation_field", fieldType: Int, description: "Relation field" }) { id name }
      }
    ]], { spaceId: source_id }
    
    assert field_result.data.addField, "Should create Int field"
    field_id = field_result.data.addField.id

    -- 2. Créer la relation (correct)
    relation_result = execute_mutation [[
      mutation {
        createRelation(input: {
          name: "test_relation"
          fromSpaceId: $sourceId
          fromFieldId: $fieldId
          toSpaceId: $targetId
          toFieldId: "id"
          reprFormula: "#{@name}"
        }) { id name }
      }
    ]], { sourceId: source_id, fieldId: field_id, targetId: target_id }

    assert relation_result.data.createRelation, "Should create relation"

  after_each ->
    -- Nettoyer
    spaces = require 'core.spaces'
    all_spaces = spaces.list_spaces!
    for space in *all_spaces
      if space.name\match '^test_relation_regression' or space.name\match '^test_source' or space.name\match '^test_target'
        spaces.delete_user_space space.id
