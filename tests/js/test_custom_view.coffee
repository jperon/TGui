# tests/js/test_custom_view.coffee — tests pour CustomView (custom_view.js)
# Teste : parsing YAML, structure du DOM produit, factor flex, filtrage colonnes, depends_on.

require './dom_stub'
{ describe, it, eq, deepEq, assert, summary } = require './runner'

# --- stubs ------------------------------------------------------------------
global.jsyaml =
  load: (src) -> JSON.parse src      # les YAML de test seront du JSON valide

global.DataView = class DataView
  constructor: (@container, @space) ->
    @_currentData = {}
    @mounted = false
  mount: -> @mounted = true
  refreshLayout: ->
  setFilter: ->
  setDefaultValues: ->
  deleteSelected: ->

# Chargement du module sous test (expose window.CustomView)
require '../../frontend/src/views/custom_view'
CV = global.window.CustomView

# --- helper -----------------------------------------------------------------
makeSpaces = ->
  [
    { id: '1', name: 'personnes', fields: [
        { id: 'f1', name: 'nom',  fieldType: 'Str' }
        { id: 'f2', name: 'age',  fieldType: 'Int' }
        { id: 'f3', name: 'ville',fieldType: 'Str' }
    ]}
    { id: '2', name: 'groupes', fields: [
        { id: 'g1', name: 'titre', fieldType: 'Str' }
        { id: 'g2', name: 'code',  fieldType: 'Str' }
    ]}
  ]

makeContainer = -> global.document.createElement 'div'

yamlJSON = (obj) -> JSON.stringify obj

# ---------------------------------------------------------------------------
describe 'CustomView — layout vertical simple', ->
  it 'monte un widget sans erreur', ->
    layout = { layout: { widget: { id: 'w1', title: 'Gens', space: 'personnes' } } }
    cv = new CV makeContainer(), yamlJSON(layout), makeSpaces()
    cv.mount()
    eq cv._widgets.length, 1
    assert cv._widgets[0].dataView.mounted, 'DataView doit être monté'

  it '_widgetsById indexé par id', ->
    layout = { layout: { widget: { id: 'mon_widget', space: 'personnes' } } }
    cv = new CV makeContainer(), yamlJSON(layout), makeSpaces()
    cv.mount()
    assert cv._widgetsById['mon_widget']?, 'index par id'

  it 'espace introuvable → dataView null', ->
    layout = { layout: { widget: { space: 'inexistant' } } }
    cv = new CV makeContainer(), yamlJSON(layout), makeSpaces()
    cv.mount()
    eq cv._widgets[0].dataView, null

describe 'CustomView — zone avec enfants', ->
  it 'crée un enfant par widget enfant', ->
    layout =
      layout:
        direction: 'horizontal'
        children: [
          { widget: { space: 'personnes' } }
          { widget: { space: 'groupes'   } }
        ]
    cv = new CV makeContainer(), yamlJSON(layout), makeSpaces()
    cv.mount()
    eq cv._widgets.length, 2

describe 'CustomView — factor', ->
  it 'applique factor comme flex', ->
    layout =
      layout:
        direction: 'vertical'
        children: [
          { factor: 3, widget: { space: 'personnes' } }
          { factor: 1, widget: { space: 'groupes'   } }
        ]
    cv = new CV makeContainer(), yamlJSON(layout), makeSpaces()
    cv.mount()
    # Le container principal a flex appliqué par _renderZoneOrWidget (nœud racine)
    # Les enfants ont leur flex dans l'élément rendu
    entries = cv._widgets
    eq entries[0].el.style.flex, '3'
    eq entries[1].el.style.flex, '1'

  it 'factor absent → flex par défaut à "1"', ->
    layout = { layout: { widget: { space: 'personnes' } } }
    cv = new CV makeContainer(), yamlJSON(layout), makeSpaces()
    cv.mount()
    eq cv._widgets[0].el.style.flex, '1'

describe 'CustomView — columns', ->
  it 'filtre les colonnes spécifiées', ->
    layout = { layout: { widget: { space: 'personnes', columns: ['age', 'nom'] } } }
    cv = new CV makeContainer(), yamlJSON(layout), makeSpaces()
    cv.mount()
    dv = cv._widgets[0].dataView
    eq dv.space.fields.length, 2
    eq dv.space.fields[0].name, 'age'
    eq dv.space.fields[1].name, 'nom'

  it 'ignore les colonnes inconnues silencieusement', ->
    layout = { layout: { widget: { space: 'personnes', columns: ['nom', 'inconnu'] } } }
    cv = new CV makeContainer(), yamlJSON(layout), makeSpaces()
    cv.mount()
    eq cv._widgets[0].dataView.space.fields.length, 1
    eq cv._widgets[0].dataView.space.fields[0].name, 'nom'

  it 'sans columns → tous les champs', ->
    layout = { layout: { widget: { space: 'personnes' } } }
    cv = new CV makeContainer(), yamlJSON(layout), makeSpaces()
    cv.mount()
    eq cv._widgets[0].dataView.space.fields.length, 3

  it 'ne modifie pas l\'espace original (clone)', ->
    spaces = makeSpaces()
    layout = { layout: { widget: { space: 'personnes', columns: ['nom'] } } }
    cv = new CV makeContainer(), yamlJSON(layout), spaces
    cv.mount()
    eq spaces[0].fields.length, 3  # original inchangé

describe 'CustomView — YAML invalide', ->
  it 'affiche une erreur sans lever d\'exception', ->
    badYaml = '{ not valid json !!!!'
    global.jsyaml.load = (s) -> throw new Error 'YAML parse error'
    cv = new CV makeContainer(), badYaml, makeSpaces()
    cv.mount()
    eq cv._widgets.length, 0
    global.jsyaml.load = (s) -> JSON.parse s  # restore

describe 'CustomView — unmount', ->
  it 'vide _widgets et _widgetsById', ->
    layout = { layout: { widget: { id: 'w', space: 'personnes' } } }
    cv = new CV makeContainer(), yamlJSON(layout), makeSpaces()
    cv.mount()
    eq cv._widgets.length, 1
    cv.unmount()
    eq cv._widgets.length, 0
    eq Object.keys(cv._widgetsById).length, 0

summary()
