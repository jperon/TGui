# tests/js/test_widget_detach.coffee
# Action « Détacher » d'une instance de widget personnalisé (spec
# docs/superpowers/specs/2026-11-16-custom-widgets-design.md §4) : le bouton
# n'est ajouté qu'en édition de page, pour un admin, sur un widget personnalisé
# (jamais pour « aggregate » / « table », ni pour un widget de données).

require './dom_stub'
{ describe, it, eq, assert, summary } = require './runner'

global.jsyaml =
  load: (src) -> JSON.parse src

global.DataView = class DataView
  constructor: (@container, @space) ->
  mount: ->
  refreshLayout: ->
  deleteSelected: ->

# Widget personnalisé minimal : javascript + html ne charge aucun compilateur.
PLUGIN =
  id: 'p1'
  name: 'sample_plugin'
  scriptLanguage: 'javascript'
  templateLanguage: 'html'
  scriptCode: ''
  templateCode: ''

syncPlugin = (plugin) ->
  then: (cb) ->
    cb plugin
  catch: ->

global.WidgetPlugins =
  getByName: -> syncPlugin PLUGIN

require '../../frontend/src/views/plugin_runtimes'
require '../../frontend/src/views/custom_view'
require '../../frontend/src/views/custom_view_plugins'
require '../../frontend/src/views/custom_view_aggregate'
CV = global.window.CustomView

makeCV = (layout, opts = {}) ->
  container = global.document.createElement 'div'
  container.setAttribute 'data-page-id', 'page1' if opts.page
  cv = new CV container, JSON.stringify(layout), [], []
  cv.mount()
  cv

pluginLayout = (extra = {}) ->
  widget = { id: 'w_plugin', type: 'sample_plugin', title: 'Plugin' }
  widget[k] = v for k, v of extra
  { layout: { widget } }

# Boutons « Détacher » de la barre de titre du premier widget monté.
detachButtons = (cv) ->
  wrapper = cv._widgets[0]?.el
  return [] unless wrapper
  titleBar = wrapper.children[0]
  return [] unless titleBar
  (el for el in titleBar.children when el.classList.contains 'cv-widget-detach-btn')

describe 'CustomView — action Détacher', ->
  it 'ajoute le bouton en édition de page pour un admin', ->
    global.window.Auth = isAdmin: -> true
    cv = makeCV pluginLayout(), page: true
    btns = detachButtons cv
    eq btns.length, 1
    eq btns[0].textContent, 'Détacher'

  it 'n’ajoute rien pour un non-admin', ->
    global.window.Auth = isAdmin: -> false
    cv = makeCV pluginLayout(), page: true
    eq detachButtons(cv).length, 0

  it 'n’ajoute rien hors édition de page (aucun id de page)', ->
    global.window.Auth = isAdmin: -> true
    cv = makeCV pluginLayout()
    eq detachButtons(cv).length, 0

  it 'n’ajoute rien en mode présentation', ->
    global.window.Auth = isAdmin: -> true
    container = global.document.createElement 'div'
    container.setAttribute 'data-page-id', 'page1'
    cv = new CV container, JSON.stringify(pluginLayout()), [], [], presentationMode: true
    cv.mount()
    eq detachButtons(cv).length, 0

  it 'n’ajoute rien pour un widget fourni par le programme', ->
    global.window.Auth = isAdmin: -> true
    cv = makeCV { layout: { widget: { id: 'w_table', type: 'table', title: 'Tableau' } } }, page: true
    eq detachButtons(cv).length, 0
    cv2 = makeCV { layout: { widget: { id: 'w_agg', type: 'aggregate', title: 'Agrégat' } } }, page: true
    eq detachButtons(cv2).length, 0

  it 'n’ajoute rien pour un widget de données (sans type)', ->
    global.window.Auth = isAdmin: -> true
    cv = makeCV { layout: { widget: { id: 'w_data', space: 'personnes' } } }, page: true
    eq detachButtons(cv).length, 0

  it 'canDetachPluginWidget exige page, admin et type personnalisé', ->
    global.window.Auth = isAdmin: -> true
    cv = makeCV pluginLayout(), page: true
    eq cv._canDetachPluginWidget({ type: 'sample_plugin' }), true
    eq cv._canDetachPluginWidget({}), false
    eq cv._canDetachPluginWidget({ type: 'aggregate' }), false
    global.window.Auth = isAdmin: -> false
    eq cv._canDetachPluginWidget({ type: 'sample_plugin' }), false

summary()
