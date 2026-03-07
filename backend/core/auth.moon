-- core/auth.moon
-- Authentication: hashing, sessions, user management.

digest   = require 'digest'
uuid_mod = require 'uuid'
log      = require 'log'

SESSION_TTL = 24 * 3600  -- 24 hours in seconds

-- ────────────────────────────────────────────────────────────────────────────
-- Password hashing (SHA-256 + random salt, hex encoded)
-- ────────────────────────────────────────────────────────────────────────────

gen_salt = ->
  digest.base64_encode digest.urandom 32

hash_password = (password, salt) ->
  digest.sha256_hex password .. salt

verify_password = (password, salt, stored_hash) ->
  hash_password(password, salt) == stored_hash

-- ────────────────────────────────────────────────────────────────────────────
-- User management
-- ────────────────────────────────────────────────────────────────────────────

create_user = (username, email, password) ->
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
  digest.base64_encode (digest.urandom 32), { nowrap: true }

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
-- Login
-- ────────────────────────────────────────────────────────────────────────────

login = (username, password) ->
  user = get_user_by_username username
  unless user
    return nil, 'Invalid username or password'
  unless verify_password password, user.salt, user.password_hash
    return nil, 'Invalid username or password'
  create_session user.id

{ :create_user, :get_user_by_username, :get_user_by_id,
  :create_session, :validate_session, :delete_session, :purge_expired_sessions,
  :login, :hash_password, :gen_salt }
