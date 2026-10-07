-- tests/test_permissions.moon
-- Tests permission coverage: require_auth, require_admin,
-- sessions, purge. Runs inside Tarantool instance.

R    = require 'tests.runner'
auth = require 'core.auth'
{ :require_auth, :require_admin } = require 'resolvers.utils'
spaces_mod = require 'core.spaces'
auth_r = require 'resolvers.auth_resolvers'
data_r = require 'resolvers.data_resolvers'
custom_view_r = require 'resolvers.custom_view_resolvers'
json = require 'json'

SUFFIX = tostring math.random 100000, 999999

-- ────────────────────────────────────────────────────────────────────────────
R.describe "require_auth — blocked without authentication", ->

  R.it "ctx nil -> Unauthorized error", ->
    ok, err = pcall require_auth, nil
    R.eq ok, false
    R.ok tostring(err)\find 'Unauthorized'

  R.it "ctx without user_id -> Unauthorized", ->
    ok, err = pcall require_auth, {}
    R.eq ok, false
    R.ok tostring(err)\find 'Unauthorized'

  R.it "ctx with user_id -> returns id", ->
    uid = require_auth { user_id: 'fake-uid' }
    R.eq uid, 'fake-uid'

-- ────────────────────────────────────────────────────────────────────────────
R.describe "require_admin — blocked for non-admin", ->

  R.it "ctx nil -> Unauthorized (not Forbidden)", ->
    ok, err = pcall require_admin, nil
    R.eq ok, false
    R.ok tostring(err)\find 'Unauthorized'

  R.it "non-admin user -> Forbidden", ->
    -- Create a non-admin user
    ok_u, user = pcall auth.create_user, "nonadmin_#{SUFFIX}", "nonadmin_#{SUFFIX}@test.local", "pass1234"
    R.ok ok_u
    -- Create a session for this user
    sess = auth.create_session user.id
    ctx  = { user_id: user.id }
    ok_a, err_a = pcall require_admin, ctx
    R.eq ok_a, false
    R.ok tostring(err_a)\find 'Forbidden'
    -- Cleanup
    auth.delete_session sess.token
    box.space._tdb_users\delete user.id

  R.it "admin user -> success", ->
    admin_user = auth.get_user_by_username 'admin'
    R.ok admin_user
    uid = require_admin { user_id: admin_user.id }
    R.eq uid, admin_user.id

-- ────────────────────────────────────────────────────────────────────────────
R.describe "Sessions — creation, validation, expiration", ->
  local token, uid

  R.it "create_session returns a token", ->
    user = auth.get_user_by_username 'admin'
    R.ok user
    uid = user.id
    sess = auth.create_session uid
    R.ok sess
    R.ok sess.token
    R.ok #sess.token > 10
    token = sess.token

  R.it "validate_session returns valid session", ->
    sess = auth.validate_session token
    R.ok sess
    R.eq sess.user_id, uid
    R.ok sess.expires_at > os.time!

  R.it "delete_session invalide le token", ->
    auth.delete_session token
    sess = auth.validate_session token
    R.eq sess, nil

  R.it "unknown token -> validate_session returns nil", ->
    sess = auth.validate_session 'tok-that-does-not-exist'
    R.eq sess, nil

-- ────────────────────────────────────────────────────────────────────────────
R.describe "Sessions — expired purge", ->

  R.it "purge_expired_sessions returns deleted session count", ->
    -- Insert an already-expired session directly into the space
    fake_token = "expired_test_#{SUFFIX}"
    box.space._tdb_sessions\insert { fake_token, 'fake-user', os.time! - 7200, os.time! - 3600 }
    -- Session is expired
    sess = auth.validate_session fake_token
    R.eq sess, nil  -- validate_session removes it and returns nil
    -- Ensure it is gone
    t = box.space._tdb_sessions\get fake_token
    R.eq t, nil

  R.it "purge_expired_sessions does not delete valid sessions", ->
    admin = auth.get_user_by_username 'admin'
    sess  = auth.create_session admin.id
    n     = auth.purge_expired_sessions!
    -- Active session must still exist
    still_valid = auth.validate_session sess.token
    R.ok still_valid
    auth.delete_session sess.token

R.describe "GraphQL resolver auth policy — admin queries", ->
  R.it "Query.users refuse un utilisateur non-admin", ->
    ok_u, user = pcall auth.create_user, "policy_nonadmin_#{SUFFIX}", "policy_nonadmin_#{SUFFIX}@test.local", "pass1234"
    R.ok ok_u
    ctx = { user_id: user.id }
    ok_q, err_q = pcall auth_r.Query.users, nil, {}, ctx
    R.eq ok_q, false
    R.ok tostring(err_q)\find 'Forbidden'
    box.space._tdb_users\delete user.id

  R.it "Query.users accepte un admin", ->
    admin_user = auth.get_user_by_username 'admin'
    res = auth_r.Query.users nil, {}, { user_id: admin_user.id }
    R.ok type(res) == 'table'

