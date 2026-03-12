-- core/config.moon
-- Centralized configuration for TGui.
-- Keeps constants and settings in one place to avoid duplication.

log = require 'log'

-- ────────────────────────────────────────────────────────────────────────────
-- Sessions and authentication
-- ────────────────────────────────────────────────────────────────────────────

SESSION_TTL = 24 * 3600  -- 24 hours in seconds
TOKEN_LENGTH = 32

-- ────────────────────────────────────────────────────────────────────────────
-- Paths and directories
-- ────────────────────────────────────────────────────────────────────────────

FRONTEND_DIR = '/app/frontend'

-- ────────────────────────────────────────────────────────────────────────────
-- Limits (user-friendly defaults)
-- ────────────────────────────────────────────────────────────────────────────

DEFAULT_FORMULA_MAX_LENGTH = 10000
DEFAULT_FIELD_NAME_MAX_LENGTH = 255

LIMITS = {
  formula: {
    max_length: DEFAULT_FORMULA_MAX_LENGTH
    warning_threshold: 5000  -- warning before hard limit
  }
  field_name: {
    max_length: DEFAULT_FIELD_NAME_MAX_LENGTH
  }
}

-- ────────────────────────────────────────────────────────────────────────────
-- Utility helpers
-- ────────────────────────────────────────────────────────────────────────────

-- Safe execution helper
safe_call = (fn, context, default_value = nil, record_id = nil) ->
  ok, result = pcall fn
  if ok
    return result
  else
    log.error "Error in #{context}#{record_id and " (record: #{record_id})" or ""}: #{result}"
    return default_value

-- Enhanced safe call with metrics tracking
formula_metrics = {
  errors: {}  -- space_name.field_name -> {count, last_error, last_timestamp}
}

safe_formula_call = (fn, context, default_value = nil, record_id = nil) ->
  ok, result = pcall fn
  if ok
    return result
  else
    -- Track error metrics
    now = os.time!
    if formula_metrics.errors[context]
      formula_metrics.errors[context].count += 1
      formula_metrics.errors[context].last_error = result
      formula_metrics.errors[context].last_timestamp = now
    else
      formula_metrics.errors[context] = {
        count: 1
        last_error: result
        last_timestamp: now
      }

    log.error "Formula error in #{context}#{record_id and " (record: #{record_id})" or ""}: #{result}"
    -- Return default_value, not nil, to avoid breaking logic
    return default_value

-- Get error metrics for monitoring
get_formula_metrics = ->
  total_errors = 0
  for _, metrics in pairs formula_metrics.errors
    total_errors += metrics.count

  {
    total_errors: total_errors
    error_details: formula_metrics.errors
    error_count: #formula_metrics.errors
  }

-- Clear error metrics (useful for tests)
clear_formula_metrics = ->
  formula_metrics.errors = {}

-- Validation helper (souple pour utilisateur)
validate_input = (type, value, context) ->
  limits = LIMITS[type]
  return true unless limits

  -- Allow empty strings for formulas (common case)
  if value == ''
    return true

  if #value > limits.max_length
    log.warn "#{context}: length #{#value} exceeds limit #{limits.max_length}"
    return false

  if limits.warning_threshold and #value > limits.warning_threshold
    log.info "#{context}: large input (#{#value} chars)"

  return true

-- Export configuration
{
  :SESSION_TTL, :TOKEN_LENGTH, :FRONTEND_DIR
  :DEFAULT_FORMULA_MAX_LENGTH, :DEFAULT_FIELD_NAME_MAX_LENGTH
  :LIMITS, :safe_call, :validate_input
  :safe_formula_call, :get_formula_metrics, :clear_formula_metrics
}
