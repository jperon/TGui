local json = require('json')
local log = require('log')
local uuid_mod = require('uuid')
local spaces_mod = require('core.spaces')
local require_auth, safe_call
do
  local _obj_0 = require('resolvers.utils')
  require_auth, safe_call = _obj_0.require_auth, _obj_0.safe_call
end
local config_mod = require('core.config')
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
matches_filter = function(self_val, flt)
  if not (flt) then
    return true
  end
  local ok
  if flt.formula and flt.formula ~= '' then
    if type(flt._formula_fn) == 'function' then
      local r_ok, r_val = config_mod.safe_formula_call((function()
        return flt._formula_fn(self_val)
      end), "filter formula evaluation")
      ok = r_ok and r_val and r_val ~= false
    else
      ok = false
    end
  else
    if flt.field then
      local v = tostring((self_val[flt.field] or ''))
      local _exp_0 = flt.op
      if 'EQ' == _exp_0 then
        ok = v == flt.value
      elseif 'NEQ' == _exp_0 then
        ok = v ~= flt.value
      elseif 'LT' == _exp_0 then
        ok = tonumber(v) < tonumber(flt.value)
      elseif 'GT' == _exp_0 then
        ok = tonumber(v) > tonumber(flt.value)
      elseif 'LTE' == _exp_0 then
        ok = tonumber(v) <= tonumber(flt.value)
      elseif 'GTE' == _exp_0 then
        ok = tonumber(v) >= tonumber(flt.value)
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
  end
  if ok and flt["and"] then
    local _list_0 = flt["and"]
    for _index_0 = 1, #_list_0 do
      local sub = _list_0[_index_0]
      if not (ok) then
        break
      end
      ok = matches_filter(self_val, sub)
    end
  end
  if flt["or"] then
    local any = false
    local _list_0 = flt["or"]
    for _index_0 = 1, #_list_0 do
      local sub = _list_0[_index_0]
      if matches_filter(self_val, sub) then
        any = true
        break
      end
    end
    ok = ok and any
  end
  return ok
