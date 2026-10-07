local R = require('tests.runner')
local auth = require('core.auth')
local LOGIN_MAX_ATTEMPTS, LOGIN_IP_MAX_ATTEMPTS, LOGIN_ATTEMPT_WINDOW, LOGIN_LOCKOUT_BASE_SECONDS, LOGIN_LOCKOUT_MAX_SECONDS, LOGIN_ATTEMPTS_TTL
do
  local _obj_0 = require('core.config')
  LOGIN_MAX_ATTEMPTS, LOGIN_IP_MAX_ATTEMPTS, LOGIN_ATTEMPT_WINDOW, LOGIN_LOCKOUT_BASE_SECONDS, LOGIN_LOCKOUT_MAX_SECONDS, LOGIN_ATTEMPTS_TTL = _obj_0.LOGIN_MAX_ATTEMPTS, _obj_0.LOGIN_IP_MAX_ATTEMPTS, _obj_0.LOGIN_ATTEMPT_WINDOW, _obj_0.LOGIN_LOCKOUT_BASE_SECONDS, _obj_0.LOGIN_LOCKOUT_MAX_SECONDS, _obj_0.LOGIN_ATTEMPTS_TTL
end
local SUFFIX = tostring(math.random(100000, 999999))
local PASS = 'pass1234'
local TOO_MANY = 'Too many failed attempts, please try again later'
local BAD_CREDS = 'Invalid username or password'
local created_usernames = { }
local create_test_user
create_test_user = function(tag)
  local uname = "rl_" .. tostring(tag) .. "_" .. tostring(SUFFIX)
  local user = auth.create_user(uname, tostring(uname) .. "@test.local", PASS)
  table.insert(created_usernames, uname)
  return user
end
local attempt
attempt = function(key)
  return box.space._tdb_login_attempts:get(key)
end
local expire_attempt
expire_attempt = function(key)
  local t = attempt(key)
  local now = os.time()
  return box.space._tdb_login_attempts:replace({
    t[1],
    0,
    now - 1,
    now - 1,
    t[5]
  })
end
local fail_n
fail_n = function(username, n, addr)
  for _ = 1, n do
    auth.login(username, 'wrong-password', addr)
  end
