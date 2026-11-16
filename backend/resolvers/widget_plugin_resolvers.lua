local uuid_mod = require('uuid')
local clock = require('clock')
local yaml = require('yaml')
local scopes = require('core.widget_scopes')
local cv_widgets = require('resolvers.custom_view_widgets')
local plugin_compile = require('core.plugin_compile')
local require_auth, require_perm
do
  local _obj_0 = require('resolvers.utils')
  require_auth, require_perm = _obj_0.require_auth, _obj_0.require_perm
end
local VALID_SCRIPT_LANGS = {
  coffeescript = true,
  javascript = true,
  lua = true,
  moonscript = true
}
local VALID_TEMPLATE_LANGS = {
  pug = true,
  html = true
}
local MAX_NAME_LEN = 120
local MAX_DESC_LEN = 2000
local MAX_CODE_LEN = 200000
local NAME_PATTERN = "^[%a_\128-\255][%w_%-%.%(%) \128-\255]*$"
local NAME_ALLOWED = "[^%w_%-%.%(%) \128-\255]"
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
  if n:match('^%s' or n:match('%s$')) then
    error('WidgetPlugin name must not start or end with a space')
  end
  local ok = n:find(NAME_PATTERN)
  if not (ok) then
    error('WidgetPlugin name must match [A-Za-z_][A-Za-z0-9_-.() ]*')
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
local MAX_MANIFEST_LEN = 20000
local VALID_ACCESS = {
  none = true,
  read = true,
  full = true
}
local is_mapping
is_mapping = function(value)
  if not (type(value) == 'table') then
    return false
  end
  for key in pairs(value) do
    if type(key) == 'string' then
      return true
    end
  end
  return false
end
local is_sequence
is_sequence = function(value)
  return type(value) == 'table' and not is_mapping(value)
end
local manifest_error
manifest_error = function(msg)
  return error("WidgetPlugin manifest: " .. tostring(msg))
end
local manifest_name
manifest_name = function(entry, where)
  local name = entry.name
  if not (type(name) == 'string' and name ~= '') then
    manifest_error(tostring(where) .. ".name is required and must be a string")
  end
  if not (name:match('^[%a_][%w_%-]*$')) then
    manifest_error(tostring(where) .. ".name must match [A-Za-z_][A-Za-z0-9_-]*")
  end
  return name
end
local validate_manifest_entries
validate_manifest_entries = function(entries, field)
  if not (entries ~= nil) then
    return 
  end
  if not (is_sequence(entries)) then
    manifest_error(tostring(field) .. " must be a list of {name, type, ...} entries")
  end
  local seen = { }
  local index = 0
  for _index_0 = 1, #entries do
    local entry = entries[_index_0]
    index = index + 1
    local where = tostring(field) .. "[" .. tostring(index) .. "]"
    if not (is_mapping(entry)) then
      manifest_error(tostring(where) .. " must be a mapping like {name: titre, type: String}")
    end
    local name = manifest_name(entry, where)
    if seen[name] then
      local singular
      if field == 'columns' then
        singular = 'column'
      else
        singular = 'option'
      end
      manifest_error("duplicate " .. tostring(singular) .. " name: " .. tostring(name))
    end
    seen[name] = true
    if not (type(entry.type) == 'string' and entry.type ~= '') then
      manifest_error(tostring(where) .. ".type is required and must be a string")
    end
  end
  return nil
end
local validate_manifest_columns
validate_manifest_columns = function(columns)
  validate_manifest_entries(columns, 'columns')
  if not (columns ~= nil) then
    return 
  end
  local index = 0
  for _index_0 = 1, #columns do
    local entry = columns[_index_0]
    index = index + 1
    if entry.optional ~= nil and type(entry.optional) ~= 'boolean' then
      manifest_error("columns[" .. tostring(index) .. "].optional must be a boolean")
    end
  end
  return nil
end
local validate_manifest_options
validate_manifest_options = function(options)
  validate_manifest_entries(options, 'options')
  if not (options ~= nil) then
    return 
  end
  local index = 0
  for _index_0 = 1, #options do
    local entry = options[_index_0]
    index = index + 1
    local default = entry.default
    if default ~= nil and default ~= box.NULL then
      local t = type(default)
      if not (t == 'string' or t == 'number' or t == 'boolean') then
        manifest_error("options[" .. tostring(index) .. "].default must be a scalar")
      end
    end
  end
  return nil
