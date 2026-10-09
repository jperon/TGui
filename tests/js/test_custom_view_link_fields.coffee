# tests/js/test_custom_view_link_fields.coffee — T21
#
# Link fields of a dependent widget must always be loaded, even when absent
# from `columns`: the DataView query is built from `sp.fields`, so a widget
# whose columns omit `id` (source side) or its `depends_on.field` (target side)
# would otherwise load rows without the values the filter compares.
#
# The DataView double below mirrors the real query behaviour: rows only contain
# the fields listed in `@space.fields` (plus __rowId). So a missing link field
# genuinely disappears from the loaded rows, exactly like in the browser.

require './dom_stub'
{ describe, it, eq, assert, summary } = require './runner'

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

# --- load the real DataView, then subclass for the test ---------------------
require '../../frontend/src/views/fk_search_editor'
require '../../frontend/src/views/data_view'
require '../../frontend/src/views/data_view_helpers'
RealDataView = global.window.DataView

SEED_ROWS = {}

global.DataView = class TestDataView extends RealDataView
  constructor: (container, space) ->
    super container, space
    @_grid    = new FakeGrid
    @_mounted = true
  mount: ->
    names = (f.name for f in (@space.fields or []))
    full  = SEED_ROWS[@space.name] or []
    @_rows = for r in full
      o = {}
      for n in names
        o[n] = r[n] if Object.prototype.hasOwnProperty.call(r, n)
      o.__rowId = r.id
      o
    @_applyData()
    @_grid.on 'click', (ev) => @setActiveRow ev.rowKey if ev?.rowKey?
    Promise.resolve()

require '../../frontend/src/views/custom_view'
require '../../frontend/src/views/custom_view_plugins'
require '../../frontend/src/views/custom_view_aggregate'
require '../../frontend/src/views/custom_view_resize'
CV = global.window.CustomView

# --- fixtures ---------------------------------------------------------------
makeSpaces = ->
  [
    { id: 'sp-livres', name: 'livres', fields: [
        { id: 'l1', name: 'id',         fieldType: 'Int' }
        { id: 'l2', name: 'titre',      fieldType: 'String' }
        { id: 'l3', name: 'auteur_nom', fieldType: 'String', formula: 'a' }
    ]}
    { id: 'sp-ex', name: 'exemplaires', fields: [
        { id: 'e1', name: 'id',         fieldType: 'Int' }
        { id: 'e2', name: 'livre',      fieldType: 'Int' }
        { id: 'e3', name: 'cote',       fieldType: 'String' }
        { id: 'e4', name: 'emprunteur', fieldType: 'String', formula: 'a' }
    ]}
    { id: 'sp-em', name: 'emprunts', fields: [
        { id: 'm1', name: 'id',         fieldType: 'Int' }
        { id: 'm2', name: 'exemplaire', fieldType: 'Int' }
        { id: 'm3', name: 'lecteur',    fieldType: 'String' }
    ]}
  ]

pageLayout = ->
  layout:
    direction: 'vertical'
    children: [
      { widget: { id: 'livres', space: 'livres', columns: ['titre', 'auteur_nom'] } }
      { widget: { id: 'ex', space: 'exemplaires', columns: ['cote', 'emprunteur']
          depends_on: { widget: 'livres', field: 'livre', from_field: 'id' } } }
      { widget: { id: 'em', space: 'emprunts', columns: ['lecteur']
          depends_on: { widget: 'ex', field: 'exemplaire', from_field: 'id' } } }
    ]

DEFAULT_ROWS =
  livres: [
    { id: 1, titre: 'L1', auteur_nom: 'A' }
    { id: 2, titre: 'L2', auteur_nom: 'B' }
  ]
  exemplaires: [
    { id: 10, livre: 1, cote: 'C1', emprunteur: 'X' }
    { id: 11, livre: 1, cote: 'C2', emprunteur: 'Y' }
    { id: 12, livre: 2, cote: 'C3', emprunteur: 'Z' }
  ]
  emprunts: [
    { id: 100, exemplaire: 10, lecteur: 'U' }
    { id: 101, exemplaire: 11, lecteur: 'V' }
    { id: 102, exemplaire: 12, lecteur: 'W' }
  ]

makeContainer = -> global.document.createElement 'div'
yamlJSON = (obj) -> JSON.stringify obj
flush = -> new Promise (resolve) -> setTimeout resolve, 0

