# tests/js/test_data_view_multi_sort.coffee
# Tri multicritère du DataView : hiérarchie réelle sur les données (le premier
# critère décide, les égalités sont départagées par le suivant), persistance
# après resetData, et Maj+clic sur un en-tête (ajout/inversion sans effacer).
#
# La grille factice reproduit le comparateur et l'état de tri de Toast UI Grid :
# `sort(col, asc, multiple)` ajoute un critère quand `multiple` est vrai.

require './dom_stub'
{ describe, it, eq, deepEq, assert, summary } = require './runner'

# TdbHtml.escape is required by data_view._escapeHtml / _formatFormulaError
require '../../frontend/src/html_escape'

global.GQL =
  query:  -> Promise.resolve {}
  mutate: -> Promise.resolve {}

compare = (a, b) ->
  isBlank = (v) -> not v? or v == ''
  ca = if isBlank(a) then null else (if isNaN(Number(a)) then String(a) else Number(a))
  cb = if isBlank(b) then null else (if isNaN(Number(b)) then String(b) else Number(b))
  return -1 if ca == null and cb != null
  return 1 if ca != null and cb == null
  return 0 if ca == cb
  if ca < cb then -1 else 1

class MultiSortGrid
  constructor: ->
    @_data = []
    @_classes = {}
    @_sortState = { columns: [{ columnName: 'sortKey', ascending: true }] }

  resetData: (rows, options = {}) ->
    rows = rows or []
    rows.forEach (row, i) -> row.rowKey = i unless row.rowKey?
    @_data = rows
    state = options.sortState
    # resetData remet le tri à zéro, sauf `sortState` explicite : comme Toast UI
    # Grid, il ne fait alors que réafficher les flèches (aucun réordonnancement).
    if state
      if state.multiple and @_sortState.columns[0].columnName != 'sortKey'
        @_sortState.columns[0].ascending = state.ascending
      else
        @_sortState = { columns: [{ columnName: state.columnName, ascending: state.ascending }] }
    else
      @_sortState = { columns: [{ columnName: 'sortKey', ascending: true }] }

  unsort: ->
    @_sortState = { columns: [{ columnName: 'sortKey', ascending: true }] }

  sort: (columnName, ascending, multiple) ->
    column = { columnName: columnName, ascending: ascending }
    initial = @_sortState.columns[0].columnName == 'sortKey'
    if multiple and not initial
      kept = (c for c in @_sortState.columns when c.columnName != columnName)
      kept.push column
      @_sortState = { columns: kept }
    else
      @_sortState = { columns: [column] }
    @_data = @_data.slice().sort @_compare

  _compare: (a, b) =>
    for column in @_sortState.columns when column.columnName != 'sortKey'
      result = compare a[column.columnName], b[column.columnName]
      continue if result == 0
      return if column.ascending then result else -result
    0

  getSortState: -> { columns: (Object.assign {}, c) for c in @_sortState.columns }
  getData: -> @_data
  getRowAt: (i) -> @_data[i] or null
  getRow: (key) -> @_data.find((row) -> row.rowKey == Number key) or null
  getColumns: -> []
  addRowClassName: (key, cls) -> (@_classes[String key] ?= {})[cls] = true
  removeRowClassName: (key, cls) -> delete @_classes[String key]?[cls]
  getCheckedRowKeys: -> []
  getFocusedCell: -> null
  destroy: ->

global.tui = Grid: MultiSortGrid

require '../../frontend/src/views/fk_search_editor'
require '../../frontend/src/views/data_view'
require '../../frontend/src/views/data_view_helpers'
DV = global.window.DataView

makeSpace = ->
  id:     'sp1'
  name:   'multi_sort'
  fields: [
    { id: 'f1', name: 'groupe', fieldType: 'Str', formula: null, triggerFields: null }
    { id: 'f2', name: 'nom',    fieldType: 'Str', formula: null, triggerFields: null }
  ]

