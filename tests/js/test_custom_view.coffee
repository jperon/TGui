# tests/js/test_custom_view.coffee — tests for CustomView (custom_view.js)
# Covers: YAML parsing, generated DOM structure, flex factor, columns filtering, depends_on.

require './dom_stub'
{ describe, it, eq, deepEq, assert, summary } = require './runner'

# --- stubs ------------------------------------------------------------------
global.jsyaml =
  load: (src) -> JSON.parse src      # test YAML fixtures are valid JSON

global.DataView = class DataView
  constructor: (@container, @space) ->
    @_currentData = {}
    @mounted = false
  mount: -> @mounted = true
  refreshLayout: ->
  setFilter: ->
  setDefaultValues: ->
  deleteSelected: ->

# Load module under test (exposes window.CustomView)
require '../../frontend/src/views/custom_view'
CV = global.window.CustomView

# --- helpers ----------------------------------------------------------------
makeSpaces = ->
  [
    { id: '1', name: 'personnes', fields: [
        { id: 'f1', name: 'nom',  fieldType: 'Str' }
        { id: 'f2', name: 'age',  fieldType: 'Int' }
        { id: 'f3', name: 'ville',fieldType: 'Str' }
    ]}
    { id: '2', name: 'groupes', fields: [
        { id: 'g1', name: 'titre', fieldType: 'Str' }
        { id: 'g2', name: 'code',  fieldType: 'Str' }
    ]}
  ]

makeContainer = -> global.document.createElement 'div'

yamlJSON = (obj) -> JSON.stringify obj

# ---------------------------------------------------------------------------
describe 'CustomView — layout vertical simple', ->
  it 'mounts a widget without error', ->
    layout = { layout: { widget: { id: 'w1', title: 'Gens', space: 'personnes' } } }
    cv = new CV makeContainer(), yamlJSON(layout), makeSpaces()
    cv.mount()
    eq cv._widgets.length, 1
    assert cv._widgets[0].dataView.mounted, 'DataView should be mounted'

  it '_widgetsById indexed by id', ->
    layout = { layout: { widget: { id: 'mon_widget', space: 'personnes' } } }
    cv = new CV makeContainer(), yamlJSON(layout), makeSpaces()
    cv.mount()
    assert cv._widgetsById['mon_widget']?, 'index by id'

  it 'unknown space -> dataView null', ->
    layout = { layout: { widget: { space: 'unknown' } } }
    cv = new CV makeContainer(), yamlJSON(layout), makeSpaces()
    cv.mount()
    eq cv._widgets[0].dataView, null

describe 'CustomView — zone with children', ->
  it 'creates one child per child widget', ->
    layout =
      layout:
        direction: 'horizontal'
        children: [
          { widget: { space: 'personnes' } }
          { widget: { space: 'groupes'   } }
        ]
    cv = new CV makeContainer(), yamlJSON(layout), makeSpaces()
    cv.mount()
    eq cv._widgets.length, 2

describe 'CustomView — factor', ->
  it 'applies factor as flex', ->
    layout =
      layout:
        direction: 'vertical'
        children: [
          { factor: 3, widget: { space: 'personnes' } }
          { factor: 1, widget: { space: 'groupes'   } }
        ]
    cv = new CV makeContainer(), yamlJSON(layout), makeSpaces()
    cv.mount()
    # Main container flex is set by _renderZoneOrWidget (root node)
    # Child nodes keep their own flex values
    entries = cv._widgets
    eq entries[0].el.style.flex, '3'
    eq entries[1].el.style.flex, '1'

  it 'missing factor -> default flex "1"', ->
    layout = { layout: { widget: { space: 'personnes' } } }
    cv = new CV makeContainer(), yamlJSON(layout), makeSpaces()
    cv.mount()
    eq cv._widgets[0].el.style.flex, '1'

describe 'CustomView — columns', ->
  it 'filters specified columns', ->
    layout = { layout: { widget: { space: 'personnes', columns: ['age', 'nom'] } } }
    cv = new CV makeContainer(), yamlJSON(layout), makeSpaces()
    cv.mount()
    dv = cv._widgets[0].dataView
    eq dv.space.fields.length, 2
    eq dv.space.fields[0].name, 'age'
    eq dv.space.fields[1].name, 'nom'

  it 'silently ignores unknown columns', ->
    layout = { layout: { widget: { space: 'personnes', columns: ['nom', 'inconnu'] } } }
    cv = new CV makeContainer(), yamlJSON(layout), makeSpaces()
    cv.mount()
    eq cv._widgets[0].dataView.space.fields.length, 1
    eq cv._widgets[0].dataView.space.fields[0].name, 'nom'

  it 'without columns -> all fields', ->
    layout = { layout: { widget: { space: 'personnes' } } }
    cv = new CV makeContainer(), yamlJSON(layout), makeSpaces()
    cv.mount()
    eq cv._widgets[0].dataView.space.fields.length, 3

  it 'does not mutate original space object (clone)', ->
    spaces = makeSpaces()
    layout = { layout: { widget: { space: 'personnes', columns: ['nom'] } } }
    cv = new CV makeContainer(), yamlJSON(layout), spaces
    cv.mount()
    eq spaces[0].fields.length, 3  # original unchanged

describe 'CustomView — invalid YAML', ->
  it 'shows an error without throwing exception', ->
    badYaml = '{ not valid json !!!!'
    global.jsyaml.load = (s) -> throw new Error 'YAML parse error'
    cv = new CV makeContainer(), badYaml, makeSpaces()
    cv.mount()
    eq cv._widgets.length, 0
    global.jsyaml.load = (s) -> JSON.parse s  # restore

describe 'CustomView — unmount', ->
  it 'clears _widgets and _widgetsById', ->
    layout = { layout: { widget: { id: 'w', space: 'personnes' } } }
    cv = new CV makeContainer(), yamlJSON(layout), makeSpaces()
    cv.mount()
    eq cv._widgets.length, 1
    cv.unmount()
    eq cv._widgets.length, 0
    eq Object.keys(cv._widgetsById).length, 0

summary()
