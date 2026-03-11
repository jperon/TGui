# tests/js/test_relation_display_frontend.coffee
# Tests statiques frontend (Node) pour l'affichage des relations.

fs = require 'fs'
path = require 'path'
{ describe, it, assert, summary } = require './runner'

root = path.resolve __dirname, '../..'
appSource = fs.readFileSync path.join(root, 'frontend/src/app.coffee'), 'utf8'
helpersSource = fs.readFileSync path.join(root, 'frontend/src/app_fields_helpers.coffee'), 'utf8'
dataViewSource = fs.readFileSync path.join(root, 'frontend/src/views/data_view.coffee'), 'utf8'

describe "Relation display frontend", ->
  it "affiche un badge de relation avec une flèche", ->
    relationBadgePattern = /badge\.textContent\s*=\s*"→ #\{targetName\}"/
    relationTitlePattern = /badge\.title\s*=\s*"Relation vers #\{targetName\}"/
    assert relationBadgePattern.test(appSource) or relationBadgePattern.test(helpersSource), "format relation badge manquant"
    assert relationTitlePattern.test(appSource) or relationTitlePattern.test(helpersSource), "tooltip relation manquant"

  it "utilise _repr pour afficher les FK dans la grille", ->
    assert /row\["_repr_#\{fieldName\}"\]\?/.test(dataViewSource), "_repr relation manquant"
    assert /displayVal\s*=\s*row\["_repr_#\{fieldName\}"\]/.test(dataViewSource), "fallback displayVal _repr manquant"
    assert /fkMap\[String val\]/.test(dataViewSource), "lookup fkMap manquant"

summary()