ROWS = [
  { __rowId: 'r1', groupe: 'B', nom: 'a' }
  { __rowId: 'r2', groupe: 'A', nom: 'b' }
  { __rowId: 'r3', groupe: 'B', nom: 'b' }
  { __rowId: 'r4', groupe: 'A', nom: 'a' }
]

# Ordonnées (groupe, nom), sentinelle exclue.
pairs = (grid) ->
  ([row.groupe, row.nom] for row in grid.getData() when not row.__isNew)

makeView = (rows = ROWS) ->
  dv = new DV (global.document.createElement 'div'), makeSpace()
  grid = new MultiSortGrid
  dv._grid = grid
  dv._rows = rows
  # Grille déjà peuplée (données chargées), comme en production avant un tri.
  dv._applyData()
  { dv, grid }

describe 'DataView — tri multicritère hiérarchique', ->
  it 'applique les critères dans l’ordre : le 1er décide, le 2e départage', ->
    { dv, grid } = makeView()
    dv._sortState = [
      { column: 'groupe', ascending: true }
      { column: 'nom', ascending: true }
    ]
    dv._applyData()
    deepEq pairs(grid), [['A', 'a'], ['A', 'b'], ['B', 'a'], ['B', 'b']]

  it 'un autre ordre de priorité change réellement l’ordre des lignes', ->
    { dv, grid } = makeView()
    dv._sortState = [
      { column: 'nom', ascending: true }
      { column: 'groupe', ascending: true }
    ]
    dv._applyData()
    deepEq pairs(grid), [['A', 'a'], ['B', 'a'], ['A', 'b'], ['B', 'b']]

  it 'conserve les deux critères après un resetData (rechargement)', ->
    { dv, grid } = makeView()
    dv.applySortEntries [
      { column: 'groupe', ascending: true }
      { column: 'nom', ascending: false }
    ]
    dv._applyData()
    deepEq dv.getSortEntries(), [
      { column: 'groupe', ascending: true }
      { column: 'nom', ascending: false }
    ]
    state = grid.getSortState()
    names = (c.columnName for c in state.columns when c.columnName != 'sortKey')
    deepEq names, ['groupe', 'nom']
    deepEq pairs(grid), [['A', 'b'], ['A', 'a'], ['B', 'b'], ['B', 'a']]

  it 'garde la sentinelle en dernier malgré le tri multiple', ->
    { dv, grid } = makeView()
    dv.applySortEntries [
      { column: 'groupe', ascending: true }
      { column: 'nom', ascending: true }
    ]
    data = grid.getData()
    assert data[data.length - 1]?.__isNew, 'la sentinelle doit rester la dernière ligne'
    eq data.length, 5

describe 'DataView — Maj+clic sur un en-tête', ->
  it 'ajoute un critère secondaire sans effacer le premier', ->
    { dv, grid } = makeView()
    dv.applySortEntries [{ column: 'groupe', ascending: true }]
    changes = 0
    dv._onSortChanged = -> changes++
    entries = dv.sortWithShiftClick 'nom'
    deepEq entries, [
      { column: 'groupe', ascending: true }
      { column: 'nom', ascending: true }
    ]
    deepEq dv.getSortEntries(), entries
    eq changes, 1
    deepEq pairs(grid), [['A', 'a'], ['A', 'b'], ['B', 'a'], ['B', 'b']]

  it 'inverse le sens d’un critère existant sans changer sa priorité', ->
    { dv, grid } = makeView()
    dv.applySortEntries [
      { column: 'groupe', ascending: true }
      { column: 'nom', ascending: true }
    ]
    entries = dv.sortWithShiftClick 'nom'
    deepEq entries, [
      { column: 'groupe', ascending: true }
      { column: 'nom', ascending: false }
    ]
    deepEq pairs(grid), [['A', 'b'], ['A', 'a'], ['B', 'b'], ['B', 'a']]

  it 'ignore un nom de colonne vide', ->
    { dv } = makeView()
    dv.applySortEntries [{ column: 'groupe', ascending: true }]
    deepEq dv.sortWithShiftClick(null), [{ column: 'groupe', ascending: true }]

summary()
