local uuid_mod = require('uuid')
local WILDCARD_ID = '00000000-0000-0000-0000-000000000000'
local LEVELS = {
  read = 1,
  write = 2,
  admin = 3
}
local level_value
level_value = function(l)
  return LEVELS[l] or 0
end
local create_group
create_group = function(name, description)
  local gid = tostring(uuid_mod.new())
  box.space._tdb_groups:insert({
    gid,
    name,
    description or '',
    os.time()
  })
  return {
    id = gid,
    name = name,
    description = description
  }
end
local delete_group
delete_group = function(group_id)
  box.space._tdb_groups:delete(group_id)
  local mems = { }
  local _list_0 = box.space._tdb_memberships.index.by_group:select({
    group_id
  })
  for _index_0 = 1, #_list_0 do
    local t = _list_0[_index_0]
    table.insert(mems, t)
  end
  for _index_0 = 1, #mems do
    local t = mems[_index_0]
    box.space._tdb_memberships:delete({
      t[1],
      t[2]
    })
  end
  local perms = { }
  local _list_1 = box.space._tdb_permissions.index.by_group:select({
    group_id
  })
  for _index_0 = 1, #_list_1 do
    local t = _list_1[_index_0]
    table.insert(perms, t)
  end
  for _index_0 = 1, #perms do
    local t = perms[_index_0]
    box.space._tdb_permissions:delete(t[1])
  end
end
local list_groups
list_groups = function()
  local result = { }
  local _list_0 = box.space._tdb_groups:select({ })
  for _index_0 = 1, #_list_0 do
    local t = _list_0[_index_0]
    table.insert(result, {
      id = t[1],
      name = t[2],
      description = t[3],
      createdAt = t[4]
    })
  end
  return result
end
local get_group
get_group = function(id)
  local t = box.space._tdb_groups:get(id)
  if not (t) then
    return nil
  end
  return {
    id = t[1],
    name = t[2],
    description = t[3],
    createdAt = t[4]
  }
end
local add_member
add_member = function(user_id, group_id)
  return box.space._tdb_memberships:insert({
    user_id,
    group_id
  })
end
local remove_member
remove_member = function(user_id, group_id)
  return box.space._tdb_memberships:delete({
    user_id,
    group_id
  })
end
local user_groups
user_groups = function(user_id)
  local result = { }
  local _list_0 = box.space._tdb_memberships.index.by_user:select({
    user_id
  })
  for _index_0 = 1, #_list_0 do
    local t = _list_0[_index_0]
    local g = box.space._tdb_groups:get(t[2])
    if g then
      table.insert(result, {
        id = g[1],
        name = g[2]
      })
    end
  end
  return result
end
local group_members
group_members = function(group_id)
  local result = { }
  local _list_0 = box.space._tdb_memberships.index.by_group:select({
    group_id
  })
  for _index_0 = 1, #_list_0 do
    local t = _list_0[_index_0]
    local u = box.space._tdb_users:get(t[1])
    if u then
      table.insert(result, {
        id = u[1],
        username = u[2]
      })
    end
  end
  return result
end
local grant
grant = function(group_id, resource_type, resource_id, level)
  local pid = tostring(uuid_mod.new())
  local rid = resource_id or WILDCARD_ID
  box.space._tdb_permissions:insert({
    pid,
    group_id,
    resource_type,
    rid,
    level
  })
  return {
    id = pid,
    groupId = group_id,
    resourceType = resource_type,
    resourceId = rid,
    level = level
  }
end
local revoke
revoke = function(permission_id)
  return box.space._tdb_permissions:delete(permission_id)
end
local list_permissions
list_permissions = function(group_id)
  local result = { }
  local _list_0 = box.space._tdb_permissions.index.by_group:select({
    group_id
  })
  for _index_0 = 1, #_list_0 do
    local t = _list_0[_index_0]
    table.insert(result, {
      id = t[1],
      groupId = t[2],
      resourceType = t[3],
      resourceId = t[4],
      level = t[5]
    })
  end
  return result
end
local can
can = function(user_id, resource_type, resource_id, required_level)
  local groups = user_groups(user_id)
  local required_val = level_value(required_level)
  for _index_0 = 1, #groups do
    local g = groups[_index_0]
    local _list_0 = box.space._tdb_permissions.index.by_resource:select({
      resource_type,
      resource_id
    })
    for _index_1 = 1, #_list_0 do
      local t = _list_0[_index_1]
      if t[2] == g.id and level_value(t[5]) >= required_val then
        return true
      end
    end
    local _list_1 = box.space._tdb_permissions.index.by_resource:select({
      resource_type,
      WILDCARD_ID
    })
    for _index_1 = 1, #_list_1 do
      local t = _list_1[_index_1]
      if t[2] == g.id and level_value(t[5]) >= required_val then
        return true
      end
    end
    local _list_2 = box.space._tdb_permissions.index.by_resource:select({
      '*',
      WILDCARD_ID
    })
    for _index_1 = 1, #_list_2 do
      local t = _list_2[_index_1]
      if t[2] == g.id and level_value(t[5]) >= required_val then
        return true
      end
    end
  end
  return false
end
return {
  create_group = create_group,
  delete_group = delete_group,
  list_groups = list_groups,
  get_group = get_group,
  add_member = add_member,
  remove_member = remove_member,
  user_groups = user_groups,
  group_members = group_members,
  grant = grant,
  revoke = revoke,
  list_permissions = list_permissions,
  can = can,
  WILDCARD_ID = WILDCARD_ID
}
