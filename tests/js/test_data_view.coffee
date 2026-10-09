# tests/js/test_data_view.coffee — tests for DataView (data_view.js)
# Tests pure logic (without mount/tui.Grid).

require './dom_stub'
{ describe, it, eq, deepEq, assert, summary } = require './runner'

# TdbHtml.escape is required by data_view._escapeHtml / _formatFormulaError
require '../../frontend/src/html_escape'

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

require '../../frontend/src/views/fk_search_editor'
require '../../frontend/src/views/data_view'
require '../../frontend/src/views/data_view_helpers'
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

describe 'DataView hidden link columns', ->
  it 'transmits a hidden field to tui.Grid as a hidden column', ->
    sp = makeSpace
      fields: [
        { id: 'f1', name: 'nom',   fieldType: 'String', formula: null, triggerFields: null }
        { id: 'f2', name: 'livre', fieldType: 'Int',    formula: null, triggerFields: null, hidden: true }
      ]
    dv = new DV container(), sp
    dv._loadColWidths = -> Promise.resolve {}
    dv.load = -> Promise.resolve []
    await dv.mount()

    cols = dv._grid.getColumns()
    hidden = cols.find (c) -> c.name == 'livre'
    assert hidden, 'hidden field must keep a grid column'
    assert hidden.hidden is true, 'hidden column must carry hidden:true'
    nom = cols.find (c) -> c.name == 'nom'
    assert not nom.hidden, 'visible column must not be hidden'

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

describe 'DataView.setActiveRow', ->
  makeGrid = ->
    classes = {}
    grid =
      resetData: -> @_data = arguments[0]
      getRowAt: -> null
      addRowClassName: (key, cls) ->
        (classes[String key] ?= {})[cls] = true
      removeRowClassName: (key, cls) ->
        delete classes[String key]?[cls]
      hasClass: (key, cls) -> !! classes[String key]?[cls]
      countClass: (cls) ->
        n = 0
        n += 1 for _k, v of classes when v[cls]
        n
    { grid, classes }

  it 'marks the given row and clears the previous one', ->
    dv = new DV container(), makeSpace()
    { grid } = makeGrid()
    dv._grid = grid
    dv.setActiveRow 0
    assert grid.hasClass(0, 'tdb-selected-row'), 'row 0 not marked'
    dv.setActiveRow 1
    assert grid.hasClass(1, 'tdb-selected-row'), 'row 1 not marked'
    assert not grid.hasClass(0, 'tdb-selected-row'), 'row 0 should be cleared'
    eq grid.countClass('tdb-selected-row'), 1

  it 'clears the active row when rowKey is null', ->
    dv = new DV container(), makeSpace()
    { grid } = makeGrid()
    dv._grid = grid
    dv.setActiveRow 2
    dv.setActiveRow null
    eq grid.countClass('tdb-selected-row'), 0
    eq dv._activeRowKey, null

describe 'DataView filter none', ->
  it 'setFilter {none:true} shows zero rows (no sentinel)', ->
    dv = new DV container(), makeSpace()
    gridData = []
    dv._grid =
      resetData: (d) -> gridData = d
      getRowAt: -> null
      addRowClassName: ->
      removeRowClassName: ->
    dv._rows = [ { __rowId: '1', nom: 'Alice' }, { __rowId: '2', nom: 'Bob' } ]
    dv.setFilter { field: 'nom', value: null, none: true }
    eq gridData.length, 0
    eq dv._currentData.length, 0

  it 'a normal setFilter still works after a none filter', ->
    dv = new DV container(), makeSpace()
    gridData = []
    dv._grid =
      resetData: (d) -> gridData = d
      getRowAt: -> null
      addRowClassName: ->
      removeRowClassName: ->
    dv._rows = [ { __rowId: '1', nom: 'Alice' } ]
    dv.setFilter { field: 'nom', value: null, none: true }
    dv.setFilter { field: 'nom', value: 'Alice' }
    eq gridData.length, 2   # Alice + sentinel
    assert gridData[1].__isNew

describe 'DataView.load computed path selection', ->
  it 'uses the dynamic space query when the only computed field is a trigger (triggerFields = [])', ->
    oldQuery = global.GQL.query
    queries  = []
    global.GQL.query = (q, vars) ->
      queries.push q
      Promise.resolve
        test_space: { items: [] }
        records:    { items: [], total: 0 }

    sp = makeSpace
      fields: [
        { id: 'f1', name: 'eleve_nom', fieldType: 'Str', formula: '@first', triggerFields: [] }
      ]
    dv = new DV container(), sp
    dv._mounted = true
    await dv.load()
    global.GQL.query = oldQuery

    assert queries.length > 0, 'no GraphQL query issued'
    assert queries[0].indexOf('test_space(limit: 2000') >= 0,
      "expected the dynamic space query, got: #{queries[0].substring 0, 60}"

  it 'still uses the plain records query for a space without computed fields', ->
    oldQuery = global.GQL.query
    queries  = []
    global.GQL.query = (q, vars) ->
      queries.push q
      Promise.resolve
        test_space: { items: [] }
        records:    { items: [], total: 0 }

    dv = new DV container(), makeSpace()
    dv._mounted = true
    await dv.load()
    global.GQL.query = oldQuery

    assert queries.length > 0, 'no GraphQL query issued'
    assert queries[0].indexOf('query Records') >= 0,
      "expected the plain records query, got: #{queries[0].substring 0, 60}"

