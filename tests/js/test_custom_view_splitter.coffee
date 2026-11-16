# tests/js/test_custom_view_splitter.coffee
# Séparateur (splitter) entre deux enfants d'une zone :
#  - les écouteurs document sont posés au mousedown et retirés au mouseup ;
#  - un simple clic ne réécrit pas le YAML (donc pas de perte de commentaires) ;
#  - pendant le glisser, les deux voisins sont répartis en FACTEURS dont la
#    somme est conservée : les autres enfants de la zone ne bougent pas.

require './dom_stub'
{ describe, it, eq, deepEq, assert, summary } = require './runner'

global.jsyaml =
  load: (src) -> JSON.parse src

global.DataView = class DataView
  constructor: (@container, @space) ->
  mount: -> Promise.resolve()
  refreshLayout: ->
  unmount: ->
  deleteSelected: ->

require '../../frontend/src/views/custom_view'
require '../../frontend/src/views/custom_view_plugins'
require '../../frontend/src/views/custom_view_aggregate'
require '../../frontend/src/views/custom_view_resize'
CV = global.window.CustomView

# --- document instrumenté ----------------------------------------------------
global.document.body = global.document.createElement 'body'
docListeners = {}
global.document.addEventListener = (ev, fn) ->
  (docListeners[ev] ?= []).push fn
global.document.removeEventListener = (ev, fn) ->
  list = docListeners[ev] ? []
  i = list.indexOf fn
  list.splice i, 1 if i != -1

resetDocListeners = ->
  for own ev of docListeners then delete docListeners[ev]
  docListeners = {}

listenCount = (ev) -> (docListeners[ev] ? []).length

# --- helpers -----------------------------------------------------------------
makeSpaces = ->
  [ { id: '1', name: 'personnes', fields: [ { id: 'f1', name: 'nom', fieldType: 'Str' } ] } ]

makePage = (layout) ->
  container = global.document.createElement 'div'
  container.setAttribute 'data-page-id', 'page1'
  cv = new CV container, JSON.stringify(layout), makeSpaces()
  cv.mount()
  cv

findByClass = (el, cls) ->
  return el if typeof el.className == 'string' and el.className.split(' ').indexOf(cls) != -1
  for child in (el._children or el.children or [])
    found = findByClass child, cls
    return found if found
  null

# Zone horizontale à trois enfants : la paire (2,1) est séparée de (4).
makeLayout = ->
  layout:
    direction: 'horizontal'
    children: [
      { factor: 2, widget: { id: 'w1', space: 'personnes' } }
      { factor: 1, widget: { id: 'w2', space: 'personnes' } }
      { factor: 4, widget: { id: 'w3', space: 'personnes' } }
    ]

setup = ->
  resetDocListeners()
  cv = makePage makeLayout()
  splitter = findByClass cv.container, 'cv-splitter'
  assert splitter?, 'un séparateur est attendu entre w1 et w2'
  widgets = cv._widgets
  saved = []
  cv._saveChildFactors = (path, factors) ->
    saved.push { path, factors }
    Promise.resolve()
  { cv, splitter, saved, w1: widgets[0].el, w2: widgets[1].el, w3: widgets[2].el }

mouseDown = (splitter, x = 0) ->
  splitter._listeners.mousedown[0] { clientX: x, preventDefault: -> }

mouseMove = (x) ->
  docListeners.mousemove[0] { clientX: x }

mouseUp = ->
  docListeners.mouseup[0] {}

approx = (a, b, tol = 0.01) -> Math.abs(a - b) <= tol

describe 'CustomView — séparateur de zones', ->
  it 'ne pose les écouteurs document qu’au mousedown', ->
    { splitter } = setup()
    eq listenCount('mousemove'), 0
    eq listenCount('mouseup'), 0
    mouseDown splitter
    eq listenCount('mousemove'), 1
    eq listenCount('mouseup'), 1
    mouseUp()
    eq listenCount('mousemove'), 0
    eq listenCount('mouseup'), 0

  it 'un simple clic ne modifie pas le YAML', ->
    { splitter, saved, w1, w2 } = setup()
    before = [w1.style.flex, w2.style.flex]
    mouseDown splitter
    mouseUp()
    eq saved.length, 0
    deepEq [w1.style.flex, w2.style.flex], before

  it 'conserve la somme des facteurs de la paire pendant le glisser', ->
    { splitter, saved, w1, w2, w3 } = setup()
    deepEq [w1.style.flex, w2.style.flex, w3.style.flex], ['2', '1', '4']
    mouseDown splitter, 0
    # 100 px par voisin, +30 px : le minimum de 80 px borne la paire à 120/80.
    mouseMove 30
    mouseUp()

    eq saved.length, 1
    [fa, fb] = (f.factor for f in saved[0].factors)
    assert approx(fa + fb, 3), "la paire doit garder sa somme (3), got #{fa + fb}"
    assert approx(fa, 1.8), "facteur du premier voisin, got #{fa}"
    assert approx(fb, 1.2), "facteur du second voisin, got #{fb}"
    # Le troisième enfant de la zone ne bouge pas : sa somme de facteurs (3)
    # face au reste de la zone reste comparable (4 face à 3, pas 200 px).
    eq w3.style.flex, '4'
    assert approx(parseFloat(w1.style.flex) + parseFloat(w2.style.flex), 3),
      "flex affichés : #{w1.style.flex} + #{w2.style.flex}"

  it 'enregistre les facteurs de la bonne paire, au bon endroit du YAML', ->
    { splitter, saved } = setup()
    mouseDown splitter, 0
    mouseMove -20
    mouseUp()
    eq saved.length, 1
    deepEq (f.index for f in saved[0].factors), [0, 1]
    eq saved[0].path.length, 0

  it 'ne enregistre plus après le mouseup (écouteurs retirés)', ->
    { splitter, saved } = setup()
    mouseDown splitter, 0
    mouseMove 10
    mouseUp()
    eq saved.length, 1
    # Un mousemove fantôme après le relâchement ne doit rien déclencher.
    eq listenCount('mousemove'), 0
    eq saved.length, 1

summary()
