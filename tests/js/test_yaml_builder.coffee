# tests/js/test_yaml_builder.coffee — tests for YamlBuilder (yaml_builder.js)
# Covers YAML generation, field click, header click (aggregate), badges, dependencies.

require './dom_stub'
{ describe, it, eq, deepEq, assert, summary } = require './runner'

# --- stubs ------------------------------------------------------------------
global.jsyaml =
  dump: (obj) -> JSON.stringify obj   # simplifies comparisons
  load: (src) ->
    # Minimal YAML-as-JSON stub: supports JSON and simple key: value
    try JSON.parse src catch e then {}

# Load module under test (exposes window.YamlBuilder)
require '../../frontend/src/yaml_builder'
YB = global.window.YamlBuilder

# --- helpers ----------------------------------------------------------------
makeSpaces = ->
  [
    { id: 'sp1', name: 'personnes', fields: [
        { id: 'f_nom',    name: 'nom',    fieldType: 'String' }
        { id: 'f_prenom', name: 'prenom', fieldType: 'String' }
        { id: 'f_age',    name: 'age',    fieldType: 'Int' }
    ]}
    { id: 'sp2', name: 'commandes', fields: [
        { id: 'f_client', name: 'client_id', fieldType: 'Int' }
        { id: 'f_total',  name: 'total',     fieldType: 'Int' }
    ]}
  ]

makeRelations = ->
  [{ id: 'r1', fromSpaceId: 'sp2', fromFieldId: 'f_client', toSpaceId: 'sp1', toFieldId: 'f_nom' }]

makeContainer = -> global.document.createElement 'div'

makeYB = (opts = {}) ->
  yb = new YB
    container:    makeContainer()
    allSpaces:    opts.spaces    or makeSpaces()
    allRelations: opts.relations or []
    initialYaml:  opts.initialYaml or null
    onChange:     opts.onChange  or ->
  yb._render = ->   # no-op: state-only tests, no SVG DOM assertions
  yb

# --- YamlBuilder: initial state ----------------------------------------------
describe 'YamlBuilder — initial', ->
  it 'no widgets on startup', ->
    yb = makeYB()
    eq yb._widgets.length, 0

  it 'empty toYaml() returns skeleton', ->
    yb = makeYB()
    yaml = yb.toYaml()
    assert yaml.indexOf('layout') != -1, 'contains layout'
    assert yaml.indexOf('children') != -1, 'contains children'

# --- YamlBuilder: field click ------------------------------------------------
describe 'YamlBuilder — field click', ->
  it 'adding a field creates a regular widget', ->
    yb = makeYB()
    yb._onFieldClick 'sp1', 'nom'
    eq yb._widgets.length, 1
    eq yb._widgets[0].spaceName, 'personnes'
    eq yb._widgets[0].columns.length, 1
    eq yb._widgets[0].columns[0], 'nom'

  it 'clicking * creates a widget without column restriction', ->
    yb = makeYB()
    yb._onFieldClick 'sp1', '*'
    eq yb._widgets[0].columns.length, 0
    assert yb._widgets[0].type != 'aggregate', 'regular widget, not aggregate'

  it 'clicking * again in all-columns mode removes widget', ->
    yb = makeYB()
    yb._onFieldClick 'sp1', '*'
    yb._onFieldClick 'sp1', '*'
    eq yb._widgets.length, 0

  it 'clicking same field again removes it', ->
    yb = makeYB()
    yb._onFieldClick 'sp1', 'nom'
    yb._onFieldClick 'sp1', 'nom'
    eq yb._widgets.length, 0

  it 'multiple fields in same widget', ->
    yb = makeYB()
    yb._onFieldClick 'sp1', 'nom'
    yb._onFieldClick 'sp1', 'age'
    eq yb._widgets.length, 1
    eq yb._widgets[0].columns.length, 2

# --- YamlBuilder: header click (aggregate) -----------------------------------
describe 'YamlBuilder — header click (aggregate)', ->
  it 'creates an aggregate widget', ->
    yb = makeYB()
    yb._onHeaderClick 'sp1'
    eq yb._widgets.length, 1
    eq yb._widgets[0].type, 'aggregate'
    eq yb._widgets[0].spaceName, 'personnes'

  it 'groupBy contains all fields (no FK for sp1)', ->
    yb = makeYB()
    yb._onHeaderClick 'sp1'
    deepEq yb._widgets[0].groupBy, ['age', 'nom', 'prenom']   # alphabetical

  it 'groupBy excludes FK fields', ->
    yb = makeYB spaces: makeSpaces(), relations: makeRelations()
    yb._onHeaderClick 'sp2'
    # client_id is FK -> excluded; only total remains
    deepEq yb._widgets[0].groupBy, ['total']

  it 'second header click removes aggregate widget', ->
    yb = makeYB()
    yb._onHeaderClick 'sp1'
    yb._onHeaderClick 'sp1'
    eq yb._widgets.length, 0

  it 'aggregate and regular widgets can coexist', ->
    yb = makeYB()
    yb._onHeaderClick 'sp1'     # aggregate
    yb._onFieldClick  'sp2', 'total'   # regular
    eq yb._widgets.length, 2
    eq (yb._widgets.filter (w) -> w.type == 'aggregate').length, 1
    eq (yb._widgets.filter (w) -> w.type != 'aggregate').length, 1

  it '_widgetForSpace ignores aggregate widgets', ->
    yb = makeYB()
    yb._onHeaderClick 'sp1'
    assert !yb._widgetForSpace('sp1'), 'no regular widget for sp1'
    assert yb._aggWidgetForSpace('sp1'), 'aggregate widget present'

