-- tests/test_auth_ratelimit.moon
-- Persistent login rate-limiting (spec §7 / audit 1.2):
-- lockout after N failures, exponential backoff, identical handling of unknown
-- username and wrong password, reset on success / quiet period, bounded purge
-- and persistence through a module reload.
--
-- The account key and the client-address key have SEPARATE thresholds: the
-- address of a client is often a shared relay (NAT, reverse proxy) — behind a
-- proxy it is the proxy's own address — and the project's Playwright suite
-- itself logs in as `admin` from the same local relay while sending a few
-- invalid credentials. A handful of account failures must therefore not lock
-- everyone sharing an address: LOGIN_IP_MAX_ATTEMPTS is much larger than
-- LOGIN_MAX_ATTEMPTS and only the address reaching its own threshold locks it.

R    = require 'tests.runner'
auth = require 'core.auth'
{ :LOGIN_MAX_ATTEMPTS, :LOGIN_IP_MAX_ATTEMPTS, :LOGIN_ATTEMPT_WINDOW,
  :LOGIN_LOCKOUT_BASE_SECONDS, :LOGIN_LOCKOUT_MAX_SECONDS,
  :LOGIN_ATTEMPTS_TTL } = require 'core.config'

SUFFIX = tostring math.random 100000, 999999
PASS   = 'pass1234'
TOO_MANY = 'Too many failed attempts, please try again later'
BAD_CREDS = 'Invalid username or password'

created_usernames = {}

create_test_user = (tag) ->
  uname = "rl_#{tag}_#{SUFFIX}"
  user  = auth.create_user uname, "#{uname}@test.local", PASS
  table.insert created_usernames, uname
  user

attempt = (key) ->
  box.space._tdb_login_attempts\get key

-- Simulate the end of a lockout without waiting: the entry expires but its
-- escalation level (lock_count) is kept so the next cycle doubles the delay.
expire_attempt = (key) ->
  t   = attempt key
  now = os.time!
  box.space._tdb_login_attempts\replace { t[1], 0, now - 1, now - 1, t[5] }

fail_n = (username, n, addr) ->
  for _ = 1, n
    auth.login username, 'wrong-password', addr

