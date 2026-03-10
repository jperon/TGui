local json = require('json')
local log = require('log')
local safe_call
safe_call = require('core.config').safe_call
local DEBUG_FK_PROXY = false
local fk_cache = {
  spaces = { },
  fk_maps = { }
}
local decode_tuple
decode_tuple = function(tup)
  local data
  if type(tup[2]) == 'string' then
    data = json.decode(tup[2])
  else
    data = tup[2]
  end
  data._id = tostring(tup[1])
  return data
end
local ensure_space
ensure_space = function(s_name, to_field_name)
  local sc = fk_cache.spaces[s_name]
  if not (sc) then
    sc = {
      records = { },
      by_field = { }
    }
    local tb = box.space["data_" .. tostring(s_name)]
    if tb then
      if DEBUG_FK_PROXY then
        print("DEBUG ensure_space: loading " .. tostring(#tb) .. " records from " .. tostring(s_name))
      end
      local _list_0 = tb:select({ })
      for _index_0 = 1, #_list_0 do
        local tup = _list_0[_index_0]
        local d = decode_tuple(tup)
        sc.records[d._id] = d
      end
    end
    fk_cache.spaces[s_name] = sc
  end
  if not (sc.by_field['_id']) then
    local idx = { }
    if DEBUG_FK_PROXY then
      print("DEBUG ensure_space: building index for _id")
    end
    for _, d in pairs(sc.records) do
      if d._id ~= nil then
        local key = tostring(d._id)
        idx[key] = d
      end
    end
    sc.by_field['_id'] = idx
  end
  if to_field_name ~= '_id' and not sc.by_field[to_field_name] then
    local idx = { }
    if DEBUG_FK_PROXY then
      print("DEBUG ensure_space: building index for " .. tostring(to_field_name))
    end
    for _, d in pairs(sc.records) do
      if d[to_field_name] ~= nil then
        local key = tostring(d[to_field_name])
        idx[key] = d
      end
    end
    sc.by_field[to_field_name] = idx
  end
  return sc
end
local ensure_fk_def_map
ensure_fk_def_map = function(space_id)
  if fk_cache.fk_maps[space_id] then
    return fk_cache.fk_maps[space_id]
  end
  local rels = { }
  local _list_0 = box.space._tdb_relations:select({ })
  for _index_0 = 1, #_list_0 do
    local t = _list_0[_index_0]
    if t[2] == space_id then
      rels[t[3]] = {
        toSpaceId = t[4],
        toFieldId = t[5]
      }
    end
  end
  local space_by_id = { }
  local _list_1 = box.space._tdb_spaces:select({ })
  for _index_0 = 1, #_list_1 do
    local t = _list_1[_index_0]
    space_by_id[t[1]] = {
      name = t[2]
    }
  end
  local field_by_id = { }
  local _list_2 = box.space._tdb_fields.index.by_space:select({
    space_id
  })
  for _index_0 = 1, #_list_2 do
    local t = _list_2[_index_0]
    field_by_id[t[1]] = {
      name = t[3]
    }
  end
  for _, rel in pairs(rels) do
    local _list_3 = box.space._tdb_fields.index.by_space:select({
      rel.toSpaceId
    })
    for _index_0 = 1, #_list_3 do
      local t = _list_3[_index_0]
      field_by_id[t[1]] = {
        name = t[3]
      }
    end
  end
  local fk_def_map = { }
  for field_name, rel in pairs(rels) do
    local to_space = space_by_id[rel.toSpaceId]
    local to_field = field_by_id[rel.toFieldId]
    if to_space and to_field then
      fk_def_map[field_name] = {
        toSpaceName = to_space.name,
        toFieldName = to_field.name
      }
    end
  end
  fk_cache.fk_maps[space_id] = fk_def_map
  return fk_def_map
end
local make_self_proxy
make_self_proxy = function(record, space_id, cache, space_name)
  if cache == nil then
    cache = fk_cache
  end
  if not (space_name) then
    local space_meta = box.space._tdb_spaces:get(space_id)
    space_name = space_meta and space_meta[2]
  end
  local fk_def_map = ensure_fk_def_map(space_id)
  local proxy = setmetatable({ }, {
    __index = function(t, k)
      local cached = rawget(t, k)
      if cached ~= nil then
        return cached
      end
      local v = record[k]
      local fk = fk_def_map and fk_def_map[k]
      if fk then
        local sc = ensure_space(fk.toSpaceName, '_id')
        local d = sc.by_field['_id'] and sc.by_field['_id'][tostring(v)]
        if DEBUG_FK_PROXY or not d then
          print("DEBUG FK lookup:")
          print("  - space: " .. tostring(fk.toSpaceName))
          print("  - toField: " .. tostring(fk.toFieldName))
          print("  - searching for value: " .. tostring(tostring(v)))
          print("  - found: " .. tostring(tostring(d)))
        end
        if d then
          local nested = make_self_proxy(d, nil, cache, fk.toSpaceName)
          rawset(t, k, nested)
          return nested
        end
        return nil
      end
      return v
    end
  })
  return proxy
end
local clear_cache
clear_cache = function()
  fk_cache.spaces = { }
  fk_cache.fk_maps = { }
end
return {
  make_self_proxy = make_self_proxy,
  clear_cache = clear_cache,
  DEBUG_FK_PROXY = DEBUG_FK_PROXY,
  ensure_space = ensure_space,
  ensure_fk_def_map = ensure_fk_def_map
}
