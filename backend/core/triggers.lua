local json = require('json')
local log = require('log')
local spaces_mod = require('core.spaces')
local safe_call, safe_formula_call
do
  local _obj_0 = require('core.config')
  safe_call, safe_formula_call = _obj_0.safe_call, _obj_0.safe_formula_call
end
local DEBUG_FK_PROXY = false
local active_triggers = { }
local FORMULA_ENV = {
  math = math,
  string = string,
  table = table,
  type = type,
  tostring = tostring,
  tonumber = tonumber,
  pairs = pairs,
  ipairs = ipairs,
  next = next,
  select = select,
  unpack = rawget(_G, 'unpack') or table.unpack,
  pcall = pcall,
  error = error,
  assert = assert,
  rawget = rawget,
  rawset = rawset,
  rawequal = rawequal,
  os = {
    time = os.time,
    clock = os.clock,
    date = os.date
  }
}
FORMULA_ENV._ENV = FORMULA_ENV
local compile_formula
compile_formula = function(formula, field_name, language)
  local lua_chunk
  if language == 'moonscript' then
    local ok_ms, moon = pcall(require, 'moonscript.base')
    if not (ok_ms) then
      log.error("tdb triggers: moonscript.base unavailable for '" .. tostring(field_name) .. "': " .. tostring(moon))
      return nil
    end
    if field_name == 'filter' then
      formula = formula:gsub('@([%w_]+)', 'self.%1')
    end
    local moon_src = "return (self, space) -> " .. formula
    local ok_c, lua_or_err = pcall(moon.to_lua, moon_src)
    if not (ok_c) then
      log.error("tdb triggers: MoonScript parse error for '" .. tostring(field_name) .. "': " .. tostring(lua_or_err))
      return nil
    end
    lua_chunk = lua_or_err
  else
    lua_chunk = "return function(self, space) return " .. formula .. " end"
  end
  local chunk_fn, load_err = load(lua_chunk)
  if not chunk_fn then
    log.error("tdb triggers: parse error for field '" .. tostring(field_name) .. "': " .. tostring(load_err))
    return nil
  end
  local ok_env, _ = pcall(setfenv, chunk_fn, FORMULA_ENV)
  if not (ok_env) then
    log.error("tdb triggers: setfenv not available, refusing to run formula '" .. tostring(field_name) .. "' unsandboxed")
    return nil
  end
  local ok2, fn = pcall(chunk_fn)
  if not ok2 or type(fn) ~= 'function' then
    log.error("tdb triggers: init error for field '" .. tostring(field_name) .. "': " .. tostring(fn))
    return nil
  end
  return fn
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
local format_formula_error
format_formula_error = function(err)
  if type(err) == 'string' then
    local s = err
  elseif type(err) == 'table' and err.message then
    local s = err.message
  else
    local s = tostring(err)
  end
  if s:find("attempt to concatenate") then
    local short = "Invalid concatenation"
  elseif s:find("unexpected symbol" or s:find("malformed number" or s:find("parse error"))) then
    local short = "Syntax error"
  elseif s:find("stack overflow") then
    local short = "Infinite loop (recursion)"
  else
    local short = "Unknown error"
  end
  local clean_msg = s:gsub('^%[string ".-"%]:%d+: ', '')
  return "[ERROR|" .. tostring(short) .. "|" .. tostring(clean_msg) .. "]"
