local json = require('json')
local digest = require('digest')
local spaces_mod = require('core.spaces')
local views_mod = require('core.views')
local perms_mod = require('core.permissions')
local ITEM_TYPES = {
  space = 'space',
  field = 'field',
  relation = 'relation',
  view = 'view',
  page = 'page',
  dataview = 'dataview',
  plugin = 'plugin',
  group = 'group',
  perm = 'perm',
  seed = 'seed'
}
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
local BUILTIN_GROUPS = {
  admin = true
}
local array_len
array_len = function(t)
  local count = 0
  local max = 0
  for k, _ in pairs(t) do
    if not (type(k) == 'number' and k == math.floor(k) and k >= 1) then
      return nil
    end
    count = count + 1
    if k > max then
      max = k
    end
  end
  if max ~= count then
    return nil
  end
  return count
end
local encode_scalar
encode_scalar = function(v)
  local ok, encoded = pcall(json.encode, v)
  if ok then
    return encoded
  end
  if type(v) == 'string' then
    return string.format('%q', v)
  end
  return 'null'
end
local canonical = nil
local canonical_array
canonical_array = function(t, len)
  local parts = { }
  for i = 1, len do
    table.insert(parts, canonical(t[i]))
  end
  return "[" .. tostring(table.concat(parts, ',')) .. "]"
end
local canonical_object
canonical_object = function(t)
  local keys
  do
    local _accum_0 = { }
    local _len_0 = 1
    for k, _ in pairs(t) do
      _accum_0[_len_0] = k
      _len_0 = _len_0 + 1
    end
    keys = _accum_0
  end
  table.sort(keys, function(a, b)
    return tostring(a) < tostring(b)
  end)
  local parts = { }
  for _index_0 = 1, #keys do
    local k = keys[_index_0]
    table.insert(parts, tostring(encode_scalar(tostring(k))) .. ":" .. tostring(canonical(t[k])))
  end
  return "{" .. tostring(table.concat(parts, ',')) .. "}"
end
canonical = function(value)
  local t = type(value)
  if t == 'table' then
    local len = array_len(value)
    if len ~= nil then
      return canonical_array(value, len)
    else
      return canonical_object(value)
    end
  elseif t == 'nil' then
    return 'null'
  else
    return encode_scalar(value)
  end
end
local fingerprint
fingerprint = function(content)
  return digest.sha256_hex(canonical(content))
end
local decode_record
decode_record = function(blob)
  if type(blob) == 'table' then
    return blob
  end
  if not (type(blob) == 'string') then
    return { }
  end
  local ok, decoded = pcall(json.decode, blob)
  if ok and type(decoded) == 'table' then
    return decoded
  else
    return { }
  end
end
local decode_config
decode_config = function(raw)
  if not (type(raw) == 'string') then
    return raw
  end
  local trimmed = raw:match('^%s*(.-)%s*$')
  local first = trimmed:sub(1, 1)
  if not (first == '{' or first == '[') then
    return raw
  end
  local ok, decoded = pcall(json.decode, raw)
  if ok and type(decoded) == 'table' then
    return decoded
  else
    return raw
  end
end
local space_name_by_id
space_name_by_id = function(sid)
  local t = box.space._tdb_spaces:get(sid)
  return t and t[2] or nil
end
local field_name_by_id
field_name_by_id = function(fid)
  local t = box.space._tdb_fields:get(fid)
  return t and t[3] or nil
end
local resolve_space_name
resolve_space_name = function(value)
  if value == nil or value == '' then
    return ''
  end
  local by_id = space_name_by_id(value)
  if by_id then
    return by_id
  end
  if spaces_mod.get_space_by_name(value) then
    return value
  end
  return value
end
local resource_name
resource_name = function(rid)
  if rid == nil or rid == perms_mod.WILDCARD_ID then
    return '*'
  end
  return resolve_space_name(rid)
end
local stable_key
stable_key = function(v)
  local t = type(v)
  if t == 'string' or t == 'number' or t == 'boolean' then
    return v
  end
