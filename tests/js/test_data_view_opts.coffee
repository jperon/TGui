# tests/js/test_data_view_opts.coffee — tests for DataView options (readOnly)
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
  ]

container = -> global.document.createElement 'div'

describe 'DataView options', ->
  it 'stores opts object in constructor', ->
    dv = new DV container(), makeSpace(), null, [], { foo: 'bar' }
    assert dv.opts?, 'opts must exist'
    eq dv.opts.foo, 'bar'

  it 'stores empty opts object when not provided', ->
    dv = new DV container(), makeSpace()
    assert dv.opts?, 'opts must exist'
    deepEq dv.opts, {}

  it 'readOnly option is accessible', ->
    dv = new DV container(), makeSpace(), null, [], { readOnly: true }
    eq dv.opts.readOnly, true

  it 'readOnly option defaults to undefined when not provided', ->
    dv = new DV container(), makeSpace()
    eq dv.opts.readOnly, undefined

  it 'opts.onColumnFocus is stored when provided', ->
    cb = -> console.log 'focus'
    dv = new DV container(), makeSpace(), null, [], { onColumnFocus: cb }
    eq dv.opts.onColumnFocus, cb

  it 'opts is preserved after multiple operations', ->
    dv = new DV container(), makeSpace(), null, [], { readOnly: true, custom: 'value' }
    dv._mounted = true
    dv._rows = []
    dv._currentData = []
    eq dv.opts.readOnly, true
    eq dv.opts.custom, 'value'

summary()
