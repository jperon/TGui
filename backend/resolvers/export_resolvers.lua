local spaces_mod = require('core.spaces')
local views_mod = require('core.views')
local perms_mod = require('core.permissions')
local auth_mod = require('core.auth')
local view_presets = require('core.view_presets')
local app_package = require('core.app_package')
local widget_scopes = require('core.widget_scopes')
local executor = require('graphql.executor')
local uuid_mod = require('uuid')
local yaml = require('yaml')
local json = require('json')
local clock = require('clock')
local require_auth, require_admin, require_perm
do
  local _obj_0 = require('resolvers.utils')
  require_auth, require_admin, require_perm = _obj_0.require_auth, _obj_0.require_admin, _obj_0.require_perm
end
local ZstdWrapper = require('zstd_wrapper')
local compress_yaml_if_needed
compress_yaml_if_needed = function(yaml_string, enable_compression)
  if not (enable_compression) then
    return yaml_string
  end
  local compressed, err = ZstdWrapper.compress_zstd(yaml_string, {
    level = 1
  })
  if err then
    error("Compression failed: " .. tostring(err))
  end
  return json.encode({
    compressed = true,
    data = require('base64').encode(compressed),
    original_size = #yaml_string,
    compressed_size = #compressed
  })
end
local decompress_yaml_if_needed
decompress_yaml_if_needed = function(yaml_or_compressed)
  if type(yaml_or_compressed) == 'string' and yaml_or_compressed:sub(1, 1) == '{' then
    local ok, parsed = pcall(json.decode, yaml_or_compressed)
    if ok and type(parsed) == 'table' and parsed.compressed then
      local compressed_data = require('base64').decode(parsed.data)
      local decompressed, err = ZstdWrapper.decompress_zstd(compressed_data)
      if err then
        error("Decompression failed: " .. tostring(err))
      end
      return decompressed
    end
  end
  return yaml_or_compressed
end
local list_relations_for_space
list_relations_for_space = function(space_id)
  local result = { }
  local _list_0 = box.space._tdb_relations.index.by_from:select({
    space_id
  })
  for _index_0 = 1, #_list_0 do
    local t = _list_0[_index_0]
    table.insert(result, {
      fromSpaceId = t[2],
      fromFieldId = t[3],
      toSpaceId = t[4],
      toFieldId = t[5]
    })
  end
  return result
end
local space_name_by_id
space_name_by_id = function(sid)
  local t = box.space._tdb_spaces:get(sid)
  return t and t[2] or nil
end
local field_name_by_id
field_name_by_id = function(fid)
  local t = box.space._tdb_fields:get(fid)
  return t and t[3] or nil
end
local decode_record_data
decode_record_data = function(blob)
  if type(blob) == 'table' then
    return blob
  end
  if not (type(blob) == 'string') then
    return { }
  end
  local ok, decoded = pcall(json.decode, blob)
  if ok and type(decoded) == 'table' then
    return decoded
  else
    return { }
  end