end
local space_content
space_content = function(sp)
  return {
    description = sp.description or ''
  }
end
local field_content
field_content = function(f)
  local content = {
    fieldType = f.fieldType,
    notNull = f.notNull == true,
    description = f.description or '',
    formula = f.formula or '',
    language = f.language or 'lua'
  }
  if f.triggerFields ~= nil then
    content.triggerFields = f.triggerFields
  end
  return content
end
local relation_cardinality
relation_cardinality = function(value)
  if value == 'many' then
    return 'many'
  end
  return 'one'
end
local relation_content
relation_content = function(from_space, from_field, to_space, to_field, cardinality)
  return {
    fromSpace = from_space,
    fromField = from_field,
    toSpace = to_space,
    toField = to_field,
    cardinality = relation_cardinality(cardinality)
  }
end
local view_content
view_content = function(space_name, v)
  return {
    space = space_name,
    name = v.name,
    viewType = v.viewType,
    config = decode_config(v.config)
  }
end
local page_content
page_content = function(row)
  return {
    name = row[2],
    description = row[3] or '',
    yaml = row[4] or ''
  }
end
local dataview_content
dataview_content = function(row)
  return {
    name = row[2],
    description = row[3] or '',
    sourceSpace = resolve_space_name(row[4]),
    config = decode_config(row[5])
  }
end
local plugin_content
plugin_content = function(row)
  return {
    name = row[2],
    description = row[3] or '',
    scriptLanguage = row[4] or 'coffeescript',
    templateLanguage = row[5] or 'pug',
    scriptCode = row[6] or '',
    templateCode = row[7] or ''
  }
end
local group_content
group_content = function(g)
  return {
    name = g.name,
    description = g.description or ''
  }
end
local perm_content
perm_content = function(group_name, p)
  return {
    group = group_name,
    resourceType = p.resourceType,
    resource = resource_name(p.resourceId),
    level = p.level
  }
end
local seed_content
seed_content = function(space_name, key, data)
  return {
    space = space_name,
    key = key,
    data = data
  }
end
local strip_null
strip_null = function(value)
  if value == box.NULL then
    return nil
  end
  if not (type(value) == 'table') then
    return value
  end
  local result = { }
  local len = array_len(value)
  if len ~= nil then
    for i = 1, len do
      local v = strip_null(value[i])
      if v ~= nil then
        table.insert(result, v)
      end
    end
  else
    for k, v in pairs(value) do
      local sv = strip_null(v)
      if sv ~= nil then
        result[k] = sv
      end
    end
  end
  return result
end
local _nonempty_or
_nonempty_or = function(value, default)
  if value == nil or value == '' then
    return default
  end
  return value
end
local _table_or_empty
_table_or_empty = function(value)
  return (type(value) == 'table') and value or { }
end
local _normalize_space_content
_normalize_space_content = function(c)
  return {
    description = c.description or ''
  }
end
local _normalize_field_content
_normalize_field_content = function(c)
  local content = {
    fieldType = c.fieldType,
    notNull = c.notNull == true,
    description = c.description or '',
    formula = c.formula or '',
    language = _nonempty_or(c.language, 'lua')
  }
  if type(c.triggerFields) == 'table' then
    content.triggerFields = c.triggerFields
  end
  return content
end
local _normalize_relation_content
_normalize_relation_content = function(c)
  return {
    fromSpace = c.fromSpace,
    fromField = c.fromField,
    toSpace = c.toSpace,
    toField = c.toField,
    cardinality = relation_cardinality(c.cardinality)
  }
end
local _normalize_view_content
_normalize_view_content = function(c)
  return {
    space = c.space,
    name = c.name,
    viewType = c.viewType,
    config = decode_config(c.config)
  }
end
local _normalize_page_content
_normalize_page_content = function(c)
  return {
    name = c.name,
    description = c.description or '',
    yaml = c.yaml or ''
  }
end
local _normalize_dataview_content
_normalize_dataview_content = function(c)
  return {
    name = c.name,
    description = c.description or '',
    sourceSpace = resolve_space_name(c.sourceSpace),
    config = decode_config(c.config)
  }
