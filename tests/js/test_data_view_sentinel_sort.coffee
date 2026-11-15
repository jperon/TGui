# tests/js/test_data_view_sentinel_sort.coffee
# La ligne sentinelle `__isNew` (saisie d'un nouvel enregistrement) doit rester
# la dernière ligne VISUELLE, même quand un tri est réappliqué après resetData
# (préréglage de vue, tri manuel mémorisé). Toast UI Grid trie toutes les lignes,
# sentinelle comprise : sans correctif, la sentinelle remonte au milieu et la
# classe `tdb-new-row` atterrit sur un vrai enregistrement.

require './dom_stub'
{ describe, it, eq, assert, summary } = require './runner'

# TdbHtml.escape is required by data_view._escapeHtml / _formatFormulaError
require '../../frontend/src/html_escape'

global.GQL =
  query:  -> Promise.resolve {}
  mutate: -> Promise.resolve {}

# Grille factice qui trie réellement : reproduit le comparateur par défaut de
# Toast UI Grid (les valeurs vides passent avant les autres en ordre croissant).
compare = (a, b) ->
  isBlank = (v) -> not v? or v == ''
  ca = if isBlank(a) then null else (if isNaN(Number(a)) then String(a) else Number(a))
  cb = if isBlank(b) then null else (if isNaN(Number(b)) then String(b) else Number(b))
  return -1 if ca == null and cb != null
  return 1 if ca != null and cb == null
  return 0 if ca == cb
  if ca < cb then -1 else 1

class SortGrid
  constructor: ->
    @_data = []
    @_classes = {}
    @_sortState = { columns: [{ columnName: 'sortKey', ascending: true }] }
  resetData: (rows, options = {}) ->
    rows = rows or []
    rows.forEach (row, i) -> row.rowKey = i unless row.rowKey?
    @_data = rows
    # resetData remet le tri à son état initial, sauf `sortState` explicite.
    if options.sortState
      @_sortState = { columns: [options.sortState] }
    else
      @_sortState = { columns: [{ columnName: 'sortKey', ascending: true }] }
  unsort: ->
    @_sortState = { columns: [{ columnName: 'sortKey', ascending: true }] }
  sort: (columnName, ascending) ->
    @_sortState = { columns: [{ columnName, ascending }] }
    @_data = @_data.slice().sort (a, b) ->
      res = compare a[columnName], b[columnName]
      if ascending then res else -res
  getSortState: -> { columns: (Object.assign {}, c) for c in @_sortState.columns }
  getData: -> @_data
  getRowAt: (i) -> @_data[i] or null
  getRow: (key) -> @_data[Number key] or null
  addRowClassName: (key, cls) ->
    (@_classes[String key] ?= {})[cls] = true
  removeRowClassName: (key, cls) ->
    delete @_classes[String key]?[cls]
  getCheckedRowKeys: -> []
  getFocusedCell: -> null
  destroy: ->
  # helpers de test
  hasClass: (key, cls) -> !! @_classes[String key]?[cls]
  keyFor: (predicate) ->
    row = @_data.find predicate
    row?.rowKey
  resetCalls: -> @_resetCalls or []

global.tui = Grid: SortGrid

require '../../frontend/src/views/fk_search_editor'
require '../../frontend/src/views/data_view'
require '../../frontend/src/views/data_view_helpers'
DV = global.window.DataView

makeSpace = ->
  id:     'sp1'
  name:   'test_space'
  fields: [
    { id: 'f1', name: 'nom', fieldType: 'Str', formula: null, triggerFields: null }
    { id: 'f2', name: 'age', fieldType: 'Int', formula: null, triggerFields: null }
  ]

container = -> global.document.createElement 'div'

# DataView prête à afficher, sans mount() (grille fournie par le test).
makeView = (rows) ->
  dv = new DV container(), makeSpace()
  grid = new SortGrid
  dv._grid = grid
  dv._rows = rows
  { dv, grid }

VISUAL_ORDER = (grid) -> (row.__rowId or 'sentinel' for row in grid.getData())

describe 'DataView — sentinelle et tri', ->
  it 'reste la dernière ligne visuelle après réapplication du tri ascendant', ->
    { dv, grid } = makeView [
      { __rowId: 'r1', nom: 'Zoe',   age: 40 }
      { __rowId: 'r2', nom: 'Alice', age: 20 }
    ]
    dv._sortState = [{ column: 'nom', ascending: true }]
    dv._applyData()

    order = VISUAL_ORDER grid
    eq order[order.length - 1], 'sentinel'
    # Tri effectif des vraies lignes (contrôle : le correctif ne casse pas le tri).
    eq order[0], 'r2'   # Alice
    eq order[1], 'r1'   # Zoe

  it 'marque la sentinelle (et elle seule) avec tdb-new-row', ->
    { dv, grid } = makeView [
      { __rowId: 'r1', nom: 'Zoe' }
      { __rowId: 'r2', nom: 'Alice' }
    ]
    dv._sortState = [{ column: 'nom', ascending: true }]
    dv._applyData()

    sentinelKey = grid.keyFor (r) -> r.__isNew
    assert sentinelKey?, 'la sentinelle doit être présente dans la grille'
    assert grid.hasClass(sentinelKey, 'tdb-new-row'), 'la sentinelle doit porter tdb-new-row'
    for row in grid.getData() when not row.__isNew
      assert not grid.hasClass(row.rowKey, 'tdb-new-row'),
        "la ligne #{row.__rowId} ne doit pas porter tdb-new-row"

  it 'reste en bas après un rechargement du filtre, tri inchangé', ->
    { dv, grid } = makeView [
      { __rowId: 'r1', nom: 'Zoe' }
      { __rowId: 'r2', nom: 'Alice' }
    ]
    dv._sortState = [{ column: 'nom', ascending: true }]
    dv._applyData()
    # Filtre modifié : _applyData repart de zéro puis réapplique le tri.
    dv.filter = { field: 'nom', value: 'Alice' }
    dv._applyData()

    order = VISUAL_ORDER grid
    eq order.length, 2                  # Alice + sentinelle
    eq order[order.length - 1], 'sentinel'
    eq order[0], 'r2'

  it 'sans tri, la sentinelle reste la dernière ligne', ->
    { dv, grid } = makeView [
      { __rowId: 'r1', nom: 'Zoe' }
      { __rowId: 'r2', nom: 'Alice' }
    ]
    dv._applyData()
    order = VISUAL_ORDER grid
    eq order[order.length - 1], 'sentinel'

summary()