end
local validate_manifest
validate_manifest = function(text)
  local raw
  if text == nil then
    raw = ''
  else
    raw = tostring(text)
  end
  if raw:match('^%s*$') then
    return ''
  end
  if #raw > MAX_MANIFEST_LEN then
    error("WidgetPlugin manifest too long: " .. tostring(#raw))
  end
  local ok, parsed = pcall(yaml.decode, raw)
  if not (ok) then
    manifest_error("invalid YAML: " .. tostring(tostring(parsed)))
  end
  if parsed == nil then
    return ''
  end
  if not (type(parsed) == 'table') then
    manifest_error('must be a YAML mapping (access, columns, options)')
  end
  if is_sequence(parsed) and next(parsed) ~= nil then
    manifest_error('must be a YAML mapping (access, columns, options)')
  end
  if parsed.access ~= nil and parsed.access ~= box.NULL then
    local access = tostring(parsed.access)
    if not (VALID_ACCESS[access]) then
      manifest_error("access must be one of none, read, full (got '" .. tostring(access) .. "')")
    end
  end
  validate_manifest_columns(parsed.columns)
  validate_manifest_options(parsed.options)
  return raw
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
    manifest = t[10] or '',
    appId = scopes.row_app_id(t),
    compiled = t[12] or '',
    createdAt = tostring(t[8]),
    updatedAt = tostring(t[9])
  }
end
local validate_app_scope
validate_app_scope = function(app_id)
  local scope = scopes.scope_of(app_id)
  if not (scope) then
    return nil
  end
  if not (box.space._tdb_apps:get(scope)) then
    error("Unknown app for widget scope: " .. tostring(scope))
  end
  return scope
end
local plugin_scope
plugin_scope = function(t)
  return scopes.row_app_id(t)
end
local assert_unique_name
assert_unique_name = function(name, ignore_id, app_id)
  local existing = scopes.find_row(name, app_id)
  if existing and existing[1] ~= ignore_id then
    return error("WidgetPlugin name already exists: " .. tostring(name))
  end
end
local get_widget_plugin
get_widget_plugin = function(id, name)
  local t = nil
  if id then
    t = box.space._tdb_widget_plugins:get(id)
  elseif name then
    local rows = box.space._tdb_widget_plugins.index.by_name:select({
      name,
      limit = 1
    })
    t = rows[1]
  end
  return tuple_to_plugin(t)
end
local create_widget_plugin
create_widget_plugin = function(input)
  local name = validate_name(input.name)
  local description = validate_description(input.description)
  local script_lang = validate_script_lang(input.scriptLanguage)
  local template_lang = validate_template_lang(input.templateLanguage)
  local script_code = validate_script_code(input.scriptCode)
  local template_code = validate_template_code(input.templateCode)
  local manifest = validate_manifest(input.manifest)
  local app_id = validate_app_scope(input.appId)
  local compiled = plugin_compile.compile_script(script_lang, script_code)
  assert_unique_name(name, nil, app_id)
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
    now,
    manifest,
    scopes.scope_column(app_id),
    compiled
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
  local manifest
  if input.manifest ~= nil then
    manifest = validate_manifest(input.manifest)
  else
    manifest = (t[10] or '')
  end
  local app_id
  if input.appId ~= nil then
    app_id = validate_app_scope(input.appId)
  else
    app_id = plugin_scope(t)
  end
  if scopes.scope_column(app_id) ~= scopes.scope_column(plugin_scope(t)) then
    local used = scopes.pages_using(t)
    if #used > 0 then
      error("WidgetPlugin '" .. tostring(t[2]) .. "' is used by page(s): " .. tostring(table.concat(used, ', ')) .. " — it cannot change scope")
    end
  end
  assert_unique_name(name, id, app_id)
  local compiled = plugin_compile.compile_script(script_lang, script_code)
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
    now,
    manifest,
    scopes.scope_column(app_id),
    compiled
  })
  return tuple_to_plugin(box.space._tdb_widget_plugins:get(id))
end
local delete_widget_plugin
delete_widget_plugin = function(id)
  local t = box.space._tdb_widget_plugins:get(id)
  if not (t) then
    error("WidgetPlugin not found: " .. tostring(id))
  end
  local used = scopes.pages_using(t)
  if not plugin_scope(t) and #used > 0 then
    error("WidgetPlugin '" .. tostring(t[2]) .. "' is used by page(s): " .. tostring(table.concat(used, ', ')))
  end
  box.space._tdb_widget_plugins:delete(id)
  return true
end
local sanitize_name
sanitize_name = function(text)
  local n = tostring(text or ''):gsub(NAME_ALLOWED, '_')
  n = n:gsub('%s+', ' ')
  n = n:match('^%s*(.-)%s*$')
  return n
end
local truncate_name
truncate_name = function(name, limit)
  if #name <= limit then
    return name
  end
  local cut = name:sub(1, limit)
  cut = cut:match('^(.*)%s' or cut)
  return cut:match('^(.-)%s*$')
end
local default_copy_name
default_copy_name = function(plugin_name, page_name)
  local base
  if type(page_name) == 'string' and page_name:match('%S') then
    base = tostring(plugin_name) .. " (" .. tostring(page_name) .. ")"
  else
    base = tostring(plugin_name) .. "_copie"
  end
  return sanitize_name(base)
