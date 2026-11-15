local uuid = require('uuid')
local json = require('json')
local trim
trim = function(s)
  return tostring(s or ''):match('^%s*(.-)%s*$')
end
local tuple_to_preset
tuple_to_preset = function(t)
  if not (t) then
    return nil
  end
  return {
    id = t[1],
    scope = t[2],
    spaceId = t[3],
    name = t[4],
    filter = t[5] or '',
    sort = t[6] or '[]',
    createdAt = t[7],
    updatedAt = t[8]
  }
end
local get_preset
get_preset = function(id)
  if not (id) then
    return nil
  end
  return tuple_to_preset(box.space._tdb_view_presets:get({
    id
  }))
end
local list_presets
list_presets = function(scope)
  local result = { }
  if not (scope and scope ~= '') then
    return result
  end
  local _list_0 = box.space._tdb_view_presets.index.by_scope_name:select({
    scope
  })
  for _index_0 = 1, #_list_0 do
    local t = _list_0[_index_0]
    table.insert(result, tuple_to_preset(t))
  end
  table.sort(result, function(a, b)
    return a.name < b.name
  end)
  return result
end
local validate_sort
validate_sort = function(sort_json)
  local raw
  if sort_json == nil or sort_json == '' then
    raw = '[]'
  else
    raw = tostring(sort_json)
  end
  local ok, decoded = pcall(json.decode, raw)
  if not (ok) then
    error("Invalid sort JSON: " .. tostring(decoded))
  end
  if not (type(decoded) == 'table') then
    error("Invalid sort JSON: expected an array of sort entries")
  end
  for key in pairs(decoded) do
    if not (type(key) == 'number') then
      error("Invalid sort JSON: expected an array of sort entries")
    end
  end
  for _index_0 = 1, #decoded do
    local entry = decoded[_index_0]
    if not (type(entry) == 'table') then
      error("Invalid sort entry: expected an object with column and ascending")
    end
    if not (type(entry.column) == 'string') then
      error("Invalid sort entry: column must be a string")
    end
    if not (type(entry.ascending) == 'boolean') then
      error("Invalid sort entry: ascending must be a boolean")
    end
  end
  return raw
end
local save_preset
save_preset = function(scope, space_id, name, filter, sort)
  scope = tostring(scope or '')
  if not (scope:match('%S')) then
    error("Preset scope cannot be empty")
  end
  local clean_name = trim(name)
  if clean_name == '' then
    error("Preset name cannot be empty")
  end
  space_id = tostring(space_id or '')
  if space_id == '' then
    error("Preset space cannot be empty")
  end
  if not (box.space._tdb_spaces:get({
    space_id
  })) then
    error("Space not found: " .. tostring(space_id))
  end
  local filter_src = tostring(filter or '')
  local sort_json = validate_sort(sort)
  local now = os.time()
  local existing = box.space._tdb_view_presets.index.by_scope_name:get({
    scope,
    clean_name
  })
  if existing then
    box.space._tdb_view_presets:update(existing[1], {
      {
        '=',
        3,
        space_id
      },
      {
        '=',
        5,
        filter_src
      },
      {
        '=',
        6,
        sort_json
      },
      {
        '=',
        8,
        now
      }
    })
    return get_preset(existing[1])
  end
  local preset_id = tostring(uuid.new())
  box.space._tdb_view_presets:insert({
    preset_id,
    scope,
    space_id,
    clean_name,
    filter_src,
    sort_json,
    now,
    now
  })
  return get_preset(preset_id)
end
local delete_preset
delete_preset = function(id)
  local t = box.space._tdb_view_presets:get({
    id
  })
  if not (t) then
    return false
  end
  box.space._tdb_view_presets:delete({
    id
  })
  return true
end
return {
  list_presets = list_presets,
  get_preset = get_preset,
  save_preset = save_preset,
  delete_preset = delete_preset,
  validate_sort = validate_sort
}
