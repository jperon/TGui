# tests/js/test_data_view.coffee — tests pour DataView (data_view.js)
# Teste la logique pure (sans mount/tui.Grid).

require './dom_stub'
{ describe, it, eq, deepEq, assert, summary } = require './runner'

# Stubs requis par data_view.js
global.GQL =
  query:  -> Promise.resolve {}
  mutate: -> Promise.resolve {}

global.tui =
  Grid: class
    constructor: -> @_data = []
    resetData: (d) -> @_data = d
    getRowAt: (i) -> @_data[i] or null
    addRowClassName: ->
    on: ->
    destroy: ->
    getIndexOfRow: -> 0
    getRowCount: -> @_data.length
    getFocusedCell: -> null
    getCheckedRowKeys: -> []

require '../../frontend/src/views/data_view'
DV = global.window.DataView

makeSpace = (overrides = {}) ->
  id:     overrides.id     or 'sp1'
  name:   overrides.name   or 'test_space'
  fields: overrides.fields or [
    { id: 'f1', name: 'nom',  fieldType: 'Str',      formula: null, triggerFields: null }
    { id: 'f2', name: 'age',  fieldType: 'Int',      formula: null, triggerFields: null }
    { id: 'f3', name: 'seq',  fieldType: 'Sequence', formula: null, triggerFields: null }
  ]

container = -> global.document.createElement 'div'

# ---------------------------------------------------------------------------
describe 'DataView._sentinel', ->
  it 'produit une ligne avec __isNew et tous les champs non-Sequence', ->
    dv = new DV container(), makeSpace()
    s  = dv._sentinel()
    assert s.__isNew, '__isNew absent'
    assert 'nom' of s, 'nom manquant'
    assert 'age' of s, 'age manquant'
    assert not ('seq' of s), 'seq (Sequence) ne doit pas figurer dans le sentinel'

  it 'utilise les defaultValues', ->
    dv = new DV container(), makeSpace()
    dv.setDefaultValues { nom: 'Alice' }
    s  = dv._sentinel()
    eq s.nom, 'Alice'
    eq s.age, ''   # pas dans defaults

  it 'retourne chaîne vide pour les champs sans default', ->
    dv = new DV container(), makeSpace()
    s  = dv._sentinel()
    eq s.nom, ''
    eq s.age, ''

describe 'DataView._lsKey', ->
  it 'inclut l\'id de l\'espace', ->
    dv = new DV container(), makeSpace { id: 'abc' }
    eq dv._lsKey(), 'tdb_colwidths_abc'

describe 'DataView._loadColWidths', ->
  it 'retourne {} si rien en localStorage', ->
    global.localStorage.clear()
    dv = new DV container(), makeSpace()
    deepEq dv._loadColWidths(), {}

  it 'parse le JSON depuis localStorage', ->
    global.localStorage.setItem 'tdb_colwidths_sp1', JSON.stringify { nom: 200 }
    dv = new DV container(), makeSpace { id: 'sp1' }
    eq dv._loadColWidths().nom, 200

  it 'retourne {} si JSON invalide', ->
    global.localStorage.setItem 'tdb_colwidths_sp1', 'not-json'
    dv = new DV container(), makeSpace { id: 'sp1' }
    deepEq dv._loadColWidths(), {}

describe 'DataView.setDefaultValues', ->
  it 'stocke les valeurs et les reflète dans le sentinel', ->
    dv = new DV container(), makeSpace()
    dv.setDefaultValues { age: '42' }
    eq dv._sentinel().age, '42'

  it 'accepte null/undefined → remet à zéro', ->
    dv = new DV container(), makeSpace()
    dv.setDefaultValues { nom: 'Bob' }
    dv.setDefaultValues null
    deepEq dv._defaultValues, {}

describe 'DataView.setFilter + _applyData', ->
  it 'setFilter met à jour @filter', ->
    dv = new DV container(), makeSpace()
    dv.setFilter { field: 'age', value: '30' }
    eq dv.filter.field, 'age'
    eq dv.filter.value, '30'

  it '_applyData filtre les lignes par field/value', ->
    sp = makeSpace()
    dv = new DV container(), sp
    # Monte un grid mock minimal
    gridData = []
    dv._grid =
      resetData: (d) -> gridData = d
      getRowAt: (i) -> null
      addRowClassName: ->
    dv._rows = [
      { __rowId: '1', nom: 'Alice', age: '30' }
      { __rowId: '2', nom: 'Bob',   age: '25' }
      { __rowId: '3', nom: 'Carol', age: '30' }
    ]
    dv.filter = { field: 'age', value: '30' }
    dv._applyData()
    # sentinel excluded from assertion count, so total = 2 data + 1 sentinel
    eq gridData.length, 3
    assert gridData[0].nom is 'Alice', 'première ligne filtrée incorrecte'
    assert gridData[1].nom is 'Carol', 'deuxième ligne filtrée incorrecte'
    assert gridData[2].__isNew, 'sentinel absent en fin'

  it '_applyData sans filtre inclut toutes les lignes', ->
    sp = makeSpace()
    dv = new DV container(), sp
    gridData = []
    dv._grid =
      resetData: (d) -> gridData = d
      getRowAt: -> null
      addRowClassName: ->
    dv._rows = [
      { __rowId: '1', nom: 'Alice' }
      { __rowId: '2', nom: 'Bob'   }
    ]
    dv._applyData()
    eq gridData.length, 3   # 2 data + 1 sentinel

describe 'DataView.unmount', ->
  it 'remet _mounted à false et vide les tableaux', ->
    dv = new DV container(), makeSpace()
    dv._mounted = true
    dv._rows = [{ __rowId: '1' }]
    dv._currentData = [{ __rowId: '1' }]
    dv._pasteListener = null
    dv._grid = null
    dv.unmount()
    assert not dv._mounted, '_mounted doit être false'
    eq dv._rows.length, 0
    eq dv._currentData.length, 0

summary()
