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
    constructor: (opts = {}) ->
      @_data = []
      @_columns = opts.columns or []
    resetData: (d) -> @_data = d
    getData: -> @_data
    getColumns: -> @_columns
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
    prefs = await dv._loadColWidths()
    deepEq prefs, {}

  it 'parse le JSON depuis localStorage', ->
    global.localStorage.setItem 'tdb_colwidths_sp1', JSON.stringify { nom: 200 }
    dv = new DV container(), makeSpace { id: 'sp1' }
    prefs = await dv._loadColWidths()
    eq prefs.nom, 200

  it 'retourne {} si JSON invalide', ->
    global.localStorage.setItem 'tdb_colwidths_sp1', 'not-json'
    dv = new DV container(), makeSpace { id: 'sp1' }
    prefs = await dv._loadColWidths()
    deepEq prefs, {}

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

describe 'DataView formula error rendering state', ->
  it '_applyData marque la cellule quand _repr_<field> contient une erreur', ->
    sp = makeSpace
      fields: [
        { id: 'f1', name: 'nom', fieldType: 'String', formula: null, triggerFields: null }
      ]
    dv = new DV container(), sp
    gridData = []
    dv._grid =
      resetData: (d) -> gridData = d
      getRowAt: -> null
      addRowClassName: ->
    dv._rows = [
      {
        __rowId: '1'
        nom: 'Hugo'
        _repr_nom: '[ERROR|Champ inconnu (nil)|attempt to index nil]'
      }
    ]
    dv._applyData()
    row = gridData[0]
    classes = row._attributes?.className?.column?.nom or []
    assert classes.includes('cell-formula-error'), 'cell-formula-error absente'

describe 'DataView FK maps use _repr', ->
  it '_buildFkMaps privilégie _repr pour le display FK', ->
    oldQuery = global.GQL.query
    global.GQL.query = (q, vars) ->
      Promise.resolve
        records:
          items: [
            { id: '1', data: JSON.stringify { id: 1, _repr: 'Hugo Victor' } }
            { id: '2', data: JSON.stringify { id: 2, _repr: 'Maupassant Guy' } }
          ]

    sp = makeSpace
      fields: [
        { id: 'bf1', name: 'auteur', fieldType: 'Relation', formula: null, triggerFields: null }
      ]
    relations = [
      { fromFieldId: 'bf1', toSpaceId: 'authors-space', reprFormula: '@_repr' }
    ]
    dv = new DV container(), sp, null, relations
    await dv._buildFkMaps()
    eq dv._fkMaps.auteur['1'], 'Hugo Victor'
    eq dv._fkMaps.auteur['2'], 'Maupassant Guy'
    global.GQL.query = oldQuery

describe 'DataView editable columns formatter regression', ->
  it 'FK et Boolean formatters ne renvoient pas de HTML brut', ->
    sp = makeSpace
      fields: [
        { id: 'f1', name: 'auteur', fieldType: 'Relation', formula: null, triggerFields: null }
        { id: 'f2', name: 'disponible', fieldType: 'Boolean', formula: null, triggerFields: null }
      ]
    rels = [
      { fromFieldId: 'f1', toSpaceId: 'authors-space', reprFormula: '@_repr' }
    ]

    dv = new DV container(), sp, null, rels
    dv._buildFkMaps = ->
      @_fkMaps.auteur = { '1': 'Hugo Victor' }
      @_fkOptions.auteur = [{ text: 'Hugo Victor', value: '1' }]
      Promise.resolve()
    dv._loadColWidths = -> Promise.resolve {}
    dv.load = -> Promise.resolve []
    await dv.mount()

    cols = dv._grid.getColumns()
    fkCol = cols.find (c) -> c.name == 'auteur'
    boolCol = cols.find (c) -> c.name == 'disponible'

    assert fkCol, 'colonne FK absente'
    assert boolCol, 'colonne Boolean absente'
    eq fkCol.editor?.type, 'select'
    eq boolCol.editor?.type, 'checkbox'

    fkRendered = fkCol.formatter { value: 1, row: { auteur: 1 } }
    boolRenderedTrue = boolCol.formatter { value: true, row: { disponible: true } }
    boolRenderedFalse = boolCol.formatter { value: false, row: { disponible: false } }

    assert fkRendered == 'Hugo Victor', 'le formatter FK doit renvoyer du texte pur'
    assert not String(fkRendered).includes('<'), 'le formatter FK ne doit pas renvoyer de HTML'
    eq boolRenderedTrue, '☑'
    eq boolRenderedFalse, '☐'
    assert not String(boolRenderedTrue).includes('<'), 'le formatter Boolean ne doit pas renvoyer de HTML'
    assert not String(boolRenderedFalse).includes('<'), 'le formatter Boolean ne doit pas renvoyer de HTML'

    dv.unmount()

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
