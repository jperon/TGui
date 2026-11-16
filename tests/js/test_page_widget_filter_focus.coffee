# tests/js/test_page_widget_filter_focus.coffee — focus du champ λ d'un widget de page.
# SortableJS a `preventOnFilter: true` par défaut : au mousedown sur un élément
# filtré il appelle preventDefault(), ce qui empêche l'input de prendre le focus.
# La zone du filtre λ d'un widget porte la classe `no-drag` (donc filtrée) :
# toute configuration Sortable dont le filtre est `.no-drag` doit désactiver
# `preventOnFilter`, sinon le clic dans le champ ne place jamais le curseur.

require './dom_stub'
{ describe, it, eq, assert, summary } = require './runner'

# Interception du constructeur Sortable : chaque configuration est conservée.
sortableConfigs = []
resetConfigs = -> sortableConfigs = []

global.Sortable = class Sortable
  constructor: (el, opts) ->
    @el   = el
    @opts = opts or {}
    sortableConfigs.push @opts
  option: (key, value) ->
    if value isnt undefined then @opts[key] = value
    @opts[key]
  destroy: ->

global.jsyaml =
  load: (src) -> JSON.parse src

global.DataView = class DataView
  constructor: (@container, @space) ->
  mount: -> Promise.resolve()
  refreshLayout: ->
  unmount: ->
  deleteSelected: ->

require '../../frontend/src/drag_drop_manager'
# dom_stub fait de `window` un objet distinct de `global` : exposer la classe
# comme global, comme le fait le navigateur avec `window.DragDropManager`.
global.DragDropManager = global.window.DragDropManager
require '../../frontend/src/views/custom_view'
CV = global.window.CustomView

SPACES = [
  { id: 'sp-1', name: 'Emprunts', fields: [ { id: 'f1', name: 'lecteur', fieldType: 'Str' } ] }
]

PAGE_LAYOUT = { layout: { widget: { id: 'w1', space: 'Emprunts' } } }

tick = -> new Promise (resolve) -> setTimeout resolve, 0

makePage = (layout = PAGE_LAYOUT) ->
  container = global.document.createElement 'div'
  container.setAttribute 'data-page-id', 'page1'
  cv = new CV container, JSON.stringify(layout), SPACES
  cv.mount()
  cv
# Toutes les configurations Sortable qui filtrent `.no-drag`.
noDragConfigs = -> sortableConfigs.filter (o) -> o.filter is '.no-drag'

assertNoDragConfigsSafe = (label) ->
  configs = noDragConfigs()
  assert configs.length > 0, "#{label} : aucune configuration Sortable avec filter '.no-drag'"
  for opts, i in configs
    assert opts.preventOnFilter is false,
      "#{label} : configuration Sortable ##{i} filtre '.no-drag' sans preventOnFilter: false (reçu #{opts.preventOnFilter})"
  configs.length

# Container dont querySelectorAll renvoie une zone : scanZones() instancie alors
# une seconde Sortable (config des zones).
makeZoneContainer = ->
  container = global.document.createElement 'div'
  zone = global.document.createElement 'div'
  zone.setAttribute 'data-zone-id', 'zone1'
  container.querySelectorAll = (sel) ->
    if sel is '[data-zone-id]' then [zone] else []
  container

describe 'Champ λ d’un widget de page — focus et Sortable preventOnFilter', ->
  it 'désactive preventOnFilter sur la configuration racine de DragDropManager', ->
    resetConfigs()
    new global.window.DragDropManager makeZoneContainer(), { pageId: 'page1' }
    eq assertNoDragConfigsSafe('DragDropManager racine'), 2

  it 'désactive preventOnFilter sur les deux configurations (racine et zone)', ->
    resetConfigs()
    new global.window.DragDropManager makeZoneContainer(), { pageId: 'page1' }
    handles = sortableConfigs.map (o) -> o.handle
    eq handles.length, 2
    eq handles[0], '.widget-header'
    eq handles[1], '.widget-header'
    assert sortableConfigs.every((o) -> o.preventOnFilter is false),
      'toutes les configurations Sortable doivent désactiver preventOnFilter'

  it 'désactive preventOnFilter pour la configuration créée par le montage d’une page', ->
    resetConfigs()
    cv = makePage()
    await tick()
    assert cv._dragDropManager?, 'un DragDropManager est attendu pour une page éditable'
    eq assertNoDragConfigsSafe('montage de page'), 1

  it 'conserve preventOnFilter: false après un aller-retour en mode présentation', ->
    resetConfigs()
    cv = makePage()
    await tick()
    cv.togglePresentationMode()
    eq cv._dragDropManager, null
    resetConfigs()
    cv.togglePresentationMode()
    assert cv._dragDropManager?, 'le DragDropManager doit être recréé en sortie de présentation'
    eq assertNoDragConfigsSafe('sortie de mode présentation'), 1

summary()
