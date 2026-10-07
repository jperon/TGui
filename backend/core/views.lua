local json = require('json')
local uuid_mod = require('uuid')
local VIEW_TYPES = {
  'grid',
  'form',
  'gallery'
}
local validate_view_yaml
validate_view_yaml = function(yaml)
  if not (yaml) then
    error('YAML de vue absent')
  end
  if not (yaml.layout) then
    error('Clé racine "layout" manquante')
  end
  local layout = yaml.layout
  if not (layout.direction) then
    error('Clé "direction" manquante dans layout')
  end
  if not (layout.children) then
    error('Clé "children" manquante dans layout')
  end
  if not (type(layout.children) == 'table') then
    error('children doit être une table')
  end
  local _list_0 = layout.children
  for _index_0 = 1, #_list_0 do
    local child = _list_0[_index_0]
    if child.widget then
      local w = child.widget
      if not (w.space) then
        error('Clé "space" manquante dans widget')
      end
      if w.depends_on then
        local d = w.depends_on
        if not (d.widget) then
          error('Clé "widget" manquante dans depends_on')
        end
        if not (d.field) then
          error('Clé "field" manquante dans depends_on')
        end
      end
    else
      if not (child.direction) then
        error('Clé "direction" manquante dans zone imbriquée')
      end
      if not (child.children) then
        error('Clé "children" manquante dans zone imbriquée')
      end
      if not (type(child.children) == 'table') then
        error('children doit être une table (zone imbriquée)')
      end
    end
  end
  return true
end
local create_view
create_view = function(space_id, name, view_type, config)
  validate_view_yaml(config)
  local now = os.time()
  local vid = tostring(uuid_mod.new())
  local config_str = json.encode(config or { })
  box.space._tdb_views:insert({
    vid,
    space_id,
    name,
    view_type,
    config_str,
    now,
    now
  })
  return {
    id = vid,
    spaceId = space_id,
    name = name,
    viewType = view_type,
    config = config_str,
    createdAt = now,
    updatedAt = now
  }
end
local update_view
update_view = function(view_id, patch)
  local t = box.space._tdb_views:get(view_id)
  if not (t) then
    error("View not found: " .. tostring(view_id))
  end
  local now = os.time()
  local name = patch.name or t[3]
  local vtype = patch.viewType or t[4]
  if patch.config then
    validate_view_yaml(patch.config)
    local config_str = json.encode(patch.config)
  else
    local config_str = t[5]
  end
  return box.space._tdb_views:replace({
    view_id,
    t[2],
    name,
    vtype,
    config_str,
    t[6],
    now
  })
end
local delete_view
delete_view = function(view_id)
  return box.space._tdb_views:delete(view_id)
end
local list_views
list_views = function(space_id)
  local result = { }
  local _list_0 = box.space._tdb_views.index.by_space:select({
    space_id
  })
  for _index_0 = 1, #_list_0 do
    local t = _list_0[_index_0]
    table.insert(result, {
      id = t[1],
      spaceId = t[2],
      name = t[3],
      viewType = t[4],
      config = t[5],
      createdAt = t[6],
      updatedAt = t[7]
    })
  end
  return result
end
local get_view
get_view = function(view_id)
  local t = box.space._tdb_views:get(view_id)
  if not (t) then
    return nil
  end
  return {
    id = t[1],
    spaceId = t[2],
    name = t[3],
    viewType = t[4],
    config = t[5],
    createdAt = t[6],
    updatedAt = t[7]
  }
end
return {
  create_view = create_view,
  update_view = update_view,
  delete_view = delete_view,
  list_views = list_views,
  get_view = get_view,
  VIEW_TYPES = VIEW_TYPES,
  validate_view_yaml = validate_view_yaml
}
