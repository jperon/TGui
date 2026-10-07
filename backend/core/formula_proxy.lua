local json = require('json')
local log = require('log')
local safe_formula_call
safe_formula_call = require('core.config').safe_formula_call
local compile_formula
compile_formula = require('core.formula_sandbox').compile_formula
local build_fk_def_map
build_fk_def_map = require('core.relation_maps').build_fk_def_map
local format_formula_error
format_formula_error = function(err)
  local s
  if type(err) == 'string' then
    s = err
  elseif type(err) == 'table' and err.message then
    s = err.message
  else
    s = tostring(err)
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
local make_space_helper
make_space_helper = function(fk_cache)
  return function(sname)
    if fk_cache and fk_cache.can_read and not fk_cache.can_read(sname) then
      return { }
    end
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
local prepare_cache
prepare_cache = function(fk_cache)
  fk_cache = fk_cache or { }
  fk_cache.spaces = fk_cache.spaces or { }
  fk_cache.fk_def_maps = fk_cache.fk_def_maps or { }
  fk_cache.formulas = fk_cache.formulas or { }
  return fk_cache
end
local ensure_space
ensure_space = function(fk_cache, s_name, to_field_name)
  if fk_cache.can_read and not fk_cache.can_read(s_name) then
    return {
      records = { },
      by_field = { }
    }
  end
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
ensure_fk_def_map = function(fk_cache, space_id)
  if fk_cache.fk_def_maps[space_id] then
    return fk_cache.fk_def_maps[space_id]
  end
  local fk_def_map = build_fk_def_map(space_id)
  fk_cache.fk_def_maps[space_id] = fk_def_map
  return fk_def_map
end
local eval_computed_formula
eval_computed_formula = function(t, k, v, space_name, fk_cache)
  if not ((v == nil or v == '') and space_name) then
    return v, false
  end
  local fns = ensure_formulas(space_name)
  if not (fns[k]) then
    return v, false
  end
  fk_cache.space_helper = fk_cache.space_helper or make_space_helper(fk_cache)
  local val, err = safe_formula_call(fns[k], "formula " .. tostring(space_name) .. "." .. tostring(k), nil, nil, {
    t,
    fk_cache.space_helper
  })
  if err ~= nil then
    log.error("tdb proxy: error evaluating formula for '" .. tostring(space_name) .. "." .. tostring(k) .. "': " .. tostring(err))
    return format_formula_error(err), true
  end
  if val ~= nil and val ~= '' then
    rawset(t, k, val)
    return val, false
  end
  return v, false
end
local make_self_proxy
make_self_proxy = function(record, fk_def_map, fk_cache, space_name)
  fk_cache = prepare_cache(fk_cache)
  local proxy = setmetatable({ }, {
    __index = function(t, k)
      local cached = rawget(t, k)
      if cached ~= nil then
        return cached
      end
      local v = record[k]
      local is_error
      v, is_error = eval_computed_formula(t, k, v, space_name, fk_cache)
      if is_error then
        return v
      end
      if v == nil or v == '' then
        return nil
      end
      local fk = fk_def_map and fk_def_map[k]
      if fk then
        local lookup_field = fk.toFieldName or '_id'
        local sc = ensure_space(fk_cache, fk.toSpaceName, lookup_field)
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
            nested_fk_map = ensure_fk_def_map(fk_cache, nested_space_id)
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
  fk_cache = prepare_cache(fk_cache)
  local resolve_multiple_references
  resolve_multiple_references = function(source_id, relation_def)
    local sc = ensure_space(fk_cache, relation_def.toSpaceName, relation_def.toFieldName)
    local results = { }
    for _, d in pairs(sc.records) do
      if d[relation_def.toFieldName] == source_id then
        local nested_space = box.space._tdb_spaces.index.by_name:get({
          relation_def.toSpaceName
        })
        local nested_space_id = nested_space and nested_space[1]
        local nested_fk_map
        if nested_space_id then
          nested_fk_map = ensure_fk_def_map(fk_cache, nested_space_id)
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
      local is_error
      v, is_error = eval_computed_formula(t, k, v, space_name, fk_cache)
      if is_error then
        return v
      end
      if v == nil or v == '' then
        return nil
      end
      local multiple_fk = multiple_fk_map and multiple_fk_map[k]
      if multiple_fk then
        local source_id = tostring(v)
        local list = resolve_multiple_references(source_id, multiple_fk)
        rawset(t, k, list)
        return list
      end
      local fk = single_fk_map and single_fk_map[k]
      if fk then
        local lookup_field = fk.toFieldName or '_id'
        local sc = ensure_space(fk_cache, fk.toSpaceName, lookup_field)
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
            nested_fk_map = ensure_fk_def_map(fk_cache, nested_space_id)
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
return {
  make_self_proxy = make_self_proxy,
  make_self_proxy_extended = make_self_proxy_extended,
  make_space_helper = make_space_helper,
  format_formula_error = format_formula_error,
  invalidate_formula_cache = invalidate_formula_cache
}
