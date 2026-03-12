local digest = require('digest')
local uuid_mod = require('uuid')
local log = require('log')
local SESSION_TTL, TOKEN_LENGTH
do
  local _obj_0 = require('core.config')
  SESSION_TTL, TOKEN_LENGTH = _obj_0.SESSION_TTL, _obj_0.TOKEN_LENGTH
end
local PBKDF2_ITERATIONS = 100000
local PBKDF2_KEY_LEN = 32
local MIN_PASSWORD_LEN = 8
local gen_salt
gen_salt = function()
  return digest.base64_encode(digest.urandom(32))
end
local hash_password
hash_password = function(password, salt)
  local raw = digest.pbkdf2(password, salt, PBKDF2_ITERATIONS, PBKDF2_KEY_LEN)
  return "pbkdf2:" .. digest.base64_encode(raw, {
    nowrap = true
  })
end
local hash_password_legacy
hash_password_legacy = function(password, salt)
  return digest.sha256_hex(password .. salt)
end
local verify_password
verify_password = function(password, salt, stored_hash)
  if stored_hash and stored_hash:sub(1, 7) == 'pbkdf2:' then
    return hash_password(password, salt) == stored_hash
  else
    return hash_password_legacy(password, salt) == stored_hash
  end
end
local check_password_length
check_password_length = function(password)
  if #password < MIN_PASSWORD_LEN then
    return error("Password must be at least " .. tostring(MIN_PASSWORD_LEN) .. " characters")
  end
end
local create_user
create_user = function(username, email, password)
  check_password_length(password)
  local now = os.time()
  local uid = tostring(uuid_mod.new())
  local salt = gen_salt()
  local hash = hash_password(password, salt)
  box.space._tdb_users:insert({
    uid,
    username,
    email,
    hash,
    salt,
    now,
    now
  })
  return {
    id = uid,
    username = username,
    email = email,
    createdAt = now
  }
end
local get_user_by_username
get_user_by_username = function(username)
  local t = box.space._tdb_users.index.by_username:get({
    username
  })
  if not (t) then
    return nil
  end
  return {
    id = t[1],
    username = t[2],
    email = t[3],
    password_hash = t[4],
    salt = t[5],
    createdAt = t[6]
  }
end
local get_user_by_id
get_user_by_id = function(id)
  local t = box.space._tdb_users:get(id)
  if not (t) then
    return nil
  end
  return {
    id = t[1],
    username = t[2],
    email = t[3],
    createdAt = t[6]
  }
end
local gen_token
gen_token = function()
  return digest.base64_encode((digest.urandom(TOKEN_LENGTH)), {
    nowrap = true
  })
end
local create_session
create_session = function(user_id)
  local now = os.time()
  local expires = now + SESSION_TTL
  local token = gen_token()
  box.space._tdb_sessions:insert({
    token,
    user_id,
    now,
    expires
  })
  return {
    token = token,
    user_id = user_id,
    expires_at = expires
  }
end
local validate_session
validate_session = function(token)
  local t = box.space._tdb_sessions:get(token)
  if not (t) then
    return nil
  end
  local expires = t[4]
  if os.time() > expires then
    box.space._tdb_sessions:delete(token)
    return nil
  end
  return {
    token = t[1],
    user_id = t[2],
    created_at = t[3],
    expires_at = t[4]
  }
end
local delete_session
delete_session = function(token)
  return box.space._tdb_sessions:delete(token)
end
local purge_expired_sessions
purge_expired_sessions = function()
  local now = os.time()
  local expired = { }
  local _list_0 = box.space._tdb_sessions:select({ })
  for _index_0 = 1, #_list_0 do
    local t = _list_0[_index_0]
    if t[4] < now then
      table.insert(expired, t[1])
    end
  end
  for _index_0 = 1, #expired do
    local token = expired[_index_0]
    box.space._tdb_sessions:delete(token)
  end
  return #expired
