local log = require('log')
local SESSION_TTL = 24 * 3600
local TOKEN_LENGTH = 32
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
safe_formula_call = function(fn, context, default_value, record_id)
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
    local now = os.time()
    if formula_metrics.errors[context] then
      formula_metrics.errors[context].count = formula_metrics.errors[context].count + 1
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
    return default_value
  end
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
  DEFAULT_FORMULA_MAX_LENGTH = DEFAULT_FORMULA_MAX_LENGTH,
  DEFAULT_FIELD_NAME_MAX_LENGTH = DEFAULT_FIELD_NAME_MAX_LENGTH,
  LIMITS = LIMITS,
  safe_call = safe_call,
  validate_input = validate_input,
  safe_formula_call = safe_formula_call,
  get_formula_metrics = get_formula_metrics,
  clear_formula_metrics = clear_formula_metrics
}