end
local build_snapshot
build_snapshot = function(include_data)
  local snap = {
    version = '1',
    exported_at = os.date('!%Y-%m-%dT%H:%M:%SZ'),
    schema = {
      spaces = { },
      relations = { },
      custom_views = { },
      data_views = { },
      view_presets = { },
      widget_plugins = { },
      groups = { }
    }
  }
  local _list_0 = spaces_mod.list_spaces()
  for _index_0 = 1, #_list_0 do
    local sp = _list_0[_index_0]
    local fields = { }
    local _list_1 = spaces_mod.list_fields(sp.id)
    for _index_1 = 1, #_list_1 do
      local f = _list_1[_index_1]
      local entry = {
        name = f.name,
        fieldType = f.fieldType,
        notNull = f.notNull,
        position = f.position
      }
      if f.description and f.description ~= '' then
        entry.description = f.description
      end
      if f.formula and f.formula ~= '' then
        entry.formula = f.formula
      end
      if f.triggerFields then
        entry.triggerFields = f.triggerFields
      end
      if f.language and f.language ~= 'lua' then
        entry.language = f.language
      end
      table.insert(fields, entry)
    end
    local sp_views = { }
    local _list_2 = views_mod.list_views(sp.id)
    for _index_1 = 1, #_list_2 do
      local v = _list_2[_index_1]
      table.insert(sp_views, {
        name = v.name,
        viewType = v.viewType
      })
    end
    local sp_entry = {
      name = sp.name,
      fields = fields,
      views = sp_views
    }
    if sp.description and sp.description ~= '' then
      sp_entry.description = sp.description
    end
    table.insert(snap.schema.spaces, sp_entry)
  end
  local seen_rels = { }
  local _list_1 = spaces_mod.list_spaces()
  for _index_0 = 1, #_list_1 do
    local sp = _list_1[_index_0]
    local _list_2 = list_relations_for_space(sp.id)
    for _index_1 = 1, #_list_2 do
      local _continue_0 = false
      repeat
        local rel = _list_2[_index_1]
        local from_sp = space_name_by_id(rel.fromSpaceId)
        local from_fld = field_name_by_id(rel.fromFieldId)
        local to_sp = space_name_by_id(rel.toSpaceId)
        local to_fld = field_name_by_id(rel.toFieldId)
        if not (from_sp and from_fld and to_sp and to_fld) then
          _continue_0 = true
          break
        end
        local key = tostring(rel.fromSpaceId) .. "/" .. tostring(rel.fromFieldId) .. "/" .. tostring(rel.toSpaceId) .. "/" .. tostring(rel.toFieldId)
        if seen_rels[key] then
          _continue_0 = true
          break
        end
        seen_rels[key] = true
        table.insert(snap.schema.relations, {
          fromSpace = from_sp,
          fromField = from_fld,
          toSpace = to_sp,
          toField = to_fld
        })
        _continue_0 = true
      until true
      if not _continue_0 then
        break
      end
    end
  end
  local _list_2 = box.space._tdb_custom_views:select({ })
  for _index_0 = 1, #_list_2 do
    local cv = _list_2[_index_0]
    local entry = {
      name = cv[2],
      yaml = cv[4]
    }
    if cv[3] and cv[3] ~= '' then
      entry.description = cv[3]
    end
    table.insert(snap.schema.custom_views, entry)
  end
  local _list_3 = box.space._tdb_data_views:select({ })
  for _index_0 = 1, #_list_3 do
    local dv = _list_3[_index_0]
    local entry = {
      name = dv[2],
      sourceSpace = space_name_by_id(dv[4]),
      config = dv[5]
    }
    if dv[3] and dv[3] ~= '' then
      entry.description = dv[3]
    end
    table.insert(snap.schema.data_views, entry)
  end
  local _list_4 = box.space._tdb_view_presets:select({ })
  for _index_0 = 1, #_list_4 do
    local _continue_0 = false
    repeat
      local vp = _list_4[_index_0]
      if app_package.preset_row_orphan(vp) then
        _continue_0 = true
        break
      end
      local entry = {
        name = vp[4],
        scope = app_package.preset_scope_portable(vp[2]),
        space = space_name_by_id(vp[3]) or vp[3],
        filter = vp[5] or '',
        sort = vp[6] or '[]'
      }
      table.insert(snap.schema.view_presets, entry)
      _continue_0 = true
    until true
    if not _continue_0 then
      break
    end
  end
  local _list_5 = box.space._tdb_widget_plugins:select({ })
  for _index_0 = 1, #_list_5 do
    local wp = _list_5[_index_0]
    local entry = {
      name = wp[2],
      scriptLanguage = wp[4] or 'coffeescript',
      templateLanguage = wp[5] or 'pug',
      scriptCode = wp[6] or '',
      templateCode = wp[7] or '',
      manifest = wp[10] or ''
    }
    if wp[3] and wp[3] ~= '' then
      entry.description = wp[3]
    end
    table.insert(snap.schema.widget_plugins, entry)
  end
  local _list_6 = box.space._tdb_groups:select({ })
  for _index_0 = 1, #_list_6 do
    local g = _list_6[_index_0]
    local members = { }
    local _list_7 = box.space._tdb_memberships.index.by_group:select({
      g[1]
    })
    for _index_1 = 1, #_list_7 do
      local m = _list_7[_index_1]
      local u = box.space._tdb_users:get(m[1])
      if u then
        table.insert(members, u[2])
      end
    end
    local permissions = { }
    local _list_8 = perms_mod.list_permissions(g[1])
    for _index_1 = 1, #_list_8 do
      local p = _list_8[_index_1]
      local perm_entry = {
        resourceType = p.resourceType,
        level = p.level
      }
      if p.resourceId and p.resourceId ~= perms_mod.WILDCARD_ID then
        local rname = space_name_by_id(p.resourceId)
        perm_entry.resourceId = rname or p.resourceId
      end
      table.insert(permissions, perm_entry)
    end
    local g_entry = {
      name = g[2],
      members = members,
      permissions = permissions
    }
    if g[3] and g[3] ~= '' then
      g_entry.description = g[3]
    end
    table.insert(snap.schema.groups, g_entry)
  end
  if include_data then
    snap.data = { }
    local _list_7 = spaces_mod.list_spaces()
    for _index_0 = 1, #_list_7 do
      local _continue_0 = false
      repeat
        local sp = _list_7[_index_0]
        local user_sp = box.space["data_" .. tostring(sp.name)]
        if not (user_sp) then
          _continue_0 = true
          break
        end
        local rows = { }
        local _list_8 = user_sp:select({ })
        for _index_1 = 1, #_list_8 do
          local tuple = _list_8[_index_1]
          table.insert(rows, decode_record_data(tuple[2]))
        end
        snap.data[sp.name] = rows
        _continue_0 = true
      until true
      if not _continue_0 then
        break
      end
    end
  end
  return snap