R.describe "Login rate-limiting (persistent)", ->
  R.after_all ->
    for t in *box.space._tdb_login_attempts\select {}
      key = tostring t[1]
      if key\find(SUFFIX, 1, true) or key\sub(1, 3) == 'ip:'
        box.space._tdb_login_attempts\delete t[1]
    for uname in *created_usernames
      u = auth.get_user_by_username uname
      box.space._tdb_users\delete u.id if u

  R.it "verrouille après MAX_ATTEMPTS échecs", ->
    user = create_test_user 'lock'
    key  = auth.login_key user.username
    -- The first MAX_ATTEMPTS-1 failures must not lock yet
    fail_n user.username, LOGIN_MAX_ATTEMPTS - 1
    entry = attempt key
    R.ok entry, 'entry created in the space'
    locked = entry and entry[4] > os.time!
    R.nok locked, 'not locked before MAX_ATTEMPTS'
    -- The MAX_ATTEMPTS-th failure triggers the lockout
    s, e = auth.login user.username, 'wrong-password'
    R.eq s, nil
    R.eq e, BAD_CREDS
    entry = attempt key
    R.ok entry[4] > os.time!, 'locked after MAX_ATTEMPTS'
    R.eq entry[4] - entry[3], LOGIN_LOCKOUT_BASE_SECONDS, 'first delay is the base'

  R.it "utilisateur légitime refusé pendant le verrouillage", ->
    user = create_test_user 'victim'
    fail_n user.username, LOGIN_MAX_ATTEMPTS
    -- Correct password is still refused while locked (documented behaviour)
    s, e = auth.login user.username, PASS
    R.eq s, nil
    R.eq e, TOO_MANY

  R.it "utilisateur inconnu et mot de passe faux : message identique", ->
    user = create_test_user 'known'
    ghost = "ghost_#{SUFFIX}"
    s1, e1 = auth.login ghost, 'anything'
    s2, e2 = auth.login user.username, 'wrong-password'
    R.eq s1, nil
    R.eq s2, nil
    R.eq e1, BAD_CREDS
    R.eq e2, e1, 'no observable difference between the two cases'
    -- The unknown username is limited exactly like a real one
    fail_n ghost, LOGIN_MAX_ATTEMPTS
    s3, e3 = auth.login ghost, 'anything'
    R.eq e3, TOO_MANY

  R.it "le délai double à chaque cycle (60, 120, 240)", ->
    uname = "exp_#{SUFFIX}"
    key   = auth.login_key uname
    fail_n uname, LOGIN_MAX_ATTEMPTS
    t1 = attempt key
    R.eq t1[4] - t1[3], LOGIN_LOCKOUT_BASE_SECONDS
    expire_attempt key
    fail_n uname, LOGIN_MAX_ATTEMPTS
    t2 = attempt key
    R.eq t2[4] - t2[3], LOGIN_LOCKOUT_BASE_SECONDS * 2
    expire_attempt key
    fail_n uname, LOGIN_MAX_ATTEMPTS
    t3 = attempt key
    R.eq t3[4] - t3[3], LOGIN_LOCKOUT_BASE_SECONDS * 4

  R.it "le délai est plafonné", ->
    uname = "cap_#{SUFFIX}"
    key   = auth.login_key uname
    now   = os.time!
    box.space._tdb_login_attempts\insert { key, 0, now - 1, now - 1, 10 }
    fail_n uname, LOGIN_MAX_ATTEMPTS
    t = attempt key
    R.eq t[4] - t[3], LOGIN_LOCKOUT_MAX_SECONDS

  R.it "une connexion réussie remet les compteurs à zéro", ->
    user = create_test_user 'reset'
    key  = auth.login_key user.username
    fail_n user.username, 3
    R.ok attempt(key), 'failures recorded'
    s, e = auth.login user.username, PASS
    R.ok s, 'successful login'
    R.is_nil attempt(key), 'counter removed after success'
    auth.delete_session s.token if s

  R.it "après une période sans échec, le compteur retombe", ->
    uname = "quiet_#{SUFFIX}"
    key   = auth.login_key uname
    fail_n uname, 3
    t = attempt key
    now = os.time!
    box.space._tdb_login_attempts\replace {
      key, t[2], now - LOGIN_ATTEMPT_WINDOW - 10, 0, t[5]
    }
    auth.login uname, 'wrong-password'
    t2 = attempt key
    R.eq t2[2], 1, 'counter reset then incremented once'

  R.it "persiste à travers un rechargement du module", ->
    uname = "persist_#{SUFFIX}"
    key   = auth.login_key uname
    fail_n uname, LOGIN_MAX_ATTEMPTS
    -- Drop the module cache: a brand new instance must read the same space
    package.loaded['core.auth'] = nil
    auth2 = require 'core.auth'
    package.loaded['core.auth'] = auth
    s, e = auth2.login uname, 'wrong-password'
    R.eq s, nil
    R.eq e, TOO_MANY
    R.ok attempt(key), 'state still present in the space'

  R.it "purge les entrées anciennes", ->
    stale_key = "user:stale_#{SUFFIX}"
    now       = os.time!
    box.space._tdb_login_attempts\insert {
      stale_key, 3, now - LOGIN_ATTEMPTS_TTL - 100, 0, 1
    }
    -- Any failure triggers the opportunistic purge
    auth.login "purgetrigger_#{SUFFIX}", 'wrong-password'
    R.is_nil box.space._tdb_login_attempts\get(stale_key), 'stale entry removed'

  R.it "l'adresse du client crée une seconde clé", ->
    addr  = '203.0.113.9'
    uname = "ipkey_#{SUFFIX}"
    auth.login uname, 'wrong-password', addr
    R.ok box.space._tdb_login_attempts\get(auth.login_ip_key(addr)), 'ip key recorded'

  R.it "5 échecs IP (noms différents) ne bloquent pas l'adresse", ->
    user = create_test_user 'ipallow'
    addr = '203.0.113.7'
    -- MAX_ATTEMPTS failures on DIFFERENT usernames from the same address
    for i = 1, LOGIN_MAX_ATTEMPTS
      auth.login "ipn_#{i}_#{SUFFIX}", 'wrong-password', addr
    ip = box.space._tdb_login_attempts\get auth.login_ip_key(addr)
    R.eq ip[2], LOGIN_MAX_ATTEMPTS, 'address counter accumulated'
    R.nok ip[4] > os.time!, 'address not locked below its own threshold'
    -- A legitimate user still logs in from that (shared) address
    s, e = auth.login user.username, PASS, addr
    R.ok s, 'legitimate user still logs in from that address'
    auth.delete_session s.token if s

  R.it "25 échecs IP bloquent l'adresse", ->
    addr = '203.0.113.8'
    for i = 1, LOGIN_IP_MAX_ATTEMPTS
      auth.login "ipb_#{i}_#{SUFFIX}", 'wrong-password', addr
    user = create_test_user 'ipblock'
    -- Correct password is refused because the ADDRESS is locked
    s, e = auth.login user.username, PASS, addr
    R.eq s, nil
    R.eq e, TOO_MANY

  R.it "5 échecs du même compte depuis des adresses différentes bloquent le compte", ->
    user = create_test_user 'acctlock'
    for i = 1, LOGIN_MAX_ATTEMPTS
      auth.login user.username, 'wrong-password', "198.51.100.#{i}"
    s, e = auth.login user.username, PASS
    R.eq s, nil
    R.eq e, TOO_MANY, 'account locked regardless of the address'
