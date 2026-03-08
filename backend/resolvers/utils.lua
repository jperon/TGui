local require_auth
require_auth = function(ctx)
  if not (ctx and ctx.user_id) then
    error("Unauthorized")
  end
  return ctx.user_id
end
local require_admin
require_admin = function(ctx)
  local uid = require_auth(ctx)
  local is_admin = false
  local _list_0 = box.space._tdb_memberships.index.by_user:select({
    uid
  })
  for _index_0 = 1, #_list_0 do
    local gid_row = _list_0[_index_0]
    local g = box.space._tdb_groups:get(gid_row[2])
    if g and g[2] == 'admin' then
      is_admin = true
      break
    end
  end
  if not (is_admin) then
    error("Forbidden")
  end
  return uid
end
return {
  require_auth = require_auth,
  require_admin = require_admin
}