end
local copy_name_for
copy_name_for = function(requested, plugin_name, page_name, app_id)
  local base = nil
  if type(requested) == 'string' and requested:match('%S') then
    base = validate_name(requested)
  else
    local candidate = truncate_name((default_copy_name(plugin_name, page_name)), MAX_NAME_LEN - 8)
    if candidate == '' then
      error('WidgetPlugin name is required')
    end
    if not (candidate:match('^[%a_\128-\255]')) then
      candidate = 'w_' .. candidate
    end
    base = validate_name(candidate)
  end
  return scopes.unique_name(base, app_id)
end
local copy_widget_plugin
copy_widget_plugin = function(source, name, app_id)
  return create_widget_plugin({
    name = name,
    description = source[3] or '',
    scriptLanguage = source[4] or 'coffeescript',
    templateLanguage = source[5] or 'pug',
    scriptCode = source[6] or '',
    templateCode = source[7] or '',
    manifest = source[10] or '',
    appId = app_id
  })
end
local detach_widget_plugin
detach_widget_plugin = function(page_id, widget_id, new_name)
  if page_id == nil or page_id == '' then
    error('pageId is required')
  end
  if widget_id == nil or widget_id == '' then
    error('widgetId is required')
  end
  local page = box.space._tdb_custom_views:get(page_id)
  if not (page) then
    error("Custom view not found: " .. tostring(page_id))
  end
  local node = cv_widgets.find_widget_in_text(page[4], widget_id)
  if not (node) then
    error("Widget not found in page '" .. tostring(page[2]) .. "': " .. tostring(widget_id))
  end
  local instance_type = node.type
  if not (type(instance_type) == 'string' and instance_type ~= '' and not scopes.BUILTIN_WIDGET_TYPES[instance_type]) then
    error("Widget '" .. tostring(widget_id) .. "' is not a custom widget")
  end
  local source = scopes.resolve_for_page(instance_type, page_id)
  if not (source) then
    error("Widget definition not found for type '" .. tostring(instance_type) .. "'")
  end
  local app_id = scopes.page_app_id(page_id)
  local copy_name = copy_name_for(new_name, source[2], page[2], app_id)
  local copy = copy_widget_plugin(source, copy_name, app_id)
  local ok, err = pcall(function()
    return cv_widgets.set_widget_type(page_id, widget_id, copy.name)
  end)
  if not (ok) then
    box.space._tdb_widget_plugins:delete(copy.id)
    error(tostring(err), 0)
  end
  return copy
end
local Query = {
  widgetPlugins = function(_, args, ctx)
    require_perm(ctx, '*', nil, 'read')
    local page_id = args.pageId
    if page_id then
      local page = box.space._tdb_custom_views:get(page_id)
      if not (page) then
        error("Custom view not found: " .. tostring(page_id))
      end
      local scope = scopes.page_app_id(page_id)
      local _accum_0 = { }
      local _len_0 = 1
      local _list_0 = scopes.visible_for_scope(scope)
      for _index_0 = 1, #_list_0 do
        local row = _list_0[_index_0]
        _accum_0[_len_0] = tuple_to_plugin(row)
        _len_0 = _len_0 + 1
      end
      return _accum_0
    end
    if args.appId ~= nil then
      local _accum_0 = { }
      local _len_0 = 1
      local _list_0 = scopes.visible_for_scope(scopes.scope_of(args.appId))
      for _index_0 = 1, #_list_0 do
        local row = _list_0[_index_0]
        _accum_0[_len_0] = tuple_to_plugin(row)
        _len_0 = _len_0 + 1
      end
      return _accum_0
    end
    local _accum_0 = { }
    local _len_0 = 1
    local _list_0 = scopes.all_rows()
    for _index_0 = 1, #_list_0 do
      local row = _list_0[_index_0]
      _accum_0[_len_0] = tuple_to_plugin(row)
      _len_0 = _len_0 + 1
    end
    return _accum_0
  end,
  widgetPlugin = function(_, args, ctx)
    require_perm(ctx, '*', nil, 'read')
    if args.pageId and args.name then
      local row = scopes.resolve_for_page(args.name, args.pageId)
      return tuple_to_plugin(row)
    end
    if not args.id and not args.name then
      error('widgetPlugin requires id or name')
    end
    return get_widget_plugin(args.id, args.name)
  end
}
local Mutation = {
  createWidgetPlugin = function(_, args, ctx)
    require_perm(ctx, '*', nil, 'admin')
    return create_widget_plugin(args.input or { })
  end,
  updateWidgetPlugin = function(_, args, ctx)
    require_perm(ctx, '*', nil, 'admin')
    return update_widget_plugin(args.id, args.input or { })
  end,
  deleteWidgetPlugin = function(_, args, ctx)
    require_perm(ctx, '*', nil, 'admin')
    return delete_widget_plugin(args.id)
  end,
  detachWidgetPlugin = function(_, args, ctx)
    require_perm(ctx, '*', nil, 'admin')
    return detach_widget_plugin(args.pageId, args.widgetId, args.newName)
  end
}
return {
  Query = Query,
  Mutation = Mutation,
  validate_manifest = validate_manifest
}
