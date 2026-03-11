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
      Promise.resolve { login: { token: 'tok99', user: { id: '1', username: 'alice', email: 'a@b.c', groups: [] } } }
    A.login('alice', 'secret').then ->
      eq captured?.username, 'alice'
      eq captured?.password, 'secret'

  it 'retourne l\'utilisateur résolu', ->
    GQL.mutate = (q, v) ->
      Promise.resolve { login: { token: 't', user: { id: '2', username: 'bob', email: '', groups: [] } } }
    A.login('bob', 'pass').then (user) ->
      eq user.username, 'bob'
      eq user.id, '2'

  it 'appelle GQL.setToken avec le token reçu', ->
    tokReceived = null
    GQL.setToken = (t) -> tokReceived = t; GQL._token = t
    GQL.mutate = (q, v) ->
      Promise.resolve { login: { token: 'secret-tok', user: { id: '3', username: 'carol', email: '', groups: [] } } }
    A.login('carol', 'pw').then ->
      eq tokReceived, 'secret-tok'

describe 'Auth.restoreSession', ->
  it 'retourne l\'utilisateur si me est défini', ->
    GQL.query = -> Promise.resolve { me: { id: '10', username: 'dan', email: '', groups: [] } }
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

describe 'Auth.isAdmin', ->
  it 'retourne true si currentUser est dans le groupe admin', ->
    A.currentUser = { id: '1', username: 'root', groups: [{ id: 'g1', name: 'admin' }] }
    assert A.isAdmin(), 'isAdmin devrait être true'

  it 'retourne false si currentUser n\'est pas dans admin', ->
    A.currentUser = { id: '2', username: 'bob', groups: [{ id: 'g2', name: 'users' }] }
    assert !A.isAdmin(), 'isAdmin devrait être false'

  it 'retourne false si currentUser est null', ->
    A.currentUser = null
    assert !A.isAdmin(), 'isAdmin devrait être false quand currentUser est null'

describe 'Auth.changePassword', ->
  it 'appelle mutate et retourne la valeur changePassword', ->
    GQL.mutate = (q, v) ->
      Promise.resolve { changePassword: true }
    A.changePassword('old', 'new').then (result) ->
      assert result, 'changePassword devrait retourner true'

describe 'Auth.isAdmin (sans groupes)', ->
  it 'retourne false si groups est undefined', ->
    A.currentUser = { id: '3', username: 'ghost' }
    assert !A.isAdmin(), 'isAdmin devrait être false si groups absent'

summary()
