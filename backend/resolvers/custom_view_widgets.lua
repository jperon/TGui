local yaml = require('yaml')
local uuid_mod = require('uuid')
local yaml_quote
yaml_quote = function(value)
  local escaped = tostring(value):gsub("'", "''")
  return "'" .. escaped .. "'"
end
local yaml_scalar
yaml_scalar = function(value)
  local s = tostring(value)
  if s == '' then
    return yaml_quote(s)
  end
  if s:match('^%s' or s:match('%s$')) then
    return yaml_quote(s)
  end
  if s:match('[:#%[%]{},&*!|>%%@`"\']') then
    return yaml_quote(s)
  end
  if s:match('^[-?]') then
    return yaml_quote(s)
  end
  if s:match('^[%d%.]+$') then
    return yaml_quote(s)
  end
  if s == 'true' or s == 'false' or s == 'null' or s == '~' then
    return yaml_quote(s)
  end
  return s
end
local position_index
position_index = function(value, fallback)
  if type(value) == 'number' then
    return value
  end
  return fallback or 1
end
local encode_widget_type
encode_widget_type = function(widget, indent)
  if not (widget.type) then
    return ''
  end
  return indent .. "type: " .. yaml_quote(widget.type) .. "\n"
end
local encode_widget_params
encode_widget_params = function(params, indent)
  if not (params and type(params) == 'table') then
    return ''
  end
  local keys = { }
  for key in pairs(params) do
    table.insert(keys, key)
  end
  table.sort(keys)
  local body = ''
  for _, key in ipairs(keys) do
    local _continue_0 = false
    repeat
      local value = params[key]
      if type(value) == 'table' then
        _continue_0 = true
        break
      end
      body = body .. (indent .. "  " .. yaml_quote(key) .. ": " .. yaml_quote(value) .. "\n")
      _continue_0 = true
    until true
    if not _continue_0 then
      break
    end
  end
  if body == '' then
    return ''
  end
  return indent .. "params:\n" .. body
end
local is_columns_mapping
is_columns_mapping = function(columns)
  if not (columns and type(columns) == 'table') then
    return false
  end
  for key in pairs(columns) do
    if type(key) == 'string' then
      return true
    end
  end
  return false
