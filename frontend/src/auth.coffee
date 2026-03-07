# auth.coffee
# Handles login, logout, and current-user state.

LOGIN_MUTATION = """
  mutation Login($username: String!, $password: String!) {
    login(username: $username, password: $password) {
      token
      user { id username email }
    }
  }
"""

LOGOUT_MUTATION = """
  mutation { logout }
"""

ME_QUERY = """
  query { me { id username email } }
"""

window.Auth =
  currentUser: null

  login: (username, password) ->
    GQL.mutate(LOGIN_MUTATION, { username, password })
      .then (data) ->
        GQL.setToken data.login.token
        Auth.currentUser = data.login.user
        Auth.currentUser

  logout: ->
    GQL.mutate(LOGOUT_MUTATION)
      .finally ->
        GQL.clearToken()
        Auth.currentUser = null
        App.showLogin()

  restoreSession: ->
    # Try to fetch current user with any existing token
    GQL.query(ME_QUERY)
      .then (data) ->
        if data.me
          Auth.currentUser = data.me
          Auth.currentUser
        else
          null
      .catch -> null
