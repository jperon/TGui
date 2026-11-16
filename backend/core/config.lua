local log = require('log')
local fiber = require('fiber')
local SESSION_TTL = 24 * 3600
local TOKEN_LENGTH = 32
local DEFAULT_ADMIN_PASSWORD = 'adminadmin'
local LOGIN_MAX_ATTEMPTS = 5
local LOGIN_IP_MAX_ATTEMPTS = 25
local LOGIN_ATTEMPT_WINDOW = 300
local LOGIN_LOCKOUT_BASE_SECONDS = 60
local LOGIN_LOCKOUT_MAX_SECONDS = 3600
local LOGIN_ATTEMPTS_TTL = 86400
local FRONTEND_DIR = '/app/frontend'
local DEFAULT_FORMULA_MAX_LENGTH = 10000
local DEFAULT_FIELD_NAME_MAX_LENGTH = 255
local LIMITS = {
  formula = {
    max_length = DEFAULT_FORMULA_MAX_LENGTH,
    warning_threshold = 5000
  },
  field_name = {
    max_length = DEFAULT_FIELD_NAME_MAX_LENGTH
  }
}
local REQUEST_SLICE = {
  warn = 1,
  err = 5
}
local YIELD_EVERY = 64
local set_request_slice
set_request_slice = function()
  return fiber.self():set_max_slice(REQUEST_SLICE)
end
local yield_every
yield_every = function(i)
  if not (YIELD_EVERY > 0 and i % YIELD_EVERY == 0) then
    return false
  end
  local in_txn = box and box.is_in_txn and box.is_in_txn() or false
  if in_txn then
    return false
  end
  fiber.yield()
  return true
end
local FORMULA_INSTRUCTION_LIMIT = 20 * 1000 * 1000
local FORMULA_HOOK_INTERVAL = 10000
local run_unguarded
run_unguarded = function(fn, ...)
  local prev_hook, prev_mask, prev_count = debug.gethook()
  debug.sethook()
  local packed = {
    pcall(fn, ...)
  }
  if prev_hook then
    debug.sethook(prev_hook, prev_mask, prev_count)
  else
    debug.sethook()
  end
  if not (packed[1]) then
    error(packed[2], 0)
  end
  return unpack(packed, 2)
end
local safe_call
safe_call = function(fn, context, default_value, record_id)
  if default_value == nil then
    default_value = nil
  end
  if record_id == nil then
    record_id = nil
  end
  local ok, result = pcall(fn)
  if ok then
    return result
  else
    log.error("Error in " .. tostring(context) .. tostring(record_id and " (record: " .. tostring(record_id) .. ")" or "") .. ": " .. tostring(result))
    return default_value
  end
end
local formula_metrics = {
  errors = { }
}
local safe_formula_call
safe_formula_call = function(fn, context, default_value, record_id, args)
  if default_value == nil then
    default_value = nil
  end
  if record_id == nil then
    record_id = nil
  end
  if args == nil then
    args = nil
  end
  local call_args = args or { }
  local owner_fid = fiber.self().fid
  local in_call = true
  local hook_calls = 0
  local guard
  guard = function()
    if fiber.self().fid ~= owner_fid then
      return 
    end
    hook_calls = hook_calls + 1
    if in_call and hook_calls * FORMULA_HOOK_INTERVAL > FORMULA_INSTRUCTION_LIMIT then
      debug.sethook()
      return error("instruction limit exceeded in " .. tostring(context) .. " (" .. tostring(FORMULA_INSTRUCTION_LIMIT) .. " instructions)", 0)
    end
  end
  local prev_hook, prev_mask, prev_count = debug.gethook()
  debug.sethook(guard, 'count', FORMULA_HOOK_INTERVAL)
  local ok, result = pcall(fn, unpack(call_args))
  in_call = false
  if prev_hook then
    debug.sethook(prev_hook, prev_mask, prev_count)
  else
    debug.sethook()
  end
  if ok then
    return result
  end
  local now = os.time()
  if formula_metrics.errors[context] then
    local _update_0 = context
    formula_metrics.errors[_update_0].count = formula_metrics.errors[_update_0].count + 1
    formula_metrics.errors[context].last_error = result
    formula_metrics.errors[context].last_timestamp = now
  else
    formula_metrics.errors[context] = {
      count = 1,
      last_error = result,
      last_timestamp = now
    }
  end
  log.error("Formula error in " .. tostring(context) .. tostring(record_id and " (record: " .. tostring(record_id) .. ")" or "") .. ": " .. tostring(result))
  return default_value, result
end
local get_formula_metrics
get_formula_metrics = function()
  local total_errors = 0
  for _, metrics in pairs(formula_metrics.errors) do
    total_errors = total_errors + metrics.count
  end
  return {
    total_errors = total_errors,
    error_details = formula_metrics.errors,
    error_count = #formula_metrics.errors
  }
end
local clear_formula_metrics
clear_formula_metrics = function()
  formula_metrics.errors = { }
end
local validate_input
validate_input = function(type, value, context)
  local limits = LIMITS[type]
  if not (limits) then
    return true
  end
  if value == '' then
    return true
  end
  if #value > limits.max_length then
    log.warn(tostring(context) .. ": length " .. tostring(#value) .. " exceeds limit " .. tostring(limits.max_length))
    return false
  end
  if limits.warning_threshold and #value > limits.warning_threshold then
    log.info(tostring(context) .. ": large input (" .. tostring(#value) .. " chars)")
  end
  return true
end
return {
  SESSION_TTL = SESSION_TTL,
  TOKEN_LENGTH = TOKEN_LENGTH,
  FRONTEND_DIR = FRONTEND_DIR,
  DEFAULT_ADMIN_PASSWORD = DEFAULT_ADMIN_PASSWORD,
  LOGIN_MAX_ATTEMPTS = LOGIN_MAX_ATTEMPTS,
  LOGIN_IP_MAX_ATTEMPTS = LOGIN_IP_MAX_ATTEMPTS,
  LOGIN_ATTEMPT_WINDOW = LOGIN_ATTEMPT_WINDOW,
  LOGIN_LOCKOUT_BASE_SECONDS = LOGIN_LOCKOUT_BASE_SECONDS,
  LOGIN_LOCKOUT_MAX_SECONDS = LOGIN_LOCKOUT_MAX_SECONDS,
  LOGIN_ATTEMPTS_TTL = LOGIN_ATTEMPTS_TTL,
  DEFAULT_FORMULA_MAX_LENGTH = DEFAULT_FORMULA_MAX_LENGTH,
  DEFAULT_FIELD_NAME_MAX_LENGTH = DEFAULT_FIELD_NAME_MAX_LENGTH,
  LIMITS = LIMITS,
  safe_call = safe_call,
  validate_input = validate_input,
  safe_formula_call = safe_formula_call,
  get_formula_metrics = get_formula_metrics,
  clear_formula_metrics = clear_formula_metrics,
  FORMULA_INSTRUCTION_LIMIT = FORMULA_INSTRUCTION_LIMIT,
  FORMULA_HOOK_INTERVAL = FORMULA_HOOK_INTERVAL,
  REQUEST_SLICE = REQUEST_SLICE,
  YIELD_EVERY = YIELD_EVERY,
  set_request_slice = set_request_slice,
  yield_every = yield_every,
  run_unguarded = run_unguarded
}
