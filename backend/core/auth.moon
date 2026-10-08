-- core/auth.moon
-- Authentication: hashing, sessions, user management.

digest   = require 'digest'
uuid_mod = require 'uuid'
log      = require 'log'
{ :SESSION_TTL, :TOKEN_LENGTH,
  :LOGIN_MAX_ATTEMPTS, :LOGIN_IP_MAX_ATTEMPTS, :LOGIN_ATTEMPT_WINDOW,
  :LOGIN_LOCKOUT_BASE_SECONDS, :LOGIN_LOCKOUT_MAX_SECONDS,
  :LOGIN_ATTEMPTS_TTL, :DEFAULT_ADMIN_PASSWORD } = require 'core.config'

-- ────────────────────────────────────────────────────────────────────────────
-- Password hashing (PBKDF2-HMAC-SHA256, 100 000 iterations)
-- ────────────────────────────────────────────────────────────────────────────

PBKDF2_ITERATIONS = 100000
PBKDF2_KEY_LEN    = 32
MIN_PASSWORD_LEN  = 8

gen_salt = ->
  digest.base64_encode digest.urandom 32

hash_password = (password, salt) ->
  raw = digest.pbkdf2 password, salt, PBKDF2_ITERATIONS, PBKDF2_KEY_LEN
  "pbkdf2:" .. digest.base64_encode raw, { nowrap: true }

-- Legacy SHA-256 hash (migration only — do not use for new passwords)
hash_password_legacy = (password, salt) ->
  digest.sha256_hex password .. salt

verify_password = (password, salt, stored_hash) ->
  if stored_hash and stored_hash\sub(1, 7) == 'pbkdf2:'
    hash_password(password, salt) == stored_hash
  else
    hash_password_legacy(password, salt) == stored_hash

check_password_length = (password) ->
  error "Password must be at least #{MIN_PASSWORD_LEN} characters" if #password < MIN_PASSWORD_LEN

-- Whether a freshly set plaintext is still the public default password. Used to
-- compute the must_change_password flag on every password write so the flag
-- clears automatically once the password actually changes (spec §7 / audit 1.4).
must_change_password_for = (password) ->
  password == DEFAULT_ADMIN_PASSWORD

-- ────────────────────────────────────────────────────────────────────────────
-- User management
-- ────────────────────────────────────────────────────────────────────────────

create_user = (username, email, password) ->
  check_password_length password
  now  = os.time!
  uid  = tostring uuid_mod.new!
  salt = gen_salt!
  hash = hash_password password, salt
  must = must_change_password_for password
  box.space._tdb_users\insert { uid, username, email, hash, salt, now, now, must }
  { id: uid, username: username, email: email, createdAt: now, must_change_password: must }

-- Convert a _tdb_users tuple to the public user shape (no password material).
user_from_tuple = (t) ->
  { id: t[1], username: t[2], email: t[3], createdAt: t[6],
    must_change_password: t[8] == true }

get_user_by_username = (username) ->
  t = box.space._tdb_users.index.by_username\get { username }
  return nil unless t
  { id: t[1], username: t[2], email: t[3], password_hash: t[4], salt: t[5],
    createdAt: t[6], must_change_password: t[8] == true }

get_user_by_id = (id) ->
  t = box.space._tdb_users\get id
  return nil unless t
  user_from_tuple t

-- ────────────────────────────────────────────────────────────────────────────
-- Sessions
-- ────────────────────────────────────────────────────────────────────────────

gen_token = ->
  digest.base64_encode (digest.urandom TOKEN_LENGTH), { nowrap: true }

create_session = (user_id) ->
  now     = os.time!
  expires = now + SESSION_TTL
  token   = gen_token!
  box.space._tdb_sessions\insert { token, user_id, now, expires }
  { token: token, user_id: user_id, expires_at: expires }

validate_session = (token) ->
  t = box.space._tdb_sessions\get token
  return nil unless t
  expires = t[4]
  if os.time! > expires
    box.space._tdb_sessions\delete token
    return nil
  { token: t[1], user_id: t[2], created_at: t[3], expires_at: t[4] }

delete_session = (token) ->
  box.space._tdb_sessions\delete token

-- Purge expired sessions (call periodically)
purge_expired_sessions = ->
  now = os.time!
  expired = {}
  for t in *box.space._tdb_sessions\select {}
    if t[4] < now then table.insert expired, t[1]
  for token in *expired
    box.space._tdb_sessions\delete token
  #expired

-- ────────────────────────────────────────────────────────────────────────────
-- Login rate-limiting (persistent, per username and per client address)
-- State lives in the _tdb_login_attempts system space (memtx, so it is WAL/
-- snapshot persisted) instead of an in-memory table: a restart no longer
-- forgives accumulated failures.
-- ────────────────────────────────────────────────────────────────────────────

LOGIN_USER_PREFIX = 'user:'
LOGIN_IP_PREFIX   = 'ip:'

-- Normalize the username so that case variations share one counter. The
-- lookup of the actual user still uses the exact username (get_user_by_username).
login_key = (username) ->
  LOGIN_USER_PREFIX .. tostring(username or '')\lower!

login_ip_key = (client_addr) ->
  LOGIN_IP_PREFIX .. tostring client_addr

-- Keys whose counters must be consulted/updated for one login attempt. The
-- address is optional (nil when http.server does not expose it).
login_keys = (username, client_addr) ->
  keys = { login_key username }
  table.insert keys, login_ip_key client_addr if client_addr
  keys