# --- YamlBuilder: toYaml with aggregate --------------------------------------
describe 'YamlBuilder — toYaml aggregate', ->
  it 'generates type:aggregate with groupBy', ->
    yb = makeYB()
    yb._onHeaderClick 'sp1'
    parsed = JSON.parse yb.toYaml()
    wObj = parsed.layout.children[0].widget
    eq wObj.type, 'aggregate'
    eq wObj.space, 'personnes'
    assert Array.isArray(wObj.groupBy), 'groupBy is an array'
    assert wObj.aggregate?.length > 0, 'aggregate has at least one entry'
    eq wObj.aggregate[0].fn, 'count'

  it 'generates regular widget correctly when aggregate is present', ->
    yb = makeYB()
    yb._onHeaderClick 'sp1'
    yb._onFieldClick  'sp2', 'total'
    parsed = JSON.parse yb.toYaml()
    eq parsed.layout.children.length, 2
    types = parsed.layout.children.map (c) -> c.widget.type
    assert 'aggregate' in types, 'aggregate present'

# --- YamlBuilder: automatic depends_on ---------------------------------------
describe 'YamlBuilder — depends_on', ->
  it 'detects FK and generates depends_on', ->
    yb = makeYB spaces: makeSpaces(), relations: makeRelations()
    yb._onFieldClick 'sp1', 'nom'    # parent
    yb._onFieldClick 'sp2', 'total'  # child (has FK to sp1)
    child = yb._widgets[1]
    assert child.dependsOn?, 'depends_on detected'
    eq child.dependsOn.field, 'client_id'

# Helper: build a JSON-YAML string (our stub parses JSON)
yamlFromObj = (obj) -> JSON.stringify obj

# --- YamlBuilder: hydration from existing YAML -------------------------------
describe 'YamlBuilder — _loadFromYaml (initialYaml)', ->
  it 'loads a regular widget', ->
    yaml = yamlFromObj
      layout:
        children: [{ widget: { id: 'w1', space: 'personnes', columns: ['nom'] } }]
    yb = makeYB initialYaml: yaml
    eq yb._widgets.length, 1
    eq yb._widgets[0].spaceName, 'personnes'
    deepEq yb._widgets[0].columns, ['nom']
    eq yb._widgets[0].id, 'w1'

  it 'loads an aggregate widget', ->
    yaml = yamlFromObj
      layout:
        children: [{ widget: { type: 'aggregate', space: 'commandes', groupBy: ['total'] } }]
    yb = makeYB initialYaml: yaml
    eq yb._widgets.length, 1
    eq yb._widgets[0].type, 'aggregate'
    eq yb._widgets[0].spaceName, 'commandes'
    deepEq yb._widgets[0].groupBy, ['total']

  it 'loads depends_on', ->
    yaml = yamlFromObj
      layout:
        children: [
          { widget: { id: 'p', space: 'personnes', columns: ['nom'] } }
          { widget: { space: 'commandes', depends_on: { widget: 'p', field: 'client_id', from_field: 'id' } } }
        ]
    yb = makeYB initialYaml: yaml
    eq yb._widgets.length, 2
    dep = yb._widgets[1].dependsOn
    assert dep?, 'depends_on present'
    eq dep.widgetId, 'p'
    eq dep.field, 'client_id'

  it 'ignores unknown spaces', ->
    yaml = yamlFromObj
      layout:
        children: [{ widget: { space: 'unknown' } }]
    yb = makeYB initialYaml: yaml
    eq yb._widgets.length, 0

  it 'does not duplicate when clicking already-loaded space', ->
    yaml = yamlFromObj
      layout:
        children: [{ widget: { space: 'personnes', columns: ['nom'] } }]
    yb = makeYB initialYaml: yaml
    # Clicking another field should ADD to existing widget, not create a new one
    yb._onFieldClick 'sp1', 'age'
    eq yb._widgets.length, 1
    assert 'age' in yb._widgets[0].columns, 'age added'

  it 'reloadFromYaml resets and re-hydrates state', ->
    yb = makeYB()
    yb._onFieldClick 'sp1', 'nom'
    eq yb._widgets.length, 1
    # Now reload with a different YAML
    newYaml = yamlFromObj
      layout:
        children: [{ widget: { type: 'aggregate', space: 'commandes', groupBy: ['total'] } }]
    yb.reloadFromYaml newYaml
    eq yb._widgets.length, 1
    eq yb._widgets[0].type, 'aggregate'

summary()
