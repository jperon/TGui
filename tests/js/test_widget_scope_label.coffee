# tests/js/test_widget_scope_label.coffee
# Portées des widgets personnalisés côté frontend (spec
# 2026-11-16-custom-widgets-design.md §5) : libellé de portée dans la fenêtre
# « ＋ Widget », résolution par pageId, et conflits d'import de définition
# (trois choix, access affiché, nom d'import par défaut).

require './dom_stub'
{ describe, it, eq, ok, assert, summary } = require './runner'

# js-yaml est chargé par la page en production (vendor) ; stub minimal ici.
global.window.jsyaml =
  load: (text) ->
    throw new Error 'invalid' if text.indexOf('[') >= 0
    m = text.match /access:\s*(\w+)/
    if m then { access: m[1] } else null

global.GQL =
  query: (query, variables) ->
    if query.indexOf('widgetPlugin(') >= 0
      Promise.resolve { widgetPlugin: { name: variables.name, appId: null } }
    else
      Promise.resolve { widgetPlugins: [] }
  mutate: (-> Promise.resolve {})
  loadToken: (->)

# Le module sous test étend window.AppViewHelpers (défini ailleurs en prod).
global.window.AppViewHelpers = {}

require '../../frontend/src/widget_plugins'
require '../../frontend/src/app_view_helpers_add_widget'
require '../../frontend/src/app_apps_helpers'

WP = global.window.WidgetPlugins
AVH = global.window.AppViewHelpers
AAH = global.window.AppAppsHelpers
document = global.document

describe 'WidgetPlugins — portée', ->
  it 'libelle la bibliothèque et les apps', ->
    eq WP.scopeLabel({ name: 'a' }), 'bibliothèque'
    eq WP.scopeLabel({ name: 'a', appId: null }), 'bibliothèque'
    eq WP.scopeLabel({ name: 'a', appId: 'org.exemple.biblio' }), 'app org.exemple.biblio'

  # Un seul it : deux it asynchrones s'entrelacent (le runner les lance tous,
  # puis attend les promesses) et se voleraient le stub GQL global.
  it 'transmet pageId à la résolution et à la liste', ->
    seen = []
    saved = global.GQL
    global.GQL =
      query: (query, variables) ->
        seen.push { query, variables }
        if query.indexOf('widgetPlugin(') >= 0
          Promise.resolve { widgetPlugin: null }
        else
          Promise.resolve { widgetPlugins: [] }
    await WP.getByName 'calendrier', 'page-1'
    await WP.list({ pageId: 'page-1' })
    await WP.list({})
    global.GQL = saved
    eq seen[0].variables.pageId, 'page-1'
    eq seen[0].variables.name, 'calendrier'
    eq seen[1].variables.pageId, 'page-1'
    eq seen[2].variables.pageId, undefined

describe 'Fenêtre ＋ Widget — portée affichée', ->
  it 'ajoute la portée dans le libellé de l’option', ->
    list = document.createElement 'div'
    list.id = 'widget-type-plugin-list'
    document._setById 'widget-type-plugin-list', list
    AVH._renderWidgetTypePlugins [
      { name: 'calendrier', description: 'Vue calendrier', appId: 'org.exemple.biblio' }
      { name: 'carte' }
    ]
    first = list._children[0]._children[1]
    assert first._children[0].classList.contains('widget-type-option-scope'), 'span de portée'
    eq first._children[0].textContent, ' (app org.exemple.biblio)'
    second = list._children[1]._children[1]
    eq second._children[0].textContent, ' (bibliothèque)'
    eq second._children[0].classList.contains('widget-type-option-scope'), true

describe 'Import d’app — conflits de définition', ->
  conflicts = [
    { key: 'plugin:calendrier', type: 'plugin' }
    { key: 'field:livres.titre', type: 'field' }
  ]

  it 'propose « importer sous un autre nom » par défaut pour une définition', ->
    decisions = AAH.buildDecisions conflicts, {}
    eq decisions[0].choice, 'rename'
    eq decisions[1].choice, 'local'

  it 'garde le choix explicite et transmet le nouveau nom', ->
    decisions = AAH.buildDecisions conflicts, { 'plugin:calendrier': 'rename' },
      { 'plugin:calendrier': 'calendrier_bis' }
    eq decisions[0].choice, 'rename'
    eq decisions[0].newName, 'calendrier_bis'

  it 'n’envoie pas de nouveau nom pour « garder le local »', ->
    decisions = AAH.buildDecisions conflicts, { 'plugin:calendrier': 'local' },
      { 'plugin:calendrier': 'calendrier_bis' }
    eq decisions[0].choice, 'local'
    eq decisions[0].newName, undefined

  it 'nom d’import par défaut : <nom>_imported', ->
    eq AAH.defaultImportName('plugin:calendrier'), 'calendrier_imported'
    eq AAH.defaultImportName('calendrier'), 'calendrier_imported'

  it 'lit l’access effectif du manifest livré', ->
    eq AAH.pluginAccessOf({ manifest: '' }), 'full'
    eq AAH.pluginAccessOf({}), 'full'
    eq AAH.pluginAccessOf({ manifest: 'access: read\n' }), 'read'
    eq AAH.pluginAccessOf({ manifest: 'access: none\n' }), 'none'
    eq AAH.pluginAccessOf({ manifest: 'access: write\n' }), 'read'
    eq AAH.pluginAccessOf({ manifest: 'columns: [\n' }), 'read'
    eq AAH.pluginAccessOf({ manifest: '# seulement un commentaire\n' }), 'full'

summary()
