local require_auth
require_auth = require('resolvers.utils').require_auth
local json = require('json')
local ALLOWED_FNS = {
  sum = true,
  count = true,
  avg = true,
  min = true,
  max = true
}
local make_alias
make_alias = function(agg)
  if agg.as and agg.as ~= '' then
    return agg.as
  end
  if not agg.field then
    return 'count'
  else
    return tostring(agg.fn) .. "_" .. tostring(agg.field)
  end
end
local Query = {
  aggregateSpace = function(_, args, ctx)
    require_auth(ctx)
    local space_name = args.spaceName
    local group_by = args.groupBy or { }
    local aggregates = args.aggregate or { }
    if not (space_name:match("^[%w_]+$")) then
      error("Nom d'espace invalide: " .. tostring(space_name))
    end
    for _index_0 = 1, #aggregates do
      local agg = aggregates[_index_0]
      local fn = (agg.fn or ''):lower()
      if not (ALLOWED_FNS[fn]) then
        error("Fonction d'agrégation non supportée: " .. tostring(agg.fn))
      end
    end
    local sp = box.space["data_" .. tostring(space_name)]
    if not (sp) then
      error("Espace introuvable: " .. tostring(space_name))
    end
    local groups = { }
    local group_keys = { }
    local _list_0 = sp:select({ })
    for _index_0 = 1, #_list_0 do
      local tuple = _list_0[_index_0]
      local d
      if type(tuple[2]) == 'string' then
        d = json.decode(tuple[2])
      else
        d = tuple[2]
      end
      local parts
      do
        local _accum_0 = { }
        local _len_0 = 1
        for _index_1 = 1, #group_by do
          local f = group_by[_index_1]
          _accum_0[_len_0] = tostring(d[f] ~= nil and d[f] or '')
          _len_0 = _len_0 + 1
        end
        parts = _accum_0
      end
      local key = table.concat(parts, '\t')
      if not (groups[key]) then
        groups[key] = {
          _d = d,
          _vals = { }
        }
        table.insert(group_keys, key)
        for _index_1 = 1, #aggregates do
          local agg = aggregates[_index_1]
          groups[key]._vals[agg] = {
            count = 0,
            sum = 0,
            min = nil,
            max = nil
          }
        end
      end
      local g = groups[key]
      for _index_1 = 1, #aggregates do
        local agg = aggregates[_index_1]
        local acc = g._vals[agg]
        acc.count = acc.count + 1
        if agg.field then
          local val = tonumber(d[agg.field])
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
    local rows
    do
      local _accum_0 = { }
      local _len_0 = 1
      for _index_0 = 1, #group_keys do
        local key = group_keys[_index_0]
        local g = groups[key]
        local row = { }
        for _index_1 = 1, #group_by do
          local f = group_by[_index_1]
          row[f] = g._d[f]
        end
        for _index_1 = 1, #aggregates do
          local agg = aggregates[_index_1]
          local alias = make_alias(agg)
          local acc = g._vals[agg]
          local fn = agg.fn:lower()
          local _exp_0 = fn
          if 'count' == _exp_0 then
            row[alias] = acc.count
          elseif 'sum' == _exp_0 then
            row[alias] = acc.sum
          elseif 'avg' == _exp_0 then
            if acc.count > 0 then
              row[alias] = acc.sum / acc.count
            else
              row[alias] = nil
            end
          elseif 'min' == _exp_0 then
            row[alias] = acc.min
          elseif 'max' == _exp_0 then
            row[alias] = acc.max
          end
        end
        local _value_0 = row
        _accum_0[_len_0] = _value_0
        _len_0 = _len_0 + 1
      end
      rows = _accum_0
    end
    return rows
  end
}
return {
  Query = Query
}
