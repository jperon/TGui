-- resolvers/auth_resolvers.moon
-- Resolvers for authentication, user management, groups, and permissions.

auth_mod  = require 'core.auth'
perms_mod = require 'core.permissions'

-- Extract session from context (set by HTTP middleware)
require_auth = (ctx) ->
  error "Unauthorized" unless ctx and ctx.user_id
  ctx.user_id

Query =
  me: (_, args, ctx) ->
    return nil unless ctx and ctx.user_id
    auth_mod.get_user_by_id ctx.user_id

  users: (_, args, ctx) ->
    require_auth ctx
    result = {}
    for t in *box.space._tdb_users\select {}
      table.insert result, { id: t[1], username: t[2], email: t[3], createdAt: t[6] }
    result

  user: (_, args, ctx) ->
    require_auth ctx
    auth_mod.get_user_by_id args.id

  groups: (_, args, ctx) ->
    require_auth ctx
    perms_mod.list_groups!

  group: (_, args, ctx) ->
    require_auth ctx
    perms_mod.get_group args.id

Mutation =
  login: (_, args, ctx) ->
    session, err = auth_mod.login args.username, args.password
    unless session
      error err or 'Login failed'
    user = auth_mod.get_user_by_id session.user_id
    { token: session.token, user: user }

  logout: (_, args, ctx) ->
    if ctx and ctx.token
      auth_mod.delete_session ctx.token
    true

  createUser: (_, args, ctx) ->
    i = args.input
    auth_mod.create_user i.username, i.email, i.password

  createGroup: (_, args, ctx) ->
    require_auth ctx
    i = args.input
    perms_mod.create_group i.name, i.description

  deleteGroup: (_, args, ctx) ->
    require_auth ctx
    perms_mod.delete_group args.id
    true

  addMember: (_, args, ctx) ->
    require_auth ctx
    perms_mod.add_member args.userId, args.groupId
    true

  removeMember: (_, args, ctx) ->
    require_auth ctx
    perms_mod.remove_member args.userId, args.groupId
    true

  grant: (_, args, ctx) ->
    require_auth ctx
    i = args.input
    perms_mod.grant args.groupId, i.resourceType, i.resourceId, i.level

  revoke: (_, args, ctx) ->
    require_auth ctx
    perms_mod.revoke args.permissionId
    true

-- Field-level resolvers for User and Group types
User =
  groups: (obj, args, ctx) -> perms_mod.user_groups obj.id

Group =
  members:     (obj, args, ctx) -> perms_mod.group_members obj.id
  permissions: (obj, args, ctx) -> perms_mod.list_permissions obj.id

{ :Query, :Mutation, :User, :Group }
