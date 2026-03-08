local json = require('json')
local uuid_mod = require('uuid')
local spaces_mod = require('core.spaces')
local require_auth
require_auth = require('resolvers.utils').require_auth
local data_space
data_space = function(space_id)
  local meta = box.space._tdb_spaces:get(space_id)
  if not (meta) then
    error("Space not found: " .. tostring(space_id))
  end
  local sp = box.space["data_" .. tostring(meta[2])]
  if not (sp) then
    error("Data space not initialized: " .. tostring(meta[2]))
  end
  return sp, meta
end
local sequence_fields
sequence_fields = function(space_id)
  local result = { }
  local _list_0 = box.space._tdb_fields.index.by_space:select({
    space_id
  })
  for _index_0 = 1, #_list_0 do
    local t = _list_0[_index_0]
    if t[4] == 'Sequence' then
      result[t[3]] = t[1]
    end
  end
  return result
end
local matches_filter
matches_filter = function(parsed, flt)
  if not (flt) then
    return true
  end
  local ok
  if flt.field then
    local v = tostring((parsed[flt.field] or ''))
    local _exp_0 = flt.op
    if 'EQ' == _exp_0 then
      ok = v == flt.value
    elseif 'NEQ' == _exp_0 then
      ok = v ~= flt.value
    elseif 'CONTAINS' == _exp_0 then
      ok = v:find(flt.value, 1, true) ~= nil
    elseif 'STARTS_WITH' == _exp_0 then
      ok = v:sub(1, #flt.value) == flt.value
    else
      ok = true
    end
  else
    ok = true
  end
  if ok and flt["and"] then
    local _list_0 = flt["and"]
    for _index_0 = 1, #_list_0 do
      local sub = _list_0[_index_0]
      if not (ok) then
        break
      end
      ok = matches_filter(parsed, sub)
    end
  end
  if not ok and flt["or"] then
    local _list_0 = flt["or"]
    for _index_0 = 1, #_list_0 do
      local sub = _list_0[_index_0]
      if matches_filter(parsed, sub) then
        ok = true
        break
      end
    end
  end
  return ok
end
local apply_filter
apply_filter = function(tuples, filter)
  if not (filter and (filter.field or filter["and"] or filter["or"])) then
    return tuples
  end
  local filtered = { }
  for _index_0 = 1, #tuples do
    local rec = tuples[_index_0]
    local parsed
    if type(rec.data) == 'string' then
      parsed = json.decode(rec.data)
    else
      parsed = rec.data
    end
    if matches_filter(parsed, filter) then
      table.insert(filtered, rec)
    end
  end
  return filtered
end
local Mutation = {
  insertRecord = function(_, args, ctx)
    require_auth(ctx)
    local sp = data_space(args.spaceId)
    local id = tostring(uuid_mod.new())
    local data
    if type(args.data) == 'string' then
      data = json.decode(args.data)
    else
      data = args.data
    end
    for field_name, field_id in pairs(sequence_fields(args.spaceId)) do
      local seq = box.sequence["_tdb_seq_" .. tostring(field_id)]
      if seq then
        data[field_name] = seq:next()
      end
    end
    sp:insert({
      id,
      json.encode(data)
    })
    return {
      id = id,
      spaceId = args.spaceId,
      data = json.encode(data)
    }
  end,
  updateRecord = function(_, args, ctx)
    require_auth(ctx)
    local sp = data_space(args.spaceId)
    local existing = sp:get(args.id)
    if not (existing) then
      error("Record not found: " .. tostring(args.id))
    end
    local old_data = json.decode(existing[2])
    local new_data
    if type(args.data) == 'string' then
      new_data = json.decode(args.data)
    else
      new_data = args.data
    end
    local seq_fields = sequence_fields(args.spaceId)
    for k, v in pairs(new_data) do
      if not (seq_fields[k]) then
        old_data[k] = v
      end
    end
    sp:replace({
      args.id,
      json.encode(old_data)
    })
    return {
      id = args.id,
      spaceId = args.spaceId,
      data = json.encode(old_data)
    }
  end,
  deleteRecord = function(_, args, ctx)
    require_auth(ctx)
    local sp = data_space(args.spaceId)
    sp:delete(args.id)
    return true
  end
}
local Query = {
  records = function(_, args, ctx)
    require_auth(ctx)
    local sp = data_space(args.spaceId)
    local limit = args.limit or 100
    local offset = args.offset or 0
    local all = { }
    local _list_0 = sp:select({ })
    for _index_0 = 1, #_list_0 do
      local t = _list_0[_index_0]
      table.insert(all, {
        id = t[1],
        spaceId = args.spaceId,
        data = t[2]
      })
    end
    local filtered = apply_filter(all, args.filter)
    local total = #filtered
    local items = { }
    for i = offset + 1, math.min(offset + limit, total) do
      table.insert(items, filtered[i])
    end
    return {
      items = items,
      total = total,
      offset = offset,
      limit = limit
    }
  end,
  record = function(_, args, ctx)
    local sp = data_space(args.spaceId)
    local t = sp:get(args.id)
    if not (t) then
      return nil
    end
    return {
      id = t[1],
      spaceId = args.spaceId,
      data = t[2]
    }
  end
}
return {
  Query = Query,
  Mutation = Mutation
}
