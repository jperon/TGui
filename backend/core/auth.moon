-- core/auth.moon
-- Authentication: hashing, sessions, user management.

digest   = require 'digest'
uuid_mod = require 'uuid'
log      = require 'log'
{ :SESSION_TTL, :TOKEN_LENGTH } = require 'core.config'

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

-- ────────────────────────────────────────────────────────────────────────────
-- User management
-- ────────────────────────────────────────────────────────────────────────────

create_user = (username, email, password) ->
  check_password_length password
  now  = os.time!
  uid  = tostring uuid_mod.new!
  salt = gen_salt!
  hash = hash_password password, salt
  box.space._tdb_users\insert { uid, username, email, hash, salt, now, now }
  { id: uid, username: username, email: email, createdAt: now }

get_user_by_username = (username) ->
  t = box.space._tdb_users.index.by_username\get { username }
  return nil unless t
  { id: t[1], username: t[2], email: t[3], password_hash: t[4], salt: t[5], createdAt: t[6] }

get_user_by_id = (id) ->
  t = box.space._tdb_users\get id
  return nil unless t
  { id: t[1], username: t[2], email: t[3], createdAt: t[6] }

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
-- Login rate-limiting (in-memory, per username)
-- ────────────────────────────────────────────────────────────────────────────

_login_attempts  = {}
MAX_ATTEMPTS     = 5    -- allowed failures within the window
LOCKOUT_SECONDS  = 60   -- cooldown after exceeding MAX_ATTEMPTS
ATTEMPT_WINDOW   = 300  -- sliding window in seconds (5 min)

record_failed_attempt = (username) ->
  now = os.time!
  _login_attempts[username] or= { attempts: {}, locked_until: 0 }
  entry = _login_attempts[username]
  table.insert entry.attempts, now
  entry.attempts = [t for t in *entry.attempts when now - t < ATTEMPT_WINDOW]
  if #entry.attempts >= MAX_ATTEMPTS
    entry.locked_until = now + LOCKOUT_SECONDS

clear_failed_attempts = (username) ->
  _login_attempts[username] = nil

is_locked_out = (username) ->
  entry = _login_attempts[username]
  return false unless entry
  now = os.time!
  if entry.locked_until > now
    return true
  if entry.locked_until > 0 and entry.locked_until <= now
    _login_attempts[username] = nil
  false

purge_login_attempts = ->
  now = os.time!
  stale = {}
  for username, entry in pairs _login_attempts
    latest = entry.attempts[#entry.attempts]
    if not latest or (latest + ATTEMPT_WINDOW < now)
      table.insert stale, username
  for username in *stale
    _login_attempts[username] = nil
  #stale

-- ────────────────────────────────────────────────────────────────────────────
-- Login
-- ────────────────────────────────────────────────────────────────────────────

login = (username, password) ->
  if is_locked_out username
    return nil, 'Too many failed attempts, please try again later'
  user = get_user_by_username username
  unless user
    record_failed_attempt username
    return nil, 'Invalid username or password'
  unless verify_password password, user.salt, user.password_hash
    record_failed_attempt username
    return nil, 'Invalid username or password'
  -- Transparent upgrade: re-hash legacy SHA-256 passwords with PBKDF2
  if user.password_hash and user.password_hash\sub(1, 7) != 'pbkdf2:'
    new_salt = gen_salt!
    new_hash = hash_password password, new_salt
    now = os.time!
    t = box.space._tdb_users\get user.id
    if t
      box.space._tdb_users\replace { t[1], t[2], t[3], new_hash, new_salt, t[6], now }
      log.info "tdb auth: upgraded password hash for user '#{username}' to PBKDF2"
  clear_failed_attempts username
  create_session user.id

change_password = (user_id, current_password, new_password) ->
  check_password_length new_password
  t = box.space._tdb_users\get user_id
  error "User not found" unless t
  unless verify_password current_password, t[5], t[4]
    error 'Current password is incorrect'
  new_salt = gen_salt!
  new_hash = hash_password new_password, new_salt
  now = os.time!
  box.space._tdb_users\replace { t[1], t[2], t[3], new_hash, new_salt, t[6], now }
  true

admin_set_password = (user_id, new_password) ->
  check_password_length new_password
  t = box.space._tdb_users\get user_id
  error "User not found" unless t
  new_salt = gen_salt!
  new_hash = hash_password new_password, new_salt
  now = os.time!
  box.space._tdb_users\replace { t[1], t[2], t[3], new_hash, new_salt, t[6], now }
  true

{ :create_user, :get_user_by_username, :get_user_by_id,
  :create_session, :validate_session, :delete_session, :purge_expired_sessions,
  :login, :hash_password, :gen_salt, :change_password, :admin_set_password,
  :purge_login_attempts, :MIN_PASSWORD_LEN }
