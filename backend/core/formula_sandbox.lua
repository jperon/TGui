local log = require('log')
local MAX_STRING_REP_BYTES = 10 * 1024 * 1024
local real_string_rep = string.rep
local rep_guarded
rep_guarded = function(s, n, sep)
  local len = 0
  if type(s) == 'string' then
    len = #s
  end
  local sep_len = 0
  if type(sep) == 'string' then
    sep_len = #sep
  end
  local n_num = tonumber(n)
  if n_num and n_num > 0 and len + sep_len > 0 and n_num * (len + sep_len) > MAX_STRING_REP_BYTES then
    error("string.rep result exceeds limit " .. tostring(MAX_STRING_REP_BYTES) .. " bytes", 0)
  end
  if sep ~= nil then
    return real_string_rep(s, n, sep)
  end
  return real_string_rep(s, n)
end
local shallow_copy
shallow_copy = function(t)
  local c = { }
  for k, v in pairs(t) do
    c[k] = v
  end
  return c
end
local make_string_copy
make_string_copy = function()
  local c = shallow_copy(string)
  c.rep = rep_guarded
  return c
end
local string_mt = getmetatable("")
if string_mt and type(string_mt) == 'table' then
  string_mt.__index = make_string_copy()
end
local build_formula_env
build_formula_env = function()
  local env = {
    math = shallow_copy(math),
    string = make_string_copy(),
    table = shallow_copy(table),
    type = type,
    tostring = tostring,
    tonumber = tonumber,
    pairs = pairs,
    ipairs = ipairs,
    next = next,
    select = select,
    unpack = rawget(_G, 'unpack') or table.unpack,
    pcall = pcall,
    error = error,
    assert = assert,
    rawget = rawget,
    rawset = rawset,
    rawequal = rawequal,
    os = {
      time = os.time,
      clock = os.clock,
      date = os.date
    }
  }
  env._ENV = env
  return env
end
local compile_formula
compile_formula = function(formula, field_name, language)
  local lua_chunk
  if language == 'moonscript' then
    local ok_ms, moon = pcall(require, 'moonscript.base')
    if not (ok_ms) then
      log.error("tdb triggers: moonscript.base unavailable for '" .. tostring(field_name) .. "': " .. tostring(moon))
      return nil
    end
    if field_name == 'filter' then
      formula = formula:gsub('@([%w_]+)', 'self.%1')
    end
    local moon_src = "return (self, space) -> " .. formula
    local ok_c, lua_or_err = pcall(moon.to_lua, moon_src)
    if not (ok_c) then
      log.error("tdb triggers: MoonScript parse error for '" .. tostring(field_name) .. "': " .. tostring(lua_or_err))
      return nil
    end
    lua_chunk = lua_or_err
  else
    lua_chunk = "return function(self, space) return " .. formula .. " end"
  end
  local chunk_fn, load_err = load(lua_chunk)
  if not chunk_fn then
    log.error("tdb triggers: parse error for field '" .. tostring(field_name) .. "': " .. tostring(load_err))
    return nil
  end
  local ok_env, _ = pcall(setfenv, chunk_fn, build_formula_env())
  if not (ok_env) then
    log.error("tdb triggers: setfenv not available, refusing to run formula '" .. tostring(field_name) .. "' unsandboxed")
    return nil
  end
  local ok2, fn = pcall(chunk_fn)
  if not ok2 or type(fn) ~= 'function' then
    log.error("tdb triggers: init error for field '" .. tostring(field_name) .. "': " .. tostring(fn))
    return nil
  end
  if jit and jit.off then
    pcall(jit.off, fn, true)
  end
  return fn
end
return {
  compile_formula = compile_formula,
  MAX_STRING_REP_BYTES = MAX_STRING_REP_BYTES
}
