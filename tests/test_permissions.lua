local R = require('tests.runner')
local auth = require('core.auth')
local require_auth, require_admin
do
  local _obj_0 = require('resolvers.utils')
  require_auth, require_admin = _obj_0.require_auth, _obj_0.require_admin
end
local spaces_mod = require('core.spaces')
local auth_r = require('resolvers.auth_resolvers')
local data_r = require('resolvers.data_resolvers')
local custom_view_r = require('resolvers.custom_view_resolvers')
local json = require('json')
local SUFFIX = tostring(math.random(100000, 999999))
R.describe("require_auth — blocage sans authentification", function()
  R.it("ctx nil → erreur Unauthorized", function()
    local ok, err = pcall(require_auth, nil)
    R.eq(ok, false)
    return R.ok(tostring(err):find('Unauthorized'))
  end)
  R.it("ctx sans user_id → erreur Unauthorized", function()
    local ok, err = pcall(require_auth, { })
    R.eq(ok, false)
    return R.ok(tostring(err):find('Unauthorized'))
  end)
  return R.it("ctx avec user_id → retourne l'id", function()
    local uid = require_auth({
      user_id = 'fake-uid'
    })
    return R.eq(uid, 'fake-uid')
  end)
end)
R.describe("require_admin — blocage non-admin", function()
  R.it("ctx nil → erreur Unauthorized (pas Forbidden)", function()
    local ok, err = pcall(require_admin, nil)
    R.eq(ok, false)
    return R.ok(tostring(err):find('Unauthorized'))
  end)
  R.it("user non-membre du groupe admin → erreur Forbidden", function()
    local ok_u, user = pcall(auth.create_user, "nonadmin_" .. tostring(SUFFIX), "nonadmin_" .. tostring(SUFFIX) .. "@test.local", "pass123")
    R.ok(ok_u)
    local sess = auth.create_session(user.id)
    local ctx = {
      user_id = user.id
    }
    local ok_a, err_a = pcall(require_admin, ctx)
    R.eq(ok_a, false)
    R.ok(tostring(err_a):find('Forbidden'))
    auth.delete_session(sess.token)
    return box.space._tdb_users:delete(user.id)
  end)
  return R.it("utilisateur admin → succès", function()
    local admin_user = auth.get_user_by_username('admin')
    R.ok(admin_user)
    local uid = require_admin({
      user_id = admin_user.id
    })
    return R.eq(uid, admin_user.id)
  end)
end)
R.describe("Sessions — création, validation, expiration", function()
  local token, uid
  R.it("create_session retourne un token", function()
    local user = auth.get_user_by_username('admin')
    R.ok(user)
    uid = user.id
    local sess = auth.create_session(uid)
    R.ok(sess)
    R.ok(sess.token)
    R.ok(#sess.token > 10)
    token = sess.token
  end)
  R.it("validate_session retourne la session valide", function()
    local sess = auth.validate_session(token)
    R.ok(sess)
    R.eq(sess.user_id, uid)
    return R.ok(sess.expires_at > os.time())
  end)
  R.it("delete_session invalide le token", function()
    auth.delete_session(token)
    local sess = auth.validate_session(token)
    return R.eq(sess, nil)
  end)
  return R.it("token inexistant → validate_session retourne nil", function()
    local sess = auth.validate_session('tok-that-does-not-exist')
    return R.eq(sess, nil)
  end)
end)
R.describe("Sessions — purge des expirées", function()
  R.it("purge_expired_sessions retourne le nombre de sessions supprimées", function()
    local fake_token = "expired_test_" .. tostring(SUFFIX)
    box.space._tdb_sessions:insert({
      fake_token,
      'fake-user',
      os.time() - 7200,
      os.time() - 3600
    })
    local sess = auth.validate_session(fake_token)
    R.eq(sess, nil)
    local t = box.space._tdb_sessions:get(fake_token)
    return R.eq(t, nil)
  end)
  return R.it("purge_expired_sessions ne supprime pas les sessions valides", function()
    local admin = auth.get_user_by_username('admin')
    local sess = auth.create_session(admin.id)
    local n = auth.purge_expired_sessions()
    local still_valid = auth.validate_session(sess.token)
    R.ok(still_valid)
    return auth.delete_session(sess.token)
  end)
end)
R.describe("GraphQL resolver auth policy — admin queries", function()
  R.it("Query.users refuse un utilisateur non-admin", function()
    local ok_u, user = pcall(auth.create_user, "policy_nonadmin_" .. tostring(SUFFIX), "policy_nonadmin_" .. tostring(SUFFIX) .. "@test.local", "pass123")
    R.ok(ok_u)
    local ctx = {
      user_id = user.id
    }
    local ok_q, err_q = pcall(auth_r.Query.users, nil, { }, ctx)
    R.eq(ok_q, false)
    R.ok(tostring(err_q):find('Forbidden'))
    return box.space._tdb_users:delete(user.id)
  end)
  return R.it("Query.users accepte un admin", function()
    local admin_user = auth.get_user_by_username('admin')
    local res = auth_r.Query.users(nil, { }, {
      user_id = admin_user.id
    })
    return R.ok(type(res) == 'table')
  end)
end)
return R.describe("GraphQL resolver auth policy — data/custom views", function()
  R.it("Query.record refuse ctx nil", function()
    local ok_q, err_q = pcall(data_r.Query.record, nil, {
      spaceId = 'any',
      id = 'any'
    }, nil)
    R.eq(ok_q, false)
    return R.ok(tostring(err_q):find('Unauthorized'))
  end)
  R.it("Query.record accepte un utilisateur authentifié", function()
    local admin_user = auth.get_user_by_username('admin')
    local sp_name = "policy_record_" .. tostring(SUFFIX)
    local sp = spaces_mod.create_user_space(sp_name, "policy record test")
    box.space["data_" .. tostring(sp_name)]:insert({
      "row1",
      json.encode({
        nom = "ok"
      })
    })
    local rec = data_r.Query.record(nil, {
      spaceId = sp.id,
      id = 'row1'
    }, {
      user_id = admin_user.id
    })
    R.ok(rec)
    R.eq(rec.id, 'row1')
    return spaces_mod.delete_user_space(sp_name)
  end)
  return R.it("customViews refuse ctx nil", function()
    local ok_q, err_q = pcall(custom_view_r.Query.customViews, nil, { }, nil)
    R.eq(ok_q, false)
    return R.ok(tostring(err_q):find('Unauthorized'))
  end)
end)