end
local apply_filter
apply_filter = function(tuples, filter, fk_def_map, fk_cache, space_name)
  if not (filter and (filter.field or filter.formula or filter["and"] or filter["or"])) then
    return tuples
  end
  if filter.formula and filter.formula ~= '' and filter._formula_fn == nil then
    local triggers = require('core.triggers')
    local lang = filter.language or 'moonscript'
    local ok_c, fn = pcall(triggers.compile_formula, filter.formula, 'filter', lang)
    if ok_c and type(fn) == 'function' then
      filter._formula_fn = fn
    else
      filter._formula_fn = false
    end
  end
  local triggers_mod = require('core.triggers')
  local filtered = { }
  for _index_0 = 1, #tuples do
    local rec = tuples[_index_0]
    local parsed
    if type(rec.data) == 'string' then
      parsed = json.decode(rec.data)
    else
      parsed = rec.data
    end
    local self_val
    if fk_def_map then
      parsed._id = tostring(rec.id)
      self_val = triggers_mod.make_self_proxy(parsed, fk_def_map, fk_cache, space_name)
    else
      self_val = parsed
    end
    if matches_filter(self_val, filter) then
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
    local ok_d, old_data = pcall(json.decode, existing[2])
    if not (ok_d) then
      error("Corrupted record data: " .. tostring(old_data))
    end
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
  end,
  deleteRecords = function(_, args, ctx)
    require_auth(ctx)
    local sp = data_space(args.spaceId)
    local results
    do
      local _accum_0 = { }
      local _len_0 = 1
      local _list_0 = args.ids
      for _index_0 = 1, #_list_0 do
        local id = _list_0[_index_0]
        sp:delete(id)
        local _value_0 = true
        _accum_0[_len_0] = _value_0
        _len_0 = _len_0 + 1
      end
      results = _accum_0
    end
    return results
  end,
  insertRecords = function(_, args, ctx)
    require_auth(ctx)
    local sp, meta = data_space(args.spaceId)
    local seq_fields = sequence_fields(args.spaceId)
    local triggers_mod = require('core.triggers')
    local results = { }
    box.atomic(function()
      local _list_0 = args.data
      for _index_0 = 1, #_list_0 do
        local d = _list_0[_index_0]
        local id = tostring(uuid_mod.new())
        local data
        if type(d) == 'string' then
          data = json.decode(d)
        else
          data = d
        end
        for field_name, field_id in pairs(seq_fields) do
          local seq = box.sequence["_tdb_seq_" .. tostring(field_id)]
          if seq then
            data[field_name] = seq:next()
          end
        end
        sp:insert({
          id,
          json.encode(data)
        })
        table.insert(results, {
          id = id,
          spaceId = args.spaceId,
          data = json.encode(data)
        })
      end
    end)
    return results
  end,
  updateRecords = function(_, args, ctx)
    require_auth(ctx)
    local sp, meta = data_space(args.spaceId)
    local seq_fields = sequence_fields(args.spaceId)
    local results = { }
    box.atomic(function()
      local _list_0 = args.records
      for _index_0 = 1, #_list_0 do
        local _continue_0 = false
        repeat
          local rec = _list_0[_index_0]
          local id = rec.id
          local existing = sp:get(id)
          if not (existing) then
            log.error("Record not found: " .. tostring(id))
            _continue_0 = true
            break
          end
          local ok_d, old_data = pcall(json.decode, existing[2])
          if not (ok_d) then
            log.error("Corrupted record data for " .. tostring(id) .. ": " .. tostring(old_data))
            _continue_0 = true
            break
          end
          local new_data
          if type(rec.data) == 'string' then
            new_data = json.decode(rec.data)
          else
            new_data = rec.data
          end
          for k, v in pairs(new_data) do
            if not (seq_fields[k]) then
              old_data[k] = v
            end
          end
          sp:replace({
            id,
            json.encode(old_data)
          })
          table.insert(results, {
            id = id,
            spaceId = args.spaceId,
            data = json.encode(old_data)
          })
          _continue_0 = true
        until true
        if not _continue_0 then
          break
        end
      end
    end)
    return results
  end
}
local Query = {
  records = function(_, args, ctx)
    require_auth(ctx)
    local sp = data_space(args.spaceId)
    local limit = args.limit or 100
    local offset = args.offset or 0
    local triggers_mod = require('core.triggers')
    local ok_fk, fk_def_map = pcall(triggers_mod.build_fk_def_map, args.spaceId)
    if ok_fk then
      fk_def_map = fk_def_map
    else
      fk_def_map = { }
    end
    local sp_meta = box.space._tdb_spaces:get(args.spaceId)
    local space_name = sp_meta and sp_meta[2]
    ctx._fk_cache = ctx._fk_cache or { }
    local repr_fn = nil
    if args.reprFormula and args.reprFormula ~= '' then
      local lang = args.reprLanguage or 'moonscript'
      local ok_c, fn = pcall(triggers_mod.compile_formula, args.reprFormula, 'repr', lang)
      if ok_c and type(fn) == 'function' then
        repr_fn = fn
      else
        repr_fn = nil
      end
    end
    local field_reprs = { }
    if sp_meta then
      local fields = box.space._tdb_fields.index.by_space_pos:select({
        args.spaceId
      })
      for _index_0 = 1, #fields do
        local f = fields[_index_0]
        if f[11] and f[11] ~= '' then
          local lang = f[10] or 'lua'
          local ok_c, fn = pcall(triggers_mod.compile_formula, f[11], "repr_" .. tostring(f[3]), lang)
          if ok_c and type(fn) == 'function' then
            field_reprs[f[3]] = fn
          end
        end
      end
    end
    local all = { }
    local has_field_reprs = next(field_reprs) ~= nil
    if repr_fn or has_field_reprs then
      local _list_0 = sp:select({ })
      for _index_0 = 1, #_list_0 do
        local t = _list_0[_index_0]
        local parsed = json.decode(t[2])
        parsed._id = tostring(t[1])
        local self_proxy = triggers_mod.make_self_proxy(parsed, fk_def_map, ctx._fk_cache, space_name)
        if repr_fn then
          local ok_r, val = pcall(repr_fn, self_proxy, nil)
          if ok_r and val ~= nil then
            parsed._repr = tostring(val)
          end
        end
        for fname, fn in pairs(field_reprs) do
          local ok_r, val = pcall(fn, self_proxy, nil)
          if ok_r and val ~= nil then
            parsed["_repr_" .. tostring(fname)] = tostring(val)
          end
        end
        parsed._id = nil
        table.insert(all, {
          id = t[1],
          spaceId = args.spaceId,
          data = json.encode(parsed)
        })
      end
    else
      local _list_0 = sp:select({ })
      for _index_0 = 1, #_list_0 do
        local t = _list_0[_index_0]
        table.insert(all, {
          id = t[1],
          spaceId = args.spaceId,
          data = t[2]
        })
      end
    end
    local filtered = apply_filter(all, args.filter, fk_def_map, ctx._fk_cache, space_name)
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
