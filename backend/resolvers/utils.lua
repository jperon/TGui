local perms_mod = require('core.permissions')
local require_auth
require_auth = function(ctx)
  if not (ctx and ctx.user_id) then
    error("Unauthorized")
  end
  return ctx.user_id
end
local is_admin_user
is_admin_user = function(uid)
  local _list_0 = box.space._tdb_memberships.index.by_user:select({
    uid
  })
  for _index_0 = 1, #_list_0 do
    local gid_row = _list_0[_index_0]
    local g = box.space._tdb_groups:get(gid_row[2])
    if g and g[2] == 'admin' then
      return true
    end
  end
  return false
end
local require_admin
require_admin = function(ctx)
  local uid = require_auth(ctx)
  if not (is_admin_user(uid)) then
    error("Forbidden")
  end
  return uid
end
local is_perm_subject
is_perm_subject = function(ctx, uid)
  if ctx.token then
    return true
  end
  local ok, t = pcall(function()
    return box.space._tdb_users:get(uid)
  end)
  return ok and t ~= nil
end
local perm_ok
perm_ok = function(ctx, resource_type, resource_id, level)
  local uid = require_auth(ctx)
  if not (is_perm_subject(ctx, uid)) then
    return true
  end
  if is_admin_user(uid) then
    return true
  end
  return perms_mod.can(uid, resource_type, resource_id or perms_mod.WILDCARD_ID, level)
end
local require_perm
require_perm = function(ctx, resource_type, resource_id, level)
  local uid = require_auth(ctx)
  if not (perm_ok(ctx, resource_type, resource_id, level)) then
    error("Forbidden")
  end
  return uid
end
local fk_cache_for
fk_cache_for = function(ctx)
  local cache = ctx._fk_cache or { }
  local readable = { }
  local _list_0 = box.space._tdb_spaces:select({ })
  for _index_0 = 1, #_list_0 do
    local sp = _list_0[_index_0]
    readable[sp[2]] = perm_ok(ctx, 'space', sp[1], 'read')
  end
  cache.readable_by_name = readable
  cache.can_read = function(space_name)
    return cache.readable_by_name[space_name] == true
  end
  ctx._fk_cache = cache
  return cache
end
return {
  require_auth = require_auth,
  require_admin = require_admin,
  require_perm = require_perm,
  perm_ok = perm_ok,
  is_admin_user = is_admin_user,
  fk_cache_for = fk_cache_for
}
