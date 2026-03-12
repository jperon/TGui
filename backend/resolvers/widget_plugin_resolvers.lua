local uuid_mod = require('uuid')
local clock = require('clock')
local require_auth
require_auth = require('resolvers.utils').require_auth
local VALID_SCRIPT_LANGS = {
  coffeescript = true,
  javascript = true
}
local VALID_TEMPLATE_LANGS = {
  pug = true,
  html = true
}
local MAX_NAME_LEN = 120
local MAX_DESC_LEN = 2000
local MAX_CODE_LEN = 200000
local normalize_script_lang
normalize_script_lang = function(lang)
  local l = tostring(lang or 'coffeescript')
  return string.lower(l)
end
local normalize_template_lang
normalize_template_lang = function(lang)
  local l = tostring(lang or 'pug')
  return string.lower(l)
end
local validate_name
validate_name = function(name)
  local n = tostring(name or '')
  if n == '' then
    error('WidgetPlugin name is required')
  end
  if #n > MAX_NAME_LEN then
    error("WidgetPlugin name too long: " .. tostring(#n))
  end
  local ok = n:find('^[%a_][%w_%-]*$')
  if not (ok) then
    error('WidgetPlugin name must match [A-Za-z_][A-Za-z0-9_-]*')
  end
  return n
end
local validate_description
validate_description = function(description)
  local d = tostring(description or '')
  if #d > MAX_DESC_LEN then
    error("WidgetPlugin description too long: " .. tostring(#d))
  end
  return d
end
local validate_script_code
validate_script_code = function(code)
  local c = tostring(code or '')
  if c == '' then
    error('WidgetPlugin scriptCode is required')
  end
  if #c > MAX_CODE_LEN then
    error("WidgetPlugin scriptCode too long: " .. tostring(#c))
  end
  return c
end
local validate_template_code
validate_template_code = function(code)
  local c = tostring(code or '')
  if c == '' then
    error('WidgetPlugin templateCode is required')
  end
  if #c > MAX_CODE_LEN then
    error("WidgetPlugin templateCode too long: " .. tostring(#c))
  end
  return c
end
local validate_script_lang
validate_script_lang = function(lang)
  local l = normalize_script_lang(lang)
  if not (VALID_SCRIPT_LANGS[l]) then
    error("Unsupported script language: " .. tostring(l))
  end
  return l
end
local validate_template_lang
validate_template_lang = function(lang)
  local l = normalize_template_lang(lang)
  if not (VALID_TEMPLATE_LANGS[l]) then
    error("Unsupported template language: " .. tostring(l))
  end
  return l
end
local tuple_to_plugin
tuple_to_plugin = function(t)
  if not (t) then
    return nil
  end
  return {
    id = t[1],
    name = t[2],
    description = t[3] or '',
    scriptLanguage = t[4] or 'coffeescript',
    templateLanguage = t[5] or 'pug',
    scriptCode = t[6] or '',
    templateCode = t[7] or '',
    createdAt = tostring(t[8]),
    updatedAt = tostring(t[9])
  }
end
local list_widget_plugins
list_widget_plugins = function()
  local result = { }
  local _list_0 = box.space._tdb_widget_plugins:select({ })
  for _index_0 = 1, #_list_0 do
    local t = _list_0[_index_0]
    table.insert(result, tuple_to_plugin(t))
  end
  table.sort(result, function(a, b)
    return a.name < b.name
  end)
  return result
end
local get_widget_plugin
get_widget_plugin = function(id, name)
  local t = nil
  if id then
    t = box.space._tdb_widget_plugins:get(id)
  elseif name then
    t = box.space._tdb_widget_plugins.index.by_name:get(name)
  end
  return tuple_to_plugin(t)
end
local assert_unique_name
assert_unique_name = function(name, ignore_id)
  if ignore_id == nil then
    ignore_id = nil
  end
  local existing = box.space._tdb_widget_plugins.index.by_name:get(name)
  if existing and existing[1] ~= ignore_id then
    return error("WidgetPlugin name already exists: " .. tostring(name))
  end
end
local create_widget_plugin
create_widget_plugin = function(input)
  local name = validate_name(input.name)
  local description = validate_description(input.description)
  local script_lang = validate_script_lang(input.scriptLanguage)
  local template_lang = validate_template_lang(input.templateLanguage)
  local script_code = validate_script_code(input.scriptCode)
  local template_code = validate_template_code(input.templateCode)
  assert_unique_name(name)
  local id = tostring(uuid_mod.new())
  local now = clock.time()
  box.space._tdb_widget_plugins:insert({
    id,
    name,
    description,
    script_lang,
    template_lang,
    script_code,
    template_code,
    now,
    now
  })
  return tuple_to_plugin(box.space._tdb_widget_plugins:get(id))
end
local update_widget_plugin
update_widget_plugin = function(id, input)
  local t = box.space._tdb_widget_plugins:get(id)
  if not (t) then
    error("WidgetPlugin not found: " .. tostring(id))
  end
  local name
  if input.name ~= nil then
    name = validate_name(input.name)
  else
    name = t[2]
  end
  local description
  if input.description ~= nil then
    description = validate_description(input.description)
  else
    description = (t[3] or '')
  end
  local script_lang
  if input.scriptLanguage ~= nil then
    script_lang = validate_script_lang(input.scriptLanguage)
  else
    script_lang = (t[4] or 'coffeescript')
  end
  local template_lang
  if input.templateLanguage ~= nil then
    template_lang = validate_template_lang(input.templateLanguage)
  else
    template_lang = (t[5] or 'pug')
  end
  local script_code
  if input.scriptCode ~= nil then
    script_code = validate_script_code(input.scriptCode)
  else
    script_code = (t[6] or '')
  end
  local template_code
  if input.templateCode ~= nil then
    template_code = validate_template_code(input.templateCode)
  else
    template_code = (t[7] or '')
  end
  assert_unique_name(name, id)
  local now = clock.time()
  box.space._tdb_widget_plugins:replace({
    id,
    name,
    description,
    script_lang,
    template_lang,
    script_code,
    template_code,
    t[8],
    now
  })
  return tuple_to_plugin(box.space._tdb_widget_plugins:get(id))
end
local delete_widget_plugin
delete_widget_plugin = function(id)
  box.space._tdb_widget_plugins:delete(id)
  return true
end
local Query = {
  widgetPlugins = function(_, args, ctx)
    require_auth(ctx)
    return list_widget_plugins()
  end,
  widgetPlugin = function(_, args, ctx)
    require_auth(ctx)
    if not args.id and not args.name then
      error('widgetPlugin requires id or name')
    end
    return get_widget_plugin(args.id, args.name)
  end
}
local Mutation = {
  createWidgetPlugin = function(_, args, ctx)
    require_auth(ctx)
    return create_widget_plugin(args.input or { })
  end,
  updateWidgetPlugin = function(_, args, ctx)
    require_auth(ctx)
    return update_widget_plugin(args.id, args.input or { })
  end,
  deleteWidgetPlugin = function(_, args, ctx)
    require_auth(ctx)
    return delete_widget_plugin(args.id)
  end
}
return {
  Query = Query,
  Mutation = Mutation
}