end
return R.describe("Login rate-limiting (persistent)", function()
  R.after_all(function()
    local _list_0 = box.space._tdb_login_attempts:select({ })
    for _index_0 = 1, #_list_0 do
      local t = _list_0[_index_0]
      local key = tostring(t[1])
      if key:find(SUFFIX, 1, true) or key:sub(1, 3) == 'ip:' then
        box.space._tdb_login_attempts:delete(t[1])
      end
    end
    for _index_0 = 1, #created_usernames do
      local uname = created_usernames[_index_0]
      local u = auth.get_user_by_username(uname)
      if u then
        box.space._tdb_users:delete(u.id)
      end
    end
  end)
  R.it("verrouille après MAX_ATTEMPTS échecs", function()
    local user = create_test_user('lock')
    local key = auth.login_key(user.username)
    fail_n(user.username, LOGIN_MAX_ATTEMPTS - 1)
    local entry = attempt(key)
    R.ok(entry, 'entry created in the space')
    local locked = entry and entry[4] > os.time()
    R.nok(locked, 'not locked before MAX_ATTEMPTS')
    local s, e = auth.login(user.username, 'wrong-password')
    R.eq(s, nil)
    R.eq(e, BAD_CREDS)
    entry = attempt(key)
    R.ok(entry[4] > os.time(), 'locked after MAX_ATTEMPTS')
    return R.eq(entry[4] - entry[3], LOGIN_LOCKOUT_BASE_SECONDS, 'first delay is the base')
  end)
  R.it("utilisateur légitime refusé pendant le verrouillage", function()
    local user = create_test_user('victim')
    fail_n(user.username, LOGIN_MAX_ATTEMPTS)
    local s, e = auth.login(user.username, PASS)
    R.eq(s, nil)
    return R.eq(e, TOO_MANY)
  end)
  R.it("utilisateur inconnu et mot de passe faux : message identique", function()
    local user = create_test_user('known')
    local ghost = "ghost_" .. tostring(SUFFIX)
    local s1, e1 = auth.login(ghost, 'anything')
    local s2, e2 = auth.login(user.username, 'wrong-password')
    R.eq(s1, nil)
    R.eq(s2, nil)
    R.eq(e1, BAD_CREDS)
    R.eq(e2, e1, 'no observable difference between the two cases')
    fail_n(ghost, LOGIN_MAX_ATTEMPTS)
    local s3, e3 = auth.login(ghost, 'anything')
    return R.eq(e3, TOO_MANY)
  end)
  R.it("le délai double à chaque cycle (60, 120, 240)", function()
    local uname = "exp_" .. tostring(SUFFIX)
    local key = auth.login_key(uname)
    fail_n(uname, LOGIN_MAX_ATTEMPTS)
    local t1 = attempt(key)
    R.eq(t1[4] - t1[3], LOGIN_LOCKOUT_BASE_SECONDS)
    expire_attempt(key)
    fail_n(uname, LOGIN_MAX_ATTEMPTS)
    local t2 = attempt(key)
    R.eq(t2[4] - t2[3], LOGIN_LOCKOUT_BASE_SECONDS * 2)
    expire_attempt(key)
    fail_n(uname, LOGIN_MAX_ATTEMPTS)
    local t3 = attempt(key)
    return R.eq(t3[4] - t3[3], LOGIN_LOCKOUT_BASE_SECONDS * 4)
  end)
  R.it("le délai est plafonné", function()
    local uname = "cap_" .. tostring(SUFFIX)
    local key = auth.login_key(uname)
    local now = os.time()
    box.space._tdb_login_attempts:insert({
      key,
      0,
      now - 1,
      now - 1,
      10
    })
    fail_n(uname, LOGIN_MAX_ATTEMPTS)
    local t = attempt(key)
    return R.eq(t[4] - t[3], LOGIN_LOCKOUT_MAX_SECONDS)
  end)
  R.it("une connexion réussie remet les compteurs à zéro", function()
    local user = create_test_user('reset')
    local key = auth.login_key(user.username)
    fail_n(user.username, 3)
    R.ok(attempt(key), 'failures recorded')
    local s, e = auth.login(user.username, PASS)
    R.ok(s, 'successful login')
    R.is_nil(attempt(key), 'counter removed after success')
    if s then
      return auth.delete_session(s.token)
    end
  end)
  R.it("après une période sans échec, le compteur retombe", function()
    local uname = "quiet_" .. tostring(SUFFIX)
    local key = auth.login_key(uname)
    fail_n(uname, 3)
    local t = attempt(key)
    local now = os.time()
    box.space._tdb_login_attempts:replace({
      key,
      t[2],
      now - LOGIN_ATTEMPT_WINDOW - 10,
      0,
      t[5]
    })
    auth.login(uname, 'wrong-password')
    local t2 = attempt(key)
    return R.eq(t2[2], 1, 'counter reset then incremented once')
  end)
  R.it("persiste à travers un rechargement du module", function()
    local uname = "persist_" .. tostring(SUFFIX)
    local key = auth.login_key(uname)
    fail_n(uname, LOGIN_MAX_ATTEMPTS)
    package.loaded['core.auth'] = nil
    local auth2 = require('core.auth')
    package.loaded['core.auth'] = auth
    local s, e = auth2.login(uname, 'wrong-password')
    R.eq(s, nil)
    R.eq(e, TOO_MANY)
    return R.ok(attempt(key), 'state still present in the space')
  end)
  R.it("purge les entrées anciennes", function()
    local stale_key = "user:stale_" .. tostring(SUFFIX)
    local now = os.time()
    box.space._tdb_login_attempts:insert({
      stale_key,
      3,
      now - LOGIN_ATTEMPTS_TTL - 100,
      0,
      1
    })
    auth.login("purgetrigger_" .. tostring(SUFFIX), 'wrong-password')
    return R.is_nil(box.space._tdb_login_attempts:get(stale_key), 'stale entry removed')
  end)
  R.it("l'adresse du client crée une seconde clé", function()
    local addr = '203.0.113.9'
    local uname = "ipkey_" .. tostring(SUFFIX)
    auth.login(uname, 'wrong-password', addr)
    return R.ok(box.space._tdb_login_attempts:get(auth.login_ip_key(addr)), 'ip key recorded')
  end)
  R.it("5 échecs IP (noms différents) ne bloquent pas l'adresse", function()
    local user = create_test_user('ipallow')
    local addr = '203.0.113.7'
    for i = 1, LOGIN_MAX_ATTEMPTS do
      auth.login("ipn_" .. tostring(i) .. "_" .. tostring(SUFFIX), 'wrong-password', addr)
    end
    local ip = box.space._tdb_login_attempts:get(auth.login_ip_key(addr))
    R.eq(ip[2], LOGIN_MAX_ATTEMPTS, 'address counter accumulated')
    R.nok(ip[4] > os.time(), 'address not locked below its own threshold')
    local s, e = auth.login(user.username, PASS, addr)
    R.ok(s, 'legitimate user still logs in from that address')
    if s then
      return auth.delete_session(s.token)
    end
  end)
  R.it("25 échecs IP bloquent l'adresse", function()
    local addr = '203.0.113.8'
    for i = 1, LOGIN_IP_MAX_ATTEMPTS do
      auth.login("ipb_" .. tostring(i) .. "_" .. tostring(SUFFIX), 'wrong-password', addr)
    end
    local user = create_test_user('ipblock')
    local s, e = auth.login(user.username, PASS, addr)
    R.eq(s, nil)
    return R.eq(e, TOO_MANY)
  end)
  return R.it("5 échecs du même compte depuis des adresses différentes bloquent le compte", function()
    local user = create_test_user('acctlock')
    for i = 1, LOGIN_MAX_ATTEMPTS do
      auth.login(user.username, 'wrong-password', "198.51.100." .. tostring(i))
    end
    local s, e = auth.login(user.username, PASS)
    R.eq(s, nil)
    return R.eq(e, TOO_MANY, 'account locked regardless of the address')
  end)
end)
