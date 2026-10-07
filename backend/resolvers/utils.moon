-- resolvers/utils.moon
-- Shared helpers for all resolvers.

perms_mod = require 'core.permissions'

-- Forced-password-change enforcement switch (spec §7 / audit 1.4). Active by
-- default; disabled for the test environment (the Lua suite and the Playwright
-- suite log in as admin/adminadmin and must not be blocked) or when an operator
-- explicitly opts out. Read from the environment on every call — never a
-- constant captured at import time — so tests can toggle it.
password_change_enforced = ->
  return false if os.getenv('TGUI_TEST_ENV') == 'true'
  return false if os.getenv('TDB_ALLOW_DEFAULT_PASSWORD') == 'true'
  true

-- Ensures an authentication context is present, WITHOUT the forced-password
-- gate. Reserved for the few operations that must stay reachable while the
-- account still uses the default password: me, changePassword and logout.
require_auth_unchecked = (ctx) ->
  error "Unauthorized" unless ctx and ctx.user_id
  ctx.user_id

-- Ensures an authentication context is present and that, when enforcement is
-- on, the account is not still using the default password. Raises a GraphQL
-- "Unauthorized" error otherwise. The error message starts with
-- PASSWORD_CHANGE_REQUIRED so the frontend can open the change-password dialog.
-- A trusted in-process context is never refused.
require_auth = (ctx) ->
  uid = require_auth_unchecked ctx
  if password_change_enforced! and not ctx.trusted and ctx.must_change_password
    error "PASSWORD_CHANGE_REQUIRED: the default password must be changed before this operation"
  uid

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

-- Builds an explicitly trusted in-process context. Such a context opts out of
-- permission evaluation; the bootstrap fixtures (backend/fixtures.moon:13-14)
-- and the test suite use it for code paths that run without a user-facing
-- session. Only code that builds a context can set `trusted`: the user-facing
-- context is built from scratch in backend/http_server.moon:96-116, which never
-- copies a `trusted` field out of the request body, so a client cannot forge it.
trusted_ctx = (user_id) ->
  { user_id: user_id, trusted: true }

-- True when the principal may perform `level` on (resource_type, resource_id).
-- A trusted in-process context always passes. Members of the 'admin' group
-- always pass. Every other context is checked: a context without a stored user
-- (or one whose user was deleted) has no grant and is refused. A nil
-- resource_id addresses the type-level wildcard, exactly like perms_mod.grant
-- (core/permissions.moon:80) which stores it as WILDCARD_ID.
perm_ok = (ctx, resource_type, resource_id, level) ->
  uid = require_auth ctx
  return true if ctx.trusted
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

{ :require_auth, :require_auth_unchecked, :require_admin, :require_perm,
  :perm_ok, :is_admin_user, :fk_cache_for, :trusted_ctx, :password_change_enforced }