R.describe "GraphQL resolver auth policy — data/custom views", ->
  R.it "Query.record refuse ctx nil", ->
    ok_q, err_q = pcall data_r.Query.record, nil, { spaceId: 'any', id: 'any' }, nil
    R.eq ok_q, false
    R.ok tostring(err_q)\find 'Unauthorized'

  R.it "Query.record accepts an authenticated user", ->
    admin_user = auth.get_user_by_username 'admin'
    sp_name = "policy_record_#{SUFFIX}"
    sp = spaces_mod.create_user_space sp_name, "policy record test"
    box.space["data_#{sp_name}"]\insert { "row1", json.encode { nom: "ok" } }
    rec = data_r.Query.record nil, { spaceId: sp.id, id: 'row1' }, { user_id: admin_user.id }
    R.ok rec
    R.eq rec.id, 'row1'
    spaces_mod.delete_user_space sp_name

  R.it "customViews refuse ctx nil", ->
    ok_q, err_q = pcall custom_view_r.Query.customViews, nil, {}, nil
    R.eq ok_q, false
    R.ok tostring(err_q)\find 'Unauthorized'

-- ────────────────────────────────────────────────────────────────────────────
-- Task 1 — permissions actually applied in each resolver family
-- ────────────────────────────────────────────────────────────────────────────

perms_mod = require 'core.permissions'
views_mod = require 'core.views'
dv_core   = require 'core.data_views'
schema_r  = require 'resolvers.schema_resolvers'
dv_r      = require 'resolvers.data_view_resolvers'
wpr       = require 'resolvers.widget_plugin_resolvers'
agg_r     = require 'resolvers.aggregate_resolvers'
export_r  = require 'resolvers.export_resolvers'
uuid_mod  = require 'uuid'
{ :require_perm, :perm_ok } = require 'resolvers.utils'

-- Builds a user with its own group and, when resource_type is given, one grant.
new_actor = (prefix, resource_type, resource_id, level) ->
  user = auth.create_user "#{prefix}_#{SUFFIX}", "#{prefix}_#{SUFFIX}@test.local", "pass1234"
  grp  = perms_mod.create_group "#{prefix}g_#{SUFFIX}", ''
  perms_mod.grant grp.id, resource_type, resource_id, level if resource_type
  perms_mod.add_member user.id, grp.id
  { user: user, group: grp }

ctx_of = (a) -> { user_id: a.user.id }

-- Fixture resources, built through core modules (they check no permission).
perm_sp   = spaces_mod.create_user_space "perm_sp_#{SUFFIX}", "permission fixture"
other_sp  = spaces_mod.create_user_space "perm_other_#{SUFFIX}", "permission fixture 2"
perm_sid  = perm_sp.id
other_sid = other_sp.id
spaces_mod.add_field perm_sid, 'nom', 'String'
perm_view_id = tostring uuid_mod.new!
-- Fixture view inserted directly: views_mod.create_view is unusable, it calls
-- validate_view_yaml before its local declaration (backend/core/views.moon:10
-- vs :98) — reported, not fixed here (file out of scope).
box.space._tdb_views\insert {
  perm_view_id
  perm_sid
  "perm_view_#{SUFFIX}"
  'grid'
  '{}'
  os.time!
  os.time!
}
perm_page_id = tostring uuid_mod.new!
box.space._tdb_custom_views\insert {
  perm_page_id
  "perm_page_#{SUFFIX}"
  ''
  'layout:\n  direction: vertical\n  children: []'
  os.time!
  os.time!
}
perm_dv      = dv_core.create_view "perm_dv_#{SUFFIX}", "permission fixture", perm_sid,
  json.encode { columns: { 'nom' } }
perm_plugin_id = tostring uuid_mod.new!
box.space._tdb_widget_plugins\insert {
  perm_plugin_id
  "perm_plugin_#{SUFFIX}"
  ''
  'coffeescript'
  'pug'
  'x = 1'
  'div x'
  os.time!
  os.time!
}

-- Actors: one per permission shape under test.
act_none    = { user: auth.create_user "pnone_#{SUFFIX}", "pnone_#{SUFFIX}@test.local", "pass1234" }
act_noperm  = new_actor 'pnop'
act_read    = new_actor 'prd', 'space', perm_sid, 'read'
act_write   = new_actor 'pwr', 'space', perm_sid, 'write'
act_typerd  = new_actor 'pty', 'space', nil, 'read'
act_global  = new_actor 'pgb', '*', nil, 'admin'
act_gread   = new_actor 'pgr', '*', nil, 'read'
act_gwrite  = new_actor 'pgw', '*', nil, 'write'
act_viewwr  = new_actor 'pvw', 'view', nil, 'write'
act_viewad  = new_actor 'pva', 'view', nil, 'admin'
act_otherrd = new_actor 'por', 'space', other_sid, 'read'

