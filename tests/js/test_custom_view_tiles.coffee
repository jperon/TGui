# tests/js/test_custom_view_tiles.coffee — page "tile" mode (T19).
#
# Part 1: page zones must fill the whole surface (CSS) and grid layouts must be
# refreshed when a tile is resized (ResizeObserver).
# Part 2 (added later): splitter persistence helpers and splitter rendering.

require './dom_stub'
{ describe, it, eq, deepEq, assert, summary } = require './runner'
fs   = require 'fs'
path = require 'path'

# --- stubs ------------------------------------------------------------------
# jsyaml.load/dump are backed by JSON: test fixtures are JSON documents and the
# pure helpers (setChildFactors) only care about structure, not YAML syntax.
global.jsyaml =
  load: (src) -> JSON.parse src
  dump: (obj) -> JSON.stringify obj

global.DataView = class DataView
  constructor: (@container, @space) ->
    @mounted = false
  mount: -> @mounted = true
  refreshLayout: ->
  unmount: ->

require '../../frontend/src/views/custom_view'
require '../../frontend/src/views/custom_view_plugins'
require '../../frontend/src/views/custom_view_aggregate'
require '../../frontend/src/views/custom_view_resize'
CV = global.window.CustomView

# --- helpers ----------------------------------------------------------------
makeSpaces = ->
  [
    { id: '1', name: 'personnes', fields: [
        { id: 'f1', name: 'nom', fieldType: 'Str' }
    ]}
    { id: '2', name: 'groupes', fields: [
        { id: 'g1', name: 'titre', fieldType: 'Str' }
    ]}
  ]

makeContainer = -> global.document.createElement 'div'

makePageContainer = (pageId) ->
  c = global.document.createElement 'div'
  c.setAttribute 'data-page-id', pageId if pageId
  c

# Depth-first collection of descendants whose className contains `cls`.
collectByClass = (root, cls) ->
  out = []
  for child in (root._children or [])
    classes = (child.className or '').split ' '
    out.push child if classes.indexOf(cls) >= 0
    out = out.concat collectByClass child, cls
  out

# ---------------------------------------------------------------------------
# Part 1 — the page surface is filled by its tiles.
# ---------------------------------------------------------------------------
describe 'app.css — page zones fill their surface (T19 part 1)', ->
  css = fs.readFileSync path.join(__dirname, '../../frontend/css/app.css'), 'utf8'

  it 'the .cv-zone rule stretches its cross axis', ->
    m = css.match /\.cv-zone\s*\{([^}]*)\}/
    assert m, ".cv-zone rule not found in app.css"
    assert /align-items\s*:\s*stretch/.test(m[1]),
      ".cv-zone must set align-items: stretch; got: #{m[1]}"

  it 'the .cv-zone rule aligns its content to flex-start', ->
    m = css.match /\.cv-zone\s*\{([^}]*)\}/
    assert m, ".cv-zone rule not found in app.css"
    assert /justify-content\s*:\s*flex-start/.test(m[1]),
      ".cv-zone must set justify-content: flex-start; got: #{m[1]}"

  it 'tiles lose the 2px margin so they touch', ->
    m = css.match /\.cv-zone\s+\.cv-widget\s*\{([^}]*)\}/
    assert m, ".cv-zone .cv-widget rule not found in app.css"
    assert /margin\s*:\s*0/.test(m[1]),
      ".cv-zone .cv-widget must set margin: 0; got: #{m[1]}"

describe 'CustomView — ResizeObserver refreshes grid layouts', ->
  it 'observes the container and refreshes grids when it resizes', ->
    observed = null
    class FakeResizeObserver
      constructor: (@cb) -> observed = @
      observe: (el) -> @el = el
      disconnect: ->
    global.ResizeObserver = FakeResizeObserver

    layout = { layout: { direction: 'vertical', children: [
      { widget: { space: 'personnes' } }
    ] } }
    cv = new CV makeContainer(), JSON.stringify(layout), makeSpaces()
    cv.mount()
    calls = 0

    new Promise (resolve, reject) ->
      setTimeout ->
        try
          assert observed?, 'ResizeObserver must be constructed'
          eq observed.el, cv.container
          cv._widgets[0].dataView._grid = { refreshLayout: -> calls++ }
          observed.cb []
          setTimeout ->
            try
              eq calls, 1, 'refreshLayout must be called (debounced)'
              global.ResizeObserver = undefined
              resolve()
            catch e
              global.ResizeObserver = undefined
              reject e
          , 80
        catch e
          global.ResizeObserver = undefined
          reject e
      , 0

summary()