end
local build_relation_map
build_relation_map = function(space_id)
  local relations = { }
  local space_by_id = { }
  local _list_0 = box.space._tdb_spaces:select({ })
  for _index_0 = 1, #_list_0 do
    local t = _list_0[_index_0]
    space_by_id[t[1]] = {
      name = t[2]
    }
  end
  local field_by_id = { }
  local _list_1 = box.space._tdb_fields.index.by_space:select({
    space_id
  })
  for _index_0 = 1, #_list_1 do
    local t = _list_1[_index_0]
    field_by_id[t[1]] = {
      name = t[3]
    }
  end
  local _list_2 = box.space._tdb_relations:select({ })
  for _index_0 = 1, #_list_2 do
    local t = _list_2[_index_0]
    if t[5](#toFieldId(function()
      return field(name)
    end)) then
      field_by_id[t[5]] = {
        name = t[3]
      }
    end
  end
  local _list_3 = box.space._tdb_relations:select({ })
  for _index_0 = 1, #_list_3 do
    local t = _list_3[_index_0]
    if t[2] == space_id then
      local fld = box.space._tdb_fields:get(t[3](#fromFieldId))
      local sp = space_by_id[t[4]](#toSpaceId)
      local tf = box.space._tdb_fields:get(t[5](#toFieldId))
      if fld and sp and tf then
        local is_multiple = is_multiple_relation(space_id, sp.name, tf[3])
        relations[fld[3]] = {
          toSpaceName = sp.name,
          toFieldName = tf[3],
          isMultiple = is_multiple
        }
      end
    end
  end
  return relations
end
local is_multiple_relation
is_multiple_relation = function(from_space_id, to_space_name, to_field_name)
  local to_space_meta = box.space._tdb_spaces.index.by_name:get({
    to_space_name
  })
  if not (to_space_meta) then
    return false
  end
  local to_space = box.space["data_" .. tostring(to_space_name)]
  if not (to_space) then
    return false
  end
  local ref_counts = { }
  local total_refs = 0
  local _list_0 = to_space:select({ })
  for _index_0 = 1, #_list_0 do
    local t = _list_0[_index_0]
    local data
    if type(t[2]) == 'string' then
      data = json.decode(t[2])
    else
      data = t[2]
    end
    if data[to_field_name] then
      local source_id = tostring(data[to_field_name])
      ref_counts[source_id] = (ref_counts[source_id] or 0) + 1
      total_refs = total_refs + 1
    end
  end
  if total_refs == 0 then
    return false
  end
  local unique_sources = 0
  for _, count in pairs(ref_counts) do
    unique_sources = unique_sources + 1
  end
  local avg_refs = total_refs / unique_sources
  local max_refs = 0
  for _, count in pairs(ref_counts) do
    max_refs = math.max(max_refs, count)
  end
  return (avg_refs > 1.5) and (total_refs > 10) and (max_refs > 2)
end
local build_single_and_multiple_maps
build_single_and_multiple_maps = function(space_id)
  local relation_map = build_relation_map(space_id)
  local single_map = { }
  local multiple_map = { }
  for field_name, relation in pairs(relation_map) do
    if relation.isMultiple then
      multiple_map[field_name] = relation
    else
      single_map[field_name] = relation
    end
  end
  return single_map, multiple_map
end
local formula_cache = { }
local invalidate_formula_cache
invalidate_formula_cache = function(space_name)
  if space_name == nil then
    space_name = nil
  end
  if space_name then
    formula_cache[space_name] = nil
  else
    for k in pairs(formula_cache) do
      formula_cache[k] = nil
    end
  end
end
local ensure_formulas
ensure_formulas = function(space_name)
  if formula_cache[space_name] then
    return formula_cache[space_name]
  end
  local space_meta = box.space._tdb_spaces.index.by_name:get({
    space_name
  })
  if not (space_meta) then
    return { }
  end
  local space_id = space_meta[1]
  local formulas = { }
  local _list_0 = box.space._tdb_fields.index.by_space:select({
    space_id
  })
  for _index_0 = 1, #_list_0 do
    local field = _list_0[_index_0]
    if field[8] and field[8] ~= '' then
      local field_name = field[3]
      local formula = field[8]
      local language = field[10] or 'lua'
      local compiled = compile_formula(formula, field_name, language)
      if compiled then
        formulas[field_name] = compiled
      end
    end
  end
  formula_cache[space_name] = formulas
  return formulas
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
local make_self_proxy
make_self_proxy = function(record, fk_def_map, fk_cache, space_name)
  fk_cache = fk_cache or { }
  fk_cache.spaces = fk_cache.spaces or { }
  fk_cache.fk_def_maps = fk_cache.fk_def_maps or { }
  fk_cache.formulas = fk_cache.formulas or { }
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
    if fk_cache.fk_def_maps[space_id] then
      return fk_cache.fk_def_maps[space_id]
    end
    fk_def_map = build_fk_def_map(space_id)
    fk_cache.fk_def_maps[space_id] = fk_def_map
    return fk_def_map
  end
  local proxy = setmetatable({ }, {
    __index = function(t, k)
      local cached = rawget(t, k)
      if cached ~= nil then
        return cached
      end
      local v = record[k]
      if (v == nil or v == '') and space_name then
        local fns = ensure_formulas(space_name)
        if fns[k] then
          fk_cache.space_helper = fk_cache.space_helper or make_space_helper()
          local r_ok, val = pcall(fns[k], t, fk_cache.space_helper)
          if r_ok and val ~= nil and val ~= '' then
            v = val
            rawset(t, k, v)
          else
            if not r_ok then
              local err_msg = format_formula_error(val)
              log.error("tdb proxy: error evaluating formula for '" .. tostring(space_name) .. "." .. tostring(k) .. "': " .. tostring(val))
              return err_msg
            end
          end
        end
      end
      if v == nil or v == '' then
        return nil
      end
      local fk = fk_def_map and fk_def_map[k]
      if fk then
        local lookup_field = fk.toFieldName or '_id'
        local sc = ensure_space(fk.toSpaceName, lookup_field)
        local d = sc.by_field[lookup_field] and sc.by_field[lookup_field][tostring(v)]
        if not d and lookup_field ~= '_id' then
          d = sc.by_field['_id'] and sc.by_field['_id'][tostring(v)]
        end
        if d then
          local nested_space = box.space._tdb_spaces.index.by_name:get({
            fk.toSpaceName
          })
          local nested_space_id = nested_space and nested_space[1]
          local nested_fk_map
          if nested_space_id then
            nested_fk_map = ensure_fk_def_map(nested_space_id)
          else
            nested_fk_map = { }
          end
          local nested = make_self_proxy(d, nested_fk_map, fk_cache, fk.toSpaceName)
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
local make_self_proxy_extended
make_self_proxy_extended = function(record, single_fk_map, multiple_fk_map, fk_cache, space_name)
  fk_cache = fk_cache or { }
  fk_cache.spaces = fk_cache.spaces or { }
  fk_cache.fk_def_maps = fk_cache.fk_def_maps or { }
  fk_cache.formulas = fk_cache.formulas or { }
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
    if fk_cache.fk_def_maps[space_id] then
      return fk_cache.fk_def_maps[space_id]
    end
    local fk_def_map = build_fk_def_map(space_id)
    fk_cache.fk_def_maps[space_id] = fk_def_map
    return fk_def_map
  end
  local resolve_multiple_references
  resolve_multiple_references = function(source_id, relation_def, fk_cache)
    local sc = ensure_space(relation_def.toSpaceName, relation_def.toFieldName)
    local results = { }
    for _, d in pairs(sc.records) do
      if d[relation_def.toFieldName] == source_id then
        local nested_space = box.space._tdb_spaces.index.by_name:get({
          relation_def.toSpaceName
        })
        local nested_space_id = nested_space and nested_space[1]
        local nested_fk_map
        if nested_space_id then
          nested_fk_map = ensure_fk_def_map(nested_space_id)
        else
          nested_fk_map = { }
        end
        local nested = make_self_proxy_extended(d, single_fk_map, multiple_fk_map, fk_cache, relation_def.toSpaceName)
        table.insert(results, nested)
      end
    end
    return results
  end
  local proxy = setmetatable({
    list = {
      length = function(list)
        return #list or 0
      end,
      first = function(list)
        return list and list[1] or nil
      end,
      last = function(list)
        return list and list[#list] or nil
      end,
      map = function(list, fn)
        local _accum_0 = { }
        local _len_0 = 1
        for _index_0 = 1, #list do
          local item = list[_index_0]
          _accum_0[_len_0] = fn(item)
          _len_0 = _len_0 + 1
        end
        return _accum_0
      end,
      filter = function(list, fn)
        local _accum_0 = { }
        local _len_0 = 1
        for _index_0 = 1, #list do
          local item = list[_index_0]
          if fn(item) then
            _accum_0[_len_0] = item
            _len_0 = _len_0 + 1
          end
        end
        return _accum_0
      end,
      reduce = function(list, fn, init)
        local result = init
        for _index_0 = 1, #list do
          local item = list[_index_0]
          result = fn(result, item)
        end
        return result
      end
    }
  }, {
    __index = function(t, k)
      local cached = rawget(t, k)
      if cached ~= nil then
        return cached
      end
      local v = record[k]
      if (v == nil or v == '') and space_name then
        local fns = ensure_formulas(space_name)
        if fns[k] then
          fk_cache.space_helper = fk_cache.space_helper or make_space_helper()
          local r_ok, val = pcall(fns[k], t, fk_cache.space_helper)
          if r_ok and val ~= nil and val ~= '' then
            v = val
            rawset(t, k, v)
          else
            if not r_ok then
              local err_msg = format_formula_error(val)
              log.error("tdb proxy: error evaluating formula for '" .. tostring(space_name) .. "." .. tostring(k) .. "': " .. tostring(val))
              return err_msg
            end
          end
        end
      end
      if v == nil or v == '' then
        return nil
      end
      local multiple_fk = multiple_fk_map and multiple_fk_map[k]
      if multiple_fk then
        local source_id = tostring(v)
        local list = resolve_multiple_references(source_id, multiple_fk, fk_cache)
        rawset(t, k, list)
        return list
      end
      local fk = single_fk_map and single_fk_map[k]
      if fk then
        local lookup_field = fk.toFieldName or '_id'
        local sc = ensure_space(fk.toSpaceName, lookup_field)
        local d = sc.by_field[lookup_field] and sc.by_field[lookup_field][tostring(v)]
        if not d and lookup_field ~= '_id' then
          d = sc.by_field['_id'] and sc.by_field['_id'][tostring(v)]
        end
        if d then
          local nested_space = box.space._tdb_spaces.index.by_name:get({
            fk.toSpaceName
          })
          local nested_space_id = nested_space and nested_space[1]
          local nested_fk_map
          if nested_space_id then
            nested_fk_map = ensure_fk_def_map(nested_space_id)
          else
            nested_fk_map = { }
          end
          local nested = make_self_proxy_extended(d, single_fk_map, multiple_fk_map, fk_cache, fk.toSpaceName)
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
local make_trigger_fn
make_trigger_fn = function(trigger_defs, space_name)
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
        local proxy = make_self_proxy(new_data, def.fk_def_map, nil, space_name)
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
    local data_sp_old = box.space["data_" .. tostring(space_name)]
    if data_sp_old then
      local ok, err = pcall(function()
        return data_sp_old:before_replace(nil, old_fn)
      end)
      if not (ok) then
        log.warn("tdb triggers: could not drop trigger for " .. tostring(space_name) .. ": " .. tostring(err))
      end
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
      local language = t[10] or 'lua'
      if formula and formula ~= '' and trigger_json ~= nil and trigger_json ~= 'null' then
        local ok, trigger_fields_list = pcall(json.decode, trigger_json)
        if not (ok) then
          log.error("tdb triggers: invalid JSON in trigger_fields for field '" .. tostring(t[3]) .. "': " .. tostring(trigger_fields_list))
          _continue_0 = true
          break
        end
        if not (fk_def_map) then
          fk_def_map = build_fk_def_map(space_id)
        end
        local fn = compile_formula(formula, t[3], language)
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
  local trigger_fn = make_trigger_fn(trigger_defs, space_name)
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
local deregister_space_trigger
deregister_space_trigger = function(space_name)
  local old_fn = active_triggers[space_name]
  if not (old_fn) then
    return 
  end
  local data_sp = box.space["data_" .. tostring(space_name)]
  if data_sp then
    pcall(function()
      return data_sp:before_replace(nil, old_fn)
    end)
  end
  active_triggers[space_name] = nil
end
return {
  compile_formula = compile_formula,
  make_self_proxy = make_self_proxy,
  make_self_proxy_extended = make_self_proxy_extended,
  build_fk_def_map = build_fk_def_map,
  build_relation_map = build_relation_map,
  is_multiple_relation = is_multiple_relation,
  build_single_and_multiple_maps = build_single_and_multiple_maps,
  register_space_trigger = register_space_trigger,
  deregister_space_trigger = deregister_space_trigger,
  init_all_triggers = init_all_triggers,
  format_formula_error = format_formula_error,
  invalidate_formula_cache = invalidate_formula_cache
}
