# tests/js/test_custom_view_cascade.coffee — cascade selection of dependent widgets.
#
# Three data widgets A -> B -> C (B depends_on A, C depends_on B). The real
# DataView filtering / active-row logic (data_view.js + data_view_helpers.js) is
# reused through a small subclass that injects seeded rows and a fake tui.Grid,
# so the CustomView cascade is what is under test.

require './dom_stub'
{ describe, it, eq, deepEq, assert, summary } = require './runner'

global.jsyaml =
  load: (src) -> JSON.parse src

# --- fake tui.Grid ----------------------------------------------------------
class FakeGrid
  constructor: ->
    @_data      = []
    @_listeners = {}
    @_classes   = {}
  resetData: (rows) ->
    @_data = rows
    row.rowKey = i for row, i in rows
  getData: -> @_data
  getRowAt: (i) -> @_data[i] or null
  getRow: (key) -> @_data[Number key] or null
  addRowClassName: (key, cls) ->
    k = String key
    @_classes[k] ?= {}
    @_classes[k][cls] = true
  removeRowClassName: (key, cls) ->
    delete @_classes[String key]?[cls]
  hasRowClass: (key, cls) -> !! @_classes[String key]?[cls]
  countRowsWithClass: (cls) ->
    c = 0
    c += 1 for _k, v of @_classes when v[cls]
    c
  on: (ev, fn) ->
    @_listeners[ev] ?= []
    @_listeners[ev].push fn
  emit: (ev, payload) ->
    fn payload for fn in (@_listeners[ev] or [])
  getCheckedRowKeys: -> []
  getFocusedCell: -> null
  destroy: ->
  refreshLayout: ->

# --- load the real DataView, then subclass it for the test -------------------
require '../../frontend/src/views/fk_search_editor'
require '../../frontend/src/views/data_view'
require '../../frontend/src/views/data_view_helpers'
RealDataView = global.window.DataView

SEED_ROWS = {}

global.DataView = class TestDataView extends RealDataView
  constructor: (container, space) ->
    super container, space
    @_grid     = new FakeGrid
    @_mounted  = true
    @_testRows = (SEED_ROWS[space.name] or []).slice()
  mount: ->
    @_rows = @_testRows
    @_applyData()
    @_grid.on 'click', (ev) => @setActiveRow ev.rowKey if ev?.rowKey?
    Promise.resolve()

require '../../frontend/src/views/custom_view'
require '../../frontend/src/views/custom_view_plugins'
require '../../frontend/src/views/custom_view_aggregate'
require '../../frontend/src/views/custom_view_resize'
CV = global.window.CustomView

# --- helpers ----------------------------------------------------------------
makeContainer = -> global.document.createElement 'div'
yamlJSON = (obj) -> JSON.stringify obj
flush = -> new Promise (resolve) -> setTimeout resolve, 0

makeSpaces = ->
  [
    { id: 'a', name: 'A', fields: [
        { id: 'af', name: 'id',   fieldType: 'Int' }
        { id: 'an', name: 'nom',  fieldType: 'String' }
    ]}
    { id: 'b', name: 'B', fields: [
        { id: 'bf', name: 'id',   fieldType: 'Int' }
        { id: 'ba', name: 'a_id', fieldType: 'Int' }
        { id: 'bn', name: 'nom',  fieldType: 'String' }
    ]}
    { id: 'c', name: 'C', fields: [
        { id: 'cf', name: 'id',   fieldType: 'Int' }
        { id: 'cb', name: 'b_id', fieldType: 'Int' }
        { id: 'cn', name: 'nom',  fieldType: 'String' }
    ]}
  ]

abcLayout = ->
  layout:
    direction: 'vertical'
    children: [
      { widget: { id: 'A', space: 'A' } }
      { widget: { id: 'B', space: 'B', depends_on: { widget: 'A', field: 'a_id', from_field: 'id' } } }
      { widget: { id: 'C', space: 'C', depends_on: { widget: 'B', field: 'b_id', from_field: 'id' } } }
    ]

