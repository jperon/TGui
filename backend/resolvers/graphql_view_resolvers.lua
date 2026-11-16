local triggers_mod = require('core.triggers')
local graphql_flattener = require('core.graphql_flattener')
local spaces_mod = require('core.spaces')
local yield_every
yield_every = require('core.config').yield_every
local _ = {
  Query = {
    records_extended = function(_, args, ctx)
      require_auth(ctx)
      local space_id = args.spaceId
      local limit = args.limit or 100
      local offset = args.offset or 0
      local single_fk_map, multiple_fk_map = triggers_mod.build_single_and_multiple_maps(space_id)
      local sp = box.space["data_" .. tostring(space_id)]
      if not (sp) then
        return { }
      end
      local space_meta = box.space._tdb_spaces:get({
        space_id
      })
      if not (space_meta) then
        return { }
      end
      local field_definitions = { }
      local _list_0 = box.space._tdb_fields.index.by_space:select({
        space_id
      })
      for _index_0 = 1, #_list_0 do
        local field = _list_0[_index_0]
        local field_name = field[3]
        local field_type = field[4]
        local single_relation = single_fk_map[field_name]
        local multiple_relation = multiple_fk_map[field_name]
        if single_relation then
          field_definitions[field_name] = {
            type = 'Single',
            space = single_relation.toSpaceName,
            isRelation = true
          }
        elseif multiple_relation then
          field_definitions[field_name] = {
            type = 'List',
            space = multiple_relation.toSpaceName,
            isRelation = true
          }
        else
          field_definitions[field_name] = {
            type = field_type,
            space = space_meta[2],
            isRelation = false
          }
        end
      end
      local records = { }
      local fk_cache = { }
      local tuples = sp:select({ }, {
        limit = limit,
        offset = offset
      })
      for i, t in ipairs(tuples) do
        yield_every(i)
        local d
        if type(t[2]) == 'string' then
          d = json.decode(t[2])
        else
          d = t[2]
        end
        d._id = tostring(t[1])
        local proxy = triggers_mod.make_self_proxy_extended(d, single_fk_map, multiple_fk_map, fk_cache, space_meta[2])
        local record_data = { }
        local _list_1 = box.space._tdb_fields.index.by_space:select({
          space_id
        })
        for _index_0 = 1, #_list_1 do
          local field = _list_1[_index_0]
          local field_name = field[3]
          local value = proxy[field_name]
          if value and type(value) == 'table' and value.__self then
            record_data[field_name] = proxy_to_table(value)
          else
            record_data[field_name] = value
          end
        end
        table.insert(records, record_data)
      end
      return records
    end,
    aggregated_records = function(_, args, ctx)
      require_auth(ctx)
      local space_id = args.config.spaceId
      local config = args.config
      local base_records = Query.records_extended(_, {
        spaceId = space_id
      }, ctx)
      if config.filter and config.filter.formula then
        base_records = apply_filter_to_records(base_records, config.filter.formula, space_id)
      end
      if config.groupBy and #config.groupBy > 0 then
        return apply_grouping_and_aggregation(base_records, config)
      end
      return base_records
    end
  }
}
local proxy_to_table
proxy_to_table = function(proxy, visited)
  if visited == nil then
    visited = { }
  end
  if not (proxy) then
    return nil
  end
  local proxy_id = tostring(proxy)
  if visited[proxy_id] then
    return {
      _circular = true
    }
  end
  visited[proxy_id] = true
  local result = { }
  for key, value in pairs(proxy) do
    if type(value) == 'table' and value.__self then
      result[key] = proxy_to_table(value, visited)
    elseif type(value) == 'table' and not (type(value) == 'function') then
      if is_array(value) then
        do
          local _accum_0 = { }
          local _len_0 = 1
          for _index_0 = 1, #value do
            local item = value[_index_0]
            if type(item) == 'table' and item.__self then
              _accum_0[_len_0] = proxy_to_table(item, visited)
              _len_0 = _len_0 + 1
            end
          end
          result[key] = _accum_0
        end
      else
        result[key] = value
      end
    else
      result[key] = value
    end
  end
  return result
end
local is_array
is_array = function(tbl)
  if not (type(tbl) == 'table') then
    return false
  end
  local count = 0
  for key, _ in pairs(tbl) do
    if type(key) ~= 'number' then
      return false
    end
    count = count + 1
  end
  return count > 0
