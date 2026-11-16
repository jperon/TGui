# tests/js/test_widget_relay_header.coffee
# Le relais des requêtes d'un widget (custom_view_plugins.coffee) doit passer
# par GQL.queryWidget, c'est-à-dire envoyer l'en-tête `X-TDB-Widget`. Le
# serveur n'autorise alors que les lectures et les mutations d'enregistrements
# de données (spec docs/superpowers/specs/2026-11-16-custom-widgets-design.md
# §6) ; l'iframe sandboxée n'a ni jeton ni accès HTTP direct, elle ne peut donc
# pas contourner la restriction.

{ localStorageStub } = require './dom_stub'
{ describe, it, eq, assert, summary } = require './runner'

localStorageStub.clear()

require '../../frontend/src/graphql_client'
G = global.window.GQL

describe 'GQL.queryWidget', ->
  it 'envoie l’en-tête X-TDB-Widget', ->
    sent = null
    global.fetch = (url, opts) ->
      sent = opts.headers
      Promise.resolve json: -> Promise.resolve { data: { ok: true } }
    G.setToken 'tok42'
    G.queryWidget('query { spaces { id } }', { a: 1 }).then ->
      eq sent['X-TDB-Widget'], '1'
      assert sent['Authorization']?.includes('tok42'), 'jeton attendu avec widgetQuery'
      G.setToken null

  it 'GQL.query simple n’envoie pas l’en-tête widget', ->
    sent = null
    global.fetch = (url, opts) ->
      sent = opts.headers
      Promise.resolve json: -> Promise.resolve { data: {} }
    G.setToken null
    G.query('query { spaces { id } }').then ->
      assert sent['X-TDB-Widget'] is undefined, 'en-tête widget inattendu'

# Le relais lui-même : custom_view_plugins étend CustomView par son prototype.
global.window.CustomView = -> null
relayed = []
global.GQL =
  query: -> Promise.resolve {}
  queryWidget: (q, v) ->
    relayed.push { query: q, variables: v }
    Promise.resolve { data: {} }
require '../../frontend/src/views/custom_view_plugins'

describe 'CustomView._relayWidgetQuery', ->
  it 'passe par GQL.queryWidget (en-tête widget), jamais GQL.query', ->
    fn = global.window.CustomView.prototype._relayWidgetQuery
    eq typeof fn, 'function'
    fn.call {}, 'query { spaces { id } }', { x: 2 }
    eq relayed.length, 1
    eq relayed[0].query, 'query { spaces { id } }'
    eq relayed[0].variables.x, 2

  it 'remplace des variables absentes par un objet vide', ->
    fn = global.window.CustomView.prototype._relayWidgetQuery
    fn.call {}, 'query { me { id } }', null
    eq relayed.length, 2
    eq typeof relayed[1].variables, 'object'

summary()
