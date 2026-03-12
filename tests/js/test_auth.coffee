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
global.Auth = A   # auth.js references Auth directly (browser global)

describe 'Auth.login', ->
  it 'calls GQL.mutate with correct arguments', ->
    captured = null
    GQL.mutate = (q, v) ->
      captured = v
      Promise.resolve { login: { token: 'tok99', user: { id: '1', username: 'alice', email: 'a@b.c', groups: [] } } }
    A.login('alice', 'secret').then ->
      eq captured?.username, 'alice'
      eq captured?.password, 'secret'

  it 'returns resolved user', ->
    GQL.mutate = (q, v) ->
      Promise.resolve { login: { token: 't', user: { id: '2', username: 'bob', email: '', groups: [] } } }
    A.login('bob', 'pass').then (user) ->
      eq user.username, 'bob'
      eq user.id, '2'

  it 'calls GQL.setToken with received token', ->
    tokReceived = null
    GQL.setToken = (t) -> tokReceived = t; GQL._token = t
    GQL.mutate = (q, v) ->
      Promise.resolve { login: { token: 'secret-tok', user: { id: '3', username: 'carol', email: '', groups: [] } } }
    A.login('carol', 'pw').then ->
      eq tokReceived, 'secret-tok'

describe 'Auth.restoreSession', ->
  it 'returns user when me is defined', ->
    GQL.query = -> Promise.resolve { me: { id: '10', username: 'dan', email: '', groups: [] } }
    A.restoreSession().then (u) ->
      eq u?.username, 'dan'

  it 'returns null when me is null', ->
    GQL.query = -> Promise.resolve { me: null }
    A.restoreSession().then (u) ->
      eq u, null

  it 'returns null on network error', ->
    GQL.query = -> Promise.reject new Error 'network error'
    A.restoreSession().then (u) ->
      eq u, null

describe 'Auth.isAdmin', ->
  it 'returns true when currentUser is in admin group', ->
    A.currentUser = { id: '1', username: 'root', groups: [{ id: 'g1', name: 'admin' }] }
    assert A.isAdmin(), 'isAdmin should be true'

  it 'returns false when currentUser is not in admin', ->
    A.currentUser = { id: '2', username: 'bob', groups: [{ id: 'g2', name: 'users' }] }
    assert !A.isAdmin(), 'isAdmin should be false'

  it 'returns false when currentUser is null', ->
    A.currentUser = null
    assert !A.isAdmin(), 'isAdmin should be false when currentUser is null'

describe 'Auth.changePassword', ->
  it 'calls mutate and returns changePassword value', ->
    GQL.mutate = (q, v) ->
      Promise.resolve { changePassword: true }
    A.changePassword('old', 'new').then (result) ->
      assert result, 'changePassword devrait retourner true'

describe 'Auth.isAdmin (sans groupes)', ->
  it 'returns false when groups is undefined', ->
    A.currentUser = { id: '3', username: 'ghost' }
    assert !A.isAdmin(), 'isAdmin should be false when groups is missing'

summary()