DEFAULT_ROWS =
  A: [ { id: 1, nom: 'A1' }, { id: 2, nom: 'A2' } ]
  B: [ { id: 10, a_id: 1, nom: 'B1' }, { id: 11, a_id: 1, nom: 'B2' }, { id: 12, a_id: 2, nom: 'B3' } ]
  C: [ { id: 100, b_id: 10, nom: 'C1' }, { id: 101, b_id: 11, nom: 'C2' }, { id: 102, b_id: 12, nom: 'C3' } ]

mountCascade = (rows, layout) ->
  SEED_ROWS.A = rows.A or []
  SEED_ROWS.B = rows.B or []
  SEED_ROWS.C = rows.C or []
  cv = new CV makeContainer(), yamlJSON(layout or abcLayout()), makeSpaces()
  cv.mount()
  flush().then -> cv

# ---------------------------------------------------------------------------
describe 'CustomView — cascade depends_on', ->

  it 'a) selecting a row in A filters B and cascades to C', ->
    mountCascade(DEFAULT_ROWS).then (cv) ->
      A = cv._widgetsById['A']; B = cv._widgetsById['B']; C = cv._widgetsById['C']
      A.dataView._grid.emit 'click', { rowKey: 1 }   # A id = 2
      eq B.dataView.filter.field, 'a_id'
      eq B.dataView.filter.value, '2'
      eq B.dataView._currentData.length, 2           # B3 + sentinel
      assert B.dataView._activeRowKey is 0, 'B first row must be active'
      eq C.dataView.filter.field, 'b_id'
      eq C.dataView.filter.value, '12'
      assert C.dataView._activeRowKey is 0, 'C first row must be active'

  it 'b) empty dependent grid -> no active row, descendants show zero rows', ->
    rows =
      A: [ { id: 1, nom: 'A1' }, { id: 3, nom: 'A3' } ]
      B: [ { id: 10, a_id: 1, nom: 'B1' } ]
      C: [ { id: 100, b_id: 10, nom: 'C1' } ]
    mountCascade(rows).then (cv) ->
      A = cv._widgetsById['A']; B = cv._widgetsById['B']; C = cv._widgetsById['C']
      A.dataView._grid.emit 'click', { rowKey: 1 }   # A id = 3 -> no B
      eq B.dataView.filter.value, '3'
      assert not B.dataView._activeRowKey?, 'B must have no active row'
      eq C.dataView.filter.none, true
      eq C.dataView._currentData.length, 0
      assert not C.dataView._activeRowKey?, 'C must have no active row'

  it 'c) mount activates the first row of A and cascades down', ->
    mountCascade(DEFAULT_ROWS).then (cv) ->
      A = cv._widgetsById['A']; B = cv._widgetsById['B']; C = cv._widgetsById['C']
      assert A.dataView._activeRowKey is 0, 'A first row must be active'
      eq B.dataView.filter.value, '1'
      assert B.dataView._activeRowKey is 0, 'B first row must be active'
      eq C.dataView.filter.value, '10'
      assert C.dataView._activeRowKey is 0, 'C first row must be active'

  it 'c2) empty root -> dependents show zero rows', ->
    mountCascade({ A: [] }).then (cv) ->
      B = cv._widgetsById['B']; C = cv._widgetsById['C']
      eq B.dataView._currentData.length, 0
      eq C.dataView._currentData.length, 0
      assert not B.dataView._activeRowKey?, 'B must have no active row'
      assert not C.dataView._activeRowKey?, 'C must have no active row'

  it 'd) clicking B changes C but never A', ->
    mountCascade(DEFAULT_ROWS).then (cv) ->
      A = cv._widgetsById['A']; B = cv._widgetsById['B']; C = cv._widgetsById['C']
      B.dataView._grid.emit 'click', { rowKey: 1 }   # B2 (id 11)
      eq A.dataView.filter, null
      assert A.dataView._activeRowKey is 0, 'A must be untouched'
      eq B.dataView._activeRowKey, 1
      eq C.dataView.filter.value, '11'
      assert C.dataView._activeRowKey is 0

  it 'e) a depends_on cycle does not loop and warns', ->
    rows =
      A: [ { id: 1, nom: 'A1' } ]
      B: [ { id: 10, nom: 'B1' } ]
      C: []
    layout =
      layout:
        direction: 'vertical'
        children: [
          { widget: { id: 'A', space: 'A', depends_on: { widget: 'B', field: 'x', from_field: 'id' } } }
          { widget: { id: 'B', space: 'B', depends_on: { widget: 'A', field: 'a_id', from_field: 'id' } } }
        ]
    warns = []
    oldWarn = console.warn
    console.warn = (m) -> warns.push m
    mountCascade(rows, layout).then (cv) ->
      B = cv._widgetsById['B']
      B.dataView._grid.emit 'click', { rowKey: 0 }
      console.warn = oldWarn
      assert warns.some((w) -> /cycle/.test String(w)), 'expected a cycle warning'

  it 'f) only one row is active per grid', ->
    mountCascade(DEFAULT_ROWS).then (cv) ->
      A = cv._widgetsById['A']
      A.dataView._grid.emit 'click', { rowKey: 1 }
      eq A.dataView._grid.countRowsWithClass('tdb-selected-row'), 1
      assert A.dataView._grid.hasRowClass(1, 'tdb-selected-row'), 'new active row'
      assert not A.dataView._grid.hasRowClass(0, 'tdb-selected-row'), 'old row cleared'

  it 'g) the sentinel row is never activated nor propagated', ->
    mountCascade(DEFAULT_ROWS).then (cv) ->
      A = cv._widgetsById['A']; C = cv._widgetsById['C']
      sentinel = A.dataView._currentData[A.dataView._currentData.length - 1]
      assert sentinel.__isNew, 'last row must be the sentinel'
      sentinelKey = A.dataView._grid.getRowAt(A.dataView._currentData.length - 1).rowKey
      cv._selectRow A, sentinelKey
      assert not A.dataView._grid.hasRowClass(sentinelKey, 'tdb-selected-row'), 'sentinel must not be active'
      assert C.dataView._activeRowKey is 0, 'C unchanged'

  it 'i) setFilter without none behaves as before', ->
    mountCascade(DEFAULT_ROWS).then (cv) ->
      B = cv._widgetsById['B']
      B.dataView.setFilter { field: 'a_id', value: '2' }
      eq B.dataView._currentData.length, 2   # B3 + sentinel
      eq B.dataView._currentData[0].nom, 'B3'
      assert B.dataView._currentData[1].__isNew

