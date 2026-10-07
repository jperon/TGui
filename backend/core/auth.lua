local digest = require('digest')
local uuid_mod = require('uuid')
local log = require('log')
local SESSION_TTL, TOKEN_LENGTH, LOGIN_MAX_ATTEMPTS, LOGIN_IP_MAX_ATTEMPTS, LOGIN_ATTEMPT_WINDOW, LOGIN_LOCKOUT_BASE_SECONDS, LOGIN_LOCKOUT_MAX_SECONDS, LOGIN_ATTEMPTS_TTL
do
  local _obj_0 = require('core.config')
  SESSION_TTL, TOKEN_LENGTH, LOGIN_MAX_ATTEMPTS, LOGIN_IP_MAX_ATTEMPTS, LOGIN_ATTEMPT_WINDOW, LOGIN_LOCKOUT_BASE_SECONDS, LOGIN_LOCKOUT_MAX_SECONDS, LOGIN_ATTEMPTS_TTL = _obj_0.SESSION_TTL, _obj_0.TOKEN_LENGTH, _obj_0.LOGIN_MAX_ATTEMPTS, _obj_0.LOGIN_IP_MAX_ATTEMPTS, _obj_0.LOGIN_ATTEMPT_WINDOW, _obj_0.LOGIN_LOCKOUT_BASE_SECONDS, _obj_0.LOGIN_LOCKOUT_MAX_SECONDS, _obj_0.LOGIN_ATTEMPTS_TTL
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
local LOGIN_USER_PREFIX = 'user:'
local LOGIN_IP_PREFIX = 'ip:'
local login_key
login_key = function(username)
  return LOGIN_USER_PREFIX .. tostring(username or ''):lower()
end
local login_ip_key
login_ip_key = function(client_addr)
  return LOGIN_IP_PREFIX .. tostring(client_addr)
end
local login_keys
login_keys = function(username, client_addr)
  local keys = {
    login_key(username)
  }
  if client_addr then
    table.insert(keys, login_ip_key(client_addr))
  end
  return keys
end
local key_max_attempts
key_max_attempts = function(key)
  if key and key:sub(1, #LOGIN_IP_PREFIX) == LOGIN_IP_PREFIX then
    return LOGIN_IP_MAX_ATTEMPTS
  end
  return LOGIN_MAX_ATTEMPTS
end
local read_attempt
read_attempt = function(key)
  local t = box.space._tdb_login_attempts:get(key)
  if not (t) then
    return nil
  end
  return {
    key = t[1],
    failures = t[2],
    last_failure_at = t[3],
    locked_until = t[4],
    lock_count = t[5]
  }
end
local new_attempt
new_attempt = function(key)
  return {
    key = key,
    failures = 0,
    last_failure_at = 0,
    locked_until = 0,
    lock_count = 0
  }
end
local write_attempt
write_attempt = function(entry)
  return box.space._tdb_login_attempts:replace({
    entry.key,
    entry.failures,
    entry.last_failure_at,
    entry.locked_until,
    entry.lock_count
  })
end
local reset_after_quiet
reset_after_quiet = function(entry, now)
  if entry.locked_until > now then
    return 
  end
  local quiet_since = math.max(entry.last_failure_at, entry.locked_until)
  if quiet_since > 0 and now - quiet_since > LOGIN_ATTEMPT_WINDOW then
    entry.failures = 0
    entry.lock_count = 0
  end
  return entry
end
local lockout_delay
lockout_delay = function(lock_count)
  local delay = LOGIN_LOCKOUT_BASE_SECONDS * (2 ^ (lock_count - 1))
  if delay > LOGIN_LOCKOUT_MAX_SECONDS then
    return LOGIN_LOCKOUT_MAX_SECONDS
  end
  return delay
end
local purge_login_attempts
purge_login_attempts = function()
  local now = os.time()
  local stale = { }
  local _list_0 = box.space._tdb_login_attempts:select({ })
  for _index_0 = 1, #_list_0 do
    local t = _list_0[_index_0]
    local quiet_since = math.max(t[3], t[4])
    if quiet_since > 0 and now - quiet_since > LOGIN_ATTEMPTS_TTL and t[4] < now then
      table.insert(stale, t[1])
    end
  end
  for _index_0 = 1, #stale do
    local key = stale[_index_0]
    box.space._tdb_login_attempts:delete(key)
  end
  return #stale
end
local record_failed_attempt
record_failed_attempt = function(key)
  local now = os.time()
  local entry = read_attempt(key) or new_attempt(key)
  reset_after_quiet(entry, now)
  entry.failures = entry.failures + 1
  entry.last_failure_at = now
  if entry.failures >= key_max_attempts(key) then
    entry.lock_count = entry.lock_count + 1
    entry.locked_until = now + lockout_delay(entry.lock_count)
    entry.failures = 0
  end
  write_attempt(entry)
  purge_login_attempts()
  return entry.locked_until
end
local clear_failed_attempts
clear_failed_attempts = function(key)
  box.space._tdb_login_attempts:delete(key)
  return true
end
local is_locked_out
is_locked_out = function(key)
  local entry = read_attempt(key)
  if not (entry) then
    return false
  end
  return entry.locked_until > os.time()
end
local login
login = function(username, password, client_addr)
  local keys = login_keys(username, client_addr)
  for _index_0 = 1, #keys do
    local key = keys[_index_0]
    if is_locked_out(key) then
      return nil, 'Too many failed attempts, please try again later'
    end
  end
  local user = get_user_by_username(username)
  if user and verify_password(password, user.salt, user.password_hash) then
    for _index_0 = 1, #keys do
      local key = keys[_index_0]
      clear_failed_attempts(key)
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
    return create_session(user.id)
  end
  for _index_0 = 1, #keys do
    local key = keys[_index_0]
    record_failed_attempt(key)
  end
  return nil, 'Invalid username or password'
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
  login_key = login_key,
  login_ip_key = login_ip_key,
  MIN_PASSWORD_LEN = MIN_PASSWORD_LEN
}
