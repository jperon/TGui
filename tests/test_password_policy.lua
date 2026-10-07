local R = require('tests.runner')
local auth = require('core.auth')
local spaces_mod = require('core.spaces')
local utils = require('resolvers.utils')
local executor = require('graphql.executor')
local DEFAULT_ADMIN_PASSWORD
DEFAULT_ADMIN_PASSWORD = require('core.config').DEFAULT_ADMIN_PASSWORD
local trusted_ctx
trusted_ctx = utils.trusted_ctx
local SUFFIX = tostring(math.random(100000, 999999))
local NEWPASS = 'newpass123'
local created = { }
local make_user
make_user = function(tag, password)
  local uname = "pwd_" .. tostring(tag) .. "_" .. tostring(SUFFIX)
  local u = auth.create_user(uname, tostring(uname) .. "@test.local", password)
  table.insert(created, u.id)
  return u
end
local run
run = function(query, ctx)
  return executor.execute({
    query = query,
    context = ctx
  })
end
local has_error
has_error = function(res, needle)
  if not (res and res.errors) then
    return false
  end
  local _list_0 = res.errors
  for _index_0 = 1, #_list_0 do
    local e = _list_0[_index_0]
    if tostring(e.message):find(needle, 1, true) then
      return true
    end
  end
  return false
end
R.describe("password policy — flag computation", function()
  R.after_all(function()
    for _index_0 = 1, #created do
      local id = created[_index_0]
      box.space._tdb_users:delete(id)
    end
    return utils.set_password_enforcement(nil)
  end)
  R.it("l'amorçage de l'admin par défaut pose le drapeau", function()
    local admin = auth.get_user_by_username('admin')
    R.ok(admin, 'admin exists')
    return R.eq(admin.must_change_password, true)
  end)
  R.it("create_user avec le mot de passe par défaut -> drapeau vrai", function()
    local u = make_user('create_default', DEFAULT_ADMIN_PASSWORD)
    return R.eq(auth.get_user_by_id(u.id).must_change_password, true)
  end)
  R.it("create_user avec un autre mot de passe -> drapeau faux", function()
    local u = make_user('create_other', 'strongpass1')
    return R.eq(auth.get_user_by_id(u.id).must_change_password, false)
  end)
  R.it("changePassword réussi efface le drapeau", function()
    local u = make_user('change_ok', DEFAULT_ADMIN_PASSWORD)
    R.eq(auth.get_user_by_id(u.id).must_change_password, true)
    auth.change_password(u.id, DEFAULT_ADMIN_PASSWORD, NEWPASS)
    return R.eq(auth.get_user_by_id(u.id).must_change_password, false)
  end)
  R.it("changer pour le mot de passe par défaut repose le drapeau", function()
    local u = make_user('change_back', NEWPASS)
    R.eq(auth.get_user_by_id(u.id).must_change_password, false)
    auth.change_password(u.id, NEWPASS, DEFAULT_ADMIN_PASSWORD)
    return R.eq(auth.get_user_by_id(u.id).must_change_password, true)
  end)
  R.it("admin_set_password suit le mot de passe posé", function()
    local u = make_user('admin_set', 'strongpass2')
    auth.admin_set_password(u.id, DEFAULT_ADMIN_PASSWORD)
    R.eq(auth.get_user_by_id(u.id).must_change_password, true)
    auth.admin_set_password(u.id, 'strongpass3')
    return R.eq(auth.get_user_by_id(u.id).must_change_password, false)
  end)
  return R.it("la migration tdb_v4 pose le drapeau d'un compte au mot de passe par défaut", function()
    local u = make_user('migrate', 'strongpass4')
    box.space._tdb_users:delete(u.id)
    local salt = auth.gen_salt()
    local hash = auth.hash_password(DEFAULT_ADMIN_PASSWORD, salt)
    local now = os.time()
    box.space._tdb_users:insert({
      u.id,
      u.username,
      u.email,
      hash,
      salt,
      now,
      now
    })
    R.eq(auth.get_user_by_id(u.id).must_change_password, false, 'flag absent before migration')
    local flagged = spaces_mod.migrate_must_change_password()
    R.ok(flagged >= 1, 'migration flagged the simulated account')
    return R.eq(auth.get_user_by_id(u.id).must_change_password, true)
  end)
end)
return R.describe("password policy — enforcement active", function()
  R.after_all(function()
    return utils.set_password_enforcement(nil)
  end)
  R.it("un compte à drapeau vrai est refusé sauf me/changePassword/logout", function()
    local u = make_user('enforce', DEFAULT_ADMIN_PASSWORD)
    local sess = auth.create_session(u.id)
    local ctx = {
      user_id = u.id,
      token = sess.token,
      must_change_password = true
    }
    utils.set_password_enforcement(true)
    R.ok(has_error(run('{ spaces { id } }', ctx), 'PASSWORD_CHANGE_REQUIRED'), 'typed query refused')
    R.ok(has_error(run('mutation { createSpace(input: {name: "s2_forbidden"}) { id } }', ctx), 'PASSWORD_CHANGE_REQUIRED'), 'schema mutation refused')
    R.ok(has_error(run('{ listApps { appId } }', ctx), 'PASSWORD_CHANGE_REQUIRED'), 'listApps refused')
    local me_res = run('{ me { id username } }', ctx)
    R.nok(has_error(me_res, 'PASSWORD_CHANGE_REQUIRED'), 'me reachable')
    R.ok(me_res.data and me_res.data.me, 'me returns the user')
    local logout_res = run('mutation { logout }', ctx)
    R.nok(has_error(logout_res, 'PASSWORD_CHANGE_REQUIRED'), 'logout reachable')
    local chg = run('mutation { changePassword(currentPassword: "adminadmin", newPassword: "brandnew123") }', ctx)
    R.nok(has_error(chg, 'PASSWORD_CHANGE_REQUIRED'), 'changePassword reachable')
    R.eq(chg.data.changePassword, true)
    R.eq(auth.get_user_by_id(u.id).must_change_password, false, 'flag cleared by changePassword')
    local fresh = {
      user_id = u.id,
      must_change_password = auth.get_user_by_id(u.id).must_change_password
    }
    R.eq(utils.require_auth(fresh), u.id, 'gate lifted after change')
    R.nok(has_error(run('{ spaces { id } }', fresh), 'PASSWORD_CHANGE_REQUIRED'), 'query passes after change')
    return utils.set_password_enforcement(nil)
  end)
  R.it("un contexte de confiance n'est jamais refusé", function()
    local u = make_user('trusted', DEFAULT_ADMIN_PASSWORD)
    utils.set_password_enforcement(true)
    local ctx = {
      user_id = u.id,
      trusted = true,
      must_change_password = true
    }
    R.eq(utils.require_auth(ctx), u.id, 'trusted context passes')
    R.nok(has_error(run('{ spaces { id } }', ctx), 'PASSWORD_CHANGE_REQUIRED'))
    return utils.set_password_enforcement(nil)
  end)
  return R.it("TGUI_TEST_ENV=true désactive l'application", function()
    local u = make_user('testenv', DEFAULT_ADMIN_PASSWORD)
    R.eq(utils.password_change_enforced(), false, 'enforcement disabled in the test environment')
    local ctx = {
      user_id = u.id,
      must_change_password = true
    }
    return R.nok(has_error(run('{ spaces { id } }', ctx), 'PASSWORD_CHANGE_REQUIRED'))
  end)
end)
