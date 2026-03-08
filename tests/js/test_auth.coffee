# tests/js/test_auth.coffee — tests pour Auth (auth.js)

require './dom_stub'
{ describe, it, eq, assert, summary } = require './runner'

global.App = showLogin: ->

global.GQL =
  _token: null
  setToken: (t) -> @_token = t
  clearToken: -> @_token = null
  query:  -> Promise.resolve {}
  mutate: -> Promise.resolve {}

require '../../frontend/src/auth'
A = global.window.Auth
global.Auth = A   # auth.js référence Auth directement (global navigateur)

describe 'Auth.login', ->
  it 'appelle GQL.mutate avec les bons arguments', ->
    captured = null
    GQL.mutate = (q, v) ->
      captured = v
      Promise.resolve { login: { token: 'tok99', user: { id: '1', username: 'alice', email: 'a@b.c' } } }
    A.login('alice', 'secret').then ->
      eq captured?.username, 'alice'
      eq captured?.password, 'secret'

  it 'retourne l\'utilisateur résolu', ->
    GQL.mutate = (q, v) ->
      Promise.resolve { login: { token: 't', user: { id: '2', username: 'bob', email: '' } } }
    A.login('bob', 'pass').then (user) ->
      eq user.username, 'bob'
      eq user.id, '2'

  it 'appelle GQL.setToken avec le token reçu', ->
    tokReceived = null
    GQL.setToken = (t) -> tokReceived = t; GQL._token = t
    GQL.mutate = (q, v) ->
      Promise.resolve { login: { token: 'secret-tok', user: { id: '3', username: 'carol', email: '' } } }
    A.login('carol', 'pw').then ->
      eq tokReceived, 'secret-tok'

describe 'Auth.restoreSession', ->
  it 'retourne l\'utilisateur si me est défini', ->
    GQL.query = -> Promise.resolve { me: { id: '10', username: 'dan', email: '' } }
    A.restoreSession().then (u) ->
      eq u?.username, 'dan'

  it 'retourne null si me est null', ->
    GQL.query = -> Promise.resolve { me: null }
    A.restoreSession().then (u) ->
      eq u, null

  it 'retourne null sur erreur réseau', ->
    GQL.query = -> Promise.reject new Error 'network error'
    A.restoreSession().then (u) ->
      eq u, null

summary()
