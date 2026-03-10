local _state = {
  passed = 0,
  failed = 0,
  errors = 0,
  current = '',
  before_all_fn = nil,
  after_all_fn = nil,
  before_all_done = false
}
local fmt
fmt = function(v)
  local t = type(v)
  if t == 'string' then
    return string.format('%q', v)
  elseif t == 'nil' then
    return 'nil'
  elseif t == 'boolean' then
    return tostring(v)
  elseif t == 'number' then
    return tostring(v)
  elseif t == 'function' then
    return 'function()'
  elseif t == 'table' then
    if #v > 0 then
      local items = { }
      for i, val in ipairs(v) do
        table.insert(items, fmt(val))
      end
      return "[" .. tostring(table.concat(items, ', ')) .. "]"
    else
      local pairs_str = { }
      for k, val in pairs(v) do
        table.insert(pairs_str, tostring(tostring(k)) .. "=" .. tostring(fmt(val)))
      end
      return "{" .. tostring(table.concat(pairs_str, ', ')) .. "}"
    end
  else
    return "<" .. tostring(t) .. ">" .. tostring(tostring(v))
  end
end
local loc
loc = function(depth)
  local info = debug.getinfo((depth or 3), 'Sl')
  if info and info.currentline > 0 then
    local src = info.short_src:gsub('.+/', '')
    return tostring(src) .. ":" .. tostring(info.currentline)
  else
    return '?'
  end
end
local _fail
_fail = function(msg, depth)
  _state.failed = _state.failed + 1
  local location = loc((depth or 3) + 1)
  print("  ✗ [" .. tostring(location) .. "] " .. tostring(msg))
  print("    Trace d'appel :")
  local level = (depth or 3) + 2
  while true do
    local info = debug.getinfo(level, 'Sl')
    if not info or info.currentline <= 0 then
      break
    end
    local src = info.short_src:gsub('.+/', '')
    print("      " .. tostring(src) .. ":" .. tostring(info.currentline))
    level = level + 1
  end
end
local _pass
_pass = function()
  _state.passed = _state.passed + 1
end
local eq
eq = function(actual, expected, label)
  if actual == expected then
    return _pass()
  else
    return _fail(tostring(label and label .. ': ' or '') .. "attendu " .. tostring(fmt(expected)) .. ", reçu " .. tostring(fmt(actual)), 3)
  end
end
local ne
ne = function(actual, expected, label)
  if actual ~= expected then
    return _pass()
  else
    return _fail(tostring(label and label .. ': ' or '') .. "attendu une valeur différente de " .. tostring(fmt(expected)), 3)
  end
end
local ok
ok = function(v, label)
  if v then
    return _pass()
  else
    return _fail(tostring(label and label .. ': ' or '') .. "attendu une valeur vraie, reçu " .. tostring(fmt(v)), 3)
  end
end
local nok
nok = function(v, label)
  if not v then
    return _pass()
  else
    return _fail(tostring(label and label .. ': ' or '') .. "attendu une valeur fausse, reçu " .. tostring(fmt(v)), 3)
  end
end
local is_nil
is_nil = function(v, label)
  return eq(v, nil, label)
end
local matches
matches = function(s, pattern, label)
  if type(s) == 'string' and s:match(pattern) then
    return _pass()
  else
    return _fail(tostring(label and label .. ': ' or '') .. "'" .. tostring(tostring(s)) .. "' ne correspond pas au pattern '" .. tostring(pattern) .. "'", 3)
  end
end
local raises
raises = function(fn, pattern, label)
  local success, err = pcall(fn)
  if success then
    return _fail(tostring(label and label .. ': ' or '') .. "aucune erreur levée", 3)
  elseif pattern and not tostring(err):match(pattern) then
    return _fail(tostring(label and label .. ': ' or '') .. "erreur '" .. tostring(err) .. "' ne correspond pas à '" .. tostring(pattern) .. "'", 3)
  else
    return _pass()
  end
end
local describe
describe = function(name, fn)
  local old_before = _state.before_all_fn
  local old_after = _state.after_all_fn
  local old_done = _state.before_all_done
  _state.current = name
  _state.before_all_fn = nil
  _state.after_all_fn = nil
  _state.before_all_done = false
  print("\n" .. tostring(name))
  fn()
  if _state.after_all_fn then
    _state.after_all_fn()
  end
  _state.before_all_fn = old_before
  _state.after_all_fn = old_after
  _state.before_all_done = old_done
end
local before_all
before_all = function(fn)
  _state.before_all_fn = fn
end
local after_all
after_all = function(fn)
  _state.after_all_fn = fn
end
local it
it = function(desc, fn)
  if _state.before_all_fn and not _state.before_all_done then
    _state.before_all_fn()
    _state.before_all_done = true
  end
  local before = _state.failed + _state.errors
  local success, err = pcall(fn)
  if not success then
    _state.errors = _state.errors + 1
    local location = loc(2)
    print("  ✗ ERREUR " .. tostring(desc))
    print("    [" .. tostring(location) .. "] " .. tostring(err))
    print("    Trace complète :")
    local level = 3
    while true do
      local info = debug.getinfo(level, 'Sl')
      if not info or info.currentline <= 0 then
        break
      end
      local src = info.short_src:gsub('.+/', '')
      print("      " .. tostring(src) .. ":" .. tostring(info.currentline))
      level = level + 1
    end
  elseif _state.failed + _state.errors == before then
    return print("  ✓ " .. tostring(desc))
  end
end
local summary
summary = function()
  local total = _state.passed + _state.failed + _state.errors
  print("\n══════════════════════════════════════")
  print(tostring(total) .. " assertions — " .. tostring(_state.passed) .. " ✓  " .. tostring(_state.failed) .. " ✗  " .. tostring(_state.errors) .. " erreurs")
  if _state.failed > 0 or _state.errors > 0 then
    print("RÉSULTAT: ÉCHEC")
    return 1
  end
  print("RÉSULTAT: SUCCÈS")
  return 0
end
return {
  describe = describe,
  it = it,
  before_all = before_all,
  after_all = after_all,
  eq = eq,
  ne = ne,
  ok = ok,
  nok = nok,
  is_nil = is_nil,
  matches = matches,
  raises = raises,
  summary = summary
}
