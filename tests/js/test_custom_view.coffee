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

# Load module under test (exposes window.CustomView) and the files that extend
# its prototype via Object.assign (loaded after custom_view.js in the SPA).
require '../../frontend/src/views/plugin_runtimes'
require '../../frontend/src/views/custom_view'
require '../../frontend/src/views/custom_view_plugins'
require '../../frontend/src/views/custom_view_aggregate'
require '../../frontend/src/views/custom_view_resize'
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

# Les tests de widgets plugins sont asynchrones : la compilation attend le
# chargement à la demande des compilateurs (spec §7). Le runner lance tous les
# `it` du fichier avant que les promesses ne se résolvent ; chaque test remet
# donc l'état global (runtimes, stubs DOM) en place *synchroniquement*, avant
# son `flush`.
setPluginWidgets = (plugin) ->
  global.WidgetPlugins =
    getByName: -> syncPlugin plugin
  global.window.addEventListener = ->
  global.window.removeEventListener = ->

describe 'CustomView — plugin widgets', ->
  it 'mounts a plugin widget and initializes iframe state', ->
    global.window.CoffeeScript = { compile: -> "module.exports = function(api){ api.render('<div>ok</div>'); }" }
    global.window.pug = { compile: -> -> "<div>tpl</div>" }
    setPluginWidgets
      id: 'p1'
      name: 'sample_plugin'
      scriptLanguage: 'coffeescript'
      templateLanguage: 'pug'
      scriptCode: 'ignored by compile stub'
      templateCode: 'ignored by pug compile stub'

    layout = { layout: { widget: { id: 'plug1', type: 'sample_plugin', title: 'Plugin' } } }
    cv = new CV makeContainer(), yamlJSON(layout), makeSpaces()
    cv.mount()
    flush().then ->
      assert cv._widgetsById['plug1']?, 'plugin indexed by id'
      assert cv._widgetsById['plug1'].plugin is true, 'entry marked as plugin'
      assert cv._pluginStateByWidgetId['plug1']?, 'iframe runtime state created'

  it 'a javascript + html widget loads no compiler bundle', ->
    global.window.PluginRuntimes._reset()
    setPluginWidgets
      id: 'p_plain'
      name: 'plain_plugin'
      scriptLanguage: 'javascript'
      templateLanguage: 'html'
      scriptCode: 'api.render("<div>ok</div>");'
      templateCode: '<div>init</div>'

    appended = []
    oldAppend = global.document.head.appendChild
    global.document.head.appendChild = (el) -> appended.push el

    layout = { layout: { widget: { id: 'plain', type: 'plain_plugin' } } }
    cv = new CV makeContainer(), yamlJSON(layout), makeSpaces()
    cv.mount()
    global.document.head.appendChild = oldAppend
    flush().then ->
      eq appended.length, 0, 'aucun bundle de compilateur ne doit être chargé'
      assert cv._pluginStateByWidgetId['plain']?, 'iframe runtime state created'

  it 'propagates depends_on from plugin selection to DataView target', ->
    global.window.CoffeeScript = { compile: -> "module.exports = function(api){}" }
    global.window.pug = { compile: -> -> "<div>tpl</div>" }
    setPluginWidgets
      id: 'p2'
      name: 'sample_plugin_2'
      scriptLanguage: 'coffeescript'
      templateLanguage: 'pug'
      scriptCode: ''
      templateCode: ''

    layout =
      layout:
        direction: 'horizontal'
        children: [
          { widget: { id: 'src', type: 'sample_plugin_2' } }
          { widget: { id: 'dst', space: 'personnes', depends_on: { widget: 'src', field: 'age', from_field: 'id' } } }
        ]
    cv = new CV makeContainer(), yamlJSON(layout), makeSpaces()
    cv.mount()
    flush().then ->
      cv._emitPluginSelection 'src', { rows: [{ id: 7 }] }
      dv = cv._widgetsById['dst'].dataView
      eq dv.lastDefaults.age, '7'
      deepEq dv.lastFilter, { field: 'age', value: '7' }

  it 'shows a fallback error when the compiler bundle cannot be loaded', ->
    savedCs = global.window.CoffeeScript
    savedPug = global.window.pug
    delete global.window.CoffeeScript
    delete global.window.pug
    global.window.PluginRuntimes._reset()
    setPluginWidgets
      id: 'p3'
      name: 'broken_plugin'
      scriptLanguage: 'coffeescript'
      templateLanguage: 'pug'
      scriptCode: 'x = 1'
      templateCode: 'div hi'

    # Bundle introuvable : le <script> inséré déclenche onerror.
    oldAppend = global.document.head.appendChild
    global.document.head.appendChild = (el) ->
      el.onerror?()
      el

    layout = { layout: { widget: { id: 'plug_err', type: 'broken_plugin' } } }
    cv = new CV makeContainer(), yamlJSON(layout), makeSpaces()
    cv.mount()
    # L'échec est déjà survenu (onerror synchrone) ; on restaure l'état global
    # tout de suite, seule la promesse rejetée reste en attente.
    global.document.head.appendChild = oldAppend
    global.window.CoffeeScript = savedCs if savedCs
    global.window.pug = savedPug if savedPug
    flush().then ->
      body = cv._widgets[0].el._children[1]
      p = body._children[0]
      assert p?, 'fallback error element missing'
      assert p.textContent.includes('Erreur plugin'), 'fallback error should be rendered'
      assert p.textContent.includes('plugin-runtime.bundle.js'),
        "le message doit nommer le bundle en échec, vu : #{p.textContent}"

describe 'CustomView — surface API', ->
  it 'exposes the frozen set of prototype methods', ->
    expected = [
      'constructor'
      '_setMessage'
      '_refreshGridLayouts'
      '_setupResizeObserver'
      '_createSplitter'
      '_saveChildFactors'
      'mount'
      '_renderZoneOrWidget'
      '_renderWidget'
      '_collectWidgetNodes'
      '_widgetLinkFields'
      '_renderAggregate'
      '_wireDepends'
      '_applyDependencySelection'
      '_dependentEntries'
      '_firstRow'
      '_selectRow'
      '_cascadeToDependents'
      '_cascadeNone'
      '_initializeCascade'
      '_setPluginSelectionListener'
      '_emitPluginSelection'
      '_renderPluginWidget'
      '_mountPluginIframe'
      '_mountCompiledPluginIframe'
      '_compilePlugin'
      '_compilePluginCode'
      '_buildPluginIframeDoc'
      '_sendPluginMessage'
      '_relayWidgetQuery'
      '_pluginManifest'
      '_pluginAccessOf'
      '_pluginColumnMapping'
      '_pluginMissingColumns'
      '_widgetQueryOperation'
      '_widgetQueryRefusal'
      '_pluginRenameRow'
      '_pluginTranslateValues'
      '_loadPluginSourceRows'
      '_pluginGqlName'
      '_handlePluginWrite'
      '_canDetachPluginWidget'
      '_addPluginDetachButton'
      '_detachPluginWidget'
      '_reloadPageAfterDetach'
      '_findSpace'
      'unmount'
      '_addResizeHandle'
      '_showResizeTooltip'
      '_hideResizeTooltip'
      '_onZoneResize'
      'toggleGrid'
      'isGridVisible'
      'togglePresentationMode'
      'isPresentationMode'
    ]
    deepEq Object.getOwnPropertyNames(CV.prototype).sort(), expected.sort()

summary()
