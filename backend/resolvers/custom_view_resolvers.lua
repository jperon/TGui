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
  for _, child in ipairs(config.layout.children) do
    if child.widget then
      widget_map[child.widget.id] = child.widget
    end
  end
  local new_children = { }
  if widgetPositions and type(widgetPositions) == 'table' and #widgetPositions > 0 then
    for i = 1, #widgetPositions do
      local pos = widgetPositions[i]
      if type(pos) == 'table' and pos.widgetId then
        local widget = widget_map[pos.widgetId]
        if widget then
          widget.position = pos.index or i
          table.insert(new_children, {
            widget = widget
          })
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
  end
}
return {
  Query = Query,
  Mutation = Mutation
}
