-- tests/runner.moon
-- Standalone test micro-framework (no external dependencies).
-- Usage:
--   R = require 'tests.runner'
--   R.describe "My module", ->
--     R.it "does something", ->
--       R.eq myValue, 42
--   R.summary!   -- prints summary and exits with code 1 on failure

_state =
  passed:  0
  failed:  0
  errors:  0
  current: ''
  before_all_fn: nil
  after_all_fn:  nil
  before_all_done: false

-- Value formatter for failure output
fmt = (v) ->
  t = type v
  if t == 'string'
    string.format('%q', v)
  elseif t == 'nil'
    'nil'
  elseif t == 'boolean'
    tostring v
  elseif t == 'number'
    tostring v
  elseif t == 'function'
    'function()'
  elseif t == 'table'
    if #v > 0  -- array
      items = {}
      for i, val in ipairs v
        table.insert items, fmt val
      "[#{table.concat items, ', '}]"
    else  -- object/dict
      pairs_str = {}
      for k, val in pairs v
        table.insert pairs_str, "#{tostring k}=#{fmt val}"
      "{#{table.concat pairs_str, ', '}}"
  else
    "<#{t}>#{tostring v}"

-- Source location helper (2 levels up from assert)
loc = (depth) ->
  info = debug.getinfo (depth or 3), 'Sl'
  if info and info.currentline > 0
    src = info.short_src\gsub '.+/', ''
    "#{src}:#{info.currentline}"
  else '?'

_fail = (msg, depth) ->
  _state.failed += 1
  location = loc (depth or 3) + 1
  print "  ✗ [#{location}] #{msg}"

  -- Add a stack trace to help debugging
  print "    Trace d'appel :"
  level = (depth or 3) + 2
  while true
    info = debug.getinfo level, 'Sl'
    if not info or info.currentline <= 0
      break
    src = info.short_src\gsub '.+/', ''
    print "      #{src}:#{info.currentline}"
    level += 1

_pass = ->
  _state.passed += 1

-- ── Assertions ───────────────────────────────────────────────────────────────

-- Strict equality
eq = (actual, expected, label) ->
  if actual == expected
    _pass!
  else
    _fail "#{label and label .. ': ' or ''}expected #{fmt expected}, got #{fmt actual}", 3

-- Difference
ne = (actual, expected, label) ->
  if actual != expected
    _pass!
  else
    _fail "#{label and label .. ': ' or ''}expected a value different from #{fmt expected}", 3

-- True (truthy)
ok = (v, label) ->
  if v
    _pass!
  else
    _fail "#{label and label .. ': ' or ''}expected a truthy value, got #{fmt v}", 3

-- False (falsy)
nok = (v, label) ->
  if not v
    _pass!
  else
    _fail "#{label and label .. ': ' or ''}expected a falsy value, got #{fmt v}", 3

-- Nil
is_nil = (v, label) ->
  eq v, nil, label

-- Matches a Lua pattern
matches = (s, pattern, label) ->
  if type(s) == 'string' and s\match pattern
    _pass!
  else
    _fail "#{label and label .. ': ' or ''}'#{tostring s}' ne correspond pas au pattern '#{pattern}'", 3

-- Raises an error (optionally checks message)
raises = (fn, pattern, label) ->
  success, err = pcall fn
  if success
    _fail "#{label and label .. ': ' or ''}no error raised", 3
  elseif pattern and not tostring(err)\match pattern
    _fail "#{label and label .. ': ' or ''}error '#{err}' does not match '#{pattern}'", 3
  else
    _pass!

-- ── Structure ─────────────────────────────────────────────────────────────────

describe = (name, fn) ->
  old_before = _state.before_all_fn
  old_after  = _state.after_all_fn
  old_done   = _state.before_all_done

  _state.current = name
  _state.before_all_fn = nil
  _state.after_all_fn  = nil
  _state.before_all_done = false

  print "\n#{name}"
  fn!

  _state.after_all_fn! if _state.after_all_fn

  _state.before_all_fn = old_before
  _state.after_all_fn  = old_after
  _state.before_all_done = old_done

before_all = (fn) -> _state.before_all_fn = fn
after_all  = (fn) -> _state.after_all_fn  = fn

it = (desc, fn) ->
  if _state.before_all_fn and not _state.before_all_done
    _state.before_all_fn!
    _state.before_all_done = true

  before = _state.failed + _state.errors
  success, err = pcall fn
  if not success
    _state.errors += 1
    location = loc 2
    print "  ✗ ERROR #{desc}"
    print "    [#{location}] #{err}"

    -- Print the full stack trace for errors
    print "    Full stack trace:"
    level = 3
    while true
      info = debug.getinfo level, 'Sl'
      if not info or info.currentline <= 0
        break
      src = info.short_src\gsub '.+/', ''
      print "      #{src}:#{info.currentline}"
      level += 1
  elseif _state.failed + _state.errors == before
    -- all assertions in this 'it' passed
    print "  ✓ #{desc}"

-- ── Summary ───────────────────────────────────────────────────────────────────

summary = ->
  total = _state.passed + _state.failed + _state.errors
  print "\n══════════════════════════════════════"
  print "#{total} assertions — #{_state.passed} ✓  #{_state.failed} ✗  #{_state.errors} errors"
  if _state.failed > 0 or _state.errors > 0
    print "RESULT: FAILURE"
    return 1
  print "RESULT: SUCCESS"
  return 0

{ :describe, :it, :before_all, :after_all, :eq, :ne, :ok, :nok, :is_nil, :matches, :raises, :summary }
