-- tests/test_relation_field.moon
-- Test pour s'assurer que le type Relation n'existe pas et que l'UI utilise les bonnes mutations

import execute_mutation, execute_query from require 'tests.runner'

describe "Relation field creation", ->
  before_each ->
    -- Nettoyer les espaces de test
    spaces = require 'core.spaces'
    all_spaces = spaces.list_spaces!
    for space in *all_spaces
      if space.name\match '^test_relation_'
        spaces.delete_user_space space.id

  it "should reject 'Relation' as a field type", ->
    -- Créer un espace de test
    space_result = execute_mutation [[
      mutation {
        createSpace(input: { name: "test_relation_space", description: "Test space" }) { id name }
      }
    ]], {}
    space_id = space_result.createSpace.id

    -- Essayer de créer un champ avec le type "Relation" (doit échouer)
    result = execute_mutation [[
      mutation AddInvalidField($spaceId: ID!) {
        addField(spaceId: $spaceId, input: { name: "test_field", fieldType: "Relation", description: "Test field" }) { id }
      }
    ]], { spaceId: space_id }

    -- Vérifier que ça échoue avec "Type de champ invalide"
    assert result.errors, "Should have errors when using Relation type"
    error_message = result.errors[1].message
    assert error_message\match("Type de champ invalide"), "Error should mention invalid field type"
    assert error_message\match("Relation"), "Error should mention Relation type"

  it "should create relation field using correct approach", ->
    -- Créer deux espaces de test
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

    -- 1. Créer un champ de type Int dans l'espace source
    field_result = execute_mutation [[
      mutation AddIntField($spaceId: ID!) {
        addField(spaceId: $spaceId, input: { name: "relation_field", fieldType: Int, description: "Relation field" }) { id name }
      }
    ]], { spaceId: source_space_id }

    assert field_result.data.addField, "Should create Int field successfully"
    field_id = field_result.data.addField.id

    -- 2. Créer la relation avec createRelation
    relation_result = execute_mutation [[
      mutation CreateRelation($sourceSpaceId: ID!, $fieldId: ID!, $targetSpaceId: ID!) {
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
      sourceSpaceId: source_space_id,
      fieldId: field_id,
      targetSpaceId: target_space_id
    }

    assert relation_result.data.createRelation, "Should create relation successfully"
    assert relation_result.data.createRelation.name == "test_relation", "Relation should have correct name"

  after_each ->
    -- Nettoyer les espaces de test
    spaces = require 'core.spaces'
    all_spaces = spaces.list_spaces!
    for space in *all_spaces
      if space.name\match '^test_relation_'
        spaces.delete_user_space space.id