end
local apply_filter_to_records
apply_filter_to_records = function(records, formula, space_id)
  if not (formula and formula ~= '') then
    return records
  end
  local compiled = triggers_mod.compile_formula(formula, 'filter', 'moonscript')
  if not (compiled) then
    return records
  end
  local space_helper
  space_helper = function()
    local sp = box.space["data_" .. tostring(space_id)]
    if not (sp) then
      return { }
    end
    local results = { }
    local _list_0 = sp:select({ })
    for _index_0 = 1, #_list_0 do
      local t = _list_0[_index_0]
      local d
      if type(t[2]) == 'string' then
        d = json.decode(t[2])
      else
        d = t[2]
      end
      d._id = tostring(t[1])
      table.insert(results, d)
    end
    return results
  end
  local filtered = { }
  for i, record in ipairs(records) do
    yield_every(i)
    local single_fk_map, multiple_fk_map = triggers_mod.build_single_and_multiple_maps(space_id)
    local proxy = triggers_mod.make_self_proxy_extended(record, single_fk_map, multiple_fk_map, nil, space_id)
    local success, result = pcall(compiled, proxy, space_helper)
    if success and result then
      table.insert(filtered, record)
    end
  end
  return filtered
end
local apply_grouping_and_aggregation
apply_grouping_and_aggregation = function(records, config)
  if not (records and #records > 0) then
    return records
  end
  local groups = { }
  for record in records do
    local key_parts = { }
    local _list_0 = config.groupBy
    for _index_0 = 1, #_list_0 do
      local group_field = _list_0[_index_0]
      local value = record[group_field] or ''
      table.insert(key_parts, tostring(value))
    end
    local key = table.concat(key_parts, '|')
    if not groups[key] then
      groups[key] = {
        records = { },
        _values = { }
      }
    end
    table.insert(groups[key].records, record)
    if config.aggregates then
      local _list_1 = config.aggregates
      for _index_0 = 1, #_list_1 do
        local agg = _list_1[_index_0]
        local agg_key = tostring(agg.field) .. "_" .. tostring(agg.func)
        groups[key]._values[agg_key] = {
          count = 0,
          sum = 0,
          min = nil,
          max = nil
        }
      end
    end
  end
  for key, group in pairs(groups) do
    if config.aggregates then
      local _list_0 = group.records
      for _index_0 = 1, #_list_0 do
        local record = _list_0[_index_0]
        local _list_1 = config.aggregates
        for _index_1 = 1, #_list_1 do
          local agg = _list_1[_index_1]
          if agg.field then
            local agg_key = tostring(agg.field) .. "_" .. tostring(agg.func)
            local value = tonumber(record[agg.field])
            if value ~= nil then
              local acc = group._values[agg_key]
              acc.count = acc.count + 1
              acc.sum = acc.sum + value
              if acc.min ~= nil then
                acc.min = math.min(acc.min, value)
              else
                acc.min = value
              end
              if acc.max ~= nil then
                acc.max = math.max(acc.max, value)
              else
                acc.max = value
              end
            end
          end
        end
      end
    end
  end
  local result = { }
  for key, group in pairs(groups) do
    local result_record = { }
    local _list_0 = config.groupBy
    for _index_0 = 1, #_list_0 do
      local i, group_field = _list_0[_index_0]
      local key_parts = { }
      local _list_1 = config.groupBy
      for _index_1 = 1, #_list_1 do
        local j, gf = _list_1[_index_1]
        if j <= i then
          table.insert(key_parts, group.records[1][gf] or '')
        end
      end
      result_record[group_field] = table.concat(key_parts, '|')
    end
    if config.aggregates then
      local _list_1 = config.aggregates
      for _index_0 = 1, #_list_1 do
        local agg = _list_1[_index_0]
        local agg_key = tostring(agg.field) .. "_" .. tostring(agg.func)
        local acc = group._values[agg_key]
        if acc then
          local alias = agg.as or tostring(agg.func) .. "_" .. tostring(agg.field)
          local func = agg.func:lower()
          local _exp_0 = func
          if 'count' == _exp_0 then
            result_record[alias] = acc.count
          elseif 'sum' == _exp_0 then
            result_record[alias] = acc.sum
          elseif 'avg' == _exp_0 then
            if acc.count > 0 then
              result_record[alias] = acc.sum / acc.count
            else
              result_record[alias] = 0
            end
          elseif 'min' == _exp_0 then
            result_record[alias] = acc.min
          elseif 'max' == _exp_0 then
            result_record[alias] = acc.max
          else
            result_record[alias] = nil
          end
        end
      end
    end
    table.insert(result, result_record)
  end
  return result
end
return {
  Query = Query
}