end
local _normalize_plugin_content
_normalize_plugin_content = function(c)
  return {
    name = c.name,
    description = c.description or '',
    scriptLanguage = _nonempty_or(c.scriptLanguage, 'coffeescript'),
    templateLanguage = _nonempty_or(c.templateLanguage, 'pug'),
    scriptCode = c.scriptCode or '',
    templateCode = c.templateCode or ''
  }
end
local _normalize_group_content
_normalize_group_content = function(c)
  return {
    name = c.name,
    description = c.description or ''
  }
end
local _normalize_perm_content
_normalize_perm_content = function(c)
  return {
    group = c.group,
    resourceType = c.resourceType,
    resource = resource_name(c.resource),
    level = c.level
  }
end
local _normalize_seed_content
_normalize_seed_content = function(c)
  return {
    space = c.space,
    key = c.key,
    data = _table_or_empty(c.data)
  }
end
local CONTENT_NORMALIZERS = {
  space = _normalize_space_content,
  field = _normalize_field_content,
  relation = _normalize_relation_content,
  view = _normalize_view_content,
  page = _normalize_page_content,
  dataview = _normalize_dataview_content,
  plugin = _normalize_plugin_content,
  group = _normalize_group_content,
  perm = _normalize_perm_content,
  seed = _normalize_seed_content
}
local normalize_content
normalize_content = function(item_type, content)
  if not (type(content) == 'table') then
    return content
  end
  local normalizer = CONTENT_NORMALIZERS[item_type]
  if not (normalizer) then
    return content
  end
  return normalizer(content)