-- ── require_perm helper ─────────────────────────────────────────────────────

R.describe "Task 1 — fixtures", ->
  R.it "fixture view, page, data view and plugin rows exist", ->
    t = box.space._tdb_views\get perm_view_id
    R.ok t, "fixture view row"
    R.eq type(t[5]), 'string', "fixture view config"
    R.ok box.space._tdb_custom_views\get perm_page_id, "fixture page row"
    R.ok dv_core.get_view perm_dv.id, "fixture data view row"
    R.ok box.space._tdb_widget_plugins\get perm_plugin_id, "fixture plugin row"

R.describe "require_perm — user without group", ->
  R.it "refuses read, write and admin", ->
    c = ctx_of act_none
    R.raises (-> require_perm c, 'space', perm_sid, 'read'), 'Forbidden'
    R.raises (-> require_perm c, 'space', perm_sid, 'write'), 'Forbidden'
    R.raises (-> require_perm c, '*', nil, 'admin'), 'Forbidden'

  R.it "refuses when the user has a group but no grant at all", ->
    R.raises (-> require_perm ctx_of(act_noperm), 'space', perm_sid, 'read'), 'Forbidden'
    R.raises (-> require_perm ctx_of(act_noperm), 'space', perm_sid, 'write'), 'Forbidden'

  R.it "refuses reads of every resource family", ->
    c = ctx_of act_none
    R.raises (-> require_perm c, 'view', perm_page_id, 'read'), 'Forbidden'
    R.raises (-> require_perm c, 'view', perm_dv.id, 'read'), 'Forbidden'
    R.raises (-> require_perm c, '*', nil, 'read'), 'Forbidden'

R.describe "require_perm — read level", ->
  R.it "read grant allows read and refuses write", ->
    c = ctx_of act_read
    R.eq require_perm(c, 'space', perm_sid, 'read'), act_read.user.id
    R.raises (-> require_perm c, 'space', perm_sid, 'write'), 'Forbidden'

  R.it "read grant does not leak to another space", ->
    R.raises (-> require_perm ctx_of(act_read), 'space', other_sid, 'read'), 'Forbidden'

  R.it "type wildcard gives read on any space of that type", ->
    c = ctx_of act_typerd
    R.eq require_perm(c, 'space', other_sid, 'read'), act_typerd.user.id
    R.eq require_perm(c, 'space', perm_sid, 'read'), act_typerd.user.id
    R.raises (-> require_perm c, 'space', perm_sid, 'write'), 'Forbidden'

R.describe "require_perm — write and admin levels", ->
  R.it "write grant allows write but not schema admin", ->
    c = ctx_of act_write
    R.eq require_perm(c, 'space', perm_sid, 'write'), act_write.user.id
    R.eq require_perm(c, 'space', perm_sid, 'read'), act_write.user.id
    R.raises (-> require_perm c, '*', nil, 'admin'), 'Forbidden'

  R.it "global '*' admin wildcard passes space, view and schema checks", ->
    c = ctx_of act_global
    R.ok require_perm(c, 'space', perm_sid, 'read')
    R.ok require_perm(c, 'space', perm_sid, 'write')
    R.ok require_perm(c, 'view', nil, 'write')
    R.ok require_perm(c, '*', nil, 'admin')

  R.it "global read wildcard allows reads but not writes", ->
    c = ctx_of act_gread
    R.ok require_perm(c, 'space', other_sid, 'read')
    R.ok require_perm(c, '*', nil, 'read')
    R.raises (-> require_perm c, 'space', other_sid, 'write'), 'Forbidden'

  R.it "global write wildcard allows writes but not schema admin", ->
    c = ctx_of act_gwrite
    R.ok require_perm(c, 'space', perm_sid, 'write')
    R.raises (-> require_perm c, '*', nil, 'admin'), 'Forbidden'

  R.it "admin group passes every check without any grant", ->
    admin_user = auth.get_user_by_username 'admin'
    c = { user_id: admin_user.id }
    R.ok require_perm(c, 'space', perm_sid, 'write')
    R.ok require_perm(c, '*', nil, 'admin')
    R.ok require_perm(c, 'view', perm_page_id, 'read')