# An active formula filter must not push a computed space onto the plain
# records query: read-computed columns have no stored value, so the dynamic
# space query (which accepts a RecordFilter) has to serve the filtered rows.
describe 'DataView.load with formula filter', ->
  computedSpace = ->
    makeSpace
      fields: [
        { id: 'f1', name: 'nom',       fieldType: 'Str', formula: null, triggerFields: null }
        { id: 'f2', name: 'eleve_nom', fieldType: 'Str', formula: '@eleve and @eleve.descriptif', triggerFields: null }
      ]

  it 'routes an active filter through the dynamic query with a $filter variable', ->
    oldQuery  = global.GQL.query
    queries   = []
    varBodies = []
    global.GQL.query = (q, vars) ->
      queries.push q
      varBodies.push vars
      Promise.resolve
        test_space: { items: [] }
        records:    { items: [], total: 0 }

    dv = new DV container(), computedSpace()
    dv._mounted = true
    dv._formulaFilter = '@x'
    await dv.load()
    global.GQL.query = oldQuery

    assert queries.length > 0, 'no GraphQL query issued'
    assert queries[0].indexOf('query') >= 0,
      "not a GraphQL query: #{queries[0].substring 0, 60}"
    assert queries[0].indexOf('test_space(limit: 2000') >= 0,
      "expected the dynamic space query, got: #{queries[0].substring 0, 80}"
    assert queries[0].indexOf('$filter') >= 0,
      "expected a $filter variable, got: #{queries[0].substring 0, 80}"
    deepEq varBodies[0].filter, { formula: '@x', language: 'moonscript' }

  it 'still uses the plain records query with an active filter on a space without computed fields', ->
    oldQuery = global.GQL.query
    queries  = []
    global.GQL.query = (q, vars) ->
      queries.push q
      Promise.resolve
        test_space: { items: [] }
        records:    { items: [], total: 0 }

    dv = new DV container(), makeSpace()
    dv._mounted = true
    dv._formulaFilter = '@x'
    await dv.load()
    global.GQL.query = oldQuery

    assert queries.length > 0, 'no GraphQL query issued'
    assert queries[0].indexOf('query Records') >= 0,
      "expected the plain records query, got: #{queries[0].substring 0, 60}"

  it 'flags the formula inputs on a failing filtered query and clears them on success', ->
    oldQuery = global.GQL.query
    input    = global.document.createElement 'input'
    byId     = global.document.createElement 'div'
    global.document._setById 'formula-filter-input', byId
    failing  = true
    global.GQL.query = ->
      if failing
        Promise.reject new Error 'bad formula'
      else
        Promise.resolve { test_space: { items: [] }, records: { items: [], total: 0 } }

    dv = new DV container(), computedSpace()
    dv._mounted = true
    dv._formulaFilter = '@x'
    dv._formulaInputEl = input
    await dv.load()
    clearTimeout dv._errorTimer
    assert input.classList.contains('input-error'), 'input-error missing on @_formulaInputEl'
    assert byId.classList.contains('input-error'), 'input-error missing on #formula-filter-input'
    eq dv._rows.length, 0

    failing = false
    await dv.load()
    assert not input.classList.contains('input-error'), 'input-error not cleared on @_formulaInputEl'
    assert not byId.classList.contains('input-error'), 'input-error not cleared on #formula-filter-input'
    global.GQL.query = oldQuery
    global.document._setById 'formula-filter-input', null


# Freeze the public prototype surface so the data_view / data_view_helpers split
# cannot silently drop or rename a method.
describe 'DataView prototype surface (frozen)', ->
  it 'exposes exactly the expected set of methods', ->
    expected = [
      '_actionContext', '_applyData', '_buildFkMaps', '_clearError',
      '_cloneJson', '_coerceCellValue', '_columnWidth', '_defaultCellValue',
      '_escapeHtml', '_extractInsertedRecords', '_formatFormulaError',
      '_loadColWidths', '_lsKey', '_saveColWidths', '_sentinel',
      '_serializeRowForMutation', '_showError', '_toBoolean', 'constructor',
      'deleteSelected', 'getFocusedColumnName', 'insertBlank', 'load', 'mount',
      'setActiveRow', 'setDefaultValues', 'setFilter', 'setFormulaFilter', 'unmount'
    ]
    deepEq Object.getOwnPropertyNames(DV.prototype).sort(), expected

summary()
