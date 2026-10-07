# tests/js/test_password_policy.coffee
# Forced default-password change, frontend side (spec §7 / audit 1.4):
# - the warning banner depends on user.mustChangePassword (server-computed flag),
#   not on the legacy localStorage shortcut nor on the username;
# - a PASSWORD_CHANGE_REQUIRED GraphQL error opens the change-password dialog.

{ makeElement, localStorageStub } = require './dom_stub'
{ describe, it, eq, assert, summary } = require './runner'

# Register the DOM elements App.showMain touches.
for id in ['login-overlay', 'main', 'current-user-btn', 'admin-sidebar-section',
           'plugins-sidebar-section', 'default-password-warning']
  document._setById id, makeElement 'div'

global.GQL =
  _token: null
  loadToken: (->)
  setToken: (t) -> @_token = t
  clearToken: -> @_token = null
  query:  -> Promise.resolve {}
  mutate: -> Promise.resolve {}

require '../../frontend/src/auth'
global.Auth = window.Auth
require '../../frontend/src/widget_plugins'
require '../../frontend/src/app'
App = window.App

warningVisible = ->
  not document.getElementById('default-password-warning').classList.contains 'hidden'

show = (user) ->
  Auth.currentUser = user
  App.showMain user

describe 'default password warning', ->
  it 'shows the banner when the server flag is true', ->
    show { id: '1', username: 'alice', email: '', groups: [], mustChangePassword: true }
    assert warningVisible(), 'banner should be visible when mustChangePassword is true'

  it 'hides the banner when the server flag is false', ->
    show { id: '1', username: 'admin', email: '', groups: [], mustChangePassword: false }
    assert !warningVisible(), 'banner should be hidden when mustChangePassword is false'

  it 'is not bypassed by the legacy localStorage flag', ->
    localStorageStub.setItem 'tdb_password_changed', '1'
    show { id: '1', username: 'admin', email: '', groups: [], mustChangePassword: true }
    assert warningVisible(), 'localStorage must no longer hide the banner'
    localStorageStub.removeItem 'tdb_password_changed'

  it 'no longer depends on the username', ->
    show { id: '1', username: 'root', email: '', groups: [], mustChangePassword: false }
    assert !warningVisible(), 'a non-admin username with a false flag hides the banner'

require '../../frontend/src/graphql_client'
GQL = window.GQL

describe 'PASSWORD_CHANGE_REQUIRED handling', ->
  it 'opens the change-password dialog with a readable message', ->
    captured = null
    window.App._openChangePasswordDialog = (message) -> captured = message
    global.fetch = (url, opts) ->
      Promise.resolve json: -> Promise.resolve {
        errors: [{ message: 'PASSWORD_CHANGE_REQUIRED: change the default password' }]
      }
    GQL.clearToken()
    GQL.query('query { me { id } }').then(
      -> throw new Error 'the query should have been rejected'
      (err) ->
        eq err.message.indexOf('PASSWORD_CHANGE_REQUIRED'), 0
        eq captured, 'change the default password'
    )

summary()