end
local strip_prefix
strip_prefix = function(key, prefix)
  if not (type(key) == 'string' and key:sub(1, #prefix) == prefix) then
    return nil
  end
  local rest = key:sub(#prefix + 1)
  if rest == '' then
    return nil
  end
  return rest
end
local key_part
key_part = function(s)
  s = tostring(s)
  s = s:gsub('%%', '%%25')
  s = s:gsub('%.', '%%2E')
  s = s:gsub('%|', '%%7C')
  s = s:gsub(':', '%%3A')
  return s
end
local unkey_part
unkey_part = function(s)
  s = tostring(s)
  s = s:gsub('%%3A', ':')
  s = s:gsub('%%7C', '|')
  s = s:gsub('%%2E', '.')
  s = s:gsub('%%25', '%%')
  return s
end
local split_scope_name
split_scope_name = function(rest)
  local scope, name = rest:match('^(.*)%.([^%.]+)$')
  if not (scope and name and scope ~= '') then
    return nil
  end
  return unkey_part(scope), unkey_part(name)
end
local split_pipes
split_pipes = function(rest)
  local parts = { }
  for piece in rest:gmatch('[^|]+') do
    table.insert(parts, piece)
  end
  return parts
end
local sorted_spaces
sorted_spaces = function()
  local list = spaces_mod.list_spaces()
  table.sort(list, function(a, b)
    return a.name < b.name
  end)
  return list
end
local collect_spaces_and_fields
collect_spaces_and_fields = function(space_bucket, field_bucket, space_list)
  for _index_0 = 1, #space_list do
    local sp = space_list[_index_0]
    table.insert(space_bucket, {
      type = ITEM_TYPES.space,
      key = "space:" .. tostring(key_part(sp.name)),
      content = space_content(sp)
    })
    local _list_0 = spaces_mod.list_fields(sp.id)
    for _index_1 = 1, #_list_0 do
      local f = _list_0[_index_1]
      table.insert(field_bucket, {
        type = ITEM_TYPES.field,
        key = "field:" .. tostring(key_part(sp.name)) .. "." .. tostring(key_part(f.name)),
        content = field_content(f)
      })
    end
  end
end
local collect_relations
collect_relations = function(bucket, space_list)
  local seen_ids = { }
  local seen_keys = { }
  for _index_0 = 1, #space_list do
    local sp = space_list[_index_0]
    local _list_0 = box.space._tdb_relations.index.by_from:select({
      sp.id
    })
    for _index_1 = 1, #_list_0 do
      local _continue_0 = false
      repeat
        local t = _list_0[_index_1]
        if seen_ids[t[1]] then
          _continue_0 = true
          break
        end
        seen_ids[t[1]] = true
        local from_sp = space_name_by_id(t[2])
        local from_fld = field_name_by_id(t[3])
        local to_sp = space_name_by_id(t[4])
        local to_fld = field_name_by_id(t[5])
        if not (from_sp and from_fld and to_sp and to_fld) then
          _continue_0 = true
          break
        end
        local key = "relation:" .. tostring(key_part(from_sp)) .. "." .. tostring(key_part(from_fld))
        if seen_keys[key] then
          _continue_0 = true
          break
        end
        seen_keys[key] = true
        table.insert(bucket, {
          type = ITEM_TYPES.relation,
          key = key,
          content = relation_content(from_sp, from_fld, to_sp, to_fld, t[8])
        })
        _continue_0 = true
      until true
      if not _continue_0 then
        break
      end
    end
  end
end
local collect_views
collect_views = function(bucket, space_list)
  for _index_0 = 1, #space_list do
    local sp = space_list[_index_0]
    local _list_0 = views_mod.list_views(sp.id)
    for _index_1 = 1, #_list_0 do
      local v = _list_0[_index_1]
      table.insert(bucket, {
        type = ITEM_TYPES.view,
        key = "view:" .. tostring(key_part(sp.name)) .. "." .. tostring(key_part(v.name)),
        content = view_content(sp.name, v)
      })
    end
  end
end
local collect_pages
collect_pages = function(bucket)
  local _list_0 = box.space._tdb_custom_views:select({ })
  for _index_0 = 1, #_list_0 do
    local row = _list_0[_index_0]
    table.insert(bucket, {
      type = ITEM_TYPES.page,
      key = "page:" .. tostring(key_part(row[2])),
      content = page_content(row)
    })
  end
end
local collect_dataviews
collect_dataviews = function(bucket)
  local _list_0 = box.space._tdb_data_views:select({ })
  for _index_0 = 1, #_list_0 do
    local row = _list_0[_index_0]
    table.insert(bucket, {
      type = ITEM_TYPES.dataview,
      key = "dataview:" .. tostring(key_part(row[2])),
      content = dataview_content(row)
    })
  end
end
local collect_plugins
collect_plugins = function(bucket)
  local _list_0 = box.space._tdb_widget_plugins:select({ })
  for _index_0 = 1, #_list_0 do
    local row = _list_0[_index_0]
    table.insert(bucket, {
      type = ITEM_TYPES.plugin,
      key = "plugin:" .. tostring(key_part(row[2])),
      content = plugin_content(row)
    })
  end
end
local collect_groups_and_perms
collect_groups_and_perms = function(group_bucket, perm_bucket)
  local seen_perms = { }
  local _list_0 = perms_mod.list_groups()
  for _index_0 = 1, #_list_0 do
    local _continue_0 = false
    repeat
      local g = _list_0[_index_0]
      if BUILTIN_GROUPS[g.name] then
        _continue_0 = true
        break
      end
      table.insert(group_bucket, {
        type = ITEM_TYPES.group,
        key = "group:" .. tostring(key_part(g.name)),
        content = group_content(g)
      })
      local _list_1 = perms_mod.list_permissions(g.id)
      for _index_1 = 1, #_list_1 do
        local _continue_1 = false
        repeat
          local p = _list_1[_index_1]
          local key = "perm:" .. tostring(key_part(g.name)) .. "|" .. tostring(key_part(p.resourceType)) .. "|" .. tostring(key_part(resource_name(p.resourceId))) .. "|" .. tostring(key_part(p.level))
          if seen_perms[key] then
            _continue_1 = true
            break
          end
          seen_perms[key] = true
          table.insert(perm_bucket, {
            type = ITEM_TYPES.perm,
            key = key,
            content = perm_content(g.name, p)
          })
          _continue_1 = true
        until true
        if not _continue_1 then
          break
        end
      end
      _continue_0 = true
    until true
    if not _continue_0 then
      break
    end
  end
end
local collect_seeds
collect_seeds = function(bucket, seed_keys)
  for space_name, key_field in pairs(seed_keys) do
    local _continue_0 = false
    repeat
      local user_sp = box.space["data_" .. tostring(space_name)]
      if not (user_sp) then
        _continue_0 = true
        break
      end
      local _list_0 = user_sp:select({ })
      for _index_0 = 1, #_list_0 do
        local _continue_1 = false
        repeat
          local t = _list_0[_index_0]
          local data = decode_record(t[2])
          local v = stable_key(data[key_field])
          if v == nil then
            _continue_1 = true
            break
          end
          table.insert(bucket, {
            type = ITEM_TYPES.seed,
            key = "seed:" .. tostring(key_part(space_name)) .. "|" .. tostring(key_part(v)),
            content = seed_content(space_name, v, data)
          })
          _continue_1 = true
        until true
        if not _continue_1 then
          break
        end
      end
      _continue_0 = true
    until true
    if not _continue_0 then
      break
    end
  end
end
local find_field
find_field = function(space_name, field_name)
  local sp = spaces_mod.get_space_by_name(space_name)
  if not (sp) then
    return nil
  end
  local _list_0 = spaces_mod.list_fields(sp.id)
  for _index_0 = 1, #_list_0 do
    local f = _list_0[_index_0]
    if f.name == field_name then
      return f
    end
  end
  return nil
end
local find_page_row
find_page_row = function(name)
  local _list_0 = box.space._tdb_custom_views:select({ })
  for _index_0 = 1, #_list_0 do
    local row = _list_0[_index_0]
    if row[2] == name then
      return row
    end
  end
  return nil
end
local find_dataview_row
find_dataview_row = function(name)
  local _list_0 = box.space._tdb_data_views:select({ })
  for _index_0 = 1, #_list_0 do
    local row = _list_0[_index_0]
    if row[2] == name then
      return row
    end
  end
  return nil
end
local find_plugin_row
find_plugin_row = function(name)
  return box.space._tdb_widget_plugins.index.by_name:get(name)
end
local find_group
find_group = function(name)
  local _list_0 = perms_mod.list_groups()
  for _index_0 = 1, #_list_0 do
    local g = _list_0[_index_0]
    if g.name == name then
      return g
    end
  end
  return nil
end
local find_seed
find_seed = function(space_name, raw_key)
  local sp = spaces_mod.get_space_by_name(space_name)
  if not (sp) then
    return nil
  end
  local user_sp = box.space["data_" .. tostring(space_name)]
  if not (user_sp) then
    return nil
  end
  local rows = { }
  local _list_0 = user_sp:select({ })
  for _index_0 = 1, #_list_0 do
    local t = _list_0[_index_0]
    table.insert(rows, decode_record(t[2]))
  end
  local _list_1 = spaces_mod.list_fields(sp.id)
  for _index_0 = 1, #_list_1 do
    local f = _list_1[_index_0]
    for _index_1 = 1, #rows do
      local data = rows[_index_1]
      local v = stable_key(data[f.name])
      if v ~= nil and tostring(v) == raw_key then
        return {
          key = v,
          data = data
        }
      end
    end
  end
  return nil
end
local describe_space
describe_space = function(key)
  local name = strip_prefix(key, 'space:')
  if not (name) then
    return nil
  end
  name = unkey_part(name)
  local sp = spaces_mod.get_space_by_name(name)
  if not (sp) then
    return nil
  end
  return space_content(sp)
end
local describe_field
describe_field = function(key)
  local rest = strip_prefix(key, 'field:')
  if not (rest) then
    return nil
  end
  local sp_name, f_name = split_scope_name(rest)
  if not (sp_name) then
    return nil
  end
  local f = find_field(sp_name, f_name)
  if not (f) then
    return nil
  end
  return field_content(f)
end
local describe_relation
describe_relation = function(key)
  local rest = strip_prefix(key, 'relation:')
  if not (rest) then
    return nil
  end
  local from_sp, from_fld = split_scope_name(rest)
  if not (from_sp) then
    return nil
  end
  local sp = spaces_mod.get_space_by_name(from_sp)
  if not (sp) then
    return nil
  end
  local _list_0 = box.space._tdb_relations.index.by_from:select({
    sp.id
  })
  for _index_0 = 1, #_list_0 do
    local _continue_0 = false
    repeat
      do
        local t = _list_0[_index_0]
        if not (field_name_by_id(t[3]) == from_fld) then
          _continue_0 = true
          break
        end
        local from_name = space_name_by_id(t[2])
        local to_sp = space_name_by_id(t[4])
        local to_fld = field_name_by_id(t[5])
        if not (from_name and to_sp and to_fld) then
          return nil
        end
        return relation_content(from_name, from_fld, to_sp, to_fld, t[8])
      end
      _continue_0 = true
    until true
    if not _continue_0 then
      break
    end
  end
  return nil
end
local describe_view
describe_view = function(key)
  local rest = strip_prefix(key, 'view:')
  if not (rest) then
    return nil
  end
  local sp_name, v_name = split_scope_name(rest)
  if not (sp_name) then
    return nil
  end
  local sp = spaces_mod.get_space_by_name(sp_name)
  if not (sp) then
    return nil
  end
  local _list_0 = views_mod.list_views(sp.id)
  for _index_0 = 1, #_list_0 do
    local v = _list_0[_index_0]
    if v.name == v_name then
      return view_content(sp_name, v)
    end
  end
  return nil
end
local describe_page
describe_page = function(key)
  local name = strip_prefix(key, 'page:')
  if not (name) then
    return nil
  end
  local row = find_page_row(unkey_part(name))
  if not (row) then
    return nil
  end
  return page_content(row)
end
local describe_dataview
describe_dataview = function(key)
  local name = strip_prefix(key, 'dataview:')
  if not (name) then
    return nil
  end
  local row = find_dataview_row(unkey_part(name))
  if not (row) then
    return nil
  end
  return dataview_content(row)
end
local describe_plugin
describe_plugin = function(key)
  local name = strip_prefix(key, 'plugin:')
  if not (name) then
    return nil
  end
  local row = find_plugin_row(unkey_part(name))
  if not (row) then
    return nil
  end
  return plugin_content(row)
end
local describe_group
describe_group = function(key)
  local name = strip_prefix(key, 'group:')
  if not (name) then
    return nil
  end
  local g = find_group(unkey_part(name))
  if not (g) then
    return nil
  end
  return group_content(g)
end
local describe_perm
describe_perm = function(key)
  local rest = strip_prefix(key, 'perm:')
  if not (rest) then
    return nil
  end
  local parts = split_pipes(rest)
  if not (#parts == 4) then
    return nil
  end
  local group_name = unkey_part(parts[1])
  local rtype = unkey_part(parts[2])
  local res = unkey_part(parts[3])
  local lvl = unkey_part(parts[4])
  local g = find_group(group_name)
  if not (g) then
    return nil
  end
  local _list_0 = perms_mod.list_permissions(g.id)
  for _index_0 = 1, #_list_0 do
    local p = _list_0[_index_0]
    if p.resourceType == rtype and p.level == lvl and resource_name(p.resourceId) == res then
      return perm_content(group_name, p)
    end
  end
  return nil
end
local describe_seed
describe_seed = function(key)
  local rest = strip_prefix(key, 'seed:')
  if not (rest) then
    return nil
  end
  local idx = rest:find('|')
  if not (idx) then
    return nil
  end
  local space_name = unkey_part(rest:sub(1, idx - 1))
  local raw_key = unkey_part(rest:sub(idx + 1))
  local found = find_seed(space_name, raw_key)
  if not (found) then
    return nil
  end
  return seed_content(space_name, found.key, found.data)
end
local DESCRIBERS = {
  space = describe_space,
  field = describe_field,
  relation = describe_relation,
  view = describe_view,
  page = describe_page,
  dataview = describe_dataview,
  plugin = describe_plugin,
  group = describe_group,
  perm = describe_perm,
  seed = describe_seed
}
local describe_local
describe_local = function(item_type, key)
  if not (type(key) == 'string') then
    return nil
  end
  local describe = DESCRIBERS[item_type]
  if not (describe) then
    return nil
  end
  return describe(key)
end
local by_key
by_key = function(a, b)
  return a.key < b.key
end
local seed_rows_error
seed_rows_error = function(space_name, key_field, key_required)
  local user_sp = box.space["data_" .. tostring(space_name)]
  if not (user_sp) then
    return 
  end
  local missing = 0
  local seen = { }
  local duplicate = nil
  local _list_0 = user_sp:select({ })
  for _index_0 = 1, #_list_0 do
    local t = _list_0[_index_0]
    local v = stable_key(decode_record(t[2])[key_field])
    if v == nil then
      if key_required then
        missing = missing + 1
      end
    else
      local sk = tostring(v)
      if duplicate == nil and seen[sk] ~= nil then
        duplicate = sk
      end
      seen[sk] = true
    end
  end
  if missing > 0 then
    error(tostring(missing) .. " seed row(s) in space '" .. tostring(space_name) .. "' have no value for key field '" .. tostring(key_field) .. "'")
  end
  if duplicate then
    return error("duplicate seed key '" .. tostring(duplicate) .. "' in space '" .. tostring(space_name) .. "' for field '" .. tostring(key_field) .. "'")
  end
end
local validate_seed_entry
validate_seed_entry = function(space_ref, key_field)
  local space_name = resolve_space_name(space_ref)
  local sp = nil
  if space_name and space_name ~= '' then
    sp = spaces_mod.get_space_by_name(space_name)
  end
  if not (sp) then
    error("unknown seed space '" .. tostring(space_ref) .. "'")
  end
  local field = find_field(space_name, key_field)
  if not (field) then
    error("unknown field '" .. tostring(key_field) .. "' in seed space '" .. tostring(space_name) .. "'")
  end
  seed_rows_error(space_name, key_field, field.notNull == true)
  return space_name
end
local validate_seed_config
validate_seed_config = function(seed_opts)
  local seed_keys = { }
  for space_ref, key_field in pairs(seed_opts or { }) do
    seed_keys[validate_seed_entry(space_ref, key_field)] = key_field
  end
  return seed_keys
end
local build_package
build_package = function(meta, opts)
  opts = opts or { }
  local buckets = { }
  for _index_0 = 1, #TYPE_ORDER do
    local t = TYPE_ORDER[_index_0]
    buckets[t] = { }
  end
  local seed_keys = validate_seed_config(opts.seed)
  local space_list = sorted_spaces()
  collect_spaces_and_fields(buckets.space, buckets.field, space_list)
  collect_relations(buckets.relation, space_list)
  collect_views(buckets.view, space_list)
  collect_pages(buckets.page)
  collect_dataviews(buckets.dataview)
  collect_plugins(buckets.plugin)
  collect_groups_and_perms(buckets.group, buckets.perm)
  collect_seeds(buckets.seed, seed_keys)
  for _index_0 = 1, #TYPE_ORDER do
    local t = TYPE_ORDER[_index_0]
    if not (t == 'field') then
      table.sort(buckets[t], by_key)
    end
  end
  local items = { }
  for _index_0 = 1, #TYPE_ORDER do
    local t = TYPE_ORDER[_index_0]
    local _list_0 = buckets[t]
    for _index_1 = 1, #_list_0 do
      local it = _list_0[_index_1]
      table.insert(items, it)
    end
  end
  return {
    app = {
      id = meta.id,
      name = meta.name,
      version = meta.version,
      description = meta.description or ''
    },
    items = items,
    seed_keys = seed_keys
  }
end
return {
  canonical = canonical,
  fingerprint = fingerprint,
  describe_local = describe_local,
  build_package = build_package,
  ITEM_TYPES = ITEM_TYPES,
  key_part = key_part,
  unkey_part = unkey_part,
  strip_null = strip_null,
  normalize_content = normalize_content
}
