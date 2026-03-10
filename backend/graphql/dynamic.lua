local json = require('json')
local log = require('log')
local spaces_mod = require('core.spaces')
local triggers = require('core.triggers')
local gql_name
gql_name = function(name)
  local s = name:gsub('[^%w]', '_')
  return s:gsub('^(%d)', '_%1')
end
local gql_scalar
gql_scalar = function(ft)
  local _exp_0 = ft
  if 'Int' == _exp_0 or 'Sequence' == _exp_0 then
    return 'Int'
  elseif 'Float' == _exp_0 then
    return 'Float'
  elseif 'Boolean' == _exp_0 then
    return 'Boolean'
  elseif 'ID' == _exp_0 or 'UUID' == _exp_0 then
    return 'ID'
  elseif 'Any' == _exp_0 or 'Map' == _exp_0 or 'Array' == _exp_0 then
    return 'Any'
  else
    return 'String'
  end
end
local matches_filter
matches_filter = function(self_val, flt)
  if not (flt) then
    return true
  end
  local ok
  if flt.formula and flt.formula ~= '' then
    if type(flt._formula_fn) == 'function' then
      local r_ok, r_val = pcall(flt._formula_fn, self_val)
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
        ok = (v:find(flt.value, 1, true)) ~= nil
      elseif 'STARTS_WITH' == _exp_0 then
        ok = (v:sub(1, #flt.value)) == flt.value
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
  if not ok and flt["or"] then
    local _list_0 = flt["or"]
    for _index_0 = 1, #_list_0 do
      local sub = _list_0[_index_0]
      if matches_filter(self_val, sub) then
        ok = true
        break
      end
    end
  end
  return ok
end
local apply_filter
apply_filter = function(all, flt, fk_def_map, fk_cache, space_name)
  if not (flt and (flt.field or flt.formula or flt["and"] or flt["or"])) then
    return all
  end
  if flt.formula and flt.formula ~= '' and flt._formula_fn == nil then
    local lang = flt.language or 'moonscript'
    local ok_c, fn = pcall(triggers.compile_formula, flt.formula, 'filter', lang)
    if ok_c and type(fn) == 'function' then
      flt._formula_fn = fn
    else
      flt._formula_fn = false
    end
  end
  local _accum_0 = { }
  local _len_0 = 1
  for _index_0 = 1, #all do
    local r = all[_index_0]
    if matches_filter(((function()
      if fk_def_map then
        return triggers.make_self_proxy(r, fk_def_map, fk_cache, space_name)
      else
        return r
      end
    end)()), flt) then
      _accum_0[_len_0] = r
      _len_0 = _len_0 + 1
    end
  end
  return _accum_0
end
local decode_tuple
decode_tuple = function(t)
  local d
  if type(t[2]) == 'string' then
    d = json.decode(t[2])
  else
    d = t[2]
  end
  d._id = t[1]
  return d
end
local generate
generate = function()
  local spaces = spaces_mod.list_spaces()
  for _index_0 = 1, #spaces do
    local sp = spaces[_index_0]
    sp.fields = spaces_mod.list_fields(sp.id)
  end
  local relations = { }
  local _list_0 = box.space._tdb_relations:select({ })
  for _index_0 = 1, #_list_0 do
    local t = _list_0[_index_0]
    table.insert(relations, {
      id = t[1],
      fromSpaceId = t[2],
      fromFieldId = t[3],
      toSpaceId = t[4],
      toFieldId = t[5],
      name = t[6]
    })
  end
  local space_by_id = { }
  for _index_0 = 1, #spaces do
    local sp = spaces[_index_0]
    space_by_id[sp.id] = sp
  end
  local field_by_id = { }
  for _index_0 = 1, #spaces do
    local sp = spaces[_index_0]
    local _list_1 = (sp.fields or { })
    for _index_1 = 1, #_list_1 do
      local f = _list_1[_index_1]
      field_by_id[f.id] = f
    end
  end
  local fk_map = { }
  local backref_map = { }
  for _index_0 = 1, #relations do
    local rel = relations[_index_0]
    fk_map[rel.fromSpaceId] = fk_map[rel.fromSpaceId] or { }
    fk_map[rel.fromSpaceId][rel.fromFieldId] = rel
    backref_map[rel.toSpaceId] = backref_map[rel.toSpaceId] or { }
    table.insert(backref_map[rel.toSpaceId], {
      rel = rel,
      fromSpace = space_by_id[rel.fromSpaceId],
      fromField = field_by_id[rel.fromFieldId],
      toField = field_by_id[rel.toFieldId]
    })
  end
  local sdl_parts = { }
  local query_fields = { }
  local query_resolvers = { }
  local type_resolvers = { }
  for _index_0 = 1, #spaces do
    local sp = spaces[_index_0]
    local tname = gql_name(sp.name)
    local fk_sp = fk_map[sp.id] or { }
    local backrefs = backref_map[sp.id] or { }
    local fields_sdl = {
      '  _id: ID!'
    }
    local _list_1 = (sp.fields or { })
    for _index_1 = 1, #_list_1 do
      local f = _list_1[_index_1]
      local fn = gql_name(f.name)
      local rel = fk_sp[f.id]
      if rel and space_by_id[rel.toSpaceId] then
        table.insert(fields_sdl, "  " .. tostring(fn) .. ": " .. tostring(gql_name(space_by_id[rel.toSpaceId].name)) .. "_record")
      else
        table.insert(fields_sdl, "  " .. tostring(fn) .. ": " .. tostring(gql_scalar(f.fieldType)))
      end
    end
    for _index_1 = 1, #backrefs do
      local ref = backrefs[_index_1]
      table.insert(fields_sdl, "  " .. tostring(gql_name(ref.rel.name)) .. "(limit: Int, offset: Int, filter: RecordFilter): " .. tostring(gql_name(ref.fromSpace.name)) .. "_page!")
    end
    table.insert(sdl_parts, "type " .. tostring(tname) .. "_record {\n" .. tostring(table.concat(fields_sdl, '\n')) .. "\n}")
    table.insert(sdl_parts, "type " .. tostring(tname) .. "_page {\n  items: [" .. tostring(tname) .. "_record!]!\n  total: Int!\n  offset: Int!\n  limit: Int!\n}")
    table.insert(query_fields, "  " .. tostring(tname) .. "(limit: Int, offset: Int, filter: RecordFilter): " .. tostring(tname) .. "_page!")
    query_resolvers[tname] = (function(sp_cap, tname_cap, fk_sp_cap, backrefs_cap)
      return function(_, args, ctx)
        local sp_box = box.space["data_" .. tostring(sp_cap.name)]
        if not (sp_box) then
          return {
            items = { },
            total = 0,
            offset = 0,
            limit = 0
          }
        end
        local limit = args.limit or 100
        local offset = args.offset or 0
        local all
        do
          local _accum_0 = { }
          local _len_0 = 1
          local _list_2 = sp_box:select({ })
          for _index_1 = 1, #_list_2 do
            local t = _list_2[_index_1]
            _accum_0[_len_0] = decode_tuple(t)
            _len_0 = _len_0 + 1
          end
          all = _accum_0
        end
        local ok_fk, fk_def_map = pcall(triggers.build_fk_def_map, sp_cap.id)
        if ok_fk then
          fk_def_map = fk_def_map
        else
          fk_def_map = { }
        end
        ctx._fk_cache = ctx._fk_cache or { }
        all = apply_filter(all, args.filter, fk_def_map, ctx._fk_cache, sp_cap.name)
        local total = #all
        local items
        do
          local _accum_0 = { }
          local _len_0 = 1
          for i = offset + 1, math.min(offset + limit, total) do
            _accum_0[_len_0] = all[i]
            _len_0 = _len_0 + 1
          end
          items = _accum_0
        end
        return {
          items = items,
          total = total,
          offset = offset,
          limit = limit
        }
      end
    end)(sp, tname, fk_sp, backrefs)
    local tr = { }
    local _list_2 = (sp.fields or { })
    for _index_1 = 1, #_list_2 do
      local f = _list_2[_index_1]
      local rel = fk_sp[f.id]
      if rel and space_by_id[rel.toSpaceId] then
        tr[gql_name(f.name)] = (function(fn_cap, to_sp_cap, to_fn_cap)
          return function(obj, a, ctx)
            local raw = obj[fn_cap]
            if raw == nil then
              return nil
            end
            local tb = box.space["data_" .. tostring(to_sp_cap.name)]
            if not (tb) then
              return nil
            end
            if to_fn_cap == '_id' then
              local t = tb:get(tostring(raw))
              return t and decode_tuple(t)
            end
            local _list_3 = tb:select({ })
            for _index_2 = 1, #_list_3 do
              local t = _list_3[_index_2]
              local d = decode_tuple(t)
              if tostring(d[to_fn_cap or 'id']) == tostring(raw) then
                return d
              end
            end
            return nil
          end
        end)(gql_name(f.name), space_by_id[rel.toSpaceId], (field_by_id[rel.toFieldId] and field_by_id[rel.toFieldId].name) or 'id')
      end
    end
    for _index_1 = 1, #backrefs do
      local ref = backrefs[_index_1]
      tr[gql_name(ref.rel.name)] = (function(rel_fn_cap, to_fn_cap, from_fn_cap, from_sp_name_cap, from_sp_id_cap)
        return function(obj, args, ctx)
          local filter_val = tostring((obj[to_fn_cap] or obj._id or ''))
          local tb = box.space["data_" .. tostring(from_sp_name_cap)]
          if not (tb) then
            return {
              items = { },
              total = 0,
              offset = 0,
              limit = 0
            }
          end
          local limit = (args and args.limit) or 100
          local offset = (args and args.offset) or 0
          local all = { }
          local _list_3 = tb:select({ })
          for _index_2 = 1, #_list_3 do
            local t = _list_3[_index_2]
            local d = decode_tuple(t)
            if from_fn_cap and tostring(d[from_fn_cap]) == filter_val then
              table.insert(all, d)
            end
          end
          if args and args.filter then
            local ok_fk, fk_def_map = pcall(triggers.build_fk_def_map, from_sp_id_cap)
            if ok_fk then
              fk_def_map = fk_def_map
            else
              fk_def_map = { }
            end
            ctx._fk_cache = ctx._fk_cache or { }
            all = apply_filter(all, args.filter, fk_def_map, ctx._fk_cache, from_sp_name_cap)
          end
          local total = #all
          local items
          do
            local _accum_0 = { }
            local _len_0 = 1
            for i = offset + 1, math.min(offset + limit, total) do
              _accum_0[_len_0] = all[i]
              _len_0 = _len_0 + 1
            end
            items = _accum_0
          end
          return {
            items = items,
            total = total,
            offset = offset,
            limit = limit
          }
        end
      end)(gql_name(ref.rel.name), (ref.toField and ref.toField.name) or 'id', ref.fromField and ref.fromField.name, ref.fromSpace.name, ref.fromSpace.id)
    end
    local fk_name_map = { }
    local _list_3 = (sp.fields or { })
    for _index_1 = 1, #_list_3 do
      local f = _list_3[_index_1]
      local rel = fk_sp[f.id]
      if rel and space_by_id[rel.toSpaceId] then
        fk_name_map[f.name] = {
          toSpaceName = space_by_id[rel.toSpaceId].name,
          toFieldName = (field_by_id[rel.toFieldId] and field_by_id[rel.toFieldId].name) or 'id'
        }
      end
    end
    local _list_4 = (sp.fields or { })
    for _index_1 = 1, #_list_4 do
      local f = _list_4[_index_1]
      if f.formula and f.formula ~= '' then
        local formula_fn = triggers.compile_formula(f.formula, f.name, (f.language or 'moonscript'))
        if formula_fn then
          tr[gql_name(f.name)] = (function(fn_cap, fk_nm_cap, raw_name_cap, sp_name_cap)
            return function(obj, a, ctx)
              local raw_val = obj[raw_name_cap]
              if raw_val ~= nil and raw_val ~= '' then
                return raw_val
              end
              ctx._fk_cache = ctx._fk_cache or { }
              local proxy = triggers.make_self_proxy(obj, fk_nm_cap, ctx._fk_cache, sp_name_cap)
              local space_helper
              space_helper = function(sname)
                local sp_box = box.space["data_" .. tostring(sname)]
                if not (sp_box) then
                  return { }
                end
                local _accum_0 = { }
                local _len_0 = 1
                local _list_5 = sp_box:select({ })
                for _index_2 = 1, #_list_5 do
                  local t = _list_5[_index_2]
                  _accum_0[_len_0] = decode_tuple(t)
                  _len_0 = _len_0 + 1
                end
                return _accum_0
              end
              local r_ok, val = pcall(fn_cap, proxy, space_helper)
              if r_ok then
                return val
              else
                log.error("tdb proxy: error evaluating formula for '" .. tostring(sp_name_cap) .. "." .. tostring(f.name) .. "': " .. tostring(val))
                return triggers.format_formula_error(val)
              end
            end
          end)(formula_fn, fk_name_map, f.name, sp.name)
        end
      end
    end
    type_resolvers[tostring(tname) .. "_record"] = tr
  end
  table.insert(sdl_parts, "extend type Query {\n" .. tostring(table.concat(query_fields, '\n')) .. "\n}")
  return {
    sdl = table.concat(sdl_parts, "\n\n"),
    Query = query_resolvers,
    type_resolvers = type_resolvers
  }
end
return {
  generate = generate,
  gql_name = gql_name,
  gql_scalar = gql_scalar
}
