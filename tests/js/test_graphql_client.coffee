# tests/js/test_graphql_client.coffee — tests pour GQL (graphql_client.js)

{ localStorageStub } = require './dom_stub'
{ describe, it, eq, assert, summary } = require './runner'

localStorageStub.clear()

require '../../frontend/src/graphql_client'
G = global.window.GQL

describe 'GQL.setToken', ->
  it 'persiste le token dans localStorage', ->
    G.setToken 'abc123'
    eq localStorageStub.getItem('tdb_token'), 'abc123'
    eq G._token, 'abc123'

  it 'clearToken removes token', ->
    G.setToken 'xyz'
    G.clearToken()
    eq G._token, null
    eq localStorageStub.getItem('tdb_token'), null

describe 'GQL.loadToken', ->
  it 'restaure le token depuis localStorage', ->
    localStorageStub.setItem 'tdb_token', 'restored'
    G._token = null
    G.loadToken()
    eq G._token, 'restored'

  it 'ne plante pas si localStorage vide', ->
    localStorageStub.clear()
    G._token = null
    G.loadToken()
    eq G._token, null

describe 'GQL.query — request body', ->
  it 'sends query and variables as JSON', ->
    body = null
    global.fetch = (url, opts) ->
      body = JSON.parse opts.body
      Promise.resolve json: -> Promise.resolve { data: { ok: true } }
    G.setToken null
    G.query('query { me { id } }', { x: 1 }).then ->
      eq body.query, 'query { me { id } }'
      eq body.variables.x, 1

  it 'adds Authorization header when token is present', ->
    sentHeaders = null
    global.fetch = (url, opts) ->
      sentHeaders = opts.headers
      Promise.resolve json: -> Promise.resolve { data: {} }
    G.setToken 'tok42'
    G.query('query { me { id } }').then ->
      assert sentHeaders['Authorization']?.includes('tok42'), 'missing Authorization'
      G.setToken null

  it 'throws an error when result.errors is non-empty', ->
    global.fetch = (url, opts) ->
      Promise.resolve
        json: -> Promise.resolve { errors: [{ message: 'not authorized' }] }
    G.query('query { me { id } }')
      .then -> throw new Error 'aurait dû rejeter'
      .catch (e) -> assert e.message.includes('not authorized'), "unexpected message: #{e.message}"

describe 'GQL.mutate', ->
  it 'delegates to query', ->
    called = null
    orig = G.query.bind G
    G.query = (q, v) -> called = { q, v }; Promise.resolve {}
    G.mutate 'mutation { logout }', { a: 1 }
    eq called.q, 'mutation { logout }'
    eq called.v.a, 1
    G.query = orig

summary()
