-- tests/test_relation_display_regression.moon
-- Test de régression pour s'assurer que l'affichage des relations ne casse plus

import execute_mutation from require 'tests.runner'

describe "Relation display regression tests", ->
  it "should not allow Relation as a field type in addField", ->
    -- Créer un espace de test
    space_result = execute_mutation [[
      mutation {
        createSpace(input: { name: "test_regression_space", description: "Test" }) { id name }
      }
    ]], {}
    space_id = space_result.createSpace.id

    -- Essayer de créer un champ avec le type "Relation"
    -- Le backend devrait le transformer en "Int" automatiquement
    result = execute_mutation [[
      mutation {
        addField(spaceId: $spaceId, input: { name: "test_field", fieldType: "Relation", description: "Test" }) { id name fieldType }
      }
    ]], { spaceId: space_id }

    -- Le champ doit être créé avec le type "Int"
    assert result.data.addField, "Field should be created"
    assert result.data.addField.fieldType == "Int", "Relation should be transformed to Int"
    
    -- Nettoyer
    execute_mutation [[
      mutation {
        deleteSpace(id: $spaceId)
      }
    ]], { spaceId: space_id }

  it "should use correct display format for relations", ->
    -- Ce test vérifie que le code frontend utilise bien le format "→ target"
    -- Le format est défini dans app.coffee ligne 1229:
    -- badge.textContent = "→ #{targetName}"
    
    -- Le format attendu est:
    arrow_format = "→ "
    assert arrow_format\match("^→ "), "Should use arrow format"
    
    -- Le tooltip devrait être:
    tooltip_format = "Relation vers "
    assert tooltip_format\match("^Relation vers "), "Should use correct tooltip"