-- An account and an address do NOT share the same threshold. A few wrong
-- passwords on one account must not lock every user that appears to come from
-- the same address: behind NAT or a reverse proxy `req.peer` is the relay's
-- address, and the project's own Playwright suite logs in as `admin` from the
-- same local relay while also sending a few invalid credentials. The address
-- threshold is therefore far higher (LOGIN_IP_MAX_ATTEMPTS); the lockout delay
-- itself stays identical (same base, same cap).
key_max_attempts = (key) ->
  if key and key\sub(1, #LOGIN_IP_PREFIX) == LOGIN_IP_PREFIX
    return LOGIN_IP_MAX_ATTEMPTS
  LOGIN_MAX_ATTEMPTS

read_attempt = (key) ->
  t = box.space._tdb_login_attempts\get key
  return nil unless t
  { key: t[1], failures: t[2], last_failure_at: t[3], locked_until: t[4], lock_count: t[5] }

new_attempt = (key) ->
  { key: key, failures: 0, last_failure_at: 0, locked_until: 0, lock_count: 0 }

write_attempt = (entry) ->
  box.space._tdb_login_attempts\replace {
    entry.key, entry.failures, entry.last_failure_at, entry.locked_until, entry.lock_count
  }

-- Forget the counters once a quiet period elapsed since the last activity
-- (a failure or the end of a lockout). Reset only happens when not currently
-- locked, so a long lockout does not erase its own escalation level.
reset_after_quiet = (entry, now) ->
  return if entry.locked_until > now
  quiet_since = math.max entry.last_failure_at, entry.locked_until
  if quiet_since > 0 and now - quiet_since > LOGIN_ATTEMPT_WINDOW
    entry.failures = 0
    entry.lock_count = 0
  entry

lockout_delay = (lock_count) ->
  delay = LOGIN_LOCKOUT_BASE_SECONDS * (2 ^ (lock_count - 1))
  if delay > LOGIN_LOCKOUT_MAX_SECONDS
    return LOGIN_LOCKOUT_MAX_SECONDS
  delay

-- Opportunistic bounded purge, run on every failure (no periodic fiber).
purge_login_attempts = ->
  now = os.time!
  stale = {}
  for t in *box.space._tdb_login_attempts\select {}
    quiet_since = math.max t[3], t[4]
    if quiet_since > 0 and now - quiet_since > LOGIN_ATTEMPTS_TTL and t[4] < now
      table.insert stale, t[1]
  for key in *stale
    box.space._tdb_login_attempts\delete key
  #stale

record_failed_attempt = (key) ->
  now   = os.time!
  entry = read_attempt(key) or new_attempt key
  reset_after_quiet entry, now
  entry.failures += 1
  entry.last_failure_at = now
  if entry.failures >= key_max_attempts key
    entry.lock_count += 1
    entry.locked_until = now + lockout_delay entry.lock_count
    entry.failures = 0
  write_attempt entry
  purge_login_attempts!
  entry.locked_until

clear_failed_attempts = (key) ->
  box.space._tdb_login_attempts\delete key
  true

is_locked_out = (key) ->
  entry = read_attempt key
  return false unless entry
  entry.locked_until > os.time!

-- ────────────────────────────────────────────────────────────────────────────
-- Login
-- ────────────────────────────────────────────────────────────────────────────

-- client_addr is optional; when provided (from http_server) the attempt also
-- updates a per-address counter. A wrong password and an unknown username take
-- exactly the same path, so nothing observable distinguishes them.
login = (username, password, client_addr) ->
  keys = login_keys username, client_addr
  for key in *keys
    if is_locked_out key
      return nil, 'Too many failed attempts, please try again later'
  user = get_user_by_username username
  if user and verify_password password, user.salt, user.password_hash
    for key in *keys
      clear_failed_attempts key
    -- Transparent upgrade: re-hash legacy SHA-256 passwords with PBKDF2
    if user.password_hash and user.password_hash\sub(1, 7) != 'pbkdf2:'
      new_salt = gen_salt!
      new_hash = hash_password password, new_salt
      now = os.time!
      t = box.space._tdb_users\get user.id
      if t
        box.space._tdb_users\replace {
          t[1], t[2], t[3], new_hash, new_salt, t[6], now,
          must_change_password_for password
        }
        log.info "tdb auth: upgraded password hash for user '#{username}' to PBKDF2"
    return create_session user.id
  for key in *keys
    record_failed_attempt key
  nil, 'Invalid username or password'

change_password = (user_id, current_password, new_password) ->
  check_password_length new_password
  t = box.space._tdb_users\get user_id
  error "User not found" unless t
  unless verify_password current_password, t[5], t[4]
    error 'Current password is incorrect'
  new_salt = gen_salt!
  new_hash = hash_password new_password, new_salt
  now = os.time!
  box.space._tdb_users\replace {
    t[1], t[2], t[3], new_hash, new_salt, t[6], now,
    must_change_password_for new_password
  }
  true

admin_set_password = (user_id, new_password) ->
  check_password_length new_password
  t = box.space._tdb_users\get user_id
  error "User not found" unless t
  new_salt = gen_salt!
  new_hash = hash_password new_password, new_salt
  now = os.time!
  box.space._tdb_users\replace {
    t[1], t[2], t[3], new_hash, new_salt, t[6], now,
    must_change_password_for new_password
  }
  true

{ :create_user, :get_user_by_username, :get_user_by_id, :user_from_tuple,
  :create_session, :validate_session, :delete_session, :purge_expired_sessions,
  :login, :hash_password, :gen_salt, :change_password, :admin_set_password,
  :verify_password, :must_change_password_for,
  :purge_login_attempts, :login_key, :login_ip_key, :MIN_PASSWORD_LEN }
