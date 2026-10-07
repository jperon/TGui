-- core/formula_sandbox.moon
-- Sandbox used to compile and run user formulas.
-- Extracted from core.triggers (T14), no functional change.
--
-- Owns the bounded string.rep guard and the ONE-TIME rebinding of the shared
-- string metatable __index at import (spec §7). That rebinding must happen
-- exactly once for the whole process; since formula_sandbox is required by
-- core.triggers and core.formula_proxy and cached by package.loaded, this
-- import-time effect still runs once.

log = require 'log'

-- Refuse string.rep results above this many bytes (memory DoS guard, spec §7).
MAX_STRING_REP_BYTES = 10 * 1024 * 1024

real_string_rep = string.rep

-- Bounded string.rep: checks the result size BEFORE allocating anything.
rep_guarded = (s, n, sep) ->
  len = 0
  len = #s if type(s) == 'string'
  sep_len = 0
  sep_len = #sep if type(sep) == 'string'
  n_num = tonumber n
  if n_num and n_num > 0 and len + sep_len > 0 and n_num * (len + sep_len) > MAX_STRING_REP_BYTES
    error "string.rep result exceeds limit #{MAX_STRING_REP_BYTES} bytes", 0
  if sep != nil
    return real_string_rep s, n, sep
  real_string_rep s, n

-- Shallow copy of a table of functions (string, table, math are such tables).
shallow_copy = (t) ->
  c = {}
  for k, v in pairs t
    c[k] = v
  c

-- Fresh copy of the string library with the bounded rep.
make_string_copy = ->
  c = shallow_copy string
  c.rep = rep_guarded
  c

-- The string metatable __index is shared by every string method call
-- (("x"):rep(n)): rebind it to the protected copy so the bound applies to
-- method syntax too, not only to explicit string.rep lookups (spec §7).
string_mt = getmetatable ""
if string_mt and type(string_mt) == 'table'
  string_mt.__index = make_string_copy!

-- Safe sandbox environment for formula execution, BUILT FOR EACH FORMULA so
-- that a formula mutating string/table/math cannot corrupt any other formula.
-- Only exposes pure/math/string functions. Explicitly excludes io, debug,
-- box, load, require — anything that could access the filesystem or Tarantool internals.
build_formula_env = ->
  env = {
    math:      shallow_copy(math)
    string:    make_string_copy()
    table:     shallow_copy(table)
    type:      type
    tostring:  tostring
    tonumber:  tonumber
    pairs:     pairs
    ipairs:    ipairs
    next:      next
    select:    select
    unpack:    rawget(_G, 'unpack') or table.unpack
    pcall:     pcall
    error:     error
    assert:    assert
    rawget:    rawget
    rawset:    rawset
    rawequal:  rawequal
    -- Limited os: only safe time functions
    os: { time: os.time, clock: os.clock, date: os.date }
  }
  env._ENV = env  -- self-reference for inner closures
  env

-- Compile a formula string into a Lua function(self, space).
-- language: 'lua' (default) or 'moonscript'.
-- For MoonScript, the formula is a MoonScript expression transpiled
-- to Lua via moonscript.base.to_lua before the regular load().
-- For filters, @ refers to the current record (self).
-- Returns the compiled function, or nil + logs an error on failure.
compile_formula = (formula, field_name, language) ->
  -- Build the Lua chunk string that returns the function.
  lua_chunk = if language == 'moonscript'
    ok_ms, moon = pcall require, 'moonscript.base'
    unless ok_ms
      log.error "tdb triggers: moonscript.base unavailable for '#{field_name}': #{moon}"
      return nil

    -- For filters, rewrite @xxx to self.xxx for compatibility.
    if field_name == 'filter'
      -- Replace @xxx with self.xxx in filter formulas.
      formula = formula\gsub '@([%w_]+)', 'self.%1'

    -- Wrap expression in a MoonScript lambda: (self, space) -> <expr>
    moon_src = "return (self, space) -> " .. formula
    ok_c, lua_or_err = pcall moon.to_lua, moon_src
    unless ok_c
      log.error "tdb triggers: MoonScript parse error for '#{field_name}': #{lua_or_err}"
      return nil
    lua_or_err
  else
    "return function(self, space) return " .. formula .. " end"
  -- Load the chunk and apply sandbox environment
  chunk_fn, load_err = load lua_chunk
  if not chunk_fn
    log.error "tdb triggers: parse error for field '#{field_name}': #{load_err}"
    return nil
  -- Apply sandbox via setfenv (Lua 5.1 / LuaJIT) — mandatory for security.
  -- Each formula gets its own environment: fresh copies of string/table/math/os,
  -- so mutating them inside a formula cannot affect any other formula.
  ok_env, _ = pcall setfenv, chunk_fn, build_formula_env!
  unless ok_env
    log.error "tdb triggers: setfenv not available, refusing to run formula '#{field_name}' unsandboxed"
    return nil
  -- Execute chunk to get the formula function
  ok2, fn = pcall chunk_fn
  if not ok2 or type(fn) != 'function'
    log.error "tdb triggers: init error for field '#{field_name}': #{fn}"
    return nil
  -- Run the formula interpreted: the instruction-count guard inspects hooks
  -- reliably only in interpreted code, and it trips ~20x faster on it
  -- (measured on Tarantool 3.7/LuaJIT: 8.3s vs 0.4s for a 200M-instruction budget).
  if jit and jit.off
    pcall jit.off, fn, true
  fn

{ :compile_formula, :MAX_STRING_REP_BYTES }
