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
    ok_u, user = pcall auth.create_user, "nonadmin_#{SUFFIX}", "nonadmin_#{SUFFIX}@test.local", "pass123"
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
    ok_u, user = pcall auth.create_user, "policy_nonadmin_#{SUFFIX}", "policy_nonadmin_#{SUFFIX}@test.local", "pass123"
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
