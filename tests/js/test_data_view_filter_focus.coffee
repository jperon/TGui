# tests/js/test_data_view_filter_focus.coffee — DataView.load focus handling.
# The live formula filter input lives outside the DataView container: a reload it
# triggers must not restore a grid cell focus, otherwise the user loses the focus
# (and the caret) while typing. A reload triggered from inside the grid must still
# restore the cell focus (cell edit case).
#
# Kept in its own file: it drives load() end to end and must not interleave with
# the shared #formula-filter-input stub used by test_data_view.coffee.

require './dom_stub'
{ describe, it, eq, deepEq, summary } = require './runner'

# TdbHtml.escape is required by data_view._escapeHtml / _formatFormulaError
require '../../frontend/src/html_escape'

global.GQL =
  query:  -> Promise.resolve {}
  mutate: -> Promise.resolve {}

global.tui =
  Grid: class
    constructor: -> @_data = []
    resetData: (d) -> @_data = d
    getData: -> @_data
    getColumns: -> []
    getRowAt: (i) -> @_data[i] or null
    addRowClassName: ->
    on: ->
    destroy: ->
    getFocusedCell: -> null
    getCheckedRowKeys: -> []

require '../../frontend/src/views/fk_search_editor'
require '../../frontend/src/views/data_view'
require '../../frontend/src/views/data_view_helpers'
DV = global.window.DataView

makeSpace = ->
  id:     'sp1'
  name:   'test_space'
  fields: [
    { id: 'f1', name: 'nom', fieldType: 'Str',      formula: null, triggerFields: null }
    { id: 'f2', name: 'age', fieldType: 'Int',      formula: null, triggerFields: null }
  ]

container = -> global.document.createElement 'div'

# Grid stub whose focused cell points at the first row: load() must only consult
# it when the browser focus is inside the DataView container.
makeFocusGrid = ->
  calls = { focus: [] }
  grid =
    _data: [{ __rowId: 'r1', nom: 'Alice', rowKey: 0 }]
    resetData: (d) ->
      d.forEach (r, i) -> r.rowKey ?= i
      @_data = d
    getData:   -> @_data
    getRow:    (k) -> @_data[k] or null
    getRowAt:  (i) -> @_data[i] or null
    addRowClassName: ->
    getFocusedCell: -> { rowKey: 0, columnName: 'nom' }
    focus: (rowKey, columnName) -> calls.focus.push [rowKey, columnName]
  { grid, calls }

# Reload the grid with two server rows.
stubQuery = ->
  oldQuery = global.GQL.query
  global.GQL.query = ->
    Promise.resolve
      records:
        items: [
          { id: 'r1', data: JSON.stringify { nom: 'Alice' } }
          { id: 'r2', data: JSON.stringify { nom: 'Bob' } }
        ]
  oldQuery

tick = -> new Promise (resolve) -> setTimeout resolve, 0

describe 'DataView.load focus preservation', ->
  it 'does not restore a grid focus when the focus is outside the container', ->
    oldQuery = stubQuery()
    dv = new DV container(), makeSpace()
    { grid, calls } = makeFocusGrid()
    dv._grid    = grid
    dv._mounted = true
    # The formula filter input: outside the DataView container.
    global.document.activeElement = global.document.createElement 'input'

    await dv.load()
    await tick()
    global.GQL.query = oldQuery
    global.document.activeElement = null

    eq dv._lastFocus, null
    eq calls.focus.length, 0

  it 'still restores the grid focus when the focus is inside the container', ->
    oldQuery = stubQuery()
    dv   = new DV container(), makeSpace()
    { grid, calls } = makeFocusGrid()
    dv._grid    = grid
    dv._mounted = true
    wrapper = global.document.createElement 'div'
    dv.container.appendChild wrapper
    global.document.activeElement = wrapper

    await dv.load()
    await tick()
    global.GQL.query = oldQuery
    global.document.activeElement = null

    eq dv._lastFocus, null   # consumed by _applyData
    deepEq calls.focus, [[0, 'nom']]

summary()