mountPage = (rows, layout) ->
  SEED_ROWS.livres      = rows.livres or []
  SEED_ROWS.exemplaires = rows.exemplaires or []
  SEED_ROWS.emprunts    = rows.emprunts or []
  cv = new CV makeContainer(), yamlJSON(layout or pageLayout()), makeSpaces()
  cv.mount()
  flush().then -> cv

names = (dv) -> dv.space.fields.map (f) -> f.name

# ---------------------------------------------------------------------------
describe 'T21 — link fields are always loaded', ->

  it '(a) source widget loads the dependent from_field as a hidden field', ->
    mountPage(DEFAULT_ROWS).then (cv) ->
      dv = cv._widgetsById['livres'].dataView
      assert names(dv).indexOf('id') >= 0, 'id must be loaded into the source rows'
      idField = dv.space.fields.find (f) -> f.name == 'id'
      assert idField.hidden is true, 'id must be marked hidden'
      titre = dv.space.fields.find (f) -> f.name == 'titre'
      assert not titre.hidden, 'titre (in columns) must stay visible'

  it '(b) dependent widget loads its own depends_on.field as a hidden field', ->
    mountPage(DEFAULT_ROWS).then (cv) ->
      dv = cv._widgetsById['ex'].dataView
      assert names(dv).indexOf('livre') >= 0, 'livre must be loaded'
      lf = dv.space.fields.find (f) -> f.name == 'livre'
      assert lf.hidden is true, 'livre must be hidden'
      idf = dv.space.fields.find (f) -> f.name == 'id'
      assert idf and idf.hidden is true, 'id (from_field of em) must be hidden'

  it '(c) a link field already in columns stays visible and is not duplicated', ->
    layout =
      layout:
        direction: 'vertical'
        children: [
          { widget: { id: 'livres', space: 'livres', columns: ['titre'] } }
          { widget: { id: 'ex', space: 'exemplaires', columns: ['livre', 'cote']
              depends_on: { widget: 'livres', field: 'livre', from_field: 'id' } } }
        ]
    mountPage(DEFAULT_ROWS, layout).then (cv) ->
      dv = cv._widgetsById['ex'].dataView
      livres = dv.space.fields.filter (f) -> f.name == 'livre'
      eq livres.length, 1
      assert not livres[0].hidden, 'livre in columns must stay visible'

  it '(d) realistic rows (only sp.fields) cascade-filter correctly', ->
    mountPage(DEFAULT_ROWS).then (cv) ->
      ex = cv._widgetsById['ex'].dataView
      eq ex.filter.field, 'livre'
      eq ex.filter.value, '1'
      eq ex._currentData.length, 3          # rows 10, 11 + sentinel
      em = cv._widgetsById['em'].dataView
      eq em.filter.value, '10'
      eq em._currentData.length, 2          # row 100 + sentinel

  it '(e) a link field missing from the space warns and does not crash', ->
    warns = []
    oldWarn = console.warn
    console.warn = (m) -> warns.push String(m)
    layout =
      layout:
        direction: 'vertical'
        children: [
          { widget: { id: 'livres', space: 'livres', columns: ['titre'] } }
          { widget: { id: 'ex', space: 'exemplaires', columns: ['cote']
              depends_on: { widget: 'livres', field: 'inexistant', from_field: 'id' } } }
        ]
    mountPage(DEFAULT_ROWS, layout).then (cv) ->
      console.warn = oldWarn
      assert cv._widgetsById['ex'].dataView?, 'dependent must still mount'
      assert warns.some((w) -> w.indexOf('inexistant') >= 0), 'expected a warning naming the field'

  it '(f) an undefined link value yields none, never the string undefined', ->
    warns = []
    oldWarn = console.warn
    console.warn = (m) -> warns.push String(m)
    mountPage(DEFAULT_ROWS).then (cv) ->
      entry = cv._widgetsById['ex']
      console.warn = oldWarn
      cv._applyDependencySelection entry, entry.node.depends_on, { titre: 'no id' }
      assert entry.dataView.filter.none is true, 'filter must be none'
      assert entry.dataView.filter.value isnt 'undefined', 'never the string undefined'
      eq entry.dataView._currentData.length, 0
      assert warns.some((w) -> w.indexOf('undefined') < 0 and w.indexOf("'id'") >= 0),
        'expected a warning naming the missing field'

  it '(g) a widget without columns or dependency is unchanged', ->
    layout = { layout: { widget: { id: 'plain', space: 'emprunts' } } }
    mountPage(DEFAULT_ROWS, layout).then (cv) ->
      dv = cv._widgetsById['plain'].dataView
      eq dv.space.fields.length, 3
      assert not (dv.space.fields.some (f) -> f.hidden), 'no field must be hidden'

summary()
