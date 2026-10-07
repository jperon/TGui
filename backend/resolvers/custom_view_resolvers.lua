local yaml = require('yaml')
local uuid_mod = require('uuid')
local json = require('json')
local require_auth, require_perm, perm_ok
do
  local _obj_0 = require('resolvers.utils')
  require_auth, require_perm, perm_ok = _obj_0.require_auth, _obj_0.require_perm, _obj_0.perm_ok
end
local add_data_view_to_page
local add_widget_to_view
local encode_layout_yaml
local create_zone
local resize_zone
local merge_zones
local split_zone
local export_layout
local import_layout
local create_layout_snapshot
local list_layout_snapshots
local restore_layout_snapshot
local create_auto_snapshot
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
local reorder_widgets
reorder_widgets = function(pageId, widgetPositions)
  local t = box.space._tdb_custom_views:get(pageId)
  if not (t) then
    error("Page not found: " .. tostring(pageId))
  end
  local yaml_content = t[4] or 'layout:\n  direction: vertical\n  children: []'
  local config = yaml.decode(yaml_content)
  if not config or type(config) ~= 'table' then
    config = {
      layout = {
        direction = 'vertical',
        children = { }
      }
    }
  elseif not config.layout then
    config.layout = {
      direction = 'vertical',
      children = { }
    }
  elseif not config.layout.children or type(config.layout.children) ~= 'table' then
    config.layout.children = { }
  end
  local widget_map = { }
  local zones_map = { }
  local collect_widgets_and_zones
  collect_widgets_and_zones = function(children, parent_id)
    if parent_id == nil then
      parent_id = null
    end
    for _, child in ipairs(children) do
      if child.widget then
        widget_map[child.widget.id] = {
          widget = child.widget,
          parent_id = parent_id
        }
      elseif child.zone then
        local zone_id = child.zone.id or "zone_" .. tostring(#zones_map + 1)
        zones_map[zone_id] = {
          zone = child.zone,
          parent_id = parent_id
        }
        if child.zone.children and type(child.zone.children) == 'table' then
          collect_widgets_and_zones(child.zone.children, zone_id)
        end
      end
    end
  end
  collect_widgets_and_zones(config.layout.children)
  local original_zone_children = { }
  for _, child in ipairs(config.layout.children) do
    if child.zone and child.zone.id then
      original_zone_children[child.zone.id] = { }
      if child.zone.children then
        for _, zchild in ipairs(child.zone.children) do
          table.insert(original_zone_children[child.zone.id], zchild)
        end
      end
    end
  end
  local new_children = { }
  local processed_zones = { }
  local zone_widgets = { }
  local root_widgets = { }
  if widgetPositions and type(widgetPositions) == 'table' and #widgetPositions > 0 then
    for i = 1, #widgetPositions do
      local pos = widgetPositions[i]
      if type(pos) == 'table' and pos.widgetId then
        local widget_data = widget_map[pos.widgetId]
        if widget_data then
          local widget = widget_data.widget
          widget.position = pos.index or i
          local parent_id = pos.parentId or null
          if parent_id and zones_map[parent_id] then
            if not zone_widgets[parent_id] then
              zone_widgets[parent_id] = { }
            end
            table.insert(zone_widgets[parent_id], {
              widget = widget
            })
            processed_zones[parent_id] = true
          else
            table.insert(root_widgets, {
              widget = widget
            })
          end
        else
          local new_widget = {
            id = pos.widgetId,
            position = pos.index or i,
            space = 'unknown',
            title = "Widget " .. tostring(pos.widgetId)
          }
          if parent_id and zones_map[parent_id] then
            if not zone_widgets[parent_id] then
              zone_widgets[parent_id] = { }
            end
            table.insert(zone_widgets[parent_id], {
              widget = new_widget
            })
            processed_zones[parent_id] = true
          else
            table.insert(root_widgets, {
              widget = new_widget
            })
          end
        end
      end
    end
  else
    for _, child in ipairs(config.layout.children) do
      table.insert(new_children, child)
    end
  end
  for _, w in ipairs(root_widgets) do
    table.insert(new_children, w)
  end
  for zone_id, zone_data in pairs(zones_map) do
    local zone = zone_data.zone
    local zone_entry = {
      zone = zone,
      children = { }
    }
    if original_zone_children[zone_id] then
      for _, child in ipairs(original_zone_children[zone_id]) do
        table.insert(zone_entry.zone.children, child)
      end
    end
    if zone_widgets[zone_id] then
      for _, w in ipairs(zone_widgets[zone_id]) do
        table.insert(zone_entry.zone.children, w)
      end
    end
    table.insert(new_children, zone_entry)
  end
  for zone_id, zone_data in pairs(zones_map) do
    if not processed_zones[zone_id] then
      table.insert(new_children, {
        zone = zone_data.zone
      })
    end
  end
  config.layout.children = new_children
  yaml_content = "layout:\n"
  yaml_content = yaml_content .. ("  direction: " .. (config.layout.direction or 'vertical') .. "\n")
  yaml_content = yaml_content .. "  children:\n"
  for _, child in ipairs(config.layout.children) do
    if child.zone then
      local zone = child.zone
      yaml_content = yaml_content .. "    - zone:\n"
      yaml_content = yaml_content .. ("        id: " .. tostring(zone.id) .. "\n")
      yaml_content = yaml_content .. ("        title: " .. tostring(zone.title or '') .. "\n")
      yaml_content = yaml_content .. ("        factor: " .. tostring(zone.factor or 1) .. "\n")
      yaml_content = yaml_content .. ("        direction: " .. tostring(zone.direction or 'vertical') .. "\n")
      if zone.children and #zone.children > 0 then
        yaml_content = yaml_content .. "        children:\n"
        for _, zone_child in ipairs(zone.children) do
          if zone_child.widget then
            local widget = zone_child.widget
            yaml_content = yaml_content .. "          - widget:\n"
            yaml_content = yaml_content .. ("              id: " .. tostring(widget.id) .. "\n")
            yaml_content = yaml_content .. ("              title: " .. tostring(widget.title or '') .. "\n")
            yaml_content = yaml_content .. ("              space: " .. tostring(widget.space or '') .. "\n")
            yaml_content = yaml_content .. ("              position: " .. tostring(widget.position or 1) .. "\n")
            if widget.columns and #widget.columns > 0 then
              yaml_content = yaml_content .. "              columns:\n"
              for _, col in ipairs(widget.columns) do
                yaml_content = yaml_content .. ("                - " .. col .. "\n")
              end
            end
            if widget.groupBy then
              yaml_content = yaml_content .. ("              groupBy: " .. tostring(widget.groupBy) .. "\n")
            end
          end
        end
      end
    elseif child.widget then
      yaml_content = yaml_content .. "    - widget:\n"
      yaml_content = yaml_content .. ("        id: " .. tostring(child.widget.id) .. "\n")
      yaml_content = yaml_content .. ("        title: " .. child.widget.title .. "\n")
      yaml_content = yaml_content .. ("        space: " .. tostring(child.widget.space) .. "\n")
      yaml_content = yaml_content .. ("        position: " .. tostring(child.widget.position) .. "\n")
      if child.widget.columns and #child.widget.columns > 0 then
        yaml_content = yaml_content .. "        columns:\n"
        for _, col in ipairs(child.widget.columns) do
          yaml_content = yaml_content .. ("          - " .. col .. "\n")
        end
      end
      if child.widget.groupBy then
        yaml_content = yaml_content .. ("        groupBy: " .. tostring(child.widget.groupBy) .. "\n")
      end
      for key, value in pairs(child.widget) do
        if key ~= 'id' and key ~= 'title' and key ~= 'space' and key ~= 'position' and key ~= 'columns' and key ~= 'groupBy' then
          yaml_content = yaml_content .. ("        " .. key .. ": " .. tostring(value) .. "\n")
        end
      end
    end
  end
  box.space._tdb_custom_views:update(pageId, {
    {
      '=',
      4,
      yaml_content
    },
    {
      '=',
      6,
      os.time()
    }
  })
  t = box.space._tdb_custom_views:get(pageId)
  return {
    id = pageId,
    name = t[2],
    description = t[3],
    yaml = yaml_content,
    createdAt = tostring(t[5]),
    updatedAt = tostring(t[6])
  }
end
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
local Query = {
  customViews = function(_, args, ctx)
    require_auth(ctx)
    local out = { }
    local _list_0 = list_custom_views()
    for _index_0 = 1, #_list_0 do
      local cv = _list_0[_index_0]
      if perm_ok(ctx, 'view', cv.id, 'read') then
        table.insert(out, cv)
      end
    end
    return out
  end,
  customView = function(_, args, ctx)
    require_perm(ctx, 'view', args.id, 'read')
    return get_custom_view(args.id)
  end,
  exportLayout = function(_, args, ctx)
    require_perm(ctx, 'view', args.pageId, 'read')
    return export_layout(args.pageId)
  end,
  listLayoutSnapshots = function(_, args, ctx)
    require_perm(ctx, 'view', args.pageId, 'read')
    return list_layout_snapshots(args.pageId)
  end
}
local Mutation = {
  createCustomView = function(_, args, ctx)
    require_perm(ctx, 'view', nil, 'write')
    local i = args.input or args
    if not (i.name) then
      error("name is required")
    end
    return create_custom_view(i.name, i.description, i.yaml)
  end,
  updateCustomView = function(_, args, ctx)
    require_perm(ctx, 'view', args.id, 'write')
    local i = args.input
    return update_custom_view(args.id, i.name, i.description, i.yaml)
  end,
  deleteCustomView = function(_, args, ctx)
    require_perm(ctx, 'view', args.id, 'admin')
    return delete_custom_view(args.id)
  end,
  addWidgetToView = function(_, args, ctx)
    require_perm(ctx, 'view', args.viewId, 'write')
    return add_widget_to_view(args.viewId, args.widget)
  end,
  reorderWidgets = function(_, args, ctx)
    require_perm(ctx, 'view', args.pageId, 'write')
    local pageId = args.pageId
    local widgetPositions = args.widgetPositions
    if not (pageId) then
      error("pageId is required")
    end
    if type(widgetPositions) == 'string' then
      error("widgetPositions must be a table, got string")
    end
    if not (widgetPositions and type(widgetPositions) == 'table') then
      error("widgetPositions must be a table")
    end
    return reorder_widgets(pageId, widgetPositions)
  end,
  createZone = function(_, args, ctx)
    require_perm(ctx, 'view', args.pageId, 'write')
    local pageId = args.pageId
    local zoneData = args.zoneData or { }
    if not (pageId) then
      error("pageId is required")
    end
    return create_zone(pageId, zoneData)
  end,
  resizeZone = function(_, args, ctx)
    require_perm(ctx, 'view', args.pageId, 'write')
    local pageId = args.pageId
    local zoneId = args.zoneId
    local factor = args.factor
    if not (pageId) then
      error("pageId is required")
    end
    if not (zoneId) then
      error("zoneId is required")
    end
    if not (factor) then
      error("factor is required")
    end
    if factor < 0.1 or factor > 1.0 then
      error("factor must be between 0.1 and 1.0")
    end
    return resize_zone(pageId, zoneId, factor)
  end,
  addDataViewToPage = function(_, args, ctx)
    require_perm(ctx, 'view', args.pageId, 'write')
    return add_data_view_to_page(args.pageId, args.dataViewId)
  end,
  importLayout = function(_, args, ctx)
    require_perm(ctx, 'view', args.pageId, 'write')
    return import_layout(args.pageId, args.yaml)
  end,
  createLayoutSnapshot = function(_, args, ctx)
    require_perm(ctx, 'view', args.pageId, 'write')
    return create_layout_snapshot(args.pageId, args.yaml, args.description)
  end,
  restoreLayoutSnapshot = function(_, args, ctx)
    local snap = box.space._tdb_layout_snapshots:get(args.snapshotId)
    require_perm(ctx, 'view', snap and snap[2], 'write')
    return restore_layout_snapshot(args.snapshotId)
  end,
  mergeZones = function(_, args, ctx)
    require_perm(ctx, 'view', args.pageId, 'write')
    return merge_zones(args.pageId, args.zoneId1, args.zoneId2)
  end,
  splitZone = function(_, args, ctx)
    require_perm(ctx, 'view', args.pageId, 'write')
    return split_zone(args.pageId, args.zoneId, args.direction)
  end
}
create_zone = function(pageId, zoneData)
  local t = box.space._tdb_custom_views:get(pageId)
  if not (t) then
    error("Page not found: " .. tostring(pageId))
  end
  local yaml_content = t[4] or 'layout:\n  direction: vertical\n  children: []'
  local config = yaml.decode(yaml_content)
  if not config or type(config) ~= 'table' then
    config = {
      layout = {
        direction = 'vertical',
        children = { }
      }
    }
  elseif not config.layout then
    config.layout = {
      direction = 'vertical',
      children = { }
    }
  elseif not config.layout.children or type(config.layout.children) ~= 'table' then
    config.layout.children = { }
  end
  local zone_id = tostring(uuid_mod.new())
  local new_zone = {
    id = zone_id,
    title = zoneData.title or "Zone " .. tostring(zone_id),
    factor = zoneData.factor or 0.5,
    direction = zoneData.direction or 'vertical',
    children = { }
  }
  table.insert(config.layout.children, {
    zone = new_zone
  })
  local updated_yaml = encode_layout_yaml(config)
  box.space._tdb_custom_views:update(pageId, {
    {
      '=',
      4,
      updated_yaml
    },
    {
      '=',
      6,
      os.time()
    }
  })
  return {
    id = zone_id,
    title = new_zone.title,
    factor = new_zone.factor,
    direction = new_zone.direction
  }
end
resize_zone = function(pageId, zoneId, factor)
  local t = box.space._tdb_custom_views:get(pageId)
  if not (t) then
    error("Page not found: " .. tostring(pageId))
  end
  local yaml_content = t[4] or 'layout:\n  direction: vertical\n  children: []'
  local config = yaml.decode(yaml_content)
  if not config or type(config) ~= 'table' then
    config = {
      layout = {
        direction = 'vertical',
        children = { }
      }
    }
  elseif not config.layout then
    config.layout = {
      direction = 'vertical',
      children = { }
    }
  elseif not config.layout.children or type(config.layout.children) ~= 'table' then
    config.layout.children = { }
  end
  local find_and_update_zone
  find_and_update_zone = function(children, parent)
    if parent == nil then
      parent = nil
    end
    for i, child in ipairs(children) do
      if child.zone and child.zone.id == zoneId then
        child.zone.factor = factor
        return {
          zone = child.zone,
          parent = children,
          index = i,
          found = true
        }
      elseif child.zone and child.zone.children then
        local result = find_and_update_zone(child.zone.children, child.zone.children)
        if result and result.found then
          return result
        end
      end
    end
    return {
      found = false
    }
  end
  local result = find_and_update_zone(config.layout.children)
  if not (result and result.found) then
    error("Zone not found: " .. tostring(zoneId))
  end
  if result.parent then
    local remaining = 1.0 - factor
    local sibling_sum = 0
    for i, child in ipairs(result.parent) do
      if i ~= result.index and child.zone then
        sibling_sum = sibling_sum + child.zone.factor
      end
    end
    if sibling_sum > 0 then
      for i, child in ipairs(result.parent) do
        if i ~= result.index and child.zone then
          child.zone.factor = (child.zone.factor / sibling_sum) * remaining
        end
      end
    end
  end
  local updated_yaml = encode_layout_yaml(config)
  box.space._tdb_custom_views:update(pageId, {
    {
      '=',
      4,
      updated_yaml
    },
    {
      '=',
      6,
      os.time()
    }
  })
  return {
    id = zoneId,
    factor = factor
  }
end
local find_zone_with_parent
find_zone_with_parent = function(children, zoneId, parent)
  if parent == nil then
    parent = nil
  end
  for i, child in ipairs(children) do
    if child.zone and child.zone.id == zoneId then
      return {
        zone = child.zone,
        parent = children,
        index = i,
        found = true
      }
    elseif child.zone and child.zone.children then
      local result = find_zone_with_parent(child.zone.children, zoneId, child.zone.children)
      if result and result.found then
        return result
      end
    end
  end
  return {
    found = false
  }
end
merge_zones = function(pageId, zoneId1, zoneId2)
  local t = box.space._tdb_custom_views:get(pageId)
  if not (t) then
    error("Page not found: " .. tostring(pageId))
  end
  local yaml_content = t[4] or 'layout:\n  direction: vertical\n  children: []'
  local config = yaml.decode(yaml_content)
  if not config or type(config) ~= 'table' then
    config = {
      layout = {
        direction = 'vertical',
        children = { }
      }
    }
  elseif not config.layout then
    config.layout = {
      direction = 'vertical',
      children = { }
    }
  elseif not config.layout.children or type(config.layout.children) ~= 'table' then
    config.layout.children = { }
  end
  local result1 = find_zone_with_parent(config.layout.children, zoneId1)
  local result2 = find_zone_with_parent(config.layout.children, zoneId2)
  if not (result1 and result1.found) then
    error("Zone not found: " .. tostring(zoneId1))
  end
  if not (result2 and result2.found) then
    error("Zone not found: " .. tostring(zoneId2))
  end
  if not (result1.parent == result2.parent) then
    error("Zones must have the same parent to be merged")
  end
  if result1.index > result2.index then
    result1, result2 = result2, result1
  end
  local zone1 = result1.zone
  local zone2 = result2.zone
  local parent = result1.parent
  if zone2.children and #zone2.children > 0 then
    if not zone1.children then
      zone1.children = { }
    end
    for _, child in ipairs(zone2.children) do
      table.insert(zone1.children, child)
    end
  end
  zone1.factor = math.min(1.0, zone1.factor + zone2.factor)
  table.remove(parent, result2.index)
  local updated_yaml = encode_layout_yaml(config)
  box.space._tdb_custom_views:update(pageId, {
    {
      '=',
      4,
      updated_yaml
    },
    {
      '=',
      6,
      os.time()
    }
  })
  return {
    id = pageId,
    yaml = updated_yaml
  }
end
split_zone = function(pageId, zoneId, direction)
  if not (direction == 'vertical' or direction == 'horizontal') then
    error("Direction must be 'vertical' or 'horizontal'")
  end
  local t = box.space._tdb_custom_views:get(pageId)
  if not (t) then
    error("Page not found: " .. tostring(pageId))
  end
  local yaml_content = t[4] or 'layout:\n  direction: vertical\n  children: []'
  local config = yaml.decode(yaml_content)
  if not config or type(config) ~= 'table' then
    config = {
      layout = {
        direction = 'vertical',
        children = { }
      }
    }
  elseif not config.layout then
    config.layout = {
      direction = 'vertical',
      children = { }
    }
  elseif not config.layout.children or type(config.layout.children) ~= 'table' then
    config.layout.children = { }
  end
  local result = find_zone_with_parent(config.layout.children, zoneId)
  if not (result and result.found) then
    error("Zone not found: " .. tostring(zoneId))
  end
  local zone = result.zone
  local parent = result.parent
  local index = result.index
  local new_factor = zone.factor / 2
  local zone_id1 = tostring(uuid_mod.new())
  local zone_id2 = tostring(uuid_mod.new())
  local new_zone1 = {
    id = zone_id1,
    title = zone.title .. " Part 1",
    factor = new_factor,
    direction = direction,
    children = { }
  }
  local new_zone2 = {
    id = zone_id2,
    title = zone.title .. " Part 2",
    factor = new_factor,
    direction = direction,
    children = { }
  }
  if zone.children and #zone.children > 0 then
    local mid = math.ceil(#zone.children / 2)
    for i = 1, mid do
      table.insert(new_zone1.children, zone.children[i])
    end
    for i = mid + 1, #zone.children do
      table.insert(new_zone2.children, zone.children[i])
    end
  end
  table.remove(parent, index)
  table.insert(parent, index, {
    zone = new_zone1
  })
  table.insert(parent, index + 1, {
    zone = new_zone2
  })
  local updated_yaml = encode_layout_yaml(config)
  box.space._tdb_custom_views:update(pageId, {
    {
      '=',
      4,
      updated_yaml
    },
    {
      '=',
      6,
      os.time()
    }
  })
  return {
    id = pageId,
    yaml = updated_yaml
  }
end
encode_layout_yaml = function(config)
  local yaml_content = "layout:\n"
  yaml_content = yaml_content .. ("  direction: " .. (config.layout.direction or 'vertical') .. "\n")
  yaml_content = yaml_content .. "  children:\n"
  local encode_children
  encode_children = function(children, indent)
    indent = indent or "    "
    for _, child in ipairs(children) do
      if child.widget then
        yaml_content = yaml_content .. (indent .. "- widget:\n")
        yaml_content = yaml_content .. (indent .. "    id: " .. tostring(child.widget.id) .. "\n")
        yaml_content = yaml_content .. (indent .. "    title: " .. child.widget.title .. "\n")
        yaml_content = yaml_content .. (indent .. "    space: " .. tostring(child.widget.space) .. "\n")
        yaml_content = yaml_content .. (indent .. "    position: " .. tostring(child.widget.position) .. "\n")
        if child.widget.dataViewId then
          yaml_content = yaml_content .. (indent .. "    dataViewId: " .. tostring(child.widget.dataViewId) .. "\n")
        end
        if child.widget.columns and #child.widget.columns > 0 then
          yaml_content = yaml_content .. (indent .. "    columns:\n")
          for _, col in ipairs(child.widget.columns) do
            yaml_content = yaml_content .. (indent .. "      - " .. col .. "\n")
          end
        end
        if child.widget.groupBy then
          yaml_content = yaml_content .. (indent .. "    groupBy: " .. tostring(child.widget.groupBy) .. "\n")
        end
        for key, value in pairs(child.widget) do
          if key ~= 'id' and key ~= 'title' and key ~= 'space' and key ~= 'position' and key ~= 'columns' and key ~= 'groupBy' and key ~= 'dataViewId' then
            yaml_content = yaml_content .. (indent .. "    " .. key .. ": " .. tostring(value) .. "\n")
          end
        end
      elseif child.zone then
        yaml_content = yaml_content .. (indent .. "- zone:\n")
        yaml_content = yaml_content .. (indent .. "    id: " .. tostring(child.zone.id) .. "\n")
        yaml_content = yaml_content .. (indent .. "    title: " .. child.zone.title .. "\n")
        yaml_content = yaml_content .. (indent .. "    factor: " .. tostring(child.zone.factor) .. "\n")
        yaml_content = yaml_content .. (indent .. "    direction: " .. (child.zone.direction or 'vertical') .. "\n")
        if child.zone.children and #child.zone.children > 0 then
          yaml_content = yaml_content .. (indent .. "    children:\n")
          encode_children(child.zone.children, indent .. "      ")
        end
      end
    end
  end
  encode_children(config.layout.children)
  return yaml_content
end
add_data_view_to_page = function(pageId, dataViewId)
  local t = box.space._tdb_custom_views:get(pageId)
  if not (t) then
    error("CustomView not found: " .. tostring(pageId))
  end
  local dv = box.space._tdb_data_views:get(dataViewId)
  if not (dv) then
    error("DataView not found: " .. tostring(dataViewId))
  end
  local widget_id = tostring(uuid_mod.new())
  local new_widget = {
    id = widget_id,
    title = "Data View: " .. dv[2],
    space = dv[2],
    dataViewId = dv[1],
    position = 0
  }
  local yaml_raw = t[4]
  if not yaml_raw or yaml_raw == '' then
    yaml_raw = 'layout:\n  direction: vertical\n  children: []'
  end
  local config = yaml.decode(yaml_raw)
  if not config or type(config) ~= 'table' then
    config = {
      layout = {
        direction = 'vertical',
        children = { }
      }
    }
  elseif not config.layout then
    config.layout = {
      direction = 'vertical',
      children = { }
    }
  elseif not config.layout.children then
    config.layout.children = { }
  end
  local position = #config.layout.children + 1
  new_widget.position = position
  table.insert(config.layout.children, {
    widget = new_widget
  })
  local updated_yaml = encode_layout_yaml(config)
  box.space._tdb_custom_views:update(pageId, {
    {
      '=',
      4,
      updated_yaml
    },
    {
      '=',
      6,
      os.time()
    }
  })
  return {
    id = t[1],
    name = t[2],
    description = t[3],
    yaml = updated_yaml,
    createdAt = tostring(t[5]),
    updatedAt = tostring(os.time())
  }
end
add_widget_to_view = function(viewId, widget)
  local t = box.space._tdb_custom_views:get(viewId)
  if not (t) then
    error("CustomView not found: " .. tostring(viewId))
  end
  if not (widget and type(widget) == 'table') then
    error("widget must be a table")
  end
  if not (widget.title) then
    error("widget.title is required")
  end
  local space_name = widget.space
  if widget.spaceId then
    local space = box.space._tdb_spaces:get(widget.spaceId)
    if space then
      space_name = space[2]
    end
  end
  if not (space_name) then
    error("widget.space or widget.spaceId is required")
  end
  local yaml_raw = t[4]
  if not yaml_raw or yaml_raw == '' then
    yaml_raw = 'layout:\n  direction: vertical\n  children: []'
  end
  local config = yaml.decode(yaml_raw)
  if not config or type(config) ~= 'table' then
    config = {
      layout = {
        direction = 'vertical',
        children = { }
      }
    }
  elseif not config.layout then
    config.layout = {
      direction = 'vertical',
      children = { }
    }
  elseif not config.layout.children then
    config.layout.children = { }
  end
  local position = #config.layout.children + 1
  local new_widget = {
    id = widget.id or tostring(uuid_mod.new()),
    title = widget.title,
    space = space_name,
    position = widget.position or position
  }
  if widget.type then
    new_widget.type = widget.type
  end
  if widget.fields and type(widget.fields) == 'table' and #widget.fields > 0 then
    new_widget.columns = widget.fields
  elseif widget.columns and type(widget.columns) == 'table' and #widget.columns > 0 then
    new_widget.columns = widget.columns
  end
  if widget.groupBy then
    new_widget.groupBy = widget.groupBy
  end
  if widget.dataViewId then
    new_widget.dataViewId = widget.dataViewId
  end
  if widget.params and type(widget.params) == 'table' then
    new_widget.params = widget.params
  end
  for key, value in pairs(widget) do
    if key ~= 'id' and key ~= 'title' and key ~= 'space' and key ~= 'spaceId' and key ~= 'position' and key ~= 'columns' and key ~= 'fields' and key ~= 'groupBy' and key ~= 'dataViewId' and key ~= 'type' and key ~= 'params' then
      new_widget[key] = value
    end
  end
  table.insert(config.layout.children, {
    widget = new_widget
  })
  local updated_yaml = encode_layout_yaml(config)
  box.space._tdb_custom_views:update(viewId, {
    {
      '=',
      4,
      updated_yaml
    },
    {
      '=',
      6,
      os.time()
    }
  })
  return {
    id = viewId,
    name = t[2],
    description = t[3],
    yaml = updated_yaml,
    createdAt = tostring(t[5]),
    updatedAt = tostring(os.time())
  }
end
return {
  Query = Query,
  Mutation = Mutation
}
