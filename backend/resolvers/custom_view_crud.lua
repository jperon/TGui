local uuid_mod = require('uuid')
local list_custom_views
list_custom_views = function()
  local result = { }
  local _list_0 = box.space._tdb_custom_views:select({ })
  for _index_0 = 1, #_list_0 do
    local t = _list_0[_index_0]
    table.insert(result, {
      id = t[1],
      name = t[2],
      description = t[3],
      yaml = t[4],
      createdAt = tostring(t[5]),
      updatedAt = tostring(t[6])
    })
  end
  return result
end
local get_custom_view
get_custom_view = function(id)
  local t = box.space._tdb_custom_views:get(id)
  if not (t) then
    return nil
  end
  return {
    id = t[1],
    name = t[2],
    description = t[3],
    yaml = t[4],
    createdAt = tostring(t[5]),
    updatedAt = tostring(t[6])
  }
end
local create_custom_view
create_custom_view = function(name, description, yaml)
  local id = tostring(uuid_mod.new())
  local now = require('clock').time()
  box.space._tdb_custom_views:insert({
    id,
    name,
    description or '',
    yaml or '',
    now,
    now
  })
  return {
    id = id,
    name = name,
    description = description or '',
    yaml = yaml or '',
    createdAt = tostring(now),
    updatedAt = tostring(now)
  }
end
local delete_custom_view
delete_custom_view = function(id)
  box.space._tdb_custom_views:delete(id)
  return true
end
local create_layout_snapshot
create_layout_snapshot = function(page_id, yaml_content, description)
  local id = tostring(uuid_mod.new())
  local now = require('clock').time()
  box.space._tdb_layout_snapshots:insert({
    id,
    page_id,
    yaml_content,
    now,
    description or ''
  })
  return {
    id = id,
    pageId = page_id,
    yaml = yaml_content,
    createdAt = now,
    description = description or ''
  }
end
local create_auto_snapshot
create_auto_snapshot = function(page_id)
  local t = box.space._tdb_custom_views:get(page_id)
  if not (t) then
    return nil
  end
  if not t[4] or t[4] == '' then
    return nil
  end
  return create_layout_snapshot(page_id, t[4], "Auto-snapshot before update")
end
local list_layout_snapshots
list_layout_snapshots = function(page_id)
  local result = { }
  local _list_0 = box.space._tdb_layout_snapshots.index.by_page:select({
    page_id
  })
  for _index_0 = 1, #_list_0 do
    local t = _list_0[_index_0]
    table.insert(result, {
      id = t[1],
      pageId = t[2],
      yaml = t[3],
      createdAt = t[4],
      description = t[5] or ''
    })
  end
  table.sort(result, function(a, b)
    return a.createdAt > b.createdAt
  end)
  return result
end
local restore_layout_snapshot
restore_layout_snapshot = function(snapshot_id)
  local snapshot = box.space._tdb_layout_snapshots:get(snapshot_id)
  if not (snapshot) then
    error("Snapshot not found: " .. tostring(snapshot_id))
  end
  local page_id = snapshot[2]
  local yaml_content = snapshot[3]
  local t = box.space._tdb_custom_views:get(page_id)
  if not (t) then
    error("CustomView not found: " .. tostring(page_id))
  end
  create_auto_snapshot(page_id)
  local now = require('clock').time()
  box.space._tdb_custom_views:replace({
    page_id,
    t[2],
    t[3],
    yaml_content,
    t[5],
    now
  })
  return {
    id = page_id,
    name = t[2],
    description = t[3],
    yaml = yaml_content,
    createdAt = tostring(t[5]),
    updatedAt = tostring(now)
  }
end
local update_custom_view
update_custom_view = function(id, name, description, yaml)
  local t = box.space._tdb_custom_views:get(id)
  if not (t) then
    error("CustomView not found: " .. tostring(id))
  end
  if yaml and yaml ~= t[4] then
    create_auto_snapshot(id)
  end
  local now = require('clock').time()
  local new_name
  if name ~= nil then
    new_name = name
  else
    new_name = t[2]
  end
  local new_desc
  if description ~= nil then
    new_desc = description
  else
    new_desc = t[3]
  end
  local new_yaml
  if yaml ~= nil then
    new_yaml = yaml
  else
    new_yaml = t[4]
  end
  box.space._tdb_custom_views:replace({
    id,
    new_name,
    new_desc,
    new_yaml,
    t[5],
    now
  })
  return {
    id = id,
    name = new_name,
    description = new_desc,
    yaml = new_yaml,
    createdAt = tostring(t[5]),
    updatedAt = tostring(now)
  }
end
local export_layout
export_layout = function(page_id)
  local t = box.space._tdb_custom_views:get(page_id)
  if not (t) then
    error("CustomView not found: " .. tostring(page_id))
  end
  return {
    id = t[1],
    name = t[2],
    yaml = t[4]
  }
end
local import_layout
import_layout = function(page_id, yaml)
  local t = box.space._tdb_custom_views:get(page_id)
  if not (t) then
    error("CustomView not found: " .. tostring(page_id))
  end
  local now = require('clock').time()
  box.space._tdb_custom_views:replace({
    page_id,
    t[2],
    t[3],
    yaml,
    t[5],
    now
  })
  return {
    id = page_id,
    name = t[2],
    description = t[3],
    yaml = yaml,
    createdAt = tostring(t[5]),
    updatedAt = tostring(now)
  }
end
return {
  list_custom_views = list_custom_views,
  get_custom_view = get_custom_view,
  create_custom_view = create_custom_view,
  delete_custom_view = delete_custom_view,
  create_layout_snapshot = create_layout_snapshot,
  list_layout_snapshots = list_layout_snapshots,
  restore_layout_snapshot = restore_layout_snapshot,
  update_custom_view = update_custom_view,
  export_layout = export_layout,
  import_layout = import_layout
}