R.describe "require_perm — principal resolution", ->
  R.it "deleted user with a live session is refused", ->
    u = auth.create_user "porph_#{SUFFIX}", "porph_#{SUFFIX}@test.local", "pass1234"
    sess = auth.create_session u.id
    box.space._tdb_users\delete u.id
    R.raises (-> require_perm { user_id: u.id, token: sess.token }, 'space', perm_sid, 'read'), 'Forbidden'
    box.space._tdb_sessions\delete sess.token

  R.it "bare in-process context (bootstrap fixtures, no session, unknown principal) is not a permission subject", ->
    -- backend/fixtures.moon:13-14 runs the demo bootstrap with
    -- { user_id: 1 } and no token: such a context has no principal for the
    -- permission model to evaluate, so only require_auth applies to it.
    R.eq require_perm({ user_id: 'bare-in-process-ctx' }, 'space', perm_sid, 'write'),
      'bare-in-process-ctx'

  R.it "ctx without user_id is still Unauthorized", ->
    R.raises (-> require_perm nil, 'space', perm_sid, 'read'), 'Unauthorized'

-- ── schema_resolvers ────────────────────────────────────────────────────────

R.describe "schema_resolvers — schema mutations need global admin", ->
  R.it "user without group: createSpace, addField, deleteSpace, relations refused", ->
    c = ctx_of act_none
    R.raises (-> schema_r.Mutation.createSpace nil, { input: { name: "permns_#{SUFFIX}" } }, c), 'Forbidden'
    R.raises (-> schema_r.Mutation.addField nil, { spaceId: perm_sid, input: { name: 'x', fieldType: 'String', notNull: false, description: '' } }, c), 'Forbidden'
    R.raises (-> schema_r.Mutation.deleteSpace nil, { id: perm_sid }, c), 'Forbidden'
    R.raises (-> schema_r.Mutation.createRelation nil, { input: { name: 'relx', fromSpaceId: perm_sid, fromFieldId: 'f', toSpaceId: other_sid, toFieldId: 'g' } }, c), 'Forbidden'
    R.raises (-> schema_r.Mutation.deleteRelation nil, { id: 'whatever' }, c), 'Forbidden'
    R.raises (-> schema_r.Mutation.updateSpace nil, { id: perm_sid, input: {} }, c), 'Forbidden'

  R.it "read-only and write users cannot change the schema", ->
    R.raises (-> schema_r.Mutation.createSpace nil, { input: { name: "permrw_#{SUFFIX}" } }, ctx_of act_read), 'Forbidden'
    R.raises (-> schema_r.Mutation.createSpace nil, { input: { name: "permrw2_#{SUFFIX}" } }, ctx_of act_write), 'Forbidden'
    R.raises (-> schema_r.Mutation.addField nil, { spaceId: perm_sid, input: { name: 'y', fieldType: 'String', notNull: false, description: '' } }, ctx_of act_write), 'Forbidden'

  R.it "global admin wildcard can create and delete a space", ->
    c = ctx_of act_global
    sp = schema_r.Mutation.createSpace nil, { input: { name: "permgadm_#{SUFFIX}" } }, c
    R.ok sp
    R.eq schema_r.Mutation.deleteSpace(nil, { id: sp.id }, c), true

  R.it "admin group can create and delete a space", ->
    admin_user = auth.get_user_by_username 'admin'
    c = { user_id: admin_user.id }
    sp = schema_r.Mutation.createSpace nil, { input: { name: "permadm_#{SUFFIX}" } }, c
    R.ok sp
    R.eq schema_r.Mutation.deleteSpace(nil, { id: sp.id }, c), true

R.describe "schema_resolvers — reads", ->
  R.it "user without group: single reads refused, lists empty", ->
    c = ctx_of act_none
    R.raises (-> schema_r.Query.space nil, { id: perm_sid }, c), 'Forbidden'
    R.raises (-> schema_r.Query.view nil, { id: perm_view_id }, c), 'Forbidden'
    R.raises (-> schema_r.Query.relations nil, { spaceId: perm_sid }, c), 'Forbidden'
    R.eq #schema_r.Query.spaces(nil, {}, c), 0
    R.eq #schema_r.Query.views(nil, { spaceId: perm_sid }, c), 0

  R.it "read-only user: reads the granted space and only that space", ->
    c = ctx_of act_read
    R.eq schema_r.Query.space(nil, { id: perm_sid }, c).id, perm_sid
    R.eq schema_r.Query.view(nil, { id: perm_view_id }, c).id, perm_view_id
    R.eq #schema_r.Query.views(nil, { spaceId: perm_sid }, c), 1
    lst = schema_r.Query.spaces nil, {}, c
    R.eq #lst, 1
    R.eq lst[1].id, perm_sid

  R.it "user reading another space: no view of the granted space", ->
    c = ctx_of act_otherrd
    R.eq #schema_r.Query.views(nil, { spaceId: perm_sid }, c), 0
    R.raises (-> schema_r.Query.space nil, { id: perm_sid }, c), 'Forbidden'

  R.it "global read wildcard sees every space", ->
    lst = schema_r.Query.spaces nil, {}, ctx_of act_gread
    found = false
    for sp in *lst
      found = true if sp.id == perm_sid
    R.ok found, "global read must list the fixture space"

