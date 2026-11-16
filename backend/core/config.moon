-- core/config.moon
-- Centralized configuration for TGui.
-- Keeps constants and settings in one place to avoid duplication.

log   = require 'log'
fiber = require 'fiber'

-- ────────────────────────────────────────────────────────────────────────────
-- Sessions and authentication
-- ────────────────────────────────────────────────────────────────────────────

SESSION_TTL = 24 * 3600  -- 24 hours in seconds
TOKEN_LENGTH = 32

-- Public default password shipped by the bootstrap. Any account whose current
-- password is still this value has must_change_password set and is refused any
-- operation but me/changePassword/logout (spec §7 / audit 1.4). Changing the
-- password clears the flag.
DEFAULT_ADMIN_PASSWORD = 'adminadmin'

-- Login rate-limiting (spec §7 / audit 1.2). The counters are persisted in the
-- `_tdb_login_attempts` system space so a server restart does not forgive
-- accumulated failures. The lockout delay doubles on every new cycle.
LOGIN_MAX_ATTEMPTS         = 5      -- consecutive failures before an account lockout
LOGIN_IP_MAX_ATTEMPTS      = 25     -- consecutive failures before an address lockout
LOGIN_ATTEMPT_WINDOW       = 300    -- seconds; failures older than this are forgotten
LOGIN_LOCKOUT_BASE_SECONDS = 60     -- first lockout duration (doubles per cycle)
LOGIN_LOCKOUT_MAX_SECONDS  = 3600   -- upper bound of the exponential backoff (1 hour)
LOGIN_ATTEMPTS_TTL         = 86400  -- seconds; stale entries purged after one day

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
-- Request fiber slice and cooperative yielding
-- ────────────────────────────────────────────────────────────────────────────

-- Fiber slice of ONE GraphQL request, set on the request fiber just before the
-- operation runs (http_server.handle_graphql). The instance-wide default slice
-- is left untouched (init.moon no longer raises it): a heavy grid read must not
-- hold every other request for the old 20 s bound. A request fiber raises only
-- its own bound, so an honest read (computed columns scanning other spaces
-- through space()) is not aborted, while a runaway one stays bounded well below
-- the instance-wide value that used to apply.
REQUEST_SLICE = { warn: 1, err: 5 }

-- Cooperate with other fibers every YIELD_EVERY iterations of a per-row read
-- loop. Tarantool is cooperative: without an explicit yield, one grid read
-- starves every other request until it returns. 64 keeps the switching cost
-- well under the per-row formula cost on the heaviest grids.
YIELD_EVERY = 64

-- Give the current fiber its own slice: Tarantool 3 per-fiber API
-- `fiber.self():set_max_slice { warn, err }` (verified on the test instance,
-- Tarantool 3.7.0; there is no getter in that version — read it back with
-- `fiber.self():info().max_slice`).
set_request_slice = ->
  fiber.self!\set_max_slice REQUEST_SLICE

-- Called once per iteration of a per-row read loop: yields every YIELD_EVERY
-- iterations, but NEVER inside a transaction. Tarantool forbids yielding in a
-- transaction ("yield is not allowed in transaction"), and reads do run inside
-- box.atomic (batch resolvers, app_apply): box.is_in_txn() is the guard, so
-- the same helper is safe to call from any loop.
-- Returns true when it actually yielded (test hook), false otherwise.
yield_every = (i) ->
  return false unless YIELD_EVERY > 0 and i % YIELD_EVERY == 0
  in_txn = box and box.is_in_txn and box.is_in_txn! or false
  return false if in_txn
  fiber.yield!
  true

-- Execution guard for formulas (spec §7): maximum number of VM instructions a
-- single formula call may execute, checked by debug.sethook every
-- FORMULA_HOOK_INTERVAL instructions. Bounds infinite loops.
FORMULA_INSTRUCTION_LIMIT = 20 * 1000 * 1000
FORMULA_HOOK_INTERVAL = 10000

-- ────────────────────────────────────────────────────────────────────────────
-- Instruction-guard escape hatch
-- ────────────────────────────────────────────────────────────────────────────

-- Run host-side work outside the formula instruction guard.
-- The guard (safe_formula_call) bounds the formula's own code (infinite
-- loops): that is what the 20M-instruction budget is for. The work the host
-- performs FOR the formula — decoding every tuple of a space for space(),
-- building a relation map, compiling a formula — is not the formula's own
-- cost and must not be charged to its budget: a single space() call on a
-- 150-line space already costs far more than FORMULA_INSTRUCTION_LIMIT, which
-- made honest formulas fail with "instruction limit exceeded".
-- Reads the current hook, disarms it, runs fn in a pcall, restores the hook
-- that was in place (or none), then re-raises the error untouched if fn
-- failed, otherwise returns fn's results.
run_unguarded = (fn, ...) ->
  prev_hook, prev_mask, prev_count = debug.gethook!
  debug.sethook!
  packed = { pcall(fn, ...) }
  if prev_hook
    debug.sethook prev_hook, prev_mask, prev_count
  else
    debug.sethook!
  unless packed[1]
    error packed[2], 0
  return unpack(packed, 2)

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

safe_formula_call = (fn, context, default_value = nil, record_id = nil, args = nil) ->
  call_args = args or {}
  owner_fid = fiber.self!.fid
  in_call = true
  hook_calls = 0
  -- Count-hook guard around the formula call.
  -- The hook MUST disarm itself before raising: LuaJIT only lets pcall catch an
  -- error raised from a count hook when the hook is already off. LuaJIT hooks
  -- are global across fibers, so the guard never trips inside another fiber
  -- (a yielding formula must not raise into an innocent caller).
  guard = ->
    return if fiber.self!.fid != owner_fid
    hook_calls += 1
    if in_call and hook_calls * FORMULA_HOOK_INTERVAL > FORMULA_INSTRUCTION_LIMIT
      debug.sethook!
      error "instruction limit exceeded in #{context} (#{FORMULA_INSTRUCTION_LIMIT} instructions)", 0

  prev_hook, prev_mask, prev_count = debug.gethook!
  debug.sethook guard, 'count', FORMULA_HOOK_INTERVAL
  ok, result = pcall fn, unpack(call_args)
  in_call = false
  -- Restore the previous hook in all cases (the guard may have disarmed itself).
  if prev_hook
    debug.sethook prev_hook, prev_mask, prev_count
  else
    debug.sethook!

  if ok
    return result

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
  -- Return default_value, not nil, to avoid breaking logic. Second return
  -- value is the error (nil on success) so callers can tell them apart.
  return default_value, result

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
  :SESSION_TTL, :TOKEN_LENGTH, :FRONTEND_DIR, :DEFAULT_ADMIN_PASSWORD
  :LOGIN_MAX_ATTEMPTS, :LOGIN_IP_MAX_ATTEMPTS, :LOGIN_ATTEMPT_WINDOW
  :LOGIN_LOCKOUT_BASE_SECONDS, :LOGIN_LOCKOUT_MAX_SECONDS, :LOGIN_ATTEMPTS_TTL
  :DEFAULT_FORMULA_MAX_LENGTH, :DEFAULT_FIELD_NAME_MAX_LENGTH
  :LIMITS, :safe_call, :validate_input
  :safe_formula_call, :get_formula_metrics, :clear_formula_metrics
  :FORMULA_INSTRUCTION_LIMIT, :FORMULA_HOOK_INTERVAL
  :REQUEST_SLICE, :YIELD_EVERY, :set_request_slice, :yield_every
  :run_unguarded
}
