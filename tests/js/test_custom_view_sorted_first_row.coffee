# tests/js/test_custom_view_sorted_first_row.coffee
# `_firstRow` sert à la cascade depends_on initiale (widget racine → premier
# widget dépendant). L'index venait de `_currentData` (ordre de chargement) alors
# que la grille peut être triée : il pouvait désigner la sentinelle `__isNew` et
# interrompre la cascade. On exige la première ligne VISUELLE non sentinelle.

require './dom_stub'
{ describe, it, eq, assert, summary } = require './runner'

global.jsyaml =
  load: (src) -> JSON.parse src

class FakeGrid
  constructor: ->
    @_data    = []
    @_classes = {}
  resetData: (rows) ->
    @_data = rows
    row.rowKey = i for row, i in rows
  getData: -> @_data
  getRowAt: (i) -> @_data[i] or null
  getRow: (key) -> @_data[Number key] or null
  addRowClassName: (key, cls) -> (@_classes[String key] ?= {})[cls] = true
  removeRowClassName: (key, cls) -> delete @_classes[String key]?[cls]
  on: ->
  getCheckedRowKeys: -> []
  getFocusedCell: -> null
  destroy: ->
  refreshLayout: ->

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
    Promise.resolve()

require '../../frontend/src/views/custom_view'
require '../../frontend/src/views/custom_view_plugins'
require '../../frontend/src/views/custom_view_aggregate'
require '../../frontend/src/views/custom_view_resize'
CV = global.window.CustomView

makeContainer = -> global.document.createElement 'div'
yamlJSON = (obj) -> JSON.stringify obj
flush = -> new Promise (resolve) -> setTimeout resolve, 0

makeSpaces = ->
  [
    { id: 'a', name: 'A', fields: [
        { id: 'af', name: 'id',  fieldType: 'Int' }
        { id: 'an', name: 'nom', fieldType: 'String' }
    ]}
    { id: 'b', name: 'B', fields: [
        { id: 'bf', name: 'id',   fieldType: 'Int' }
        { id: 'ba', name: 'a_id', fieldType: 'Int' }
        { id: 'bn', name: 'nom',  fieldType: 'String' }
    ]}
  ]

layout = ->
  layout:
    direction: 'vertical'
    children: [
      { widget: { id: 'A', space: 'A' } }
      { widget: { id: 'B', space: 'B', depends_on: { widget: 'A', field: 'a_id', from_field: 'id' } } }
    ]

# Monte la page puis simule un tri visuel : la sentinelle remonte en tête et
# l'ordre d'affichage n'est plus celui de `_currentData`.
mountSorted = (rows) ->
  SEED_ROWS.A = rows.A
  SEED_ROWS.B = rows.B
  cv = new CV makeContainer(), yamlJSON(layout()), makeSpaces()
  cv.mount()
  flush().then ->
    A = cv._widgetsById['A']
    data = A.dataView._grid.getData()
    sentinel = data.find (r) -> r.__isNew
    others   = (r for r in data when not r.__isNew)
    reversed = others.slice().reverse()
    # rowKey recalculé comme le ferait un resetData trié.
    rows0 = [sentinel].concat reversed
    rows0.forEach (r, i) -> r.rowKey = i
    A.dataView._grid._data = rows0
    A.dataView._currentData = others.concat [sentinel]   # ordre de chargement
    cv

DEFAULT_ROWS =
  A: [ { id: 1, nom: 'A1' }, { id: 2, nom: 'A2' } ]
  B: [ { id: 10, a_id: 1, nom: 'B1' }, { id: 20, a_id: 2, nom: 'B2' } ]

describe 'CustomView._firstRow — tri', ->
  it 'ignore la sentinelle et prend la première ligne visuelle triée', ->
    mountSorted(DEFAULT_ROWS).then (cv) ->
      A = cv._widgetsById['A']
      first = cv._firstRow A
      assert first?, 'une première ligne est attendue'
      row = A.dataView._grid.getRow first.rowKey
      assert row?, 'rowKey résolue'
      assert not row.__isNew, 'la sentinelle ne doit jamais être la première ligne'
      eq row.nom, 'A2'   # première ligne visuelle (ordre inversé)

  it 'la cascade initiale repart de cette première ligne visuelle', ->
    mountSorted(DEFAULT_ROWS).then (cv) ->
      A = cv._widgetsById['A']; B = cv._widgetsById['B']
      cv._initializeCascade()
      assert A.dataView._activeRowKey?, 'A doit avoir une ligne active'
      eq B.dataView.filter.value, '2'   # dépend de A2, pas de la sentinelle

summary()
