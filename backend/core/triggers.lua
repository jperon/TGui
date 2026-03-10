local json = require('json')
local log = require('log')
local spaces_mod = require('core.spaces')
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
      log.error("tdb triggers: moonscript.base non disponible pour '" .. tostring(field_name) .. "': " .. tostring(moon))
      return nil
    end
    local moon_src = "return (self, space) -> " .. formula
    local ok_c, lua_or_err = pcall(moon.to_lua, moon_src)
    if not (ok_c) then
      log.error("tdb triggers: MoonScript parse error pour '" .. tostring(field_name) .. "': " .. tostring(lua_or_err))
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
    log.warn("tdb triggers: setfenv not available, formula '" .. tostring(field_name) .. "' runs unsandboxed")
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
  local s = tostring(err)
  local short = "Erreur de formule"
  if s:find("attempt to index") then
    short = "Champ inconnu (nil)"
  elseif s:find("attempt to call") then
    short = "Fonction inconnue (nil)"
  elseif s:find("attempt to perform arithmetic") then
    short = "Opération sur nil"
  elseif s:find("attempt to concatenate") then
    short = "Concaténation invalide"
  elseif s:find("unexpected symbol" or s:find("malformed number" or s:find("parse error"))) then
    short = "Erreur de syntaxe"
  elseif s:find("stack overflow") then
    short = "Boucle infinie (récursion)"
  else
    short = "Erreur (inconnue)"
  end
  local clean_msg = s:gsub('^%[string ".-"%]:%d+: ', '')
  return "[ERROR|" .. tostring(short) .. "|" .. tostring(clean_msg) .. "]"
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
        if DEBUG_FK_PROXY then
          print("DEBUG ensure_space: loading " .. tostring(#tb) .. " records from " .. tostring(s_name))
        end
        local _list_0 = tb:select({ })
        for _index_0 = 1, #_list_0 do
          local tup = _list_0[_index_0]
          local d = decode_tuple(tup)
          if DEBUG_FK_PROXY then
            print("DEBUG ensure_space: record _id=" .. tostring(d._id) .. ", " .. tostring(to_field_name) .. "=" .. tostring(tostring(d[to_field_name])))
          end
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
          if DEBUG_FK_PROXY then
            print("DEBUG ensure_space: indexing _id key='" .. tostring(key) .. "'")
          end
          idx[key] = d
        end
      end
      sc.by_field['_id'] = idx
      if DEBUG_FK_PROXY then
        print("DEBUG ensure_space: _id index built with " .. tostring(#idx) .. " keys")
      end
    end
    if to_field_name ~= '_id' and not sc.by_field[to_field_name] then
      local idx = { }
      if DEBUG_FK_PROXY then
        print("DEBUG ensure_space: building index for " .. tostring(to_field_name))
      end
      for _, d in pairs(sc.records) do
        if d[to_field_name] ~= nil then
          local key = tostring(d[to_field_name])
          if DEBUG_FK_PROXY then
            print("DEBUG ensure_space: indexing key='" .. tostring(key) .. "' for _id=" .. tostring(d._id))
          end
          idx[key] = d
        end
      end
      sc.by_field[to_field_name] = idx
      if DEBUG_FK_PROXY then
        if next(idx) == nil then
          print("WARNING: No records indexed for field '" .. tostring(to_field_name) .. "' in space '" .. tostring(s_name) .. "'")
        end
        print("DEBUG ensure_space: index built with " .. tostring(next(idx) and #idx or '0') .. " keys")
      end
    end
    return sc
  end
  local ensure_fk_def_map
  ensure_fk_def_map = function(s_name)
    if not (fk_cache.fk_def_maps[s_name]) then
      local target_sp_meta = box.space._tdb_spaces.index.by_name:get({
        s_name
      })
      if target_sp_meta then
        fk_cache.fk_def_maps[s_name] = build_fk_def_map(target_sp_meta[1])
      else
        fk_cache.fk_def_maps[s_name] = { }
      end
    end
    return fk_cache.fk_def_maps[s_name]
  end
  local ensure_formulas
  ensure_formulas = function(s_name)
    if not (fk_cache.formulas[s_name]) then
      local fns = { }
      local sp_meta = box.space._tdb_spaces.index.by_name:get({
        s_name
      })
      if sp_meta then
        local _list_0 = box.space._tdb_fields.index.by_space:select({
          sp_meta[1]
        })
        for _index_0 = 1, #_list_0 do
          local t = _list_0[_index_0]
          local formula = t[8]
          local language = t[10] or 'lua'
          if formula and formula ~= '' then
            local fn = compile_formula(formula, t[3], language)
            if fn then
              fns[t[3]] = fn
            end
          end
        end
      end
      fk_cache.formulas[s_name] = fns
    end
    return fk_cache.formulas[s_name]
  end
  local proxy = { }
  setmetatable(proxy, {
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
        local sc = ensure_space(fk.toSpaceName, '_id')
        local d = sc.by_field['_id'] and sc.by_field['_id'][tostring(v)]
        if DEBUG_FK_PROXY or not d then
          print("DEBUG FK lookup:")
          print("  - space: " .. tostring(fk.toSpaceName))
          print("  - toField: " .. tostring(fk.toFieldName))
          print("  - searching for value: " .. tostring(tostring(v)))
          print("  - found: " .. tostring(tostring(d)))
          if sc.by_field['_id'] then
            local keys
            do
              local _accum_0 = { }
              local _len_0 = 1
              for key, _ in pairs(sc.by_field['_id']) do
                _accum_0[_len_0] = key
                _len_0 = _len_0 + 1
              end
              keys = _accum_0
            end
            print("  - available _id keys: " .. tostring(table.concat(keys, ', ')))
          else
            print("  - no _id index built")
          end
        end
        if d then
          local nested_fk_map = ensure_fk_def_map(fk.toSpaceName)
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
  build_fk_def_map = build_fk_def_map,
  register_space_trigger = register_space_trigger,
  deregister_space_trigger = deregister_space_trigger,
  init_all_triggers = init_all_triggers,
  format_formula_error = format_formula_error
}