end
local encode_widget_columns
encode_widget_columns = function(widget, indent)
  local columns = widget.columns
  if not (columns and type(columns) == 'table') then
    return ''
  end
  if is_columns_mapping(columns) then
    local keys = { }
    for key in pairs(columns) do
      table.insert(keys, key)
    end
    table.sort(keys)
    local body = ''
    for _, key in ipairs(keys) do
      local _continue_0 = false
      repeat
        local value = columns[key]
        if value == nil or value == '' then
          _continue_0 = true
          break
        end
        body = body .. (indent .. "  " .. yaml_scalar(key) .. ": " .. yaml_scalar(value) .. "\n")
        _continue_0 = true
      until true
      if not _continue_0 then
        break
      end
    end
    if body == '' then
      return ''
    end
    return indent .. "columns:\n" .. body
  end
  if #columns == 0 then
    return ''
  end
  local body = indent .. "columns:\n"
  for _, col in ipairs(columns) do
    body = body .. (indent .. "  - " .. yaml_scalar(col) .. "\n")
  end
  return body
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
        yaml_content = yaml_content .. (indent .. "    title: " .. yaml_scalar(child.widget.title or '') .. "\n")
        yaml_content = yaml_content .. (indent .. "    space: " .. yaml_scalar(child.widget.space or '') .. "\n")
        yaml_content = yaml_content .. (indent .. "    position: " .. tostring(position_index(child.widget.position, 1)) .. "\n")
        yaml_content = yaml_content .. encode_widget_type(child.widget, indent .. "    ")
        if child.widget.dataViewId then
          yaml_content = yaml_content .. (indent .. "    dataViewId: " .. tostring(child.widget.dataViewId) .. "\n")
        end
        yaml_content = yaml_content .. encode_widget_columns(child.widget, indent .. "    ")
        if child.widget.groupBy then
          yaml_content = yaml_content .. (indent .. "    groupBy: " .. tostring(child.widget.groupBy) .. "\n")
        end
        yaml_content = yaml_content .. encode_widget_params(child.widget.params, indent .. "    ")
        for key, value in pairs(child.widget) do
          if key ~= 'id' and key ~= 'title' and key ~= 'space' and key ~= 'position' and key ~= 'columns' and key ~= 'groupBy' and key ~= 'dataViewId' and key ~= 'type' and key ~= 'params' then
            yaml_content = yaml_content .. (indent .. "    " .. key .. ": " .. tostring(value) .. "\n")
          end
        end
      elseif child.zone then
        yaml_content = yaml_content .. (indent .. "- zone:\n")
        yaml_content = yaml_content .. (indent .. "    id: " .. tostring(child.zone.id) .. "\n")
        yaml_content = yaml_content .. (indent .. "    title: " .. yaml_scalar(child.zone.title or '') .. "\n")
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
      yaml_content = yaml_content .. ("        title: " .. yaml_scalar(zone.title or '') .. "\n")
      yaml_content = yaml_content .. ("        factor: " .. tostring(zone.factor or 1) .. "\n")
      yaml_content = yaml_content .. ("        direction: " .. tostring(zone.direction or 'vertical') .. "\n")
      if zone.children and #zone.children > 0 then
        yaml_content = yaml_content .. "        children:\n"
        for _, zone_child in ipairs(zone.children) do
          if zone_child.widget then
            local widget = zone_child.widget
            yaml_content = yaml_content .. "          - widget:\n"
            yaml_content = yaml_content .. ("              id: " .. tostring(widget.id) .. "\n")
            yaml_content = yaml_content .. ("              title: " .. yaml_scalar(widget.title or '') .. "\n")
            yaml_content = yaml_content .. ("              space: " .. yaml_scalar(widget.space or '') .. "\n")
            yaml_content = yaml_content .. ("              position: " .. tostring(position_index(widget.position, 1)) .. "\n")
            yaml_content = yaml_content .. encode_widget_type(widget, "              ")
            yaml_content = yaml_content .. encode_widget_columns(widget, "              ")
            if widget.groupBy then
              yaml_content = yaml_content .. ("              groupBy: " .. tostring(widget.groupBy) .. "\n")
            end
            yaml_content = yaml_content .. encode_widget_params(widget.params, "              ")
          end
        end
      end
    elseif child.widget then
      yaml_content = yaml_content .. "    - widget:\n"
      yaml_content = yaml_content .. ("        id: " .. tostring(child.widget.id) .. "\n")
      yaml_content = yaml_content .. ("        title: " .. yaml_scalar(child.widget.title or '') .. "\n")
      yaml_content = yaml_content .. ("        space: " .. yaml_scalar(child.widget.space or '') .. "\n")
      yaml_content = yaml_content .. ("        position: " .. tostring(position_index(child.widget.position, 1)) .. "\n")
      yaml_content = yaml_content .. encode_widget_type(child.widget, "        ")
      yaml_content = yaml_content .. encode_widget_columns(child.widget, "        ")
      if child.widget.groupBy then
        yaml_content = yaml_content .. ("        groupBy: " .. tostring(child.widget.groupBy) .. "\n")
      end
      yaml_content = yaml_content .. encode_widget_params(child.widget.params, "        ")
      for key, value in pairs(child.widget) do
        if key ~= 'id' and key ~= 'title' and key ~= 'space' and key ~= 'position' and key ~= 'columns' and key ~= 'groupBy' and key ~= 'type' and key ~= 'params' then
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
local add_widget_to_view
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
  local yaml_position = position_index(widget.position, position)
  local new_widget = {
    id = widget.id or tostring(uuid_mod.new()),
    title = widget.title,
    space = space_name,
    position = yaml_position
  }
  if widget.type then
    new_widget.type = widget.type
  end
  if is_columns_mapping(widget.columns) then
    new_widget.columns = widget.columns
  elseif widget.fields and type(widget.fields) == 'table' and #widget.fields > 0 then
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
  reorder_widgets = reorder_widgets,
  add_widget_to_view = add_widget_to_view,
  add_data_view_to_page = add_data_view_to_page,
  encode_layout_yaml = encode_layout_yaml
}
