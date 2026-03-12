# tests/js/test_relation_display_frontend.coffee
# Static frontend tests (Node) for relation display.

fs = require 'fs'
path = require 'path'
{ describe, it, assert, summary } = require './runner'

root = path.resolve __dirname, '../..'
appSource = fs.readFileSync path.join(root, 'frontend/src/app.coffee'), 'utf8'
helpersSource = fs.readFileSync path.join(root, 'frontend/src/app_fields_helpers.coffee'), 'utf8'
dataViewSource = fs.readFileSync path.join(root, 'frontend/src/views/data_view.coffee'), 'utf8'

describe "Relation display frontend", ->
  it "renders relation badge with arrow", ->
    relationBadgePattern = /badge\.textContent\s*=\s*"→ #\{targetName\}"/
    relationTitlePattern = /badge\.title\s*=\s*"Relation vers #\{targetName\}"/
    assert relationBadgePattern.test(appSource) or relationBadgePattern.test(helpersSource), "missing relation badge format"
    assert relationTitlePattern.test(appSource) or relationTitlePattern.test(helpersSource), "missing relation tooltip"

  it "uses _repr to display FK values in grid", ->
    assert /row\["_repr_#\{fieldName\}"\]\?/.test(dataViewSource), "missing relation _repr"
    assert /displayVal\s*=\s*row\["_repr_#\{fieldName\}"\]/.test(dataViewSource), "missing _repr displayVal fallback"
    assert /fkMap\[String val\]/.test(dataViewSource), "missing fkMap lookup"

summary()
