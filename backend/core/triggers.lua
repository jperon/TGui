local json = require('json')
local log = require('log')
local spaces_mod = require('core.spaces')
local active_triggers = { }
local compile_formula
compile_formula = function(formula, field_name)
  local fn_str = "return function(self, space) return " .. formula .. " end"
  local ok, compiled = pcall(load, fn_str)
  if not ok or type(compiled) ~= 'function' then
    log.error("tdb triggers: parse error for field '" .. tostring(field_name) .. "': " .. tostring(compiled))
    return nil
  end
  local ok2, fn = pcall(compiled)
  if not ok2 or type(fn) ~= 'function' then
    log.error("tdb triggers: init error for field '" .. tostring(field_name) .. "': " .. tostring(fn))
    return nil
  end
  return fn
end
local make_self_proxy
make_self_proxy = function(record, fk_def_map)
  local decode_tuple
  decode_tuple = function(t)
    local d
    if type(t[2]) == 'string' then
      d = json.decode(t[2])
    else
      d = t[2]
    end
    d._id = tostring(t[1])
    return d
  end
  local proxy = { }
  setmetatable(proxy, {
    __index = function(t, k)
      local cached = rawget(t, k)
      if cached ~= nil then
        return cached
      end
      local v = record[k]
      if v == nil then
        return nil
      end
      local fk = fk_def_map and fk_def_map[k]
      if fk then
        local tb = box.space["data_" .. tostring(fk.toSpaceName)]
        if tb then
          local _list_0 = tb:select({ })
          for _index_0 = 1, #_list_0 do
            local tup = _list_0[_index_0]
            local d = decode_tuple(tup)
            if tostring(d[fk.toFieldName]) == tostring(v) then
              rawset(t, k, d)
              return d
            end
          end
        end
        return nil
      end
      return v
    end
  })
  return proxy
end
local should_run
should_run = function(is_insert, trigger_fields_list, old_data, new_data)
  if is_insert then
    return true
  end
  if #trigger_fields_list == 0 then
    return false
  end
  if trigger_fields_list[1] == '*' then
    return true
  end
  for _, fname in ipairs(trigger_fields_list) do
    if tostring(old_data[fname] or '') ~= tostring(new_data[fname] or '') then
      return true
    end
  end
  return false
end
local make_space_helper
make_space_helper = function()
  local decode_tuple
  decode_tuple = function(t)
    local d
    if type(t[2]) == 'string' then
      d = json.decode(t[2])
    else
      d = t[2]
    end
    d._id = tostring(t[1])
    return d
  end
  return function(sname)
    local sp = box.space["data_" .. tostring(sname)]
    if not (sp) then
      return { }
    end
    local _accum_0 = { }
    local _len_0 = 1
    local _list_0 = sp:select({ })
    for _index_0 = 1, #_list_0 do
      local t = _list_0[_index_0]
      _accum_0[_len_0] = decode_tuple(t)
      _len_0 = _len_0 + 1
    end
    return _accum_0
  end
end
local make_trigger_fn
make_trigger_fn = function(trigger_defs)
  local space_helper = make_space_helper()
  return function(old_tuple, new_tuple)
    if new_tuple == nil then
      return nil
    end
    local is_insert = (old_tuple == nil)
    local old_data
    if is_insert then
      old_data = { }
    else
      local d
      if type(old_tuple[2]) == 'string' then
        d = json.decode(old_tuple[2])
      else
        d = old_tuple[2]
      end
      old_data = d
    end
    local new_data
    if type(new_tuple[2]) == 'string' then
      new_data = json.decode(new_tuple[2])
    else
      new_data = new_tuple[2]
    end
    local modified = false
    for _index_0 = 1, #trigger_defs do
      local def = trigger_defs[_index_0]
      if should_run(is_insert, def.trigger_fields_list, old_data, new_data) then
        local proxy = make_self_proxy(new_data, def.fk_def_map)
        local r_ok, val = pcall(def.fn, proxy, space_helper)
        if r_ok then
          new_data[def.field_name] = val
          modified = true
        else
          log.error("tdb trigger: error evaluating formula for '" .. tostring(def.field_name) .. "': " .. tostring(val))
        end
      end
    end
    if modified then
      return box.tuple.new({
        new_tuple[1],
        json.encode(new_data)
      })
    else
      return new_tuple
    end
  end
end
local build_fk_def_map
build_fk_def_map = function(space_id)
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
  local fk_def_map = { }
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
    local tf = box.space._tdb_fields:get(rel.toFieldId)
    field_by_id[rel.toFieldId] = {
      name = tf and tf[3] or 'id'
    }
  end
  for field_id, rel in pairs(rels) do
    local fld = box.space._tdb_fields:get(field_id)
    local sp = space_by_id[rel.toSpaceId]
    if fld and sp then
      fk_def_map[fld[3]] = {
        toSpaceName = sp.name,
        toFieldName = (field_by_id[rel.toFieldId] and field_by_id[rel.toFieldId].name) or 'id'
      }
    end
  end
  return fk_def_map
end
local register_space_trigger
register_space_trigger = function(space_name)
  local sp_meta = box.space._tdb_spaces.index.by_name:get({
    space_name
  })
  if not (sp_meta) then
    return 
  end
  local space_id = sp_meta[1]
  local old_fn = active_triggers[space_name]
  if old_fn then
    local ok, err = pcall(function()
      return box.space["data_" .. tostring(space_name)]:before_replace(nil, old_fn)
    end)
    if not (ok) then
      log.error("tdb triggers: failed to drop trigger for " .. tostring(space_name) .. ": " .. tostring(err))
    end
    active_triggers[space_name] = nil
  end
  local trigger_defs = { }
  local fk_def_map = nil
  local _list_0 = box.space._tdb_fields.index.by_space:select({
    space_id
  })
  for _index_0 = 1, #_list_0 do
    local _continue_0 = false
    repeat
      local t = _list_0[_index_0]
      local formula = t[8]
      local trigger_json = t[9]
      if formula and formula ~= '' and trigger_json ~= nil then
        local ok, trigger_fields_list = pcall(json.decode, trigger_json)
        if not (ok) then
          log.error("tdb triggers: invalid JSON in trigger_fields for field '" .. tostring(t[3]) .. "': " .. tostring(trigger_fields_list))
          _continue_0 = true
          break
        end
        if not (fk_def_map) then
          fk_def_map = build_fk_def_map(space_id)
        end
        local fn = compile_formula(formula, t[3])
        if fn then
          table.insert(trigger_defs, {
            field_name = t[3],
            fn = fn,
            trigger_fields_list = trigger_fields_list,
            fk_def_map = fk_def_map
          })
        end
      end
      _continue_0 = true
    until true
    if not _continue_0 then
      break
    end
  end
  if #trigger_defs == 0 then
    return 
  end
  local data_sp = box.space["data_" .. tostring(space_name)]
  if not (data_sp) then
    return 
  end
  local trigger_fn = make_trigger_fn(trigger_defs)
  data_sp:before_replace(trigger_fn)
  active_triggers[space_name] = trigger_fn
  return log.info("tdb triggers: registered " .. tostring(#trigger_defs) .. " trigger formula(s) on '" .. tostring(space_name) .. "'")
end
local init_all_triggers
init_all_triggers = function()
  local _list_0 = box.space._tdb_spaces:select({ })
  for _index_0 = 1, #_list_0 do
    local t = _list_0[_index_0]
    register_space_trigger(t[2])
  end
end
return {
  register_space_trigger = register_space_trigger,
  init_all_triggers = init_all_triggers
}
