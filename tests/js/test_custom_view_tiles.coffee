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
      # Ne garde que la PREMIÈRE instance : les tests suivants montent d'autres
      # vues et ne doivent pas écraser la référence observée ici.
      constructor: (@cb) -> observed ?= @
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
          # Laisse passer le rafraîchissement initial du montage avant de mesurer.
          setTimeout ->
            baseline = calls
            observed.cb []
            setTimeout ->
              try
                assert calls > baseline, 'refreshLayout must be called (debounced)'
                global.ResizeObserver = undefined
                resolve()
              catch e
                global.ResizeObserver = undefined
                reject e
            , 80
          , 10
        catch e
          global.ResizeObserver = undefined
          reject e
      , 0

# ---------------------------------------------------------------------------
# Part 2 — draggable splitters between tiles.
# ---------------------------------------------------------------------------
describe 'CustomView.redistribute (pure)', ->
  it 'moves space by a positive delta, keeping the sum', ->
    [a, b] = CV.redistribute 300, 200, 50, 80
    eq a, 350
    eq b, 150

  it 'moves space by a negative delta, keeping the sum', ->
    [a, b] = CV.redistribute 300, 200, -50, 80
    eq a, 250
    eq b, 250

  it 'clamps a positive overshoot to the minimum of the second tile', ->
    [a, b] = CV.redistribute 300, 200, 500, 80
    eq a, 420
    eq b, 80

  it 'clamps a negative overshoot to the minimum of the first tile', ->
    [a, b] = CV.redistribute 300, 200, -500, 80
    eq a, 80
    eq b, 420

  it 'always preserves the total', ->
    [a, b] = CV.redistribute 123, 456, 33, 10
    eq a + b, 579

describe 'CustomView.setChildFactors (pure)', ->
  it 'updates the factor of the two wanted children and keeps everything else', ->
    yaml = JSON.stringify {
      layout:
        direction: 'horizontal'
        children: [
          { widget: { id: 'a', space: 'x', title: 'A' } }
          { layout: { direction: 'vertical', children: [
              { widget: { id: 'b', space: 'y' } }
              { widget: { id: 'c', space: 'z' } }
          ] } }
        ]
    }
    out = CV.setChildFactors yaml, [], [
      { index: 0, factor: 2.5 }
      { index: 1, factor: 0.5 }
    ]
    parsed = JSON.parse out
    eq parsed.layout.children[0].widget.factor, 2.5
    eq parsed.layout.children[1].layout.factor, 0.5
    # Le reste du YAML est conservé.
    eq parsed.layout.direction, 'horizontal'
    eq parsed.layout.children[0].widget.id, 'a'
    eq parsed.layout.children[0].widget.title, 'A'
    eq parsed.layout.children[1].layout.children[0].widget.id, 'b'
    eq parsed.layout.children[1].layout.children[1].widget.id, 'c'
    eq parsed.layout.children[1].layout.children[0].widget.factor, undefined

  it 'navigates a nested path and leaves siblings untouched', ->
    yaml = JSON.stringify {
      layout:
        direction: 'vertical'
        children: [
          { layout: { direction: 'horizontal', children: [
              { widget: { id: 'a', space: 'x' } }
              { widget: { id: 'b', space: 'y' } }
          ] } }
        ]
    }
    out = CV.setChildFactors yaml, [0], [{ index: 0, factor: 3 }]
    parsed = JSON.parse out
    eq parsed.layout.children[0].layout.children[0].widget.factor, 3
    eq parsed.layout.children[0].layout.children[1].widget.factor, undefined

  it 'writes factor on a bare zone child too', ->
    yaml = JSON.stringify { layout: { direction: 'horizontal', children: [
      { direction: 'vertical', children: [{ widget: { id: 'a', space: 'x' } }] }
      { widget: { id: 'b', space: 'y' } }
    ] } }
    out = CV.setChildFactors yaml, [], [{ index: 0, factor: 2 }]
    parsed = JSON.parse out
    eq parsed.layout.children[0].factor, 2

  it 'rounds factors to two decimals', ->
    yaml = JSON.stringify { layout: { direction: 'horizontal', children: [
      { widget: { id: 'a', space: 'x' } }
      { widget: { id: 'b', space: 'y' } }
    ] } }
    out = CV.setChildFactors yaml, [], [{ index: 0, factor: 1.239 }]
    eq JSON.parse(out).layout.children[0].widget.factor, 1.24

describe 'CustomView — factor read from both locations', ->
  it 'reads factor on the entry (legacy)', ->
    layout = { layout: { direction: 'vertical', children: [
      { factor: 3, widget: { space: 'personnes' } }
      { widget: { space: 'groupes' } }
    ] } }
    cv = new CV makeContainer(), JSON.stringify(layout), makeSpaces()
    cv.mount()
    eq cv._widgets[0].el.style.flex, '3'
    eq cv._widgets[1].el.style.flex, '1'

  it 'reads factor inside the widget mapping (documented form)', ->
    layout = { layout: { direction: 'vertical', children: [
      { widget: { space: 'personnes', factor: 3 } }
      { widget: { space: 'groupes' } }
    ] } }
    cv = new CV makeContainer(), JSON.stringify(layout), makeSpaces()
    cv.mount()
    eq cv._widgets[0].el.style.flex, '3'
    eq cv._widgets[1].el.style.flex, '1'

  it 'reads factor inside a layout mapping', ->
    layout = { layout: { direction: 'vertical', children: [
      { layout: { direction: 'horizontal', factor: 2, children: [
        { widget: { id: 'a', space: 'personnes' } }
      ] } }
      { widget: { space: 'groupes' } }
    ] } }
    cv = new CV makeContainer(), JSON.stringify(layout), makeSpaces()
    cv.mount()
    zones = collectByClass cv.container, 'cv-zone'
    eq zones.length, 2
    eq zones[1].style.flex, '2'

describe 'CustomView — splitters between tiles', ->
  makeThreeTiles = ->
    layout = { layout: { direction: 'horizontal', children: [
      { widget: { space: 'personnes' } }
      { widget: { space: 'groupes' } }
      { widget: { space: 'personnes' } }
    ] } }

  it 'a zone with three children renders two splitters', ->
    cv = new CV makePageContainer('p1'), JSON.stringify(makeThreeTiles()), makeSpaces()
    cv.mount()
    eq collectByClass(cv.container, 'cv-splitter').length, 2

  it 'renders no splitter in presentation mode', ->
    cv = new CV makePageContainer('p1'), JSON.stringify(makeThreeTiles()), makeSpaces(), [], { presentationMode: true }
    cv.mount()
    eq collectByClass(cv.container, 'cv-splitter').length, 0

  it 'renders no splitter without an editable page id', ->
    cv = new CV makePageContainer(null), JSON.stringify(makeThreeTiles()), makeSpaces()
    cv.mount()
    eq collectByClass(cv.container, 'cv-splitter').length, 0

  it 'splitters are oriented along their zone direction', ->
    cv = new CV makePageContainer('p1'), JSON.stringify(makeThreeTiles()), makeSpaces()
    cv.mount()
    for sp in collectByClass cv.container, 'cv-splitter'
      assert /cv-splitter--horizontal/.test(sp.className), "expected a horizontal splitter, got #{sp.className}"

summary()