R.describe "schema_resolvers — view mutations", ->
  R.it "user without group: createView, updateView and deleteView refused", ->
    c = ctx_of act_none
    input = { spaceId: perm_sid, name: "permv_#{SUFFIX}", viewType: 'grid',
      config: { layout: { direction: 'vertical', children: {} } } }
    R.raises (-> schema_r.Mutation.createView nil, { input: input }, c), 'Forbidden'
    R.raises (-> schema_r.Mutation.deleteView nil, { id: perm_view_id }, c), 'Forbidden'
    R.raises (-> schema_r.Mutation.updateView nil, { id: perm_view_id, input: {} }, c), 'Forbidden'

  R.it "space write is not enough to create or edit a view", ->
    input = { spaceId: perm_sid, name: "permv2_#{SUFFIX}", viewType: 'grid',
      config: { layout: { direction: 'vertical', children: {} } } }
    R.raises (-> schema_r.Mutation.createView nil, { input: input }, ctx_of act_write), 'Forbidden'
    R.raises (-> schema_r.Mutation.updateView nil, { id: perm_view_id, input: {} }, ctx_of act_write), 'Forbidden'

  R.it "view write wildcard passes the createView permission check", ->
    input = { spaceId: perm_sid, name: "permv3_#{SUFFIX}", viewType: 'grid',
      config: { layout: { direction: 'vertical', children: {} } } }
    ok_c, err_c = pcall schema_r.Mutation.createView, nil, { input: input }, ctx_of act_viewwr
    -- views_mod.create_view itself raises a pre-existing error (see fixture note)
    R.ok (ok_c or not tostring(err_c)\find 'Forbidden'), "view writer passes the permission check"

  R.it "view write wildcard passes the updateView permission check", ->
    ok_u, err_u = pcall schema_r.Mutation.updateView, nil, { id: perm_view_id, input: {} }, ctx_of act_viewwr
    -- views_mod.update_view is broken: config_str is local to each if/else
    -- branch (backend/core/views.moon:42-47), so the replace always receives a
    -- nil config. Reported, not fixed here (file out of scope).
    R.ok (ok_u or not tostring(err_u)\find 'Forbidden'), "view writer passes the permission check"
    R.raises (-> schema_r.Mutation.deleteView nil, { id: perm_view_id }, ctx_of act_viewwr), 'Forbidden'

  R.it "view admin wildcard deletes a view", ->
    vid = tostring uuid_mod.new!
    now_t = os.time!
    box.space._tdb_views\insert { vid, perm_sid, "permv_del_#{SUFFIX}", 'grid', '{}', now_t, now_t }
    R.eq schema_r.Mutation.deleteView(nil, { id: vid }, ctx_of act_viewad), true

-- ── data_resolvers ──────────────────────────────────────────────────────────

