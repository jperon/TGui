# tests/js/test_custom_view_widget_menu.coffee
# Menu « Trier / Filtrer » d'un widget de page : il ne doit PAS être attaché
# quand la source du widget est une Data View. `_findSpace` renvoie alors
# `{ id: <id de la data view>, isView: true }` ; cet id n'est pas un espace et
# `saveViewPreset` le refuse (« Space not found »).

require './dom_stub'
{ describe, it, eq, deepEq, assert, summary } = require './runner'

global.jsyaml =
  load: (src) -> JSON.parse src

attachCalls = []
global.window.ViewPresetsMenu =
  attach: (wrap, opts) ->
    attachCalls.push opts
    { destroy: -> }

global.DataView = class DataView
  constructor: (@container, @space) ->
    @mounted = false
  mount: -> @mounted = true
  refreshLayout: ->
  unmount: ->
  deleteSelected: ->

require '../../frontend/src/views/custom_view'
CV = global.window.CustomView

SOURCE =
  id: 'sp-1'
  name: 'Emprunts'
  fields: [
    { name: 'lecteur', fieldType: 'Str' }
    { name: 'montant', fieldType: 'Int' }
  ]

VIEW =
  id: 'dv-1'
  name: 'Vue emprunts'
  sourceSpace: 'sp-1'
  config: JSON.stringify { columns: ['lecteur', 'montant'] }

# Page éditable : c'est `data-page-id` qui autorise le menu des widgets.
makePage = (layout, spaces = [SOURCE], views = []) ->
  container = global.document.createElement 'div'
  container.setAttribute 'data-page-id', 'page1'
  cv = new CV container, JSON.stringify(layout), spaces, views
  cv.mount()
  cv

# Sans page (lecture seule), le menu n'est jamais attaché non plus.
makeReadOnly = (layout) ->
  cv = new CV global.document.createElement('div'), JSON.stringify(layout), [SOURCE], []
  cv.mount()
  cv

describe 'CustomView — menu de widget et Data View', ->
  it 'n’attache pas le menu quand la source du widget est une Data View', ->
    attachCalls = []
    layout = { layout: { widget: { id: 'w1', space: 'Vue emprunts' } } }
    cv = makePage layout, [SOURCE], [VIEW]
    eq cv._widgets.length, 1
    assert cv._widgets[0].dataView.space.isView, 'la source doit être une vue'
    eq attachCalls.length, 0

  it 'attache le menu pour un widget sur un vrai espace', ->
    attachCalls = []
    layout = { layout: { widget: { id: 'w2', space: 'Emprunts' } } }
    makePage layout
    eq attachCalls.length, 1
    eq attachCalls[0].scope, 'widget:page1:w2'
    eq attachCalls[0].spaceId, 'sp-1'

  it 'n’attache rien hors page éditable', ->
    attachCalls = []
    layout = { layout: { widget: { id: 'w3', space: 'Emprunts' } } }
    makeReadOnly layout
    eq attachCalls.length, 0

summary()