describe 'CustomView — plugin dependents are not auto-filled', ->
  it 'h) a plugin widget depending on A receives no automatic selection', ->
    global.window.CoffeeScript = { compile: -> "module.exports = function(api){}" }
    global.window.pug = { compile: -> -> "<div>tpl</div>" }
    global.WidgetPlugins =
      getByName: ->
        plugin = { id: 'p', name: 'sample_plugin', scriptLanguage: 'coffeescript', templateLanguage: 'pug', scriptCode: '', templateCode: '' }
        thenable =
          then: (cb) ->
            err = null
            try
              cb plugin
            catch e
              err = e
            catch: (onErr) -> onErr(err) if err
        thenable
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
          { widget: { id: 'A', space: 'A' } }
          { widget: { id: 'P', type: 'sample_plugin', depends_on: { widget: 'A', field: 'a_id', from_field: 'id' } } }
        ]
    SEED_ROWS.A = (DEFAULT_ROWS.A).slice()
    SEED_ROWS.B = []; SEED_ROWS.C = []
    cv = new CV makeContainer(), yamlJSON(layout), makeSpaces()
    sent = []
    cv._sendPluginMessage = (id, msg) -> sent.push { id, msg }
    cv.mount()
    flush().then ->
      A = cv._widgetsById['A']
      A.dataView._grid.emit 'click', { rowKey: 1 } if A?.dataView?._grid?
      eq sent.length, 0
      global.document.createElement = oldCreate

summary()