end
local _login_attempts = { }
local MAX_ATTEMPTS = 5
local LOCKOUT_SECONDS = 60
local ATTEMPT_WINDOW = 300
local record_failed_attempt
record_failed_attempt = function(username)
  local now = os.time()
  _login_attempts[username] = _login_attempts[username] or {
    attempts = { },
    locked_until = 0
  }
  local entry = _login_attempts[username]
  table.insert(entry.attempts, now)
  do
    local _accum_0 = { }
    local _len_0 = 1
    local _list_0 = entry.attempts
    for _index_0 = 1, #_list_0 do
      local t = _list_0[_index_0]
      if now - t < ATTEMPT_WINDOW then
        _accum_0[_len_0] = t
        _len_0 = _len_0 + 1
      end
    end
    entry.attempts = _accum_0
  end
  if #entry.attempts >= MAX_ATTEMPTS then
    entry.locked_until = now + LOCKOUT_SECONDS
  end
end
local clear_failed_attempts
clear_failed_attempts = function(username)
  _login_attempts[username] = nil
end
local is_locked_out
is_locked_out = function(username)
  local entry = _login_attempts[username]
  if not (entry) then
    return false
  end
  local now = os.time()
  if entry.locked_until > now then
    return true
  end
  if entry.locked_until > 0 and entry.locked_until <= now then
    _login_attempts[username] = nil
  end
  return false
end
local purge_login_attempts
purge_login_attempts = function()
  local now = os.time()
  local stale = { }
  for username, entry in pairs(_login_attempts) do
    local latest = entry.attempts[#entry.attempts]
    if not latest or (latest + ATTEMPT_WINDOW < now) then
      table.insert(stale, username)
    end
  end
  for _index_0 = 1, #stale do
    local username = stale[_index_0]
    _login_attempts[username] = nil
  end
  return #stale
end
local login
login = function(username, password)
  if is_locked_out(username) then
    return nil, 'Too many failed attempts, please try again later'
  end
  local user = get_user_by_username(username)
  if not (user) then
    record_failed_attempt(username)
    return nil, 'Invalid username or password'
  end
  if not (verify_password(password, user.salt, user.password_hash)) then
    record_failed_attempt(username)
    return nil, 'Invalid username or password'
  end
  if user.password_hash and user.password_hash:sub(1, 7) ~= 'pbkdf2:' then
    local new_salt = gen_salt()
    local new_hash = hash_password(password, new_salt)
    local now = os.time()
    local t = box.space._tdb_users:get(user.id)
    if t then
      box.space._tdb_users:replace({
        t[1],
        t[2],
        t[3],
        new_hash,
        new_salt,
        t[6],
        now
      })
      log.info("tdb auth: upgraded password hash for user '" .. tostring(username) .. "' to PBKDF2")
    end
  end
  clear_failed_attempts(username)
  return create_session(user.id)
end
local change_password
change_password = function(user_id, current_password, new_password)
  check_password_length(new_password)
  local t = box.space._tdb_users:get(user_id)
  if not (t) then
    error("User not found")
  end
  if not (verify_password(current_password, t[5], t[4])) then
    error('Current password is incorrect')
  end
  local new_salt = gen_salt()
  local new_hash = hash_password(new_password, new_salt)
  local now = os.time()
  box.space._tdb_users:replace({
    t[1],
    t[2],
    t[3],
    new_hash,
    new_salt,
    t[6],
    now
  })
  return true
end
local admin_set_password
admin_set_password = function(user_id, new_password)
  check_password_length(new_password)
  local t = box.space._tdb_users:get(user_id)
  if not (t) then
    error("User not found")
  end
  local new_salt = gen_salt()
  local new_hash = hash_password(new_password, new_salt)
  local now = os.time()
  box.space._tdb_users:replace({
    t[1],
    t[2],
    t[3],
    new_hash,
    new_salt,
    t[6],
    now
  })
  return true
end
return {
  create_user = create_user,
  get_user_by_username = get_user_by_username,
  get_user_by_id = get_user_by_id,
  create_session = create_session,
  validate_session = validate_session,
  delete_session = delete_session,
  purge_expired_sessions = purge_expired_sessions,
  login = login,
  hash_password = hash_password,
  gen_salt = gen_salt,
  change_password = change_password,
  admin_set_password = admin_set_password,
  purge_login_attempts = purge_login_attempts,
  MIN_PASSWORD_LEN = MIN_PASSWORD_LEN
}