R.describe "data_resolvers — reads and writes on a space", ->
  R.it "user without group: every read and write refused", ->
    c = ctx_of act_none
    R.raises (-> data_r.Query.records nil, { spaceId: perm_sid }, c), 'Forbidden'
    R.raises (-> data_r.Query.record nil, { spaceId: perm_sid, id: 'row' }, c), 'Forbidden'
    R.raises (-> data_r.Mutation.insertRecord nil, { spaceId: perm_sid, data: { nom: 'a' } }, c), 'Forbidden'
    R.raises (-> data_r.Mutation.updateRecord nil, { spaceId: perm_sid, id: 'row', data: { nom: 'b' } }, c), 'Forbidden'
    R.raises (-> data_r.Mutation.deleteRecord nil, { spaceId: perm_sid, id: 'row' }, c), 'Forbidden'
    R.raises (-> data_r.Mutation.deleteRecords nil, { spaceId: perm_sid, ids: { 'row' } }, c), 'Forbidden'
    R.raises (-> data_r.Mutation.insertRecords nil, { spaceId: perm_sid, data: { { nom: 'a' } } }, c), 'Forbidden'
    R.raises (-> data_r.Mutation.updateRecords nil, { spaceId: perm_sid, records: {} }, c), 'Forbidden'
    R.raises (-> data_r.Mutation.restoreRecords nil, { spaceId: perm_sid, records: {} }, c), 'Forbidden'

  R.it "read-only user: reads the granted space, cannot write", ->
    c = ctx_of act_read
    res = data_r.Query.records nil, { spaceId: perm_sid }, c
    R.eq res.total, 0
    R.raises (-> data_r.Mutation.insertRecord nil, { spaceId: perm_sid, data: { nom: 'a' } }, c), 'Forbidden'
    R.raises (-> data_r.Query.records nil, { spaceId: other_sid }, c), 'Forbidden'

  R.it "write user: inserts, reads and deletes", ->
    rec = data_r.Mutation.insertRecord nil, { spaceId: perm_sid, data: { nom: 'perm' } }, ctx_of act_write
    R.ok rec
    R.eq data_r.Query.records(nil, { spaceId: perm_sid }, ctx_of act_read).total, 1
    R.eq data_r.Mutation.deleteRecord(nil, { spaceId: perm_sid, id: rec.id }, ctx_of act_write), true
    R.eq data_r.Query.records(nil, { spaceId: perm_sid }, ctx_of act_read).total, 0

  R.it "type wildcard read: reads any space but cannot write", ->
    c = ctx_of act_typerd
    R.eq data_r.Query.records(nil, { spaceId: other_sid }, c).total, 0
    R.raises (-> data_r.Mutation.insertRecord nil, { spaceId: other_sid, data: { nom: 'a' } }, c), 'Forbidden'

  R.it "global admin wildcard can insert", ->
    rec = data_r.Mutation.insertRecord nil, { spaceId: perm_sid, data: { nom: 'adm' } }, ctx_of act_global
    R.ok rec
    R.eq data_r.Mutation.deleteRecord(nil, { spaceId: perm_sid, id: rec.id }, ctx_of act_global), true

  R.it "admin group can insert", ->
    admin_user = auth.get_user_by_username 'admin'
    c = { user_id: admin_user.id }
    rec = data_r.Mutation.insertRecord nil, { spaceId: perm_sid, data: { nom: 'root' } }, c
    R.ok rec
    data_r.Mutation.deleteRecord nil, { spaceId: perm_sid, id: rec.id }, c

-- ── custom_view_resolvers (pages) ───────────────────────────────────────────

R.describe "custom_view_resolvers — pages", ->
  fixture_page = ->
    pid = tostring uuid_mod.new!
    now_t = os.time!
    box.space._tdb_custom_views\insert {
      pid
      "perm_page2_#{SUFFIX}"
      ''
      'layout:\n  direction: vertical\n  children: []'
      now_t
      now_t
    }
    pid

  R.it "user without group: single read refused, list empty", ->
    c = ctx_of act_none
    R.eq #custom_view_r.Query.customViews(nil, {}, c), 0
    R.raises (-> custom_view_r.Query.customView nil, { id: perm_page_id }, c), 'Forbidden'
    R.raises (-> custom_view_r.Query.exportLayout nil, { pageId: perm_page_id }, c), 'Forbidden'
    R.raises (-> custom_view_r.Query.listLayoutSnapshots nil, { pageId: perm_page_id }, c), 'Forbidden'

  R.it "user without group: every page mutation refused", ->
    c = ctx_of act_none
    R.raises (-> custom_view_r.Mutation.createCustomView nil, { input: { name: "permcp_#{SUFFIX}", yaml: 'layout:\n  direction: vertical\n  children: []' } }, c), 'Forbidden'
    R.raises (-> custom_view_r.Mutation.updateCustomView nil, { id: perm_page_id, input: {} }, c), 'Forbidden'
    R.raises (-> custom_view_r.Mutation.deleteCustomView nil, { id: perm_page_id }, c), 'Forbidden'
    R.raises (-> custom_view_r.Mutation.addWidgetToView nil, { viewId: perm_page_id, widget: { title: 't', space: 's' } }, c), 'Forbidden'
    R.raises (-> custom_view_r.Mutation.reorderWidgets nil, { pageId: perm_page_id, widgetPositions: {} }, c), 'Forbidden'
    R.raises (-> custom_view_r.Mutation.createZone nil, { pageId: perm_page_id, zoneData: {} }, c), 'Forbidden'
    R.raises (-> custom_view_r.Mutation.importLayout nil, { pageId: perm_page_id, yaml: 'x' }, c), 'Forbidden'
    R.raises (-> custom_view_r.Mutation.createLayoutSnapshot nil, { pageId: perm_page_id, yaml: 'x' }, c), 'Forbidden'

  R.it "space write is not enough to edit a page", ->
    R.raises (-> custom_view_r.Mutation.updateCustomView nil, { id: perm_page_id, input: {} }, ctx_of act_write), 'Forbidden'

  R.it "view write wildcard edits a page but cannot delete it", ->
    pg = fixture_page!
    c = ctx_of act_viewwr
    updated = custom_view_r.Mutation.updateCustomView nil, { id: pg, input: { yaml: 'layout:\n  direction: vertical\n  children: []' } }, c
    R.ok updated
    R.raises (-> custom_view_r.Mutation.deleteCustomView nil, { id: pg }, c), 'Forbidden'
    R.eq custom_view_r.Mutation.deleteCustomView(nil, { id: pg }, ctx_of act_viewad), true

  R.it "view write wildcard can create a page", ->
    res = custom_view_r.Mutation.createCustomView nil, {
      input: { name: "permcp2_#{SUFFIX}", yaml: 'layout:\n  direction: vertical\n  children: []' }
    }, ctx_of act_viewwr
    R.ok res
    custom_view_r.Mutation.deleteCustomView nil, { id: res.id }, ctx_of act_viewad

  R.it "read-only space user sees no page", ->
    R.eq #custom_view_r.Query.customViews(nil, {}, ctx_of act_read), 0
    R.raises (-> custom_view_r.Query.customView nil, { id: perm_page_id }, ctx_of act_read), 'Forbidden'

  R.it "global read wildcard can read pages", ->
    R.ok custom_view_r.Query.customView(nil, { id: perm_page_id }, ctx_of act_gread)
    R.ok #custom_view_r.Query.customViews({}, {}, ctx_of act_gread) >= 1

