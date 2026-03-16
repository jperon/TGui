local yaml = require('yaml')
local uuid_mod = require('uuid')
local json = require('json')
local require_auth
require_auth = require('resolvers.utils').require_auth
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
local update_custom_view
update_custom_view = function(id, name, description, yaml)
  local t = box.space._tdb_custom_views:get(id)
  if not (t) then
    error("CustomView not found: " .. tostring(id))
  end
  local now = require('clock').time()
  local new_name = name or t[2]
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
local delete_custom_view
delete_custom_view = function(id)
  box.space._tdb_custom_views:delete(id)
  return true
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
  local new_children = { }
  local processed_zones = { }
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
            local zone = zones_map[parent_id].zone
            if not zone.children then
              zone.children = { }
            end
            table.insert(zone.children, {
              widget = widget
            })
            processed_zones[parent_id] = true
          else
            table.insert(new_children, {
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
          table.insert(new_children, {
            widget = new_widget
          })
        end
      end
    end
  else
    for _, child in ipairs(config.layout.children) do
      table.insert(new_children, child)
    end
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
    if child.widget then
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
  local updated_yaml = yaml_content
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
local add_widget_to_view
add_widget_to_view = function(viewId, widget)
  local t = box.space._tdb_custom_views:get(viewId)
  if not (t) then
    error("CustomView not found: " .. tostring(viewId))
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
  local widget_id = uuid_mod()
  local source_name = widget.spaceId
  local space_record = box.space._tdb_spaces:get(widget.spaceId)
  if space_record then
    source_name = space_record[2]
  else
    local dv_record = box.space._tdb_data_views:get(widget.spaceId)
    if dv_record then
      source_name = dv_record[2]
    end
  end
  local position = #config.layout.children + 1
  local new_widget = {
    id = widget_id,
    title = widget.title,
    space = source_name,
    position = position
  }
  if widget.fields and #widget.fields > 0 then
    new_widget.columns = widget.fields
  end
  if widget.groupBy then
    new_widget.groupBy = widget.groupBy
  end
  if widget.params and next(widget.params) then
    for key, value in pairs(widget.params) do
      new_widget[key] = value
    end
  end
  table.insert(config.layout.children, {
    widget = new_widget
  })
  local yaml_content = "layout:\n"
  yaml_content = yaml_content .. ("  direction: " .. (config.layout.direction or 'vertical') .. "\n")
  yaml_content = yaml_content .. "  children:\n"
  for _, child in ipairs(config.layout.children) do
    if child.widget then
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
  local updated_yaml = yaml_content
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
local Query = {
  customViews = function(_, args, ctx)
    require_auth(ctx)
    return list_custom_views()
  end,
  customView = function(_, args, ctx)
    require_auth(ctx)
    return get_custom_view(args.id)
  end
}
local Mutation = {
  createCustomView = function(_, args, ctx)
    require_auth(ctx)
    local i = args.input or args
    if not (i.name) then
      error("name is required")
    end
    return create_custom_view(i.name, i.description, i.yaml)
  end,
  updateCustomView = function(_, args, ctx)
    require_auth(ctx)
    local i = args.input
    return update_custom_view(args.id, i.name, i.description, i.yaml)
  end,
  deleteCustomView = function(_, args, ctx)
    require_auth(ctx)
    return delete_custom_view(args.id)
  end,
  addWidgetToView = function(_, args, ctx)
    require_auth(ctx)
    return add_widget_to_view(args.viewId, args.widget)
  end,
  reorderWidgets = function(_, args, ctx)
    require_auth(ctx)
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
    require_auth(ctx)
    local pageId = args.pageId
    local zoneData = args.zoneData or { }
    if not (pageId) then
      error("pageId is required")
    end
    return create_zone(pageId, zoneData)
  end,
  resizeZone = function(_, args, ctx)
    require_auth(ctx)
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
    require_auth(ctx)
    return add_data_view_to_page(args.pageId, args.dataViewId)
  end
}
local create_zone
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
local resize_zone
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
local merge_zones
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
local split_zone
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
local encode_layout_yaml
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
local add_data_view_to_page
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
local _ = {
  mergeZones = function(_, args, ctx)
    require_auth(ctx)
    return merge_zones(args.pageId, args.zoneId1, args.zoneId2)
  end
}
_ = {
  splitZone = function(_, args, ctx)
    require_auth(ctx)
    return split_zone(args.pageId, args.zoneId, args.direction)
  end
}
return {
  Query = Query,
  Mutation = Mutation
}
