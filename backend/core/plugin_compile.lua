local MAX_COMPILED_LEN = 400000
local line_of
line_of = function(err)
  local s = tostring(err)
  local line = s:match('line (%d+)')
  if not (line) then
    line = s:match(':(%d+):')
  end
  return line
end
local location_suffix
location_suffix = function(err)
  local line = line_of(err)
  if line then
    return " (ligne " .. tostring(line) .. ")"
  else
    return ''
  end
end
local compile_error
compile_error = function(language, err)
  return error("WidgetPlugin script: " .. tostring(language) .. " invalide" .. tostring(location_suffix(err)) .. " : " .. tostring(tostring(err)), 0)
end
local compile_lua
compile_lua = function(code)
  return code
end
local compile_moonscript
compile_moonscript = function(code)
  local ok, moon = pcall(require, 'moonscript.base')
  if not (ok) then
    error("WidgetPlugin script: compilateur MoonScript indisponible : " .. tostring(tostring(moon)), 0)
  end
  local lua, err = moon.to_lua(code)
  if not (lua and type(lua) == 'string') then
    compile_error('MoonScript', err or 'compilation impossible')
  end
  if #lua > MAX_COMPILED_LEN then
    error("WidgetPlugin script: code compilé trop long (" .. tostring(#lua) .. " > " .. tostring(MAX_COMPILED_LEN) .. ")")
  end
  return lua
end
local compile_script
compile_script = function(language, code)
  local source = tostring(code or '')
  local _exp_0 = string.lower(tostring(language or ''))
  if 'lua' == _exp_0 then
    return compile_lua(source)
  elseif 'moonscript' == _exp_0 then
    return compile_moonscript(source)
  else
    return ''
  end
end
return {
  compile_script = compile_script,
  MAX_COMPILED_LEN = MAX_COMPILED_LEN
}