end
local diff_snapshot
diff_snapshot = function(snap)
  local result = {
    spacesToCreate = { },
    spacesToDelete = { },
    fieldsToCreate = { },
    fieldsToDelete = { },
    fieldsToChange = { },
    pagesToCreate = { },
    pagesToUpdate = { },
    dataViewsToCreate = { },
    dataViewsToUpdate = { },
    widgetPluginsToCreate = { },
    widgetPluginsToUpdate = { }
  }
  local current_spaces = { }
  local _list_0 = spaces_mod.list_spaces()
  for _index_0 = 1, #_list_0 do
    local sp = _list_0[_index_0]
    current_spaces[sp.name] = sp
  end
  local current_cvs = { }
  local _list_1 = box.space._tdb_custom_views:select({ })
  for _index_0 = 1, #_list_1 do
    local cv = _list_1[_index_0]
    current_cvs[cv[2]] = cv[4]
  end
  local current_dvs = { }
  local _list_2 = box.space._tdb_data_views:select({ })
  for _index_0 = 1, #_list_2 do
    local dv = _list_2[_index_0]
    current_dvs[dv[2]] = {
      sourceSpace = space_name_by_id(dv[4]),
      config = dv[5]
    }
  end
  local current_wps = { }
  local _list_3 = box.space._tdb_widget_plugins:select({ })
  for _index_0 = 1, #_list_3 do
    local wp = _list_3[_index_0]
    current_wps[wp[2]] = {
      description = wp[3] or '',
      scriptLanguage = wp[4] or 'coffeescript',
      templateLanguage = wp[5] or 'pug',
      scriptCode = wp[6] or '',
      templateCode = wp[7] or ''
    }
  end
  local incoming_spaces = snap.schema and snap.schema.spaces or { }
  local incoming_cvs = snap.schema and snap.schema.custom_views or { }
  local incoming_dvs = snap.schema and snap.schema.data_views or { }
  local incoming_wps = snap.schema and snap.schema.widget_plugins or { }
  local incoming_names = { }
  for _index_0 = 1, #incoming_spaces do
    local isp = incoming_spaces[_index_0]
    incoming_names[isp.name] = true
    if not current_spaces[isp.name] then
      table.insert(result.spacesToCreate, isp.name)
    else
      local cur_fields = { }
      local _list_4 = spaces_mod.list_fields(current_spaces[isp.name].id)
      for _index_1 = 1, #_list_4 do
        local f = _list_4[_index_1]
        cur_fields[f.name] = f.fieldType
      end
      local inc_fields = { }
      local _list_5 = (isp.fields or { })
      for _index_1 = 1, #_list_5 do
        local f = _list_5[_index_1]
        inc_fields[f.name] = f.fieldType
        if not cur_fields[f.name] then
          table.insert(result.fieldsToCreate, {
            space = isp.name,
            field = f.name,
            oldType = nil,
            newType = f.fieldType
          })
        elseif cur_fields[f.name] ~= f.fieldType then
          table.insert(result.fieldsToChange, {
            space = isp.name,
            field = f.name,
            oldType = cur_fields[f.name],
            newType = f.fieldType
          })
        end
      end
      for fname, ftype in pairs(cur_fields) do
        if not (inc_fields[fname]) then
          table.insert(result.fieldsToDelete, {
            space = isp.name,
            field = fname,
            oldType = ftype,
            newType = nil
          })
        end
      end
    end
  end
  for sname, _ in pairs(current_spaces) do
    if not (incoming_names[sname]) then
      table.insert(result.spacesToDelete, sname)
    end
  end
  for _index_0 = 1, #incoming_cvs do
    local icv = incoming_cvs[_index_0]
    if not current_cvs[icv.name] then
      table.insert(result.pagesToCreate, icv.name)
    elseif current_cvs[icv.name] ~= icv.yaml then
      table.insert(result.pagesToUpdate, icv.name)
    end
  end
  for _index_0 = 1, #incoming_dvs do
    local idv = incoming_dvs[_index_0]
    local cur = current_dvs[idv.name]
    if not cur then
      table.insert(result.dataViewsToCreate, idv.name)
    elseif cur.sourceSpace ~= idv.sourceSpace or cur.config ~= idv.config then
      table.insert(result.dataViewsToUpdate, idv.name)
    end
  end
  for _index_0 = 1, #incoming_wps do
    local iwp = incoming_wps[_index_0]
    local cur = current_wps[iwp.name]
    if not cur then
      table.insert(result.widgetPluginsToCreate, iwp.name)
    else
      local inc_desc = iwp.description or ''
      local inc_script_lang = iwp.scriptLanguage or 'coffeescript'
      local inc_tpl_lang = iwp.templateLanguage or 'pug'
      local inc_script = iwp.scriptCode or ''
      local inc_tpl = iwp.templateCode or ''
      if cur.description ~= inc_desc or cur.scriptLanguage ~= inc_script_lang or cur.templateLanguage ~= inc_tpl_lang or cur.scriptCode ~= inc_script or cur.templateCode ~= inc_tpl then
        table.insert(result.widgetPluginsToUpdate, iwp.name)
      end
    end
  end
  return result
