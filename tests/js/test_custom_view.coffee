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
  setFilter: (f) -> @lastFilter = f
  setDefaultValues: (d) -> @lastDefaults = d
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
flush = -> new Promise (resolve) -> setTimeout resolve, 0
syncPlugin = (plugin) ->
  then: (cb) ->
    err = null
    try
      cb plugin
    catch e
      err = e
    catch: (onErr) -> onErr(err) if err

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

describe 'CustomView — plugin widgets', ->
  it 'mounts a plugin widget and initializes iframe state', ->
    global.window.CoffeeScript = { compile: -> "module.exports = function(api){ api.render('<div>ok</div>'); }" }
    global.window.pug = { compile: -> -> "<div>tpl</div>" }
    global.WidgetPlugins =
      getByName: -> syncPlugin
        id: 'p1'
        name: 'sample_plugin'
        scriptLanguage: 'coffeescript'
        templateLanguage: 'pug'
        scriptCode: 'ignored by compile stub'
        templateCode: 'ignored by pug compile stub'
    global.window.addEventListener = ->
    global.window.removeEventListener = ->

    oldCreate = global.document.createElement
    global.document.createElement = (tag) ->
      el = oldCreate tag
      if tag is 'iframe'
        el.setAttribute ?= ->
        el.contentWindow = { postMessage: -> }
      el

    layout = { layout: { widget: { id: 'plug1', type: 'sample_plugin', title: 'Plugin' } } }
    cv = new CV makeContainer(), yamlJSON(layout), makeSpaces()
    try
      cv.mount()
      assert cv._widgetsById['plug1']?, 'plugin indexed by id'
      assert cv._widgetsById['plug1'].plugin is true, 'entry marked as plugin'
      assert cv._pluginStateByWidgetId['plug1']?, 'iframe runtime state created'
    catch e
      global.document.createElement = oldCreate
      throw e
    global.document.createElement = oldCreate

  it 'propagates depends_on from plugin selection to DataView target', ->
    global.window.CoffeeScript = { compile: -> "module.exports = function(api){}" }
    global.window.pug = { compile: -> -> "<div>tpl</div>" }
    global.WidgetPlugins =
      getByName: -> syncPlugin
        id: 'p2'
        name: 'sample_plugin_2'
        scriptLanguage: 'coffeescript'
        templateLanguage: 'pug'
        scriptCode: ''
        templateCode: ''
    global.window.addEventListener = ->
    global.window.removeEventListener = ->

    oldCreate = global.document.createElement
    global.document.createElement = (tag) ->
      el = oldCreate tag
      if tag is 'iframe'
        el.setAttribute ?= ->
        el.contentWindow = { postMessage: -> }
      el

    layout =
      layout:
        direction: 'horizontal'
        children: [
          { widget: { id: 'src', type: 'sample_plugin_2' } }
          { widget: { id: 'dst', space: 'personnes', depends_on: { widget: 'src', field: 'age', from_field: 'id' } } }
        ]
    cv = new CV makeContainer(), yamlJSON(layout), makeSpaces()
    try
      cv.mount()
      cv._emitPluginSelection 'src', { rows: [{ id: 7 }] }
      dv = cv._widgetsById['dst'].dataView
      eq dv.lastDefaults.age, '7'
      deepEq dv.lastFilter, { field: 'age', value: '7' }
    catch e
      global.document.createElement = oldCreate
      throw e
    global.document.createElement = oldCreate

  it 'shows a fallback error when CoffeeScript runtime is missing', ->
    delete global.window.CoffeeScript
    global.window.pug = { compile: -> -> "<div>tpl</div>" }
    global.WidgetPlugins =
      getByName: -> syncPlugin
        id: 'p3'
        name: 'broken_plugin'
        scriptLanguage: 'coffeescript'
        templateLanguage: 'pug'
        scriptCode: 'x = 1'
        templateCode: 'div hi'
    global.window.addEventListener = ->
    global.window.removeEventListener = ->

    oldCreate = global.document.createElement
    global.document.createElement = (tag) ->
      el = oldCreate tag
      if tag is 'iframe'
        el.setAttribute ?= ->
        el.contentWindow = { postMessage: -> }
      el

    layout = { layout: { widget: { id: 'plug_err', type: 'broken_plugin' } } }
    cv = new CV makeContainer(), yamlJSON(layout), makeSpaces()
    try
      cv.mount()
      body = cv._widgets[0].el._children[1]
      assert body.innerHTML.includes('Erreur plugin'), 'fallback error should be rendered'
    catch e
      global.document.createElement = oldCreate
      throw e
    global.document.createElement = oldCreate

summary()
