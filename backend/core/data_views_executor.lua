local json = require('json')
local log = require('log')
local make_self_proxy, build_fk_def_map
do
  local _obj_0 = require('core.triggers')
  make_self_proxy, build_fk_def_map = _obj_0.make_self_proxy, _obj_0.build_fk_def_map
end
local execute_view
execute_view = function(source_space_ref, config_json, params)
  local config
  if type(config_json) == 'string' and config_json ~= '' then
    config = json.decode(config_json)
  else
    config = { }
  end
  local sp_meta = box.space._tdb_spaces:get({
    source_space_ref
  })
  sp_meta = sp_meta or box.space._tdb_spaces.index.by_name:get({
    source_space_ref
  })
  if not (sp_meta) then
    error("Source space not found: " .. tostring(source_space_ref))
  end
  local space_id = sp_meta[1]
  local source_space_name = sp_meta[2]
  local sp = box.space["data_" .. tostring(source_space_name)]
  if not (sp) then
    return { }
  end
  local fk_def_map = build_fk_def_map(space_id)
  local fk_cache = { }
  local records = { }
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
    local proxy = make_self_proxy(d, fk_def_map, fk_cache, source_space_name)
    table.insert(records, {
      d = d,
      proxy = proxy
    })
  end
  if config.filter then
    local resolvers = require('resolvers.data_resolvers')
    local filtered = { }
    for _index_0 = 1, #records do
      local rec = records[_index_0]
      if resolvers.matches_filter(rec.proxy, config.filter) then
        table.insert(filtered, rec)
      end
    end
    records = filtered
  end
  if config.groupBy and #config.groupBy > 0 then
    local groups = { }
    local group_keys = { }
    for _index_0 = 1, #records do
      local rec = records[_index_0]
      local parts
      do
        local _accum_0 = { }
        local _len_0 = 1
        local _list_1 = config.groupBy
        for _index_1 = 1, #_list_1 do
          local f = _list_1[_index_1]
          _accum_0[_len_0] = tostring(rec.proxy[f] ~= nil and rec.proxy[f] or '')
          _len_0 = _len_0 + 1
        end
        parts = _accum_0
      end
      local key = table.concat(parts, '\t')
      if not (groups[key]) then
        groups[key] = {
          _d = rec.d,
          _vals = { }
        }
        table.insert(group_keys, key)
        if config.aggregates then
          local _list_1 = config.aggregates
          for _index_1 = 1, #_list_1 do
            local agg = _list_1[_index_1]
            groups[key]._vals[agg] = {
              count = 0,
              sum = 0,
              min = nil,
              max = nil
            }
          end
        end
      end
      local g = groups[key]
      if config.aggregates then
        local _list_1 = config.aggregates
        for _index_1 = 1, #_list_1 do
          local agg = _list_1[_index_1]
          local acc = g._vals[agg]
          acc.count = acc.count + 1
          if agg.field then
            local val = tonumber(rec.proxy[agg.field])
            if val ~= nil then
              acc.sum = acc.sum + val
              if acc.min ~= nil then
                acc.min = math.min(acc.min, val)
              else
                acc.min = val
              end
              if acc.max ~= nil then
                acc.max = math.max(acc.max, val)
              else
                acc.max = val
              end
            end
          end
        end
      end
    end
    local agg_records = { }
    for _index_0 = 1, #group_keys do
      local key = group_keys[_index_0]
      local g = groups[key]
      local row = { }
      local _list_1 = config.groupBy
      for _index_1 = 1, #_list_1 do
        local f = _list_1[_index_1]
        row[f] = g._d[f]
      end
      if config.aggregates then
        local _list_2 = config.aggregates
        for _index_1 = 1, #_list_2 do
          local agg = _list_2[_index_1]
          local alias = agg.as or ((function()
            if agg.field then
              return tostring(agg.fn) .. "_" .. tostring(agg.field)
            else
              return "count"
            end
          end)())
          local acc = g._vals[agg]
          local fn = (agg.fn or ''):lower()
          if fn == 'count' then
            row[alias] = acc.count
          elseif fn == 'sum' then
            row[alias] = acc.sum
          elseif fn == 'avg' then
            if acc.count > 0 then
              row[alias] = acc.sum / acc.count
            else
              row[alias] = nil
            end
          elseif fn == 'min' then
            row[alias] = acc.min
          elseif fn == 'max' then
            row[alias] = acc.max
          end
        end
      end
      table.insert(agg_records, row)
    end
    do
      local _accum_0 = { }
      local _len_0 = 1
      for _index_0 = 1, #agg_records do
        local row = agg_records[_index_0]
        _accum_0[_len_0] = {
          d = row,
          proxy = row
        }
        _len_0 = _len_0 + 1
      end
      records = _accum_0
    end
  end
  if config.orderBy and #config.orderBy > 0 then
    table.sort(records, function(a, b)
      local _list_1 = config.orderBy
      for _index_0 = 1, #_list_1 do
        local _continue_0 = false
        repeat
          local order = _list_1[_index_0]
          local field = order.field
          local vA = a.proxy[field]
          local vB = b.proxy[field]
          if vA == nil and vB == nil then
            _continue_0 = true
            break
          end
          if vA == nil then
            return false
          end
          if vB == nil then
            return true
          end
          local cmp
          if type(vA) == "number" and type(vB) == "number" then
            cmp = vA < vB
          else
            cmp = tostring(vA) < tostring(vB)
          end
          if tostring(vA) ~= tostring(vB) then
            if order.desc then
              return not cmp
            else
              return cmp
            end
          end
          _continue_0 = true
        until true
        if not _continue_0 then
          break
        end
      end
      return false
    end)
  end
  if config.columns and #config.columns > 0 then
    local mapped = { }
    for _index_0 = 1, #records do
      local rec = records[_index_0]
      local row = { }
      local _list_1 = config.columns
      for _index_1 = 1, #_list_1 do
        local col = _list_1[_index_1]
        if type(col) == 'string' then
          row[col] = rec.proxy[col]
        elseif type(col) == 'table' and col.field then
          local alias = col.as or col.field
          row[alias] = rec.proxy[col.field]
        end
      end
      if not (row.id) then
        row.id = rec.d._id
      end
      table.insert(mapped, row)
    end
    do
      local _accum_0 = { }
      local _len_0 = 1
      for _index_0 = 1, #mapped do
        local row = mapped[_index_0]
        _accum_0[_len_0] = {
          d = row,
          proxy = row
        }
        _len_0 = _len_0 + 1
      end
      records = _accum_0
    end
  end
  local limit = tonumber(params and params.limit) or tonumber(config.limit)
  local offset = tonumber(params and params.offset) or tonumber(config.offset) or 0
  if limit or offset > 0 then
    local sliced = { }
    local start_idx = offset + 1
    local end_idx
    if limit then
      end_idx = offset + limit
    else
      end_idx = #records
    end
    for i = start_idx, math.min(end_idx, #records) do
      table.insert(sliced, records[i])
    end
    records = sliced
  end
  local _accum_0 = { }
  local _len_0 = 1
  for _index_0 = 1, #records do
    local rec = records[_index_0]
    _accum_0[_len_0] = rec.d
    _len_0 = _len_0 + 1
  end
  return _accum_0
end
return {
  execute_view = execute_view
}
