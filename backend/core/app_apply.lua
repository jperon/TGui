local json = require('json')
local uuid_mod = require('uuid')
local clock = require('clock')
local spaces_mod = require('core.spaces')
local views_mod = require('core.views')
local perms_mod = require('core.permissions')
local data_views = require('core.data_views')
local app_package = require('core.app_package')
local plan_update
plan_update = require('core.app_plan').plan_update
local TYPE_ORDER = {
  'space',
  'field',
  'relation',
  'view',
  'page',
  'dataview',
  'plugin',
  'group',
  'perm',
  'seed'
}
local TYPE_RANK
do
  local _tbl_0 = { }
  for i, t in ipairs(TYPE_ORDER) do
    _tbl_0[t] = i
  end
  TYPE_RANK = _tbl_0
end
local _scope_name
_scope_name = function(rest)
  local scope, name = rest:match('^(.*)%.([^%.]+)$')
  if not (scope and name and scope ~= '') then
    return nil
  end
  return app_package.unkey_part(scope), app_package.unkey_part(name)
end
local _after
_after = function(key, prefix)
  if not (type(key) == 'string' and key:sub(1, #prefix) == prefix) then
    return nil
  end
  local rest = key:sub(#prefix + 1)
  return rest ~= '' and rest or nil
end
local _split_scope
_split_scope = function(key, prefix)
  local rest = _after(key, prefix)
  if not (rest) then
    return nil
  end
  return _scope_name(rest)
end
local _normalize_item
_normalize_item = function(entry, errors)
  if not (type(entry) == 'table') then
    table.insert(errors, 'package item must be a table')
    return nil
  end
  if not (type(entry.type) == 'string' and app_package.ITEM_TYPES[entry.type]) then
    table.insert(errors, 'package item has an unknown type')
    return nil
  end
  if not (type(entry.key) == 'string' and entry.key ~= '') then
    table.insert(errors, "package item of type " .. tostring(entry.type) .. " is missing key")
    return nil
  end
  if not (type(entry.content) == 'table') then
    table.insert(errors, "package item " .. tostring(entry.key) .. " is missing content")
    return nil
  end
  local content = app_package.normalize_content(entry.type, app_package.strip_null(entry.content))
  local item = {
    type = entry.type,
    key = entry.key,
    content = content,
    fingerprint = app_package.fingerprint(content)
  }
  if entry.renamed_from then
    item.renamed_from = entry.renamed_from
  end
  return item
end
local _normalize
_normalize = function(package)
  local errors = { }
  local pkg = {
    app = { },
    items = { },
    seed_keys = { }
  }
  if not (type(package) == 'table') then
    table.insert(errors, 'package must be a table')
    return {
      package = pkg,
      errors = errors
    }
  end
  local app = package.app
  if type(app) == 'table' and type(app.id) == 'string' and app.id ~= '' then
    pkg.app = {
      id = app.id,
      name = app.name,
      version = app.version,
      description = app_package.strip_null(app.description) or ''
    }
  else
    table.insert(errors, 'package app id is required')
  end
  if not (type(package.items) == 'table') then
    table.insert(errors, 'package items must be a list')
    return {
      package = pkg,
      errors = errors
    }
  end
  local _list_0 = package.items
  for _index_0 = 1, #_list_0 do
    local entry = _list_0[_index_0]
    local item = _normalize_item(entry, errors)
    if item then
      table.insert(pkg.items, item)
    end
  end
  pkg.seed_keys = app_package.strip_null(package.seed_keys) or { }
  return {
    package = pkg,
    errors = errors
  }
end
local load_package
load_package = function(package)
  local normalized = _normalize(package)
  if #normalized.errors > 0 then
    return nil, table.concat(normalized.errors, '; ')
  end
  return normalized.package
end
local _read_installed
_read_installed = function(app_id)
  local result = { }
  if not (app_id) then
    return result
  end
  local _list_0 = box.space._tdb_app_items.index.by_app:select({
    app_id
  })
  for _index_0 = 1, #_list_0 do
    local t = _list_0[_index_0]
    result[t[2]] = {
      type = t[3],
      local_id = t[4],
      fingerprint = t[5],
      state = t[6],
      version = t[7]
    }
  end
  return result
end
local _installed_version
_installed_version = function(app_id)
  if not (app_id) then
    return nil
  end
  local t = box.space._tdb_apps:get(app_id)
  return t and t[3] or nil
end
local _local_state
_local_state = function(item_type, key)
  local content = app_package.describe_local(item_type, key)
  if not (content) then
    return nil
  end
  return {
    fingerprint = app_package.fingerprint(content),
    content = content
  }
end
local _space_renames
_space_renames = function(package, installed)
  local map = { }
  local _list_0 = package.items
  for _index_0 = 1, #_list_0 do
    local _continue_0 = false
    repeat
      local it = _list_0[_index_0]
      if not (it.type == 'space' and it.renamed_from) then
        _continue_0 = true
        break
      end
      if not (installed[it.renamed_from]) then
        _continue_0 = true
        break
      end
      local new_name = _after(it.key, 'space:')
      local old_name = _after(it.renamed_from, 'space:')
      if new_name then
        new_name = app_package.unkey_part(new_name)
      end
      if old_name then
        old_name = app_package.unkey_part(old_name)
      end
      if new_name and old_name then
        map[new_name] = old_name
      end
      _continue_0 = true
    until true
    if not _continue_0 then
      break
    end
  end
  return map
end
local _child_old_key
_child_old_key = function(key, space_renames)
  local _list_0 = {
    'field:',
    'relation:',
    'view:'
  }
  for _index_0 = 1, #_list_0 do
    local prefix = _list_0[_index_0]
    local scope, name = _split_scope(key, prefix)
    local old_scope = scope and space_renames[scope]
    if old_scope and name then
      return tostring(prefix) .. tostring(app_package.key_part(old_scope)) .. "." .. tostring(app_package.key_part(name))
    end
  end
  local rest = _after(key, 'seed:')
  if rest then
    local sep = rest:find('|')
    if sep then
      local scope = app_package.unkey_part(rest:sub(1, sep - 1))
      if space_renames[scope] then
        return "seed:" .. tostring(app_package.key_part(space_renames[scope])) .. tostring(rest:sub(sep))
      end
    end
  end
  return nil
end
local _expand_renames
_expand_renames = function(package, installed)
  local space_renames = _space_renames(package, installed)
  local items = { }
  local _list_0 = package.items
  for _index_0 = 1, #_list_0 do
    local _continue_0 = false
    repeat
      local it = _list_0[_index_0]
      if it.renamed_from and not installed[it.renamed_from] and installed[it.key] then
        table.insert(items, {
          type = it.type,
          key = it.key,
          content = it.content,
          fingerprint = it.fingerprint
        })
        _continue_0 = true
        break
      end
      if it.renamed_from or it.type == 'space' then
        table.insert(items, it)
        _continue_0 = true
        break
      end
      local old_key = _child_old_key(it.key, space_renames)
      if old_key and installed[old_key] then
        table.insert(items, {
          type = it.type,
          key = it.key,
          content = it.content,
          fingerprint = it.fingerprint,
          renamed_from = old_key
        })
      else
        table.insert(items, it)
      end
      _continue_0 = true
    until true
    if not _continue_0 then
      break
    end
  end
  return {
    app = package.app,
    items = items,
    seed_keys = package.seed_keys
  }
end
local _build_local_states
_build_local_states = function(package, installed)
  local types = { }
  local _list_0 = package.items
  for _index_0 = 1, #_list_0 do
    local it = _list_0[_index_0]
    if it.key then
      types[it.key] = it.type
    end
    if it.renamed_from then
      types[it.renamed_from] = it.type
    end
  end
  for key, info in pairs(installed) do
    types[key] = info.type
  end
  local states = { }
  for key, item_type in pairs(types) do
    local state = _local_state(item_type, key)
    if state then
      states[key] = state
    end
  end
  return states
end
local _error_plan
_error_plan = function(errors)
  return {
    create = { },
    update = { },
    conflict = { },
    keep_local = { },
    obsolete = { },
    rename = { },
    unchanged = { },
    errors = errors
  }
end
local _effective_opts
_effective_opts = function(app_id, opts)
  return {
    allow_downgrade = opts.allow_downgrade,
    installed_version = _installed_version(app_id) or opts.installed_version
  }
end
local preview_update
preview_update = function(package, opts)
  opts = opts or { }
  local normalized = _normalize(package)
  if #normalized.errors > 0 then
    return _error_plan(normalized.errors)
  end
  local pkg = normalized.package
  local installed = _read_installed(pkg.app.id)
  pkg = _expand_renames(pkg, installed)
  local local_states = _build_local_states(pkg, installed)
  return plan_update(installed, pkg, local_states, _effective_opts(pkg.app.id, opts))
end
local _order
_order = function(entries)
  local copy
  do
    local _accum_0 = { }
    local _len_0 = 1
    for _index_0 = 1, #entries do
      local e = entries[_index_0]
      _accum_0[_len_0] = e
      _len_0 = _len_0 + 1
    end
    copy = _accum_0
  end
  table.sort(copy, function(a, b)
    local ra = TYPE_RANK[a.type] or 99
    local rb = TYPE_RANK[b.type] or 99
    if ra ~= rb then
      return ra < rb
    else
      return a.key < b.key
    end
  end)
  return copy
end
local _order_conflicts
_order_conflicts = function(conflicts)
  local copy
  do
    local _accum_0 = { }
    local _len_0 = 1
    for _index_0 = 1, #conflicts do
      local c = conflicts[_index_0]
      _accum_0[_len_0] = c
      _len_0 = _len_0 + 1
    end
    copy = _accum_0
  end
  table.sort(copy, function(a, b)
    local ra = TYPE_RANK[a[1].type] or 99
    local rb = TYPE_RANK[b[1].type] or 99
    if ra ~= rb then
      return ra < rb
    else
      return a[1].key < b[1].key
    end
  end)
  return copy
end
local _effective_old
_effective_old = function(ctx, entry)
  return ctx.installed[entry.key] or (entry.renamed_from and ctx.installed[entry.renamed_from])
end
local _skip
_skip = function(entry, report)
  return false
end
local _check_decisions
_check_decisions = function(conflicts, decisions)
  for _index_0 = 1, #conflicts do
    local _continue_0 = false
    repeat
      local c = conflicts[_index_0]
      local entry = c[1]
      if entry.type == 'seed' then
        _continue_0 = true
        break
      end
      local d = decisions[entry.key]
      if not (d == 'local' or d == 'delivered') then
        return "conflict on '" .. tostring(entry.key) .. "' requires a decision ('local' or 'delivered')"
      end
      _continue_0 = true
    until true
    if not _continue_0 then
      break
    end
  end
  return nil
end
local _empty_report
_empty_report = function()
  return {
    ok = false,
    error = nil,
    reinit_error = nil,
    created = { },
    updated = { },
    unchanged = { },
    kept = { },
    obsolete = { },
    skipped = { },
    conflicts = { }
  }
end
local _abort
_abort = function(report, errors)
  report.ok = false
  report.error = table.concat(errors, '; ')
  return report
end
local _space_id
_space_id = function(name)
  local sp = spaces_mod.get_space_by_name(name)
  if not (sp) then
    error("unknown space '" .. tostring(name) .. "'")
  end
  return sp.id
end
local _field_id
_field_id = function(space_id, field_name)
  local _list_0 = spaces_mod.list_fields(space_id)
  for _index_0 = 1, #_list_0 do
    local f = _list_0[_index_0]
    if f.name == field_name then
      return f.id
    end
  end
  return error("unknown field '" .. tostring(field_name) .. "'")
end
local _resource_name
_resource_name = function(resource_id)
  if resource_id == nil or resource_id == perms_mod.WILDCARD_ID then
    return '*'
  end
  local t = box.space._tdb_spaces:get(resource_id)
  return t and t[2] or resource_id
end
local _find_group_by_name
_find_group_by_name = function(name)
  local _list_0 = perms_mod.list_groups()
  for _index_0 = 1, #_list_0 do
    local g = _list_0[_index_0]
    if g.name == name then
      return g
    end
  end
  return nil
end
local _resolve_field_id
_resolve_field_id = function(key)
  local rest = _after(key, 'field:')
  if not (rest) then
    return nil
  end
  local sp_name, f_name = _scope_name(rest)
  local sp = sp_name and spaces_mod.get_space_by_name(sp_name)
  if not (sp) then
    return nil
  end
  local _list_0 = spaces_mod.list_fields(sp.id)
  for _index_0 = 1, #_list_0 do
    local f = _list_0[_index_0]
    if f.name == f_name then
      return f.id
    end
  end
  return nil
end
local _resolve_relation_id
_resolve_relation_id = function(key)
  local rest = _after(key, 'relation:')
  if not (rest) then
    return nil
  end
  local sp_name, f_name = _scope_name(rest)
  local sp = sp_name and spaces_mod.get_space_by_name(sp_name)
  if not (sp) then
    return nil
  end
  local _list_0 = box.space._tdb_relations.index.by_from:select({
    sp.id
  })
  for _index_0 = 1, #_list_0 do
    local t = _list_0[_index_0]
    local fld = box.space._tdb_fields:get(t[3])
    if fld and fld[3] == f_name then
      return t[1]
    end
  end
  return nil
end
local _resolve_view_id
_resolve_view_id = function(key)
  local rest = _after(key, 'view:')
  if not (rest) then
    return nil
  end
  local sp_name, v_name = _scope_name(rest)
  local sp = sp_name and spaces_mod.get_space_by_name(sp_name)
  if not (sp) then
    return nil
  end
  local _list_0 = views_mod.list_views(sp.id)
  for _index_0 = 1, #_list_0 do
    local v = _list_0[_index_0]
    if v.name == v_name then
      return v.id
    end
  end
  return nil
end
local _resolve_perm_id
_resolve_perm_id = function(key)
  local rest = _after(key, 'perm:')
  if not (rest) then
    return nil
  end
  local parts
  do
    local _accum_0 = { }
    local _len_0 = 1
    for p in rest:gmatch('[^|]+') do
      _accum_0[_len_0] = p
      _len_0 = _len_0 + 1
    end
    parts = _accum_0
  end
  if not (#parts == 4) then
    return nil
  end
  local group_name = app_package.unkey_part(parts[1])
  local rtype = app_package.unkey_part(parts[2])
  local res = app_package.unkey_part(parts[3])
  local lvl = app_package.unkey_part(parts[4])
  local group = _find_group_by_name(group_name)
  if not (group) then
    return nil
  end
  local _list_0 = perms_mod.list_permissions(group.id)
  for _index_0 = 1, #_list_0 do
    local p = _list_0[_index_0]
    local match = p.resourceType == rtype and p.level == lvl
    if match and _resource_name(p.resourceId) == res then
      return p.id
    end
  end
  return nil
end
local _page_by_name
_page_by_name = function(name)
  local _list_0 = box.space._tdb_custom_views:select({ })
  for _index_0 = 1, #_list_0 do
    local row = _list_0[_index_0]
    if row[2] == name then
      return row
    end
  end
  return nil
end
local _resolve_page_id
_resolve_page_id = function(key)
  local name = _after(key, 'page:')
  local row = name and _page_by_name(app_package.unkey_part(name))
  return row and row[1]
end
local _resolve_dataview_id
_resolve_dataview_id = function(key)
  local name = _after(key, 'dataview:')
  local v = name and data_views.get_view_by_name(app_package.unkey_part(name))
  return v and v.id
end
local _resolve_plugin_id
_resolve_plugin_id = function(key)
  local name = _after(key, 'plugin:')
  local row = name and box.space._tdb_widget_plugins.index.by_name:get(app_package.unkey_part(name))
  return row and row[1]
end
local _resolve_group_id
_resolve_group_id = function(key)
  local name = _after(key, 'group:')
  local g = name and _find_group_by_name(app_package.unkey_part(name))
  return g and g.id
end
local _resolve_local_id
_resolve_local_id = function(item_type, key)
  if not (key) then
    return nil
  end
  if item_type == 'space' then
    local name = _after(key, 'space:')
    local sp = name and spaces_mod.get_space_by_name(app_package.unkey_part(name))
    return sp and sp.id
  end
  if item_type == 'field' then
    return _resolve_field_id(key)
  end
  if item_type == 'relation' then
    return _resolve_relation_id(key)
  end
  if item_type == 'view' then
    return _resolve_view_id(key)
  end
  if item_type == 'page' then
    return _resolve_page_id(key)
  end
  if item_type == 'dataview' then
    return _resolve_dataview_id(key)
  end
  if item_type == 'plugin' then
    return _resolve_plugin_id(key)
  end
  if item_type == 'group' then
    return _resolve_group_id(key)
  end
  if item_type == 'perm' then
    return _resolve_perm_id(key)
  end
  return nil
end
local _create_space
_create_space = function(entry)
  local name = app_package.unkey_part(_after(entry.key, 'space:'))
  local sp = spaces_mod.create_user_space(name, entry.content.description or '')
  return {
    id = sp.id,
    space = name
  }
end
local _update_space
_update_space = function(entry, old)
  local t = box.space._tdb_spaces:get(old.local_id)
  if not (t) then
    error("space not found: " .. tostring(old.local_id))
  end
  box.space._tdb_spaces:replace({
    t[1],
    t[2],
    entry.content.description or '',
    t[4],
    os.time()
  })
  return {
    id = t[1],
    space = t[2]
  }
end
local _create_field
_create_field = function(entry)
  local rest = _after(entry.key, 'field:')
  local sp_name, f_name = _scope_name(rest)
  if not (sp_name) then
    error("invalid field key '" .. tostring(entry.key) .. "'")
  end
  local sid = _space_id(sp_name)
  local c = entry.content
  local f = spaces_mod.add_field(sid, f_name, c.fieldType, c.notNull or false, c.description or '', c.formula or '', c.triggerFields or { }, c.language or 'lua')
  return {
    id = f.id,
    space = sp_name
  }
end
local _update_field
_update_field = function(entry, old)
  local rest = _after(entry.key, 'field:')
  local sp_name, f_name = _scope_name(rest)
  local fid = old.local_id
  local t = box.space._tdb_fields:get(fid)
  if not (t) then
    error("field not found: " .. tostring(tostring(fid)))
  end
  local c = entry.content
  if c.fieldType and t[4] ~= c.fieldType then
    spaces_mod.change_field_type(fid, c.fieldType)
  end
  spaces_mod.update_field(fid, {
    notNull = c.notNull,
    description = c.description,
    formula = c.formula or '',
    triggerFields = c.triggerFields or { },
    language = c.language
  })
  return {
    id = fid,
    space = sp_name
  }
end
local _relations_have_cardinality
_relations_have_cardinality = function()
  local fmt = box.space._tdb_relations:format()
  return fmt ~= nil and #fmt >= 8
end
local _cardinality
_cardinality = function(value)
  if value == 'many' then
    return 'many'
  end
  return 'one'
end
local _create_relation
_create_relation = function(entry)
  local rest = _after(entry.key, 'relation:')
  local from_sp, from_fld = _scope_name(rest)
  if not (from_sp) then
    error("invalid relation key '" .. tostring(entry.key) .. "'")
  end
  local c = entry.content
  local from_sid = _space_id(from_sp)
  local to_sid = _space_id(c.toSpace)
  local from_fid = _field_id(from_sid, from_fld)
  local to_fid = _field_id(to_sid, c.toField)
  local rid = tostring(uuid_mod.new())
  local tuple = {
    rid,
    from_sid,
    from_fid,
    to_sid,
    to_fid,
    tostring(from_sp) .. "_" .. tostring(from_fld),
    ''
  }
  if _relations_have_cardinality() then
    table.insert(tuple, _cardinality(c.cardinality))
  end
  box.space._tdb_relations:insert(tuple)
  return {
    id = rid,
    space = from_sp
  }
end
local _update_relation
_update_relation = function(entry, old)
  local rest = _after(entry.key, 'relation:')
  local from_sp, from_fld = _scope_name(rest)
  local c = entry.content
  local to_sid = _space_id(c.toSpace)
  local to_fid = _field_id(to_sid, c.toField)
  local ops = {
    {
      '=',
      4,
      to_sid
    },
    {
      '=',
      5,
      to_fid
    }
  }
  if _relations_have_cardinality() then
    table.insert(ops, {
      '=',
      8,
      _cardinality(c.cardinality)
    })
  end
  box.space._tdb_relations:update(old.local_id, ops)
  return {
    id = old.local_id,
    space = from_sp
  }
end
local _create_view
_create_view = function(entry)
  local c = entry.content
  local sid = _space_id(c.space)
  local v = views_mod.create_view(sid, c.name, c.viewType, c.config)
  return {
    id = v.id,
    space = c.space
  }
end
local _update_view
_update_view = function(entry, old)
  local c = entry.content
  views_mod.update_view(old.local_id, {
    name = c.name,
    viewType = c.viewType,
    config = c.config
  })
  return {
    id = old.local_id,
    space = c.space
  }
end
local _create_page
_create_page = function(entry)
  local c = entry.content
  local id = tostring(uuid_mod.new())
  local now = clock.time()
  box.space._tdb_custom_views:insert({
    id,
    c.name,
    c.description or '',
    c.yaml or '',
    now,
    now
  })
  return {
    id = id
  }
end
local _update_page
_update_page = function(entry, old)
  local c = entry.content
  box.space._tdb_custom_views:update(old.local_id, {
    {
      '=',
      3,
      c.description or ''
    },
    {
      '=',
      4,
      c.yaml or ''
    },
    {
      '=',
      6,
      clock.time()
    }
  })
  return {
    id = old.local_id
  }
end
local _config_json
_config_json = function(config)
  if config == nil then
    return '{}'
  end
  if type(config) == 'string' then
    return config
  end
  return json.encode(config)
end
local _create_dataview
_create_dataview = function(entry)
  local c = entry.content
  local sid = _space_id(c.sourceSpace)
  local v = data_views.create_view(c.name, c.description or '', sid, _config_json(c.config))
  return {
    id = v.id
  }
end
local _update_dataview
_update_dataview = function(entry, old)
  local c = entry.content
  local sid = _space_id(c.sourceSpace)
  data_views.update_view(old.local_id, {
    name = c.name,
    description = c.description or '',
    sourceSpace = sid,
    config = _config_json(c.config)
  })
  return {
    id = old.local_id
  }
end
local _create_plugin
_create_plugin = function(entry)
  local c = entry.content
  local id = tostring(uuid_mod.new())
  local now = clock.time()
  box.space._tdb_widget_plugins:insert({
    id,
    c.name,
    c.description or '',
    c.scriptLanguage or 'coffeescript',
    c.templateLanguage or 'pug',
    c.scriptCode or '',
    c.templateCode or '',
    now,
    now
  })
  return {
    id = id
  }
end
local _update_plugin
_update_plugin = function(entry, old)
  local c = entry.content
  box.space._tdb_widget_plugins:update(old.local_id, {
    {
      '=',
      3,
      c.description or ''
    },
    {
      '=',
      4,
      c.scriptLanguage or 'coffeescript'
    },
    {
      '=',
      5,
      c.templateLanguage or 'pug'
    },
    {
      '=',
      6,
      c.scriptCode or ''
    },
    {
      '=',
      7,
      c.templateCode or ''
    },
    {
      '=',
      9,
      clock.time()
    }
  })
  return {
    id = old.local_id
  }
end
local _create_group
_create_group = function(entry)
  local c = entry.content
  local g = perms_mod.create_group(c.name, c.description)
  return {
    id = g.id
  }
end
local _update_group
_update_group = function(entry, old)
  box.space._tdb_groups:update(old.local_id, {
    {
      '=',
      3,
      entry.content.description or ''
    }
  })
  return {
    id = old.local_id
  }
end
local _resource_id
_resource_id = function(resource)
  if resource == nil or resource == '' or resource == '*' then
    return perms_mod.WILDCARD_ID
  end
  local sp = spaces_mod.get_space_by_name(resource)
  return sp and sp.id or resource
end
local _create_perm
_create_perm = function(entry)
  local c = entry.content
  local group = _find_group_by_name(c.group)
  if not (group) then
    error("unknown group '" .. tostring(c.group) .. "'")
  end
  local p = perms_mod.grant(group.id, c.resourceType or 'space', _resource_id(c.resource), c.level)
  return {
    id = p.id
  }
end
local EXECUTORS = {
  space = {
    create = _create_space,
    update = _update_space
  },
  field = {
    create = _create_field,
    update = _update_field
  },
  relation = {
    create = _create_relation,
    update = _update_relation
  },
  view = {
    create = _create_view,
    update = _update_view
  },
  page = {
    create = _create_page,
    update = _update_page
  },
  dataview = {
    create = _create_dataview,
    update = _update_dataview
  },
  plugin = {
    create = _create_plugin,
    update = _update_plugin
  },
  group = {
    create = _create_group,
    update = _update_group
  },
  perm = {
    create = _create_perm
  }
}
local _record
_record = function(app_id, version, item_type, key, local_id, fingerprint, state)
  return box.space._tdb_app_items:replace({
    app_id,
    key,
    item_type,
    local_id or '',
    fingerprint,
    state or 'actif',
    version
  })
end
local _record_kept
_record_kept = function(ctx, entry, old, fingerprint)
  local local_id = old and old.local_id or _resolve_local_id(entry.type, entry.key)
  return _record(ctx.pkg.app.id, ctx.pkg.app.version, entry.type, entry.key, local_id, fingerprint, 'actif')
end
local _do_creates
_do_creates = function(ctx)
  local _list_0 = _order(ctx.plan.create)
  for _index_0 = 1, #_list_0 do
    local _continue_0 = false
    repeat
      local entry = _list_0[_index_0]
      if _skip(entry, ctx.report) then
        _continue_0 = true
        break
      end
      if entry.type == 'seed' then
        _continue_0 = true
        break
      end
      local ex = EXECUTORS[entry.type]
      if not (ex and ex.create) then
        error("unsupported type '" .. tostring(entry.type) .. "'")
      end
      local result = ex.create(entry)
      _record(ctx.pkg.app.id, ctx.pkg.app.version, entry.type, entry.key, result.id, entry.fingerprint, 'actif')
      table.insert(ctx.report.created, entry.key)
      if result.space then
        ctx.touched[result.space] = true
      end
      _continue_0 = true
    until true
    if not _continue_0 then
      break
    end
  end
end
local _do_updates
_do_updates = function(ctx)
  local _list_0 = _order(ctx.plan.update)
  for _index_0 = 1, #_list_0 do
    local _continue_0 = false
    repeat
      local entry = _list_0[_index_0]
      if _skip(entry, ctx.report) then
        _continue_0 = true
        break
      end
      if entry.type == 'seed' then
        _continue_0 = true
        break
      end
      local old = _effective_old(ctx, entry)
      if not (old) then
        error("cannot update unknown item '" .. tostring(entry.key) .. "'")
      end
      local ex = EXECUTORS[entry.type]
      if not (ex and ex.update) then
        error("unsupported type '" .. tostring(entry.type) .. "'")
      end
      local result = ex.update(entry, old)
      _record(ctx.pkg.app.id, ctx.pkg.app.version, entry.type, entry.key, result.id, entry.fingerprint, 'actif')
      table.insert(ctx.report.updated, entry.key)
      if result.space then
        ctx.touched[result.space] = true
      end
      _continue_0 = true
    until true
    if not _continue_0 then
      break
    end
  end
end
local _do_conflicts
_do_conflicts = function(ctx)
  local _list_0 = _order_conflicts(ctx.plan.conflict)
  for _index_0 = 1, #_list_0 do
    local _continue_0 = false
    repeat
      local c = _list_0[_index_0]
      local entry = c[1]
      if _skip(entry, ctx.report) then
        _continue_0 = true
        break
      end
      if entry.type == 'seed' then
        _continue_0 = true
        break
      end
      local old = _effective_old(ctx, entry)
      local resolution = ctx.decisions[entry.key]
      if resolution == 'delivered' then
        local ex = EXECUTORS[entry.type]
        if not (ex and ex.update) then
          error("unsupported type '" .. tostring(entry.type) .. "'")
        end
        local result = ex.update(entry, old)
        _record(ctx.pkg.app.id, ctx.pkg.app.version, entry.type, entry.key, result.id, entry.fingerprint, 'actif')
        if result.space then
          ctx.touched[result.space] = true
        end
      else
        _record_kept(ctx, entry, old, entry.fingerprint)
      end
      table.insert(ctx.report.conflicts, {
        key = entry.key,
        resolution = resolution
      })
      _continue_0 = true
    until true
    if not _continue_0 then
      break
    end
  end
end
local _do_keep_local
_do_keep_local = function(ctx)
  local _list_0 = _order(ctx.plan.keep_local)
  for _index_0 = 1, #_list_0 do
    local _continue_0 = false
    repeat
      local entry = _list_0[_index_0]
      if _skip(entry, ctx.report) then
        _continue_0 = true
        break
      end
      if entry.type == 'seed' then
        _continue_0 = true
        break
      end
      _record_kept(ctx, entry, _effective_old(ctx, entry), entry.fingerprint)
      table.insert(ctx.report.kept, entry.key)
      _continue_0 = true
    until true
    if not _continue_0 then
      break
    end
  end
end
local _do_unchanged
_do_unchanged = function(ctx)
  local _list_0 = ctx.plan.unchanged
  for _index_0 = 1, #_list_0 do
    local _continue_0 = false
    repeat
      local key = _list_0[_index_0]
      local item = ctx.pkg_map[key]
      if not (item) then
        _continue_0 = true
        break
      end
      if item.type == 'seed' then
        _continue_0 = true
        break
      end
      local old = _effective_old(ctx, item)
      local local_id = old and old.local_id or _resolve_local_id(item.type, key)
      _record(ctx.pkg.app.id, ctx.pkg.app.version, item.type, key, local_id, item.fingerprint, 'actif')
      table.insert(ctx.report.unchanged, key)
      _continue_0 = true
    until true
    if not _continue_0 then
      break
    end
  end
end
local _decode
_decode = function(blob)
  if type(blob) == 'table' then
    return blob
  end
  if not (type(blob) == 'string') then
    return { }
  end
  local ok, d = pcall(json.decode, blob)
  return (ok and type(d) == 'table') and d or { }
end
local _find_seed_id
_find_seed_id = function(ctx, entry)
  local c = entry.content
  local key_field = ctx.pkg.seed_keys[c.space]
  local sp = box.space["data_" .. tostring(c.space)]
  if not (sp and key_field) then
    return nil
  end
  local _list_0 = sp:select({ })
  for _index_0 = 1, #_list_0 do
    local t = _list_0[_index_0]
    local v = _decode(t[2])[key_field]
    if v ~= nil and tostring(v) == tostring(c.key) then
      return t[1]
    end
  end
  return nil
end
local _seed_local_id
_seed_local_id = function(ctx, entry, old)
  if old and old.local_id and old.local_id ~= '' then
    local sp = box.space["data_" .. tostring(entry.content.space)]
    if sp and sp:get(old.local_id) then
      return old.local_id
    end
  end
  return _find_seed_id(ctx, entry)
end
local _seed_create
_seed_create = function(ctx, entry)
  local c = entry.content
  local sp = box.space["data_" .. tostring(c.space)]
  if not (sp) then
    error("unknown seed space '" .. tostring(c.space) .. "'")
  end
  local id = tostring(uuid_mod.new())
  sp:insert({
    id,
    json.encode(c.data)
  })
  _record(ctx.pkg.app.id, ctx.pkg.app.version, 'seed', entry.key, id, entry.fingerprint, 'actif')
  table.insert(ctx.report.created, entry.key)
  ctx.seed_spaces = ctx.seed_spaces or { }
  ctx.seed_spaces[c.space] = true
end
local _seed_update
_seed_update = function(ctx, entry, old)
  local c = entry.content
  local sp = box.space["data_" .. tostring(c.space)]
  if not (sp) then
    error("unknown seed space '" .. tostring(c.space) .. "'")
  end
  local id = _seed_local_id(ctx, entry, old)
  if id then
    sp:replace({
      id,
      json.encode(c.data)
    })
  else
    id = tostring(uuid_mod.new())
    sp:insert({
      id,
      json.encode(c.data)
    })
  end
  _record(ctx.pkg.app.id, ctx.pkg.app.version, 'seed', entry.key, id, entry.fingerprint, 'actif')
  table.insert(ctx.report.updated, entry.key)
  ctx.seed_spaces = ctx.seed_spaces or { }
  ctx.seed_spaces[c.space] = true
end
local _seed_keep
_seed_keep = function(ctx, entry, old)
  local id = _seed_local_id(ctx, entry, old)
  _record(ctx.pkg.app.id, ctx.pkg.app.version, 'seed', entry.key, id or '', entry.fingerprint, 'actif')
  return table.insert(ctx.report.kept, entry.key)
end
local _seed_unchanged
_seed_unchanged = function(ctx, entry)
  local old = _effective_old(ctx, entry)
  local id = (old and old.local_id) or _find_seed_id(ctx, entry)
  _record(ctx.pkg.app.id, ctx.pkg.app.version, 'seed', entry.key, id or '', entry.fingerprint, 'actif')
  return table.insert(ctx.report.unchanged, entry.key)
end
local _bump_sequences
_bump_sequences = function(space_name)
  local meta = spaces_mod.get_space_by_name(space_name)
  local data_sp = box.space["data_" .. tostring(space_name)]
  if not (meta and data_sp) then
    return 
  end
  local _list_0 = spaces_mod.list_fields(meta.id)
  for _index_0 = 1, #_list_0 do
    local _continue_0 = false
    repeat
      local f = _list_0[_index_0]
      if not (f.fieldType == 'Sequence') then
        _continue_0 = true
        break
      end
      local seq = box.sequence["_tdb_seq_" .. tostring(f.id)]
      if not (seq) then
        _continue_0 = true
        break
      end
      local max_val = 0
      local _list_1 = data_sp:select({ })
      for _index_1 = 1, #_list_1 do
        local t = _list_1[_index_1]
        local v = _decode(t[2])[f.name]
        if type(v) == 'number' and v > max_val then
          max_val = v
        end
      end
      local n = seq:next()
      if n <= max_val then
        seq:set(max_val)
      end
      _continue_0 = true
    until true
    if not _continue_0 then
      break
    end
  end
end
local _do_seeds
_do_seeds = function(ctx)
  local _list_0 = _order(ctx.plan.create)
  for _index_0 = 1, #_list_0 do
    local entry = _list_0[_index_0]
    if entry.type == 'seed' then
      _seed_create(ctx, entry)
    end
  end
  local _list_1 = _order(ctx.plan.update)
  for _index_0 = 1, #_list_1 do
    local entry = _list_1[_index_0]
    if entry.type == 'seed' then
      _seed_update(ctx, entry, _effective_old(ctx, entry))
    end
  end
  local _list_2 = _order_conflicts(ctx.plan.conflict)
  for _index_0 = 1, #_list_2 do
    local c = _list_2[_index_0]
    if c[1].type == 'seed' then
      _seed_keep(ctx, c[1], _effective_old(ctx, c[1]))
    end
  end
  local _list_3 = _order(ctx.plan.keep_local)
  for _index_0 = 1, #_list_3 do
    local entry = _list_3[_index_0]
    if entry.type == 'seed' then
      _seed_keep(ctx, entry, _effective_old(ctx, entry))
    end
  end
  local _list_4 = ctx.plan.unchanged
  for _index_0 = 1, #_list_4 do
    local key = _list_4[_index_0]
    local item = ctx.pkg_map[key]
    if item and item.type == 'seed' then
      _seed_unchanged(ctx, item)
    end
  end
  for space_name, _ in pairs((ctx.seed_spaces or { })) do
    _bump_sequences(space_name)
  end
end
local _remap_child_key
_remap_child_key = function(key, old_name, new_name)
  local _list_0 = {
    'field:',
    'relation:',
    'view:'
  }
  for _index_0 = 1, #_list_0 do
    local prefix = _list_0[_index_0]
    local rest = _after(key, tostring(prefix) .. tostring(app_package.key_part(old_name)) .. ".")
    if rest then
      return tostring(prefix) .. tostring(app_package.key_part(new_name)) .. "." .. tostring(rest)
    end
  end
  local rest = _after(key, "seed:" .. tostring(app_package.key_part(old_name)) .. "|")
  if rest then
    return "seed:" .. tostring(app_package.key_part(new_name)) .. "|" .. tostring(rest)
  end
  return nil
end
local _remap_child_tracking
_remap_child_tracking = function(app_id, old_name, new_name)
  local rows = box.space._tdb_app_items.index.by_app:select({
    app_id
  })
  for _index_0 = 1, #rows do
    local _continue_0 = false
    repeat
      local t = rows[_index_0]
      local new_key = _remap_child_key(t[2], old_name, new_name)
      if not (new_key) then
        _continue_0 = true
        break
      end
      box.space._tdb_app_items:delete({
        t[1],
        t[2]
      })
      box.space._tdb_app_items:replace({
        t[1],
        new_key,
        t[3],
        t[4],
        t[5],
        t[6],
        t[7]
      })
      _continue_0 = true
    until true
    if not _continue_0 then
      break
    end
  end
end
local _delete_tracking
_delete_tracking = function(app_id, key)
  return box.space._tdb_app_items:delete({
    app_id,
    key
  })
end
local _rename_space
_rename_space = function(ctx, from_key, to_key)
  local old_name = _after(from_key, 'space:')
  local new_name = _after(to_key, 'space:')
  if not (old_name and new_name) then
    return 
  end
  old_name = app_package.unkey_part(old_name)
  new_name = app_package.unkey_part(new_name)
  local data_sp = box.space["data_" .. tostring(old_name)]
  if data_sp then
    data_sp:rename("data_" .. tostring(new_name))
  end
  local meta = spaces_mod.get_space_by_name(old_name)
  if meta then
    box.space._tdb_spaces:update(meta.id, {
      {
        '=',
        2,
        new_name
      },
      {
        '=',
        5,
        os.time()
      }
    })
  end
  _remap_child_tracking(ctx.pkg.app.id, old_name, new_name)
  return _delete_tracking(ctx.pkg.app.id, from_key)
end
local _rename_record_key
_rename_record_key = function(sp, old_key, new_key)
  local _list_0 = sp:select({ })
  for _index_0 = 1, #_list_0 do
    local row = _list_0[_index_0]
    local d = _decode(row[2])
    if d[old_key] ~= nil then
      d[new_key] = d[old_key]
      d[old_key] = nil
      sp:replace({
        row[1],
        json.encode(d)
      })
    end
  end
end
local _rename_field
_rename_field = function(ctx, from_key, to_key)
  local f_scope, f_name = _split_scope(from_key, 'field:')
  local t_scope, t_name = _split_scope(to_key, 'field:')
  if f_scope == t_scope and f_name ~= t_name then
    local old = ctx.installed[from_key]
    local fid = old and old.local_id
    if fid and box.space._tdb_fields:get(fid) then
      spaces_mod.update_field(fid, {
        name = t_name
      })
      local sp = box.space["data_" .. tostring(f_scope)]
      if sp then
        _rename_record_key(sp, f_name, t_name)
      end
    end
  end
  return _delete_tracking(ctx.pkg.app.id, from_key)
end
local _rename_row_name
_rename_row_name = function(space_name, id, name_col, new_name)
  local t = id and box.space[space_name]:get(id)
  if t then
    return box.space[space_name]:update(id, {
      {
        '=',
        name_col,
        new_name
      }
    })
  end
end
local _rename_view
_rename_view = function(ctx, from_key, to_key)
  local f_scope, f_name = _split_scope(from_key, 'view:')
  local t_scope, t_name = _split_scope(to_key, 'view:')
  local old = ctx.installed[from_key]
  if old and f_scope == t_scope and f_name ~= t_name then
    _rename_row_name('_tdb_views', old.local_id, 3, t_name)
  end
  return _delete_tracking(ctx.pkg.app.id, from_key)
end
local _rename_page
_rename_page = function(ctx, from_key, to_key)
  local name = app_package.unkey_part(_after(to_key, 'page:'))
  local old = ctx.installed[from_key]
  _rename_row_name('_tdb_custom_views', old and old.local_id, 2, name)
  return _delete_tracking(ctx.pkg.app.id, from_key)
end
local _rename_dataview
_rename_dataview = function(ctx, from_key, to_key)
  local name = app_package.unkey_part(_after(to_key, 'dataview:'))
  local old = ctx.installed[from_key]
  _rename_row_name('_tdb_data_views', old and old.local_id, 2, name)
  return _delete_tracking(ctx.pkg.app.id, from_key)
end
local _rename_plugin
_rename_plugin = function(ctx, from_key, to_key)
  local name = app_package.unkey_part(_after(to_key, 'plugin:'))
  local old = ctx.installed[from_key]
  _rename_row_name('_tdb_widget_plugins', old and old.local_id, 2, name)
  return _delete_tracking(ctx.pkg.app.id, from_key)
end
local _rename_group
_rename_group = function(ctx, from_key, to_key)
  local name = app_package.unkey_part(_after(to_key, 'group:'))
  local old = ctx.installed[from_key]
  _rename_row_name('_tdb_groups', old and old.local_id, 2, name)
  return _delete_tracking(ctx.pkg.app.id, from_key)
end
local _do_rename
_do_rename = function(ctx, from_key, to_key)
  local old = ctx.installed[from_key]
  if not (old) then
    return 
  end
  local _exp_0 = old.type
  if 'space' == _exp_0 then
    return _rename_space(ctx, from_key, to_key)
  elseif 'field' == _exp_0 then
    return _rename_field(ctx, from_key, to_key)
  elseif 'view' == _exp_0 then
    return _rename_view(ctx, from_key, to_key)
  elseif 'page' == _exp_0 then
    return _rename_page(ctx, from_key, to_key)
  elseif 'dataview' == _exp_0 then
    return _rename_dataview(ctx, from_key, to_key)
  elseif 'plugin' == _exp_0 then
    return _rename_plugin(ctx, from_key, to_key)
  elseif 'group' == _exp_0 then
    return _rename_group(ctx, from_key, to_key)
  else
    return _delete_tracking(ctx.pkg.app.id, from_key)
  end
end
local _do_renames
_do_renames = function(ctx)
  local renames
  do
    local _accum_0 = { }
    local _len_0 = 1
    local _list_0 = ctx.plan.rename
    for _index_0 = 1, #_list_0 do
      local p = _list_0[_index_0]
      _accum_0[_len_0] = p
      _len_0 = _len_0 + 1
    end
    renames = _accum_0
  end
  table.sort(renames, function(a, b)
    local ta = ctx.installed[a[1]] and ctx.installed[a[1]].type
    local tb = ctx.installed[b[1]] and ctx.installed[b[1]].type
    local ra = TYPE_RANK[ta] or 99
    local rb = TYPE_RANK[tb] or 99
    if ra ~= rb then
      return ra < rb
    else
      return a[1] < b[1]
    end
  end)
  for _index_0 = 1, #renames do
    local pair = renames[_index_0]
    _do_rename(ctx, pair[1], pair[2])
  end
end
local _check_renames
_check_renames = function(plan, pkg_map)
  local _list_0 = plan.rename
  for _index_0 = 1, #_list_0 do
    local _continue_0 = false
    repeat
      local pair = _list_0[_index_0]
      local target = pair[2]
      local item = pkg_map[target]
      local itype = item and item.type
      if not (itype) then
        _continue_0 = true
        break
      end
      if app_package.describe_local(itype, target) then
        return "rename target '" .. tostring(target) .. "' already exists locally"
      end
      _continue_0 = true
    until true
    if not _continue_0 then
      break
    end
  end
  return nil
end
local _do_obsolete
_do_obsolete = function(ctx)
  local _list_0 = ctx.plan.obsolete
  for _index_0 = 1, #_list_0 do
    local _continue_0 = false
    repeat
      local key = _list_0[_index_0]
      local old = ctx.installed[key]
      if not (old) then
        _continue_0 = true
        break
      end
      _record(ctx.pkg.app.id, (old.version or ctx.pkg.app.version), old.type, key, old.local_id, old.fingerprint, 'obsolète')
      _continue_0 = true
    until true
    if not _continue_0 then
      break
    end
  end
end
local _write_app
_write_app = function(app, opts)
  local existing = box.space._tdb_apps:get(app.id)
  local source = opts.source or (existing and existing[5]) or 'package'
  local name = app.name or (existing and existing[2]) or ''
  local version = app.version or (existing and existing[3]) or ''
  return box.space._tdb_apps:replace({
    app.id,
    name,
    version,
    os.time(),
    source
  })
end
local _transaction
_transaction = function(ctx)
  box.begin()
  _do_renames(ctx)
  _do_creates(ctx)
  _do_updates(ctx)
  _do_conflicts(ctx)
  _do_keep_local(ctx)
  _do_unchanged(ctx)
  _do_seeds(ctx)
  _do_obsolete(ctx)
  _write_app(ctx.pkg.app, ctx.opts)
  return box.commit()
end
local _do_apply
_do_apply = function(plan, pkg, pkg_map, decisions, opts, installed, report)
  local ctx = {
    plan = plan,
    pkg = pkg,
    pkg_map = pkg_map,
    decisions = decisions,
    opts = opts,
    installed = installed,
    report = report,
    touched = { }
  }
  local ok, err = pcall(_transaction, ctx)
  if not (ok) then
    pcall(function()
      if box.is_in_txn() then
        return box.rollback()
      end
    end)
    return tostring(err)
  end
  report.touched = ctx.touched
  return nil
end
local _finalize
_finalize = function(report, touched)
  local executor = require('graphql.executor')
  local triggers = require('core.triggers')
  local ok, err = pcall(function()
    executor.reinit_schema()
    return triggers.invalidate_formula_cache()
  end)
  if not (ok) then
    report.reinit_error = tostring(err)
  end
  for name, _ in pairs(touched) do
    pcall(triggers.register_space_trigger, name)
  end
end
local _normalize_keys
_normalize_keys = function(keys)
  if type(keys) == 'string' then
    return {
      keys
    }
  end
  return keys or { }
end
local _purge_rows
_purge_rows = function(app_id, keys)
  local rows = { }
  local _list_0 = _normalize_keys(keys)
  for _index_0 = 1, #_list_0 do
    local key = _list_0[_index_0]
    local t = box.space._tdb_app_items:get({
      app_id,
      key
    })
    if not (t) then
      return nil, "unknown app item '" .. tostring(key) .. "' for app '" .. tostring(app_id) .. "'"
    end
    if not (t[6] == 'obsolète') then
      return nil, "item '" .. tostring(key) .. "' is not obsolete (state=" .. tostring(t[6]) .. "); only obsolete installed items can be purged"
    end
    table.insert(rows, {
      key = t[2],
      type = t[3],
      local_id = t[4]
    })
  end
  return rows, nil
end
local _relation_touching_count
_relation_touching_count = function(sid)
  local seen = { }
  local n = 0
  local _list_0 = box.space._tdb_relations.index.by_from:select({
    sid
  })
  for _index_0 = 1, #_list_0 do
    local t = _list_0[_index_0]
    if not (seen[t[1]]) then
      n = n + 1
    end
    seen[t[1]] = true
  end
  local _list_1 = box.space._tdb_relations.index.by_to:select({
    sid
  })
  for _index_0 = 1, #_list_1 do
    local t = _list_1[_index_0]
    if not (seen[t[1]]) then
      n = n + 1
    end
    seen[t[1]] = true
  end
  return n
end
local _views_referencing_count
_views_referencing_count = function(name, sid)
  local n = 0
  local _list_0 = views_mod.list_views(sid)
  for _index_0 = 1, #_list_0 do
    local _ = _list_0[_index_0]
    n = n + 1
  end
  local _list_1 = box.space._tdb_data_views:select({ })
  for _index_0 = 1, #_list_1 do
    local t = _list_1[_index_0]
    if t[4] == sid or t[4] == name then
      n = n + 1
    end
  end
  local _list_2 = box.space._tdb_custom_views:select({ })
  for _index_0 = 1, #_list_2 do
    local row = _list_2[_index_0]
    if row[4] and row[4]:find(name, 1, true) then
      n = n + 1
    end
  end
  return n
end
local _field_value_count
_field_value_count = function(key)
  local scope, name = _split_scope(key, 'field:')
  local sp = scope and box.space["data_" .. tostring(scope)]
  if not (sp and name) then
    return 0
  end
  local n = 0
  local _list_0 = sp:select({ })
  for _index_0 = 1, #_list_0 do
    local t = _list_0[_index_0]
    if _decode(t[2])[name] ~= nil then
      n = n + 1
    end
  end
  return n
end
local _loss_for
_loss_for = function(row)
  local loss = {
    key = row.key,
    type = row.type,
    records = 0,
    fields = 0,
    relations = 0,
    views = 0
  }
  if row.type == 'field' then
    loss.records = _field_value_count(row.key)
  elseif row.type == 'space' then
    local name = app_package.unkey_part(_after(row.key, 'space:'))
    local sp = name and spaces_mod.get_space_by_name(name)
    if sp then
      local data_sp = box.space["data_" .. tostring(name)]
      loss.records = data_sp and #data_sp:select({ }) or 0
      loss.fields = #spaces_mod.list_fields(sp.id)
      loss.relations = _relation_touching_count(sp.id)
      loss.views = _views_referencing_count(name, sp.id)
    end
  end
  return loss
end
local preview_purge
preview_purge = function(app_id, keys)
  local rows, err = _purge_rows(app_id, keys)
  if err then
    return {
      error = err,
      losses = { },
      total_records = 0
    }
  end
  local losses = { }
  local total = 0
  for _index_0 = 1, #rows do
    local row = rows[_index_0]
    local loss = _loss_for(row)
    table.insert(losses, loss)
    total = total + loss.records
  end
  return {
    losses = losses,
    total_records = total,
    error = nil
  }
end
local _is_child_of_space
_is_child_of_space = function(key, name)
  local _list_0 = {
    'field:',
    'relation:',
    'view:'
  }
  for _index_0 = 1, #_list_0 do
    local prefix = _list_0[_index_0]
    if _after(key, tostring(prefix) .. tostring(app_package.key_part(name)) .. ".") then
      return true
    end
  end
  return _after(key, "seed:" .. tostring(app_package.key_part(name)) .. "|") ~= nil
end
local _delete_space_children
_delete_space_children = function(app_id, name)
  local rows = box.space._tdb_app_items.index.by_app:select({
    app_id
  })
  for _index_0 = 1, #rows do
    local t = rows[_index_0]
    if _is_child_of_space(t[2], name) then
      box.space._tdb_app_items:delete({
        t[1],
        t[2]
      })
    end
  end
end
local _remove_record_key
_remove_record_key = function(sp, field_name)
  local _list_0 = sp:select({ })
  for _index_0 = 1, #_list_0 do
    local t = _list_0[_index_0]
    local d = _decode(t[2])
    if d[field_name] ~= nil then
      d[field_name] = nil
      sp:replace({
        t[1],
        json.encode(d)
      })
    end
  end
end
local _purge_field
_purge_field = function(row)
  local scope, name = _split_scope(row.key, 'field:')
  if row.local_id and box.space._tdb_fields:get(row.local_id) then
    spaces_mod.remove_field(row.local_id)
  end
  local sp = scope and box.space["data_" .. tostring(scope)]
  if sp and name then
    return _remove_record_key(sp, name)
  end
end
local _purge_space
_purge_space = function(ctx, row)
  local name = app_package.unkey_part(_after(row.key, 'space:'))
  if name then
    spaces_mod.delete_user_space(name)
  end
  if name then
    return _delete_space_children(ctx.app_id, name)
  end
end
local _purge_seed
_purge_seed = function(row)
  local rest = _after(row.key, 'seed:')
  if not (rest) then
    return 
  end
  local sep = rest:find('|')
  if not (sep) then
    return 
  end
  local sp = box.space["data_" .. tostring(app_package.unkey_part(rest:sub(1, sep - 1)))]
  if sp and row.local_id and row.local_id ~= '' then
    return sp:delete(row.local_id)
  end
end
local _purge_one
_purge_one = function(ctx, row)
  if not (row.local_id and row.local_id ~= '') then
    error("missing local_id for '" .. tostring(row.key) .. "'")
  end
  local _exp_0 = row.type
  if 'field' == _exp_0 then
    return _purge_field(row)
  elseif 'space' == _exp_0 then
    return _purge_space(ctx, row)
  elseif 'relation' == _exp_0 then
    return box.space._tdb_relations:delete(row.local_id)
  elseif 'view' == _exp_0 then
    return box.space._tdb_views:delete(row.local_id)
  elseif 'page' == _exp_0 then
    return box.space._tdb_custom_views:delete(row.local_id)
  elseif 'dataview' == _exp_0 then
    return box.space._tdb_data_views:delete(row.local_id)
  elseif 'plugin' == _exp_0 then
    return box.space._tdb_widget_plugins:delete(row.local_id)
  elseif 'group' == _exp_0 then
    return perms_mod.delete_group(row.local_id)
  elseif 'perm' == _exp_0 then
    return box.space._tdb_permissions:delete(row.local_id)
  elseif 'seed' == _exp_0 then
    return _purge_seed(row)
  else
    return error("unsupported purge type '" .. tostring(row.type) .. "'")
  end
end
local _purge_transaction
_purge_transaction = function(app_id, rows)
  local ordered
  do
    local _accum_0 = { }
    local _len_0 = 1
    for _index_0 = 1, #rows do
      local r = rows[_index_0]
      _accum_0[_len_0] = r
      _len_0 = _len_0 + 1
    end
    ordered = _accum_0
  end
  table.sort(ordered, function(a, b)
    local ra = TYPE_RANK[a.type] or 99
    local rb = TYPE_RANK[b.type] or 99
    if ra ~= rb then
      return ra < rb
    else
      return a.key < b.key
    end
  end)
  box.begin()
  local ctx = {
    app_id = app_id
  }
  for _index_0 = 1, #ordered do
    local row = ordered[_index_0]
    _purge_one(ctx, row)
  end
  for _index_0 = 1, #rows do
    local row = rows[_index_0]
    _delete_tracking(app_id, row.key)
  end
  return box.commit()
end
local purge_obsolete
purge_obsolete = function(app_id, keys, opts)
  opts = opts or { }
  local report = {
    ok = false,
    purged = { },
    error = nil
  }
  if not (opts.confirmed == true) then
    report.error = 'confirmation required'
    return report
  end
  local rows, err = _purge_rows(app_id, keys)
  if err then
    report.error = err
    return report
  end
  local ok, err2 = pcall(_purge_transaction, app_id, rows)
  if not (ok) then
    pcall(function()
      if box.is_in_txn() then
        return box.rollback()
      end
    end)
    report.error = tostring(err2)
    return report
  end
  report.ok = true
  report.purged = keys
  _finalize(report, { })
  return report
end
local apply_update
apply_update = function(package, decisions, opts)
  decisions = decisions or { }
  opts = opts or { }
  local report = _empty_report()
  local normalized = _normalize(package)
  if #normalized.errors > 0 then
    return _abort(report, normalized.errors)
  end
  local pkg = normalized.package
  local installed = _read_installed(pkg.app.id)
  pkg = _expand_renames(pkg, installed)
  local pkg_map = { }
  local _list_0 = pkg.items
  for _index_0 = 1, #_list_0 do
    local it = _list_0[_index_0]
    pkg_map[it.key] = it
  end
  local local_states = _build_local_states(pkg, installed)
  local plan = plan_update(installed, pkg, local_states, _effective_opts(pkg.app.id, opts))
  if #plan.errors > 0 then
    return _abort(report, plan.errors)
  end
  local rename_error = _check_renames(plan, pkg_map)
  if rename_error then
    return _abort(report, {
      rename_error
    })
  end
  local conflict_error = _check_decisions(plan.conflict, decisions)
  if conflict_error then
    return _abort(report, {
      conflict_error
    })
  end
  local _list_1 = plan.obsolete
  for _index_0 = 1, #_list_1 do
    local key = _list_1[_index_0]
    table.insert(report.obsolete, key)
  end
  local err = _do_apply(plan, pkg, pkg_map, decisions, opts, installed, report)
  if err then
    return _abort(report, {
      err
    })
  end
  report.ok = true
  _finalize(report, report.touched)
  return report
end
return {
  load_package = load_package,
  preview_update = preview_update,
  apply_update = apply_update,
  preview_purge = preview_purge,
  purge_obsolete = purge_obsolete
}
