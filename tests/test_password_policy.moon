-- tests/test_password_policy.moon
-- Forced change of the default admin password (spec §7 / audit 1.4).
-- The must_change_password flag is computed on every password write, exposed
-- over GraphQL, and enforced by resolvers.utils.require_auth unless the context
-- is trusted or enforcement is disabled (TGUI_TEST_ENV / TDB_ALLOW_DEFAULT_PASSWORD).

R          = require 'tests.runner'
auth       = require 'core.auth'
spaces_mod = require 'core.spaces'
utils      = require 'resolvers.utils'
executor   = require 'graphql.executor'
{ :DEFAULT_ADMIN_PASSWORD } = require 'core.config'
{ :trusted_ctx } = utils

SUFFIX  = tostring math.random 100000, 999999
NEWPASS = 'newpass123'

created = {}

make_user = (tag, password) ->
  uname = "pwd_#{tag}_#{SUFFIX}"
  u = auth.create_user uname, "#{uname}@test.local", password
  table.insert created, u.id
  u

run = (query, ctx) ->
  executor.execute { query: query, context: ctx }

has_error = (res, needle) ->
  return false unless res and res.errors
  for e in *res.errors
    return true if tostring(e.message)\find needle, 1, true
  false

R.describe "password policy — flag computation", ->
  R.after_all ->
    for id in *created
      box.space._tdb_users\delete id
    utils.set_password_enforcement nil

  R.it "l'amorçage de l'admin par défaut pose le drapeau", ->
    admin = auth.get_user_by_username 'admin'
    R.ok admin, 'admin exists'
    R.eq admin.must_change_password, true

  R.it "create_user avec le mot de passe par défaut -> drapeau vrai", ->
    u = make_user 'create_default', DEFAULT_ADMIN_PASSWORD
    R.eq auth.get_user_by_id(u.id).must_change_password, true

  R.it "create_user avec un autre mot de passe -> drapeau faux", ->
    u = make_user 'create_other', 'strongpass1'
    R.eq auth.get_user_by_id(u.id).must_change_password, false

  R.it "changePassword réussi efface le drapeau", ->
    u = make_user 'change_ok', DEFAULT_ADMIN_PASSWORD
    R.eq auth.get_user_by_id(u.id).must_change_password, true
    auth.change_password u.id, DEFAULT_ADMIN_PASSWORD, NEWPASS
    R.eq auth.get_user_by_id(u.id).must_change_password, false

  R.it "changer pour le mot de passe par défaut repose le drapeau", ->
    u = make_user 'change_back', NEWPASS
    R.eq auth.get_user_by_id(u.id).must_change_password, false
    auth.change_password u.id, NEWPASS, DEFAULT_ADMIN_PASSWORD
    R.eq auth.get_user_by_id(u.id).must_change_password, true

  R.it "admin_set_password suit le mot de passe posé", ->
    u = make_user 'admin_set', 'strongpass2'
    auth.admin_set_password u.id, DEFAULT_ADMIN_PASSWORD
    R.eq auth.get_user_by_id(u.id).must_change_password, true
    auth.admin_set_password u.id, 'strongpass3'
    R.eq auth.get_user_by_id(u.id).must_change_password, false

  R.it "la migration tdb_v4 pose le drapeau d'un compte au mot de passe par défaut", ->
    -- Simulate a pre-migration row: a user whose stored password is the default
    -- but which was inserted without the flag column (7 fields).
    u = make_user 'migrate', 'strongpass4'
    box.space._tdb_users\delete u.id
    salt = auth.gen_salt!
    hash = auth.hash_password DEFAULT_ADMIN_PASSWORD, salt
    now  = os.time!
    box.space._tdb_users\insert { u.id, u.username, u.email, hash, salt, now, now }
    R.eq auth.get_user_by_id(u.id).must_change_password, false, 'flag absent before migration'
    flagged = spaces_mod.migrate_must_change_password!
    R.ok flagged >= 1, 'migration flagged the simulated account'
    R.eq auth.get_user_by_id(u.id).must_change_password, true

R.describe "password policy — enforcement active", ->
  R.after_all ->
    utils.set_password_enforcement nil

  R.it "un compte à drapeau vrai est refusé sauf me/changePassword/logout", ->
    u    = make_user 'enforce', DEFAULT_ADMIN_PASSWORD
    sess = auth.create_session u.id
    ctx  = { user_id: u.id, token: sess.token, must_change_password: true }
    utils.set_password_enforcement true

    R.ok has_error(run('{ spaces { id } }', ctx), 'PASSWORD_CHANGE_REQUIRED'), 'typed query refused'
    R.ok has_error(run('mutation { createSpace(input: {name: "s2_forbidden"}) { id } }', ctx),
      'PASSWORD_CHANGE_REQUIRED'), 'schema mutation refused'
    R.ok has_error(run('{ listApps { appId } }', ctx), 'PASSWORD_CHANGE_REQUIRED'), 'listApps refused'

    me_res = run '{ me { id username } }', ctx
    R.nok has_error(me_res, 'PASSWORD_CHANGE_REQUIRED'), 'me reachable'
    R.ok me_res.data and me_res.data.me, 'me returns the user'

    logout_res = run 'mutation { logout }', ctx
    R.nok has_error(logout_res, 'PASSWORD_CHANGE_REQUIRED'), 'logout reachable'

    chg = run 'mutation { changePassword(currentPassword: "adminadmin", newPassword: "brandnew123") }', ctx
    R.nok has_error(chg, 'PASSWORD_CHANGE_REQUIRED'), 'changePassword reachable'
    R.eq chg.data.changePassword, true
    R.eq auth.get_user_by_id(u.id).must_change_password, false, 'flag cleared by changePassword'

    fresh = { user_id: u.id, must_change_password: auth.get_user_by_id(u.id).must_change_password }
    R.eq utils.require_auth(fresh), u.id, 'gate lifted after change'
    R.nok has_error(run('{ spaces { id } }', fresh), 'PASSWORD_CHANGE_REQUIRED'), 'query passes after change'

    utils.set_password_enforcement nil

  R.it "un contexte de confiance n'est jamais refusé", ->
    u = make_user 'trusted', DEFAULT_ADMIN_PASSWORD
    utils.set_password_enforcement true
    ctx = { user_id: u.id, trusted: true, must_change_password: true }
    R.eq utils.require_auth(ctx), u.id, 'trusted context passes'
    R.nok has_error(run('{ spaces { id } }', ctx), 'PASSWORD_CHANGE_REQUIRED')
    utils.set_password_enforcement nil

  R.it "TGUI_TEST_ENV=true désactive l'application", ->
    u = make_user 'testenv', DEFAULT_ADMIN_PASSWORD
    -- No override is set here: the value comes from the environment.
    R.eq utils.password_change_enforced!, false, 'enforcement disabled in the test environment'
    ctx = { user_id: u.id, must_change_password: true }
    R.nok has_error(run('{ spaces { id } }', ctx), 'PASSWORD_CHANGE_REQUIRED')