-- ── data_view_resolvers ─────────────────────────────────────────────────────

R.describe "data_view_resolvers — permissions", ->
  R.it "user without group: lists empty and single fetch refused", ->
    c = ctx_of act_none
    R.eq #dv_r.Query.dataViews(nil, {}, c), 0
    R.raises (-> dv_r.Query.dataView nil, { id: perm_dv.id }, c), 'Forbidden'
    R.raises (-> dv_r.Query.executeDataView nil, { id: perm_dv.id }, c), 'Forbidden'

  R.it "user without group: create, update and delete refused", ->
    c = ctx_of act_none
    input = { name: "permdv_#{SUFFIX}", description: '', sourceSpace: perm_sid, config: '{}' }
    R.raises (-> dv_r.Mutation.createDataView nil, { input: input }, c), 'Forbidden'
    R.raises (-> dv_r.Mutation.updateDataView nil, { id: perm_dv.id, input: {} }, c), 'Forbidden'
    R.raises (-> dv_r.Mutation.deleteDataView nil, { id: perm_dv.id }, c), 'Forbidden'

  R.it "reader of the source space can list, fetch and execute", ->
    c = ctx_of act_read
    R.eq #dv_r.Query.dataViews(nil, {}, c), 1
    R.ok dv_r.Query.dataView nil, { id: perm_dv.id }, c
    ok_e, err = pcall dv_r.Query.executeDataView, nil, { id: perm_dv.id }, c
    R.ok (ok_e or not tostring(err)\find 'Forbidden'), "reader passes the permission check"

  R.it "user reading another space sees no data view", ->
    c = ctx_of act_otherrd
    R.eq #dv_r.Query.dataViews(nil, {}, c), 0
    R.raises (-> dv_r.Query.dataView nil, { id: perm_dv.id }, c), 'Forbidden'
    R.raises (-> dv_r.Query.executeDataView nil, { id: perm_dv.id }, c), 'Forbidden'

  R.it "space write is not enough, view write creates and view admin deletes", ->
    input = { name: "permdv2_#{SUFFIX}", description: '', sourceSpace: perm_sid, config: '{}' }
    R.raises (-> dv_r.Mutation.createDataView nil, { input: input }, ctx_of act_write), 'Forbidden'
    dv2 = dv_r.Mutation.createDataView nil, { input: input }, ctx_of act_viewwr
    R.ok dv2
    R.raises (-> dv_r.Mutation.deleteDataView nil, { id: dv2.id }, ctx_of act_viewwr), 'Forbidden'
    R.eq dv_r.Mutation.deleteDataView(nil, { id: dv2.id }, ctx_of act_viewad), true

-- ── widget_plugin_resolvers (plugins) ───────────────────────────────────────

