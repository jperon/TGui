# auth.coffee
# Handles login, logout, current-user state, and password management.

LOGIN_MUTATION = """
  mutation Login($username: String!, $password: String!) {
    login(username: $username, password: $password) {
      token
      user { id username email groups { id name } }
    }
  }
"""

LOGOUT_MUTATION = """
  mutation { logout }
"""

ME_QUERY = """
  query { me { id username email groups { id name } } }
"""

CHANGE_PASSWORD_MUTATION = """
  mutation ChangePassword($currentPassword: String!, $newPassword: String!) {
    changePassword(currentPassword: $currentPassword, newPassword: $newPassword)
  }
"""

CREATE_USER_MUTATION = """
  mutation CreateUser($input: CreateUserInput!) {
    createUser(input: $input) { id username email }
  }
"""

LIST_USERS_QUERY = """
  query { users { id username email groups { id name } } }
"""

LIST_GROUPS_QUERY = """
  query { groups { id name description members { id username } permissions { id resourceType resourceId level } } }
"""

CREATE_GROUP_MUTATION = """
  mutation CreateGroup($input: CreateGroupInput!) {
    createGroup(input: $input) { id name description }
  }
"""

DELETE_GROUP_MUTATION = """
  mutation DeleteGroup($id: ID!) { deleteGroup(id: $id) }
"""

ADD_MEMBER_MUTATION = """
  mutation AddMember($userId: ID!, $groupId: ID!) { addMember(userId: $userId, groupId: $groupId) }
"""

REMOVE_MEMBER_MUTATION = """
  mutation RemoveMember($userId: ID!, $groupId: ID!) { removeMember(userId: $userId, groupId: $groupId) }
"""

GRANT_MUTATION = """
  mutation Grant($groupId: ID!, $input: PermissionInput!) {
    grant(groupId: $groupId, input: $input) { id resourceType resourceId level }
  }
"""

REVOKE_MUTATION = """
  mutation Revoke($permissionId: ID!) { revoke(permissionId: $permissionId) }
"""

window.Auth =
  currentUser: null

  isAdmin: ->
    return false unless @currentUser?.groups
    @currentUser.groups.some (g) -> g.name == 'admin'

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
    GQL.query(ME_QUERY)
      .then (data) ->
        if data.me
          Auth.currentUser = data.me
          Auth.currentUser
        else
          null
      .catch -> null

  changePassword: (currentPassword, newPassword) ->
    GQL.mutate(CHANGE_PASSWORD_MUTATION, { currentPassword, newPassword })
      .then (data) -> data.changePassword

  # Admin-only operations
  createUser: (username, email, password) ->
    GQL.mutate(CREATE_USER_MUTATION, { input: { username, email, password } })
      .then (data) -> data.createUser

  listUsers: ->
    GQL.query(LIST_USERS_QUERY).then (data) -> data.users

  listGroups: ->
    GQL.query(LIST_GROUPS_QUERY).then (data) -> data.groups

  createGroup: (name, description = '') ->
    GQL.mutate(CREATE_GROUP_MUTATION, { input: { name, description } })
      .then (data) -> data.createGroup

  deleteGroup: (id) ->
    GQL.mutate(DELETE_GROUP_MUTATION, { id })

  addMember: (userId, groupId) ->
    GQL.mutate(ADD_MEMBER_MUTATION, { userId, groupId })

  removeMember: (userId, groupId) ->
    GQL.mutate(REMOVE_MEMBER_MUTATION, { userId, groupId })

  grant: (groupId, resourceType, resourceId, level) ->
    GQL.mutate(GRANT_MUTATION, { groupId, input: { resourceType, resourceId, level } })
      .then (data) -> data.grant

  revoke: (permissionId) ->
    GQL.mutate(REVOKE_MUTATION, { permissionId })
