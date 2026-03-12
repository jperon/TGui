# tests/js/test_data_view.coffee — tests for DataView (data_view.js)
# Tests pure logic (without mount/tui.Grid).

require './dom_stub'
{ describe, it, eq, deepEq, assert, summary } = require './runner'

# Stubs required by data_view.js
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
  it 'produces a row with __isNew and all non-Sequence fields', ->
    dv = new DV container(), makeSpace()
    s  = dv._sentinel()
    assert s.__isNew, '__isNew missing'
    assert 'nom' of s, 'nom missing'
    assert 'age' of s, 'age missing'
    assert not ('seq' of s), 'seq (Sequence) must not appear in sentinel'

  it 'uses defaultValues', ->
    dv = new DV container(), makeSpace()
    dv.setDefaultValues { nom: 'Alice' }
    s  = dv._sentinel()
    eq s.nom, 'Alice'
    eq s.age, ''   # not in defaults

  it 'returns empty string for fields without default', ->
    dv = new DV container(), makeSpace()
    s  = dv._sentinel()
    eq s.nom, ''
    eq s.age, ''

describe 'DataView._lsKey', ->
  it 'includes space id', ->
    dv = new DV container(), makeSpace { id: 'abc' }
    eq dv._lsKey(), 'tdb_colwidths_abc'

describe 'DataView._loadColWidths', ->
  it 'returns {} when localStorage is empty', ->
    global.localStorage.clear()
    dv = new DV container(), makeSpace()
    prefs = await dv._loadColWidths()
    deepEq prefs, {}

  it 'parses JSON from localStorage', ->
    global.localStorage.setItem 'tdb_colwidths_sp1', JSON.stringify { nom: 200 }
    dv = new DV container(), makeSpace { id: 'sp1' }
    prefs = await dv._loadColWidths()
    eq prefs.nom, 200

  it 'returns {} on invalid JSON', ->
    global.localStorage.setItem 'tdb_colwidths_sp1', 'not-json'
    dv = new DV container(), makeSpace { id: 'sp1' }
    prefs = await dv._loadColWidths()
    deepEq prefs, {}

describe 'DataView.setDefaultValues', ->
  it 'stores values and reflects them in sentinel', ->
    dv = new DV container(), makeSpace()
    dv.setDefaultValues { age: '42' }
    eq dv._sentinel().age, '42'

  it 'accepts null/undefined -> resets state', ->
    dv = new DV container(), makeSpace()
    dv.setDefaultValues { nom: 'Bob' }
    dv.setDefaultValues null
    deepEq dv._defaultValues, {}

describe 'DataView.setFilter + _applyData', ->
  it 'setFilter updates @filter', ->
    dv = new DV container(), makeSpace()
    dv.setFilter { field: 'age', value: '30' }
    eq dv.filter.field, 'age'
    eq dv.filter.value, '30'

  it '_applyData filters rows by field/value', ->
    sp = makeSpace()
    dv = new DV container(), sp
    # Mount a minimal mocked grid
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
    assert gridData[0].nom is 'Alice', 'first filtered row is incorrect'
    assert gridData[1].nom is 'Carol', 'second filtered row is incorrect'
    assert gridData[2].__isNew, 'missing sentinel at end'

  it '_applyData without filter includes all rows', ->
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
  it '_applyData marks cell when _repr_<field> contains an error', ->
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
    assert classes.includes('cell-formula-error'), 'cell-formula-error missing'

describe 'DataView FK maps use _repr', ->
  it '_buildFkMaps prioritizes _repr for FK display', ->
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
  it 'FK and Boolean formatters do not return raw HTML', ->
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

    assert fkCol, 'missing FK column'
    assert boolCol, 'missing Boolean column'
    assert typeof fkCol.editor?.type is 'function', 'missing custom FK editor'
    eq fkCol.editor?.type?.name, 'FkSearchEditor'
    eq boolCol.editor?.type, 'checkbox'

    fkRendered = fkCol.formatter { value: 1, row: { auteur: 1 } }
    boolRenderedTrue = boolCol.formatter { value: true, row: { disponible: true } }
    boolRenderedFalse = boolCol.formatter { value: false, row: { disponible: false } }

    assert fkRendered == 'Hugo Victor', 'FK formatter must return plain text'
    assert not String(fkRendered).includes('<'), 'FK formatter must not return HTML'
    eq boolRenderedTrue, '☑'
    eq boolRenderedFalse, '☐'
    assert not String(boolRenderedTrue).includes('<'), 'Boolean formatter must not return HTML'
    assert not String(boolRenderedFalse).includes('<'), 'Boolean formatter must not return HTML'

    dv.unmount()

describe 'DataView FK fuzzy autocomplete editor', ->
  it 'supports fuzzy search and maps label -> id', ->
    sp = makeSpace
      fields: [
        { id: 'f1', name: 'auteur', fieldType: 'Relation', formula: null, triggerFields: null }
      ]
    rels = [
      { fromFieldId: 'f1', toSpaceId: 'authors-space', reprFormula: '@_repr' }
    ]

    dv = new DV container(), sp, null, rels
    dv._buildFkMaps = ->
      @_fkMaps.auteur = { '1': 'Hugo Victor', '2': 'Camus Albert' }
      @_fkOptions.auteur = [
        { text: 'Hugo Victor', value: '1' }
        { text: 'Camus Albert', value: '2' }
      ]
      Promise.resolve()
    dv._loadColWidths = -> Promise.resolve {}
    dv.load = -> Promise.resolve []
    await dv.mount()

    fkCol = dv._grid.getColumns().find (c) -> c.name == 'auteur'
    Editor = fkCol.editor?.type
    assert typeof Editor is 'function', 'missing FK editor class'

    editor = new Editor
      value: ''
      columnInfo:
        editor:
          options:
            items: dv._fkOptions.auteur

    el = editor.getElement()
    assert not ('list' of el), 'FK editor must not use a native datalist'

    matches = editor._filterItems 'hgo'
    assert matches.length > 0, 'no fuzzy result'
    eq matches[0].label, 'Hugo Victor'

    editor._renderMenu 'hgo'
    eq editor.visibleItems[0].label, 'Hugo Victor'
    editor._applySelection 0
    eq editor.getValue(), '1'

    dv.unmount()

describe 'DataView.unmount', ->
  it 'sets _mounted to false and clears arrays', ->
    dv = new DV container(), makeSpace()
    dv._mounted = true
    dv._rows = [{ __rowId: '1' }]
    dv._currentData = [{ __rowId: '1' }]
    dv._pasteListener = null
    dv._grid = null
    dv.unmount()
    assert not dv._mounted, '_mounted must be false'
    eq dv._rows.length, 0
    eq dv._currentData.length, 0

summary()
