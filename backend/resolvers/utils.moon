-- resolvers/utils.moon
-- Shared helpers for all resolvers.

-- Ensures an authentication context is present.
-- Raises a GraphQL "Unauthorized" error otherwise.
require_auth = (ctx) ->
  error "Unauthorized" unless ctx and ctx.user_id
  ctx.user_id

-- Ensures the authenticated user belongs to the 'admin' group.
-- Group lookup is done by name instead of id for robustness.
require_admin = (ctx) ->
  uid = require_auth ctx
  is_admin = false
  for gid_row in *box.space._tdb_memberships.index.by_user\select { uid }
    g = box.space._tdb_groups\get gid_row[2]
    if g and g[2] == 'admin'
      is_admin = true
      break
  error "Forbidden" unless is_admin
  uid

{ :require_auth, :require_admin }
