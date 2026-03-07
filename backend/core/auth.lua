local digest = require('digest')
local uuid_mod = require('uuid')
local log = require('log')
local SESSION_TTL = 24 * 3600
local gen_salt
gen_salt = function()
  return digest.base64_encode(digest.urandom(32))
end
local hash_password
hash_password = function(password, salt)
  return digest.sha256_hex(password .. salt)
end
local verify_password
verify_password = function(password, salt, stored_hash)
  return hash_password(password, salt) == stored_hash
end
local create_user
create_user = function(username, email, password)
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
  return digest.base64_encode((digest.urandom(32)), {
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
local login
login = function(username, password)
  local user = get_user_by_username(username)
  if not (user) then
    return nil, 'Invalid username or password'
  end
  if not (verify_password(password, user.salt, user.password_hash)) then
    return nil, 'Invalid username or password'
  end
  return create_session(user.id)
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
  gen_salt = gen_salt
}