end
local do_import
do_import = function(snap, mode)
  local created = 0
  local skipped = 0
  local errors = { }
  local spaces_by_name = { }
  if mode == 'replace' then
    local _list_0 = spaces_mod.list_spaces()
    for _index_0 = 1, #_list_0 do
      local sp = _list_0[_index_0]
      local ok, err = pcall(function()
        return spaces_mod.delete_user_space(sp.name)
      end)
      if not (ok) then
        table.insert(errors, "delete space " .. tostring(sp.name) .. ": " .. tostring(err))
      end
    end
    local _list_1 = box.space._tdb_custom_views:select({ })
    for _index_0 = 1, #_list_1 do
      local cv = _list_1[_index_0]
      box.space._tdb_custom_views:delete(cv[1])
    end
    local _list_2 = box.space._tdb_data_views:select({ })
    for _index_0 = 1, #_list_2 do
      local dv = _list_2[_index_0]
      box.space._tdb_data_views:delete(dv[1])
    end
    local _list_3 = box.space._tdb_view_presets:select({ })
    for _index_0 = 1, #_list_3 do
      local vp = _list_3[_index_0]
      box.space._tdb_view_presets:delete(vp[1])
    end
    local _list_4 = box.space._tdb_widget_plugins:select({ })
    for _index_0 = 1, #_list_4 do
      local wp = _list_4[_index_0]
      box.space._tdb_widget_plugins:delete(wp[1])
    end
    local _list_5 = box.space._tdb_groups:select({ })
    for _index_0 = 1, #_list_5 do
      local g = _list_5[_index_0]
      if not (g[2] == 'admin') then
        perms_mod.delete_group(g[1])
      end
    end
  end
  local _list_0 = (snap.schema and snap.schema.spaces or { })
  for _index_0 = 1, #_list_0 do
    local isp = _list_0[_index_0]
    local existing = nil
    local _list_1 = spaces_mod.list_spaces()
    for _index_1 = 1, #_list_1 do
      local sp = _list_1[_index_1]
      if sp.name == isp.name then
        existing = sp
        break
      end
    end
    if existing then
      spaces_by_name[isp.name] = existing.id
      skipped = skipped + 1
    else
      local ok, sp_or_err = pcall(function()
        return spaces_mod.create_user_space(isp.name, isp.description)
      end)
      if ok then
        local sid = sp_or_err.id
        spaces_by_name[isp.name] = sid
        local _list_2 = (isp.fields or { })
        for _index_1 = 1, #_list_2 do
          local f = _list_2[_index_1]
          local ok2, ferr = pcall(function()
            return spaces_mod.add_field(sid, f.name, f.fieldType, f.notNull or false, f.description, f.formula, f.triggerFields, f.language)
          end)
          if not (ok2) then
            table.insert(errors, "add field " .. tostring(isp.name) .. "." .. tostring(f.name) .. ": " .. tostring(ferr))
          end
        end
        local _list_3 = (isp.views or { })
        for _index_1 = 1, #_list_3 do
          local v = _list_3[_index_1]
          local ok3, verr = pcall(function()
            return views_mod.create_view(sid, v.name, v.viewType or 'Grid')
          end)
          if not (ok3) then
            table.insert(errors, "add view " .. tostring(isp.name) .. "/" .. tostring(v.name) .. ": " .. tostring(verr))
          end
        end
        created = created + 1
      else
        table.insert(errors, "create space " .. tostring(isp.name) .. ": " .. tostring(sp_or_err))
      end
    end
  end
  local ok_reinit, reinit_err = pcall(function()
    return executor.reinit_schema()
  end)
  if not (ok_reinit) then
    table.insert(errors, "schema reinitialization: " .. tostring(reinit_err))
  end
  local _list_1 = (snap.schema and snap.schema.relations or { })
  for _index_0 = 1, #_list_1 do
    local rel = _list_1[_index_0]
    local ok, err = pcall(function()
      local from_sid = spaces_by_name[rel.fromSpace]
      local to_sid = spaces_by_name[rel.toSpace]
      if not (from_sid) then
        error("unknown space " .. tostring(rel.fromSpace))
      end
      if not (to_sid) then
        error("unknown space " .. tostring(rel.toSpace))
      end
      local from_fid, to_fid = nil, nil
      local _list_2 = spaces_mod.list_fields(from_sid)
      for _index_1 = 1, #_list_2 do
        local f = _list_2[_index_1]
        if f.name == rel.fromField then
          from_fid = f.id
        end
      end
      local _list_3 = spaces_mod.list_fields(to_sid)
      for _index_1 = 1, #_list_3 do
        local f = _list_3[_index_1]
        if f.name == rel.toField then
          to_fid = f.id
        end
      end
      if not (from_fid) then
        error("field " .. tostring(rel.fromSpace) .. "." .. tostring(rel.fromField) .. " not found")
      end
      if not (to_fid) then
        error("field " .. tostring(rel.toSpace) .. "." .. tostring(rel.toField) .. " not found")
      end
      local is_dup = false
      local _list_4 = box.space._tdb_relations.index.by_from:select({
        from_sid
      })
      for _index_1 = 1, #_list_4 do
        local t = _list_4[_index_1]
        if t[3] == from_fid and t[4] == to_sid and t[5] == to_fid then
          is_dup = true
          break
        end
      end
      if is_dup then
        skipped = skipped + 1
        return 
      end
      local rid = tostring(uuid_mod.new())
      box.space._tdb_relations:insert({
        rid,
        from_sid,
        from_fid,
        to_sid,
        to_fid,
        tostring(rel.fromSpace) .. "_" .. tostring(rel.fromField)
      })
      created = created + 1
    end)
    if not (ok) then
      table.insert(errors, "relation " .. tostring(rel.fromSpace) .. "." .. tostring(rel.fromField) .. "→" .. tostring(rel.toSpace) .. "." .. tostring(rel.toField) .. ": " .. tostring(err))
    end
  end
  local _list_2 = (snap.schema and snap.schema.custom_views or { })
  for _index_0 = 1, #_list_2 do
    local icv = _list_2[_index_0]
    local existing_cv = nil
    local _list_3 = box.space._tdb_custom_views:select({ })
    for _index_1 = 1, #_list_3 do
      local cv = _list_3[_index_1]
      if cv[2] == icv.name then
        existing_cv = cv
        break
      end
    end
    if existing_cv then
      skipped = skipped + 1
    else
      local ok, err = pcall(function()
        local id = tostring(uuid_mod.new())
        local now = clock.time()
        return box.space._tdb_custom_views:insert({
          id,
          icv.name,
          icv.description or '',
          icv.yaml or '',
          now,
          now
        })
      end)
      if ok then
        created = created + 1
      else
        table.insert(errors, "custom_view " .. tostring(icv.name) .. ": " .. tostring(err))
      end
    end
  end
  local _list_3 = (snap.schema and snap.schema.data_views or { })
  for _index_0 = 1, #_list_3 do
    local idv = _list_3[_index_0]
    local existing_dv = nil
    local _list_4 = box.space._tdb_data_views:select({ })
    for _index_1 = 1, #_list_4 do
      local dv = _list_4[_index_1]
      if dv[2] == idv.name then
        existing_dv = dv
        break
      end
    end
    if existing_dv then
      skipped = skipped + 1
    else
      local ok, err = pcall(function()
        local id = tostring(uuid_mod.new())
        local sid = spaces_by_name[idv.sourceSpace]
        if not (sid) then
          error("source space " .. tostring(idv.sourceSpace) .. " not found")
        end
        return box.space._tdb_data_views:insert({
          id,
          idv.name,
          idv.description or '',
          sid,
          idv.config or '{}'
        })
      end)
      if ok then
        created = created + 1
      else
        table.insert(errors, "data_view " .. tostring(idv.name) .. ": " .. tostring(err))
      end
    end
  end
  local _list_4 = (snap.schema and snap.schema.view_presets or { })
  for _index_0 = 1, #_list_4 do
    local ivp = _list_4[_index_0]
    local scope = app_package.preset_scope_local(ivp.scope)
    local sid = spaces_by_name[ivp.space]
    if not scope then
      table.insert(errors, "view_preset " .. tostring(ivp.name) .. ": scope " .. tostring(ivp.scope) .. " not found")
    elseif not sid then
      table.insert(errors, "view_preset " .. tostring(ivp.name) .. ": space " .. tostring(ivp.space) .. " not found")
    elseif box.space._tdb_view_presets.index.by_scope_name:get({
      scope,
      ivp.name
    }) then
      skipped = skipped + 1
    else
      local ok, err = pcall(function()
        return view_presets.save_preset(scope, sid, ivp.name, ivp.filter or '', ivp.sort or '[]')
      end)
      if ok then
        created = created + 1
      else
        table.insert(errors, "view_preset " .. tostring(ivp.name) .. ": " .. tostring(err))
      end
    end
  end
  local _list_5 = (snap.schema and snap.schema.widget_plugins or { })
  for _index_0 = 1, #_list_5 do
    local iwp = _list_5[_index_0]
    local existing_wp = widget_scopes.find_row(iwp.name, nil)
    if existing_wp then
      skipped = skipped + 1
    else
      local ok, err = pcall(function()
        local id = tostring(uuid_mod.new())
        local now = clock.time()
        return box.space._tdb_widget_plugins:insert({
          id,
          iwp.name,
          iwp.description or '',
          iwp.scriptLanguage or 'coffeescript',
          iwp.templateLanguage or 'pug',
          iwp.scriptCode or '',
          iwp.templateCode or '',
          now,
          now,
          iwp.manifest or '',
          ''
        })
      end)
      if ok then
        created = created + 1
      else
        table.insert(errors, "widget_plugin " .. tostring(iwp.name) .. ": " .. tostring(err))
      end
    end
  end
  local _list_6 = (snap.schema and snap.schema.groups or { })
  for _index_0 = 1, #_list_6 do
    local _continue_0 = false
    repeat
      local ig = _list_6[_index_0]
      local existing_g = nil
      local _list_7 = box.space._tdb_groups:select({ })
      for _index_1 = 1, #_list_7 do
        local g = _list_7[_index_1]
        if g[2] == ig.name then
          existing_g = g
          break
        end
      end
      local gid = nil
      if existing_g then
        gid = existing_g[1]
        skipped = skipped + 1
      else
        local ok, g_or_err = pcall(function()
          return perms_mod.create_group(ig.name, ig.description)
        end)
        if ok then
          gid = g_or_err.id
          created = created + 1
        else
          table.insert(errors, "group " .. tostring(ig.name) .. ": " .. tostring(g_or_err))
          _continue_0 = true
          break
        end
      end
      local _list_8 = (ig.members or { })
      for _index_1 = 1, #_list_8 do
        local uname = _list_8[_index_1]
        local u = auth_mod.get_user_by_username(uname)
        if u then
          local ok2, err2 = pcall(function()
            return box.space._tdb_memberships:insert({
              u.id,
              gid
            })
          end)
        else
          table.insert(errors, "member " .. tostring(uname) .. " not found (group " .. tostring(ig.name) .. ")")
        end
      end
      local _list_9 = (ig.permissions or { })
      for _index_1 = 1, #_list_9 do
        local perm = _list_9[_index_1]
        local ok3, err3 = pcall(function()
          local rid = perms_mod.WILDCARD_ID
          if perm.resourceId then
            local _list_10 = spaces_mod.list_spaces()
            for _index_2 = 1, #_list_10 do
              local sp = _list_10[_index_2]
              if sp.name == perm.resourceId then
                rid = sp.id
              end
            end
          end
          local _list_10 = perms_mod.list_permissions(gid)
          for _index_2 = 1, #_list_10 do
            local ep = _list_10[_index_2]
            if ep.resourceType == (perm.resourceType or 'space') and ep.resourceId == rid and ep.level == perm.level then
              return 
            end
          end
          return perms_mod.grant(gid, perm.resourceType or 'space', rid, perm.level)
        end)
        if not (ok3) then
          table.insert(errors, "permission " .. tostring(ig.name) .. "/" .. tostring(perm.level) .. ": " .. tostring(err3))
        end
      end
      _continue_0 = true
    until true
    if not _continue_0 then
      break
    end
  end
  if snap.data then
    for sp_name, rows in pairs(snap.data) do
      local _continue_0 = false
      repeat
        local sp = nil
        local _list_7 = spaces_mod.list_spaces()
        for _index_0 = 1, #_list_7 do
          local s = _list_7[_index_0]
          if s.name == sp_name then
            sp = s
          end
        end
        if not (sp) then
          _continue_0 = true
          break
        end
        local user_sp = box.space["data_" .. tostring(sp_name)]
        if not (user_sp) then
          _continue_0 = true
          break
        end
        local fields = spaces_mod.list_fields(sp.id)
        for _index_0 = 1, #rows do
          local row = rows[_index_0]
          local ok4, err4 = pcall(function()
            for _index_1 = 1, #fields do
              local f = fields[_index_1]
              if row[f.name] == nil and f.notNull then
                error("Missing required field '" .. tostring(f.name) .. "' in row data")
              end
            end
            local id = tostring(uuid_mod.new())
            return user_sp:insert({
              id,
              json.encode(row)
            })
          end)
          if ok4 then
            created = created + 1
          else
            table.insert(errors, "data " .. tostring(sp_name) .. ": " .. tostring(err4))
          end
        end
        _continue_0 = true
      until true
      if not _continue_0 then
        break
      end
    end
  end
  executor.reinit_schema()
  return {
    ok = #errors == 0,
    created = created,
    skipped = skipped,
    errors = errors
  }
