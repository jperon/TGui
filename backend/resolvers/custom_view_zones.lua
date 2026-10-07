local yaml = require('yaml')
local uuid_mod = require('uuid')
local encode_layout_yaml
encode_layout_yaml = require('resolvers.custom_view_widgets').encode_layout_yaml
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
return {
  create_zone = create_zone,
  resize_zone = resize_zone,
  merge_zones = merge_zones,
  split_zone = split_zone,
  find_zone_with_parent = find_zone_with_parent
}
