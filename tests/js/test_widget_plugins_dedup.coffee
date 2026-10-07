# tests/js/test_widget_plugins_dedup.coffee
# T13 guard: LIST_WIDGET_PLUGINS must be defined in exactly one frontend source
# (widget_plugins.coffee), and app.coffee's _listWidgetPluginsQuery must keep
# the exact same query text, character for character.

fs = require 'fs'
path = require 'path'

require './dom_stub'
{ describe, it, eq, assert, summary } = require './runner'

SRC_DIR = path.join __dirname, '../../frontend/src'

# Canonical pre-refactor text: the identical heredoc that existed in BOTH
# app.coffee (old lines 33-46) and widget_plugins.coffee (lines 4-17).
REFERENCE = """
  query {
    widgetPlugins {
      id
      name
      description
      scriptLanguage
      templateLanguage
      scriptCode
      templateCode
      updatedAt
    }
  }
"""

global.GQL =
  query: (-> Promise.resolve {})
  mutate: (-> Promise.resolve {})
  loadToken: (->)
require '../../frontend/src/widget_plugins'
require '../../frontend/src/app'

describe 'T13 widget plugin query dedup', ->
  it 'expose la requête via window.WidgetPlugins.LIST_QUERY', ->
    eq typeof global.window.WidgetPlugins.LIST_QUERY, 'string'

  it 'conserve le texte de la requête caractère pour caractère (widget_plugins)', ->
    eq global.window.WidgetPlugins.LIST_QUERY, REFERENCE

  it 'conserve le texte de la requête caractère pour caractère (app)', ->
    eq global.window.App._listWidgetPluginsQuery, REFERENCE

  it 'app lit la même valeur que widget_plugins (pas de seconde définition)', ->
    eq global.window.App._listWidgetPluginsQuery, global.window.WidgetPlugins.LIST_QUERY

  it 'ne définit LIST_WIDGET_PLUGINS que dans un seul fichier source', ->
    files = fs.readdirSync SRC_DIR
      .filter (f) -> f.match /\.coffee$/
      .map (f) -> path.join SRC_DIR, f
    defs = []
    for f in files
      content = fs.readFileSync f, 'utf8'
      defs.push path.basename f if /^LIST_WIDGET_PLUGINS\s*=/m.test content
    eq defs.length, 1, "définitions trouvées: #{defs.join(', ')}"
    eq defs[0], 'widget_plugins.coffee'

summary()
