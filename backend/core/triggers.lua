local json = require('json')
local log = require('log')
local safe_formula_call
safe_formula_call = require('core.config').safe_formula_call
local compile_formula, MAX_STRING_REP_BYTES
do
  local _obj_0 = require('core.formula_sandbox')
  compile_formula, MAX_STRING_REP_BYTES = _obj_0.compile_formula, _obj_0.MAX_STRING_REP_BYTES
end
local build_fk_def_map, build_relation_map, build_single_and_multiple_maps
do
  local _obj_0 = require('core.relation_maps')
  build_fk_def_map, build_relation_map, build_single_and_multiple_maps = _obj_0.build_fk_def_map, _obj_0.build_relation_map, _obj_0.build_single_and_multiple_maps
end
local make_self_proxy, make_self_proxy_extended, make_space_helper, format_formula_error, invalidate_formula_cache
do
  local _obj_0 = require('core.formula_proxy')
  make_self_proxy, make_self_proxy_extended, make_space_helper, format_formula_error, invalidate_formula_cache = _obj_0.make_self_proxy, _obj_0.make_self_proxy_extended, _obj_0.make_space_helper, _obj_0.format_formula_error, _obj_0.invalidate_formula_cache
end
local active_triggers = { }
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
        local val, err = safe_formula_call(def.fn, "trigger " .. tostring(space_name) .. "." .. tostring(def.field_name), nil, nil, {
          proxy,
          space_helper
        })
        if err ~= nil then
          log.error("tdb trigger: error evaluating formula for '" .. tostring(def.field_name) .. "': " .. tostring(err))
        else
          new_data[def.field_name] = val
          modified = true
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
  build_single_and_multiple_maps = build_single_and_multiple_maps,
  register_space_trigger = register_space_trigger,
  deregister_space_trigger = deregister_space_trigger,
  init_all_triggers = init_all_triggers,
  format_formula_error = format_formula_error,
  invalidate_formula_cache = invalidate_formula_cache,
  MAX_STRING_REP_BYTES = MAX_STRING_REP_BYTES
}
