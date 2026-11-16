# tests/js/test_custom_view_dataview_widget.coffee — T18 regression tests.
#
# A page widget whose `space` names a Data View must expose the view's output
# columns, otherwise the grid mounts with an empty space and renders blank.
# The Data View `config` arrives from the list GraphQL query as a JSON string.
# Also guards the sidebar CSS for #page-list / #data-view-list.

require './dom_stub'
{ describe, it, eq, deepEq, assert, summary } = require './runner'
fs   = require 'fs'
path = require 'path'

global.jsyaml =
  load: (src) -> JSON.parse src

global.DataView = class DataView
  constructor: (@container, @space) ->
    @mounted = false
  mount: -> @mounted = true
  refreshLayout: ->
  unmount: ->

require '../../frontend/src/views/custom_view'
CV = global.window.CustomView

makeContainer = -> global.document.createElement 'div'

# Build a CustomView whose only purpose is to expose _findSpace. `spaces` and
# `views` mimic what the SPA holds in _allSpaces / _allDataViews.
makeCV = (spaces, views) -> new CV makeContainer(), '{}', spaces, views

SOURCE =
  id: 'sp-1'
  name: 'Emprunts'
  fields: [
    { name: 'lecteur', fieldType: 'Str' }
    { name: 'ouvrage', fieldType: 'Str' }
    { name: 'montant', fieldType: 'Int' }
  ]

describe 'CustomView._findSpace — data view widgets', ->
  it 'parses a JSON-string config and maps its columns', ->
    dv =
      id: 'dv1'
      name: 'Ma vue'
      sourceSpace: 'sp-1'
      config: JSON.stringify { columns: ['lecteur', 'ouvrage'] }
    sp = makeCV([SOURCE], [dv])._findSpace 'Ma vue'
    assert sp?, 'view should resolve'
    eq sp.isView, true
    deepEq (f.name for f in sp.fields), ['lecteur', 'ouvrage']
    eq sp.fields[0].fieldType, 'Str'
    eq sp.fields[1].fieldType, 'Str'

  it 'aggregated view: groupBy names then aggregate aliases', ->
    config = { groupBy: ['lecteur'], aggregates: [{ fn: 'count', as: 'nb_livres' }] }
    dv = { id: 'dv2', name: 'Agrégée', sourceSpace: 'sp-1', config: JSON.stringify config }
    sp = makeCV([SOURCE], [dv])._findSpace 'Agrégée'
    deepEq (f.name for f in sp.fields), ['lecteur', 'nb_livres']

  it 'aggregate alias falls back to fn_field then count', ->
    config = { groupBy: ['lecteur'], aggregates: [{ fn: 'sum', field: 'montant' }, { fn: 'count' }] }
    dv = { id: 'dv3', name: 'Alias', sourceSpace: 'sp-1', config: JSON.stringify config }
    sp = makeCV([SOURCE], [dv])._findSpace 'Alias'
    deepEq (f.name for f in sp.fields), ['lecteur', 'sum_montant', 'count']

  it 'view without columns nor groupBy falls back to source space fields', ->
    dv = { id: 'dv4', name: 'Brute', sourceSpace: 'sp-1', config: '{}' }
    sp = makeCV([SOURCE], [dv])._findSpace 'Brute'
    deepEq (f.name for f in sp.fields), ['lecteur', 'ouvrage', 'montant']

  it 'invalid JSON config -> no exception, empty fields', ->
    dv = { id: 'dv5', name: 'Cassée', sourceSpace: 'sp-1', config: '{ not json' }
    sp = null
    try
      sp = makeCV([SOURCE], [dv])._findSpace 'Cassée'
    catch e
      assert false, "should not throw: #{e.message}"
    deepEq sp.fields, []

  it 'unknown source space without columns -> empty fields', ->
    dv = { id: 'dv6', name: 'Orpheline', sourceSpace: 'missing', config: '{}' }
    sp = makeCV([SOURCE], [dv])._findSpace 'Orpheline'
    deepEq sp.fields, []

  it 'a real space is unchanged', ->
    sp = makeCV([SOURCE], [])._findSpace 'Emprunts'
    eq sp.fields.length, 3
    eq sp.isView, undefined

describe 'CustomView — widget on a data view filters columns', ->
  it 'keeps only the requested columns of the view', ->
    dv =
      id: 'dv7'
      name: 'Trois'
      sourceSpace: 'sp-1'
      config: JSON.stringify { columns: ['a', 'b', 'c'] }
    layout = { layout: { widget: { space: 'Trois', columns: ['b'] } } }
    cv = new CV makeContainer(), JSON.stringify(layout), [SOURCE], [dv]
    cv.mount()
    eq cv._widgets.length, 1
    fields = cv._widgets[0].dataView.space.fields
    deepEq (f.name for f in fields), ['b']

describe 'app.css — pages / data views sidebar items', ->
  css = fs.readFileSync path.join(__dirname, '../../frontend/css/app.css'), 'utf8'

  it 'styles #page-list and #data-view-list with the same base rule as #space-list', ->
    assert /#space-list li[^{]*#page-list[^{]*#data-view-list[^{]*\{/.test(css),
      'expected one rule to style #space-list li, #page-list and #data-view-list together'

  it 'shares the hover/active rule', ->
    assert /#space-list li:hover[^{]*#data-view-list[^{]*\{/.test(css),
      'expected #page-list and #data-view-list to share the hover/active rule with #space-list'

summary()