end
local _is_spaces_list
_is_spaces_list = function(spaces_list)
  if not (type(spaces_list) == 'table') then
    return false
  end
  if next(spaces_list) == nil then
    return true
  end
  return spaces_list[1] ~= nil
end
local _check_snapshot_document
_check_snapshot_document = function(snap)
  if snap.app ~= nil and snap.items ~= nil then
    error("Ce fichier est un paquet d'application, pas un instantané : installez-le depuis Administration › Applications.")
  end
  if not (type(snap.schema) == 'table' and _is_spaces_list(snap.schema.spaces)) then
    return error("Fichier non reconnu : ce n'est pas un instantané TGui (clé schema.spaces absente).")
  end
end
local Query = {
  exportSnapshot = function(_, args, ctx)
    require_admin(ctx)
    local snap = build_snapshot(args.includeData)
    local yaml_str = yaml.encode(snap)
    return compress_yaml_if_needed(yaml_str, args.compress or false)
  end,
  diffSnapshot = function(_, args, ctx)
    require_perm(ctx, '*', nil, 'read')
    local yaml_str = decompress_yaml_if_needed(args.yaml)
    local ok, snap = pcall(function()
      return yaml.decode(yaml_str)
    end)
    if not (ok and snap) then
      error("Invalid YAML: " .. tostring(snap))
    end
    return diff_snapshot(snap)
  end
}
local Mutation = {
  importSnapshot = function(_, args, ctx)
    require_admin(ctx)
    local yaml_str = decompress_yaml_if_needed(args.yaml)
    local ok, snap = pcall(function()
      return yaml.decode(yaml_str)
    end)
    if not (ok and snap) then
      error("Invalid YAML: " .. tostring(snap))
    end
    if not (type(snap) == 'table') then
      error("Invalid YAML: expected a mapping")
    end
    _check_snapshot_document(snap)
    return do_import(snap, args.mode)
  end
}
return {
  Query = Query,
  Mutation = Mutation,
  compress_yaml_if_needed = compress_yaml_if_needed,
  decompress_yaml_if_needed = decompress_yaml_if_needed,
  build_snapshot = build_snapshot
}
