-- resolvers/utils.moon
-- Shared helpers for all resolvers.

perms_mod = require 'core.permissions'

-- Ensures an authentication context is present.
-- Raises a GraphQL "Unauthorized" error otherwise.
require_auth = (ctx) ->
  error "Unauthorized" unless ctx and ctx.user_id
  ctx.user_id

-- True when the user belongs to the built-in 'admin' group.
-- Group lookup is done by name instead of id for robustness.
is_admin_user = (uid) ->
  for gid_row in *box.space._tdb_memberships.index.by_user\select { uid }
    g = box.space._tdb_groups\get gid_row[2]
    return true if g and g[2] == 'admin'
  false

-- Ensures the authenticated user belongs to the 'admin' group.
-- Group lookup is done by name instead of id for robustness.
require_admin = (ctx) ->
  uid = require_auth ctx
  error "Forbidden" unless is_admin_user uid
  uid

-- True when the principal is one the permission model can evaluate: a stored
-- user record, or a context carrying a validated session token.
-- backend/http_server.moon:79-86 sets ctx.token together with ctx.user_id, so
-- every user-facing GraphQL request is covered; a deleted user with a live
-- session still carries its token and stays subject to the check.
-- The bare in-process contexts that reference no stored user — the bootstrap
-- fixtures (backend/fixtures.moon:13-14, { user_id: 1 }, no token) and the
-- test suite (tests/test_relations.moon:15, tests/test_data_filters.moon:21,
-- tests/test_data_views.moon:42) — are only checked by require_auth.
is_perm_subject = (ctx, uid) ->
  return true if ctx.token
  ok, t = pcall -> box.space._tdb_users\get uid
  ok and t != nil

-- True when the principal may perform `level` on (resource_type, resource_id).
-- Members of the 'admin' group always pass. A nil resource_id addresses the
-- type-level wildcard, exactly like perms_mod.grant (core/permissions.moon:80)
-- which stores it as WILDCARD_ID.
perm_ok = (ctx, resource_type, resource_id, level) ->
  uid = require_auth ctx
  return true unless is_perm_subject ctx, uid
  return true if is_admin_user uid
  perms_mod.can uid, resource_type, resource_id or perms_mod.WILDCARD_ID, level

-- Enforces a permission check for one resolver.
-- Returns the authenticated user id, raises a GraphQL "Forbidden" error otherwise.
require_perm = (ctx, resource_type, resource_id, level) ->
  uid = require_auth ctx
  error "Forbidden" unless perm_ok ctx, resource_type, resource_id, level
  uid

-- Returns the per-request FK cache (creating it if absent) with a `can_read`
-- predicate attached. Formula columns and FK traversal consult it through the
-- cache (core/triggers.moon make_space_helper and ensure_space): a space the
-- user cannot read yields no records, so no indirect read leaks. The
-- server-side write-trigger context builds no cache, so `can_read` stays absent
-- and triggers keep full access.
--
-- The readability map is (re)computed here, rather than inside can_read:
-- can_read runs from a metatable __index while safe_formula_call installs a
-- debug count hook (core/config.moon), and performing the permission lookups
-- (box accesses) at that point makes the hook trip the instruction limit
-- spuriously. Resolving every space by name up front keeps can_read a pure
-- table lookup. The map is rebuilt on every call so a cache stored on a
-- long-lived context cannot go stale when spaces are created; callers that
-- loop over records reuse the same cache instead of calling this again.
-- Spaces are read directly from the metadata space (no extra module import)
-- to avoid a require cycle.
fk_cache_for = (ctx) ->
  cache = ctx._fk_cache or {}
  readable = {}
  for sp in *box.space._tdb_spaces\select {}
    readable[sp[2]] = perm_ok ctx, 'space', sp[1], 'read'
  cache.readable_by_name = readable
  cache.can_read = (space_name) -> cache.readable_by_name[space_name] == true
  ctx._fk_cache = cache
  cache

{ :require_auth, :require_admin, :require_perm, :perm_ok, :is_admin_user, :fk_cache_for }