R.describe "widget_plugin_resolvers — permissions", ->
  R.it "user without group: reads and writes refused", ->
    c = ctx_of act_none
    R.raises (-> wpr.Query.widgetPlugins nil, {}, c), 'Forbidden'
    R.raises (-> wpr.Query.widgetPlugin nil, { id: perm_plugin_id }, c), 'Forbidden'
    R.raises (-> wpr.Mutation.createWidgetPlugin nil, { input: { name: "permpg_#{SUFFIX}", scriptCode: 'x = 1', templateCode: 'div x' } }, c), 'Forbidden'
    R.raises (-> wpr.Mutation.updateWidgetPlugin nil, { id: perm_plugin_id, input: {} }, c), 'Forbidden'
    R.raises (-> wpr.Mutation.deleteWidgetPlugin nil, { id: perm_plugin_id }, c), 'Forbidden'

  R.it "space-only reader cannot read plugins", ->
    R.raises (-> wpr.Query.widgetPlugins nil, {}, ctx_of act_read), 'Forbidden'
    R.raises (-> wpr.Query.widgetPlugin nil, { id: perm_plugin_id }, ctx_of act_read), 'Forbidden'

  R.it "global read reads plugins but cannot create", ->
    R.eq #wpr.Query.widgetPlugins({}, {}, ctx_of act_gread), 1
    R.ok wpr.Query.widgetPlugin(nil, { id: perm_plugin_id }, ctx_of act_gread)
    R.raises (-> wpr.Mutation.createWidgetPlugin nil, { input: { name: "permpg2_#{SUFFIX}", scriptCode: 'x = 1', templateCode: 'div x' } }, ctx_of act_gread), 'Forbidden'

  R.it "global write creates but cannot delete", ->
    p2 = wpr.Mutation.createWidgetPlugin nil, {
      input: { name: "permpg3_#{SUFFIX}", scriptCode: 'x = 1', templateCode: 'div x' }
    }, ctx_of act_gwrite
    R.ok p2
    R.raises (-> wpr.Mutation.deleteWidgetPlugin nil, { id: p2.id }, ctx_of act_gwrite), 'Forbidden'
    R.eq wpr.Mutation.deleteWidgetPlugin(nil, { id: p2.id }, ctx_of act_global), true

  R.it "admin group can delete", ->
    p3 = wpr.Mutation.createWidgetPlugin nil, {
      input: { name: "permpg4_#{SUFFIX}", scriptCode: 'x = 1', templateCode: 'div x' }
    }, ctx_of act_global
    R.ok p3
    R.eq wpr.Mutation.deleteWidgetPlugin(nil, { id: p3.id }, ctx_of act_global), true

-- ── aggregate_resolvers ─────────────────────────────────────────────────────

R.describe "aggregate_resolvers — permissions", ->
  agg_args = -> { spaceName: perm_sp.name, aggregate: { { fn: 'count' } } }

  R.it "user without group -> Forbidden", ->
    R.raises (-> agg_r.Query.aggregateSpace nil, agg_args!, ctx_of act_none), 'Forbidden'

  R.it "read-only user on that space -> allowed", ->
    res = agg_r.Query.aggregateSpace nil, agg_args!, ctx_of act_read
    R.ok type(res) == 'table'

  R.it "user reading another space -> Forbidden", ->
    R.raises (-> agg_r.Query.aggregateSpace nil, agg_args!, ctx_of act_otherrd), 'Forbidden'

  R.it "global read -> allowed", ->
    res = agg_r.Query.aggregateSpace nil, agg_args!, ctx_of act_gread
    R.ok type(res) == 'table'

-- ── export_resolvers ────────────────────────────────────────────────────────

R.describe "export_resolvers — permissions", ->
  snap_yaml = 'version: "1"\nschema:\n  spaces: []\n'

  R.it "user without group: export, import and diff refused", ->
    c = ctx_of act_none
    R.raises (-> export_r.Query.exportSnapshot nil, { includeData: false }, c), 'Forbidden'
    R.raises (-> export_r.Mutation.importSnapshot nil, { yaml: snap_yaml, mode: 'merge' }, c), 'Forbidden'
    R.raises (-> export_r.Query.diffSnapshot nil, { yaml: snap_yaml }, c), 'Forbidden'

  R.it "read-only user: diff refused", ->
    R.raises (-> export_r.Query.diffSnapshot nil, { yaml: snap_yaml }, ctx_of act_read), 'Forbidden'

  R.it "admin group can export", ->
    admin_user = auth.get_user_by_username 'admin'
    res = export_r.Query.exportSnapshot nil, { includeData: false }, { user_id: admin_user.id }
    R.ok type(res) == 'string'

-- ── Cleanup ─────────────────────────────────────────────────────────────────

for actor in *{ act_noperm, act_read, act_write, act_typerd, act_global, act_gread,
                act_gwrite, act_viewwr, act_viewad, act_otherrd }
  perms_mod.delete_group actor.group.id
  box.space._tdb_users\delete actor.user.id
box.space._tdb_users\delete act_none.user.id
box.space._tdb_custom_views\delete perm_page_id
dv_core.delete_view perm_dv.id
box.space._tdb_widget_plugins\delete perm_plugin_id
views_mod.delete_view perm_view_id
spaces_mod.delete_user_space perm_sp.name
spaces_mod.delete_user_space other_sp.name
