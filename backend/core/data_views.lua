local uuid = require('uuid')
local json = require('json')
local log = require('log')
local make_self_proxy, build_fk_def_map, compile_formula
do
  local _obj_0 = require('core.triggers')
  make_self_proxy, build_fk_def_map, compile_formula = _obj_0.make_self_proxy, _obj_0.build_fk_def_map, _obj_0.compile_formula
end
local get_view
get_view = function(id)
  local t = box.space._tdb_data_views:get({
    id
  })
  if not (t) then
    return nil
  end
  return {
    id = t[1],
    name = t[2],
    description = t[3],
    source_space = t[4],
    config = t[5],
    created_at = t[6],
    updated_at = t[7]
  }
end
local create_view
create_view = function(name, description, source_space, config_json)
  if not name or name == '' then
    error("Name cannot be empty")
  end
  if not source_space or source_space == '' then
    error("Source space cannot be empty")
  end
  local existing = box.space._tdb_data_views.index.by_name:get({
    name
  })
  if existing then
    error("A view with name '" .. tostring(name) .. "' already exists")
  end
  if config_json and config_json ~= '' then
    local ok, err = pcall(json.decode, config_json)
    if not (ok) then
      error("Invalid config JSON: " .. tostring(err))
    end
  end
  local view_id = uuid.str()
  local now = os.time()
  box.space._tdb_data_views:insert({
    view_id,
    name,
    description or '',
    source_space,
    config_json or '{}',
    now,
    now
  })
  return get_view(view_id)
end
local get_view_by_name
get_view_by_name = function(name)
  local t = box.space._tdb_data_views.index.by_name:get({
    name
  })
  if not (t) then
    return nil
  end
  return get_view(t[1])
end
local list_views
list_views = function()
  local _accum_0 = { }
  local _len_0 = 1
  local _list_0 = box.space._tdb_data_views:select({ })
  for _index_0 = 1, #_list_0 do
    local t = _list_0[_index_0]
    _accum_0[_len_0] = get_view(t[1])
    _len_0 = _len_0 + 1
  end
  return _accum_0
end
local update_view
update_view = function(id, params)
  local t = box.space._tdb_data_views:get({
    id
  })
  if not (t) then
    error("View not found")
  end
  local name = params.name
  if name and name ~= t[2] then
    local existing = box.space._tdb_data_views.index.by_name:get({
      name
    })
    if existing then
      error("A view with name '" .. tostring(name) .. "' already exists")
    end
  end
  if params.config then
    local ok, err = pcall(json.decode, params.config)
    if not (ok) then
      error("Invalid config JSON: " .. tostring(err))
    end
  end
  box.space._tdb_data_views:update(id, {
    {
      '=',
      2,
      params.name or t[2]
    },
    {
      '=',
      3,
      params.description or t[3]
    },
    {
      '=',
      4,
      params.source_space or t[4]
    },
    {
      '=',
      5,
      params.config or t[5]
    },
    {
      '=',
      7,
      os.time()
    }
  })
  return get_view(id)
end
local delete_view
delete_view = function(id)
  local t = box.space._tdb_data_views:get({
    id
  })
  if not (t) then
    return false
  end
  box.space._tdb_data_views:delete({
    id
  })
  return true
end
return {
  create_view = create_view,
  get_view = get_view,
  get_view_by_name = get_view_by_name,
  list_views = list_views,
  update_view = update_view,
  delete_view = delete_view
}
