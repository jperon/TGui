# tests/js/test_drag_drop_manager.coffee - tests for DragDropManager

require './dom_stub'
{ describe, it, eq, assert, summary } = require './runner'

global.window = global.window or {}
global.document = global.document or {}
global.Sortable = global.Sortable or class Sortable
  constructor: (el, opts) ->
    @el = el
    @opts = opts
  option: (key, value) ->
    if value isnt undefined
      @opts[key] = value
    @opts[key]
  destroy: ->

global.document.createElement = (tag) ->
  tagName: tag.toUpperCase()
  classList:
    add: ->
    remove: ->
    contains: -> false
  querySelectorAll: -> []
  addEventListener: ->
  setAttribute: ->
  getAttribute: -> null
  parentElement: null
  closest: -> null

global.document.body = global.document.body or
  classList:
    add: ->
    remove: ->

require '../../frontend/src/drag_drop_manager'

describe 'DragDropManager', ->
  it 'exports DragDropManager class', ->
    eq typeof window.DragDropManager, 'function'

  it 'can be instantiated with container and options', ->
    container = document.createElement 'div'
    ddm = new window.DragDropManager container, { pageId: 'test-page' }
    assert ddm != null, 'DragDropManager instance should exist'

  it 'stores container reference', ->
    container = document.createElement 'div'
    ddm = new window.DragDropManager container, { pageId: 'test-page' }
    eq ddm.container, container

  it 'stores options', ->
    container = document.createElement 'div'
    opts = { pageId: 'test-page', foo: 'bar' }
    ddm = new window.DragDropManager container, opts
    eq ddm.options.foo, 'bar'

  it 'initializes with null sortable when no container', ->
    ddm = new window.DragDropManager null, { pageId: 'test-page' }
    eq ddm.sortable, null

  it 'has extractWidgetPositions method', ->
    container = document.createElement 'div'
    ddm = new window.DragDropManager container, { pageId: 'test-page' }
    eq typeof ddm.extractWidgetPositions, 'function'

  it 'has enable and disable methods', ->
    container = document.createElement 'div'
    ddm = new window.DragDropManager container, { pageId: 'test-page' }
    assert typeof ddm.enable is 'function', 'enable should be a function'
    assert typeof ddm.disable is 'function', 'disable should be a function'

  it 'has destroy method', ->
    container = document.createElement 'div'
    ddm = new window.DragDropManager container, { pageId: 'test-page' }
    eq typeof ddm.destroy, 'function'

  it 'has getWidgetOrder method', ->
    container = document.createElement 'div'
    ddm = new window.DragDropManager container, { pageId: 'test-page' }
    eq typeof ddm.getWidgetOrder, 'function'

  it 'has zone management methods', ->
    container = document.createElement 'div'
    ddm = new window.DragDropManager container, { pageId: 'test-page' }
    assert typeof ddm.scanZones is 'function', 'scanZones should be a function'
    assert typeof ddm.getZoneById is 'function', 'getZoneById should be a function'
    assert typeof ddm.createZone is 'function', 'createZone should be a function'

  it 'has updatePageId method', ->
    container = document.createElement 'div'
    ddm = new window.DragDropManager container, { pageId: 'test-page' }
    ddm.updatePageId 'new-page-id'
    eq ddm.currentPageId, 'new-page-id'

summary()
