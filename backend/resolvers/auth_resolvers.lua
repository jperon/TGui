local auth_mod = require('core.auth')
local perms_mod = require('core.permissions')
local require_auth, require_admin
do
  local _obj_0 = require('resolvers.utils')
  require_auth, require_admin = _obj_0.require_auth, _obj_0.require_admin
end
local Query = {
  me = function(_, args, ctx)
    if not (ctx and ctx.user_id) then
      return nil
    end
    return auth_mod.get_user_by_id(ctx.user_id)
  end,
  users = function(_, args, ctx)
    require_auth(ctx)
    local result = { }
    local _list_0 = box.space._tdb_users:select({ })
    for _index_0 = 1, #_list_0 do
      local t = _list_0[_index_0]
      table.insert(result, {
        id = t[1],
        username = t[2],
        email = t[3],
        createdAt = t[6]
      })
    end
    return result
  end,
  user = function(_, args, ctx)
    require_auth(ctx)
    return auth_mod.get_user_by_id(args.id)
  end,
  groups = function(_, args, ctx)
    require_auth(ctx)
    return perms_mod.list_groups()
  end,
  group = function(_, args, ctx)
    require_auth(ctx)
    return perms_mod.get_group(args.id)
  end
}
local Mutation = {
  login = function(_, args, ctx)
    local session, err = auth_mod.login(args.username, args.password)
    if not (session) then
      error(err or 'Login failed')
    end
    local user = auth_mod.get_user_by_id(session.user_id)
    return {
      token = session.token,
      user = user
    }
  end,
  logout = function(_, args, ctx)
    if ctx and ctx.token then
      auth_mod.delete_session(ctx.token)
    end
    return true
  end,
  createUser = function(_, args, ctx)
    require_admin(ctx)
    local i = args.input
    return auth_mod.create_user(i.username, i.email, i.password)
  end,
  changePassword = function(_, args, ctx)
    local uid = require_auth(ctx)
    return auth_mod.change_password(uid, args.currentPassword, args.newPassword)
  end,
  adminSetPassword = function(_, args, ctx)
    require_admin(ctx)
    return auth_mod.admin_set_password(args.userId, args.newPassword)
  end,
  createGroup = function(_, args, ctx)
    require_admin(ctx)
    local i = args.input
    return perms_mod.create_group(i.name, i.description)
  end,
  deleteGroup = function(_, args, ctx)
    require_admin(ctx)
    perms_mod.delete_group(args.id)
    return true
  end,
  addMember = function(_, args, ctx)
    require_admin(ctx)
    perms_mod.add_member(args.userId, args.groupId)
    return true
  end,
  removeMember = function(_, args, ctx)
    require_admin(ctx)
    perms_mod.remove_member(args.userId, args.groupId)
    return true
  end,
  grant = function(_, args, ctx)
    require_admin(ctx)
    local i = args.input
    return perms_mod.grant(args.groupId, i.resourceType, i.resourceId, i.level)
  end,
  revoke = function(_, args, ctx)
    require_admin(ctx)
    perms_mod.revoke(args.permissionId)
    return true
  end
}
local User = {
  groups = function(obj, args, ctx)
    return perms_mod.user_groups(obj.id)
  end
}
local Group = {
  members = function(obj, args, ctx)
    return perms_mod.group_members(obj.id)
  end,
  permissions = function(obj, args, ctx)
    return perms_mod.list_permissions(obj.id)
  end
}
return {
  Query = Query,
  Mutation = Mutation,
  User = User,
  Group = Group
}
