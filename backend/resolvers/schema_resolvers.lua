local spaces_mod = require('core.spaces')
local views_mod = require('core.views')
local triggers = require('core.triggers')
local executor = require('graphql.executor')
local json = require('json')
local data_r
data_r = require('resolvers.data_resolvers')
local require_auth, require_admin, require_perm, perm_ok
do
  local _obj_0 = require('resolvers.utils')
  require_auth, require_admin, require_perm, perm_ok = _obj_0.require_auth, _obj_0.require_admin, _obj_0.require_perm, _obj_0.perm_ok
end
local reinit_with_formula_cache_reset
reinit_with_formula_cache_reset = function()
  executor.reinit_schema()
  return triggers.invalidate_formula_cache()
end
local list_relations
list_relations = function(space_id)
  local result = { }
  local _list_0 = box.space._tdb_relations.index.by_from:select({
    space_id
  })
  for _index_0 = 1, #_list_0 do
    local t = _list_0[_index_0]
    table.insert(result, {
      id = t[1],
      fromSpaceId = t[2],
      fromFieldId = t[3],
      toSpaceId = t[4],
      toFieldId = t[5],
      name = t[6],
      reprFormula = t[7] or ''
    })
  end
  return result
end
local create_relation
create_relation = function(name, from_space_id, from_field_id, to_space_id, to_field_id, repr_formula)
  local uuid_mod = require('uuid')
  local rid = tostring(uuid_mod.new())
  box.space._tdb_relations:insert({
    rid,
    from_space_id,
    from_field_id,
    to_space_id,
    to_field_id,
    name,
    repr_formula or ''
  })
  return {
    id = rid,
    name = name,
    fromSpaceId = from_space_id,
    fromFieldId = from_field_id,
    toSpaceId = to_space_id,
    toFieldId = to_field_id,
    reprFormula = repr_formula or ''
  }
end
local delete_relation
delete_relation = function(id)
  box.space._tdb_relations:delete(id)
  return true
end
local update_relation
update_relation = function(id, repr_formula)
  local t = box.space._tdb_relations:get(id)
  if not (t) then
    return nil
  end
  box.space._tdb_relations:update(id, {
    {
      '=',
      7,
      repr_formula or ''
    }
  })
  local t2 = box.space._tdb_relations:get(id)
  return {
    id = t2[1],
    fromSpaceId = t2[2],
    fromFieldId = t2[3],
    toSpaceId = t2[4],
    toFieldId = t2[5],
    name = t2[6],
    reprFormula = t2[7] or ''
  }
end
local Query = {
  spaces = function(_, args, ctx)
    require_auth(ctx)
    local _accum_0 = { }
    local _len_0 = 1
    local _list_0 = spaces_mod.list_spaces()
    for _index_0 = 1, #_list_0 do
      local sp = _list_0[_index_0]
      if perm_ok(ctx, 'space', sp.id, 'read') then
        _accum_0[_len_0] = sp
        _len_0 = _len_0 + 1
      end
    end
    return _accum_0
  end,
  space = function(_, args, ctx)
    require_perm(ctx, 'space', args.id, 'read')
    return spaces_mod.get_space(args.id)
  end,
  views = function(_, args, ctx)
    require_auth(ctx)
    if not (perm_ok(ctx, 'space', args.spaceId, 'read')) then
      return { }
    end
    return views_mod.list_views(args.spaceId)
  end,
  view = function(_, args, ctx)
    local v = views_mod.get_view(args.id)
    if not (v) then
      return nil
    end
    require_perm(ctx, 'space', v.spaceId, 'read')
    return v
  end,
  relations = function(_, args, ctx)
    require_perm(ctx, 'space', args.spaceId, 'read')
    return list_relations(args.spaceId)
  end,
  gridColumnPrefs = function(_, args, ctx)
    local uid = require_perm(ctx, 'space', args.spaceId, 'read')
    local sp = box.space._tdb_ui_prefs
    if not (sp) then
      return { }
    end
    local user_t = sp:get({
      uid,
      args.spaceId
    })
    if user_t and user_t[3] and user_t[3] ~= '' then
      local ok, decoded = pcall(json.decode, user_t[3])
      if ok and type(decoded) == 'table' then
        return decoded
      end
    end
    local default_t = sp:get({
      'default',
      args.spaceId
    })
    if default_t and default_t[3] and default_t[3] ~= '' then
      local ok, decoded = pcall(json.decode, default_t[3])
      if ok and type(decoded) == 'table' then
        return decoded
      end
    end
    return { }
  end
}
local Mutation = {
  createSpace = function(_, args, ctx)
    require_perm(ctx, '*', nil, 'admin')
    local i = args.input
    local result = spaces_mod.create_user_space(i.name, i.description)
    spaces_mod.add_field(result.id, 'id', 'Sequence', true, 'Identifiant auto-incrémenté')
    reinit_with_formula_cache_reset()
    return spaces_mod.get_space(result.id)
  end,
  updateSpace = function(_, args, ctx)
    require_perm(ctx, '*', nil, 'admin')
    local t = box.space._tdb_spaces:get(args.id)
    if not (t) then
      error("Space not found")
    end
    local now = os.time()
    local name = args.input.name or t[2]
    local desc = args.input.description or t[3]
    box.space._tdb_spaces:replace({
      args.id,
      name,
      desc,
      t[4],
      now
    })
    local result = spaces_mod.get_space(args.id)
    reinit_with_formula_cache_reset()
    return result
  end,
  deleteSpace = function(_, args, ctx)
    require_perm(ctx, '*', nil, 'admin')
    local t = box.space._tdb_spaces:get(args.id)
    if not (t) then
      error("Space not found")
    end
    spaces_mod.delete_user_space(t[2])
    reinit_with_formula_cache_reset()
    return true
  end,
  addField = function(_, args, ctx)
    require_perm(ctx, '*', nil, 'admin')
    local i = args.input
    local result = spaces_mod.add_field(args.spaceId, i.name, i.fieldType, i.notNull, i.description, i.formula, i.triggerFields, i.language, i.reprFormula)
    reinit_with_formula_cache_reset()
    local sp_meta = box.space._tdb_spaces:get(args.spaceId)
    if sp_meta then
      triggers.register_space_trigger(sp_meta[2])
    end
    return result
  end,
  addFields = function(_, args, ctx)
    require_perm(ctx, '*', nil, 'admin')
    local results = { }
    local _list_0 = args.inputs
    for _index_0 = 1, #_list_0 do
      local input = _list_0[_index_0]
      local result = spaces_mod.add_field(args.spaceId, input.name, input.fieldType, input.notNull, input.description, input.formula, input.triggerFields, input.language, input.reprFormula)
      table.insert(results, result)
    end
    reinit_with_formula_cache_reset()
    local sp_meta = box.space._tdb_spaces:get(args.spaceId)
    if sp_meta then
      triggers.register_space_trigger(sp_meta[2])
    end
    return results
  end,
  removeField = function(_, args, ctx)
    require_perm(ctx, '*', nil, 'admin')
    local fld = box.space._tdb_fields:get(args.fieldId)
    local sp_meta = fld and box.space._tdb_spaces:get(fld[2])
    spaces_mod.remove_field(args.fieldId)
    reinit_with_formula_cache_reset()
    if sp_meta then
      triggers.register_space_trigger(sp_meta[2])
    end
    return true
  end,
  reorderFields = function(_, args, ctx)
    require_perm(ctx, '*', nil, 'admin')
    local result = spaces_mod.reorder_fields(args.spaceId, args.fieldIds)
    reinit_with_formula_cache_reset()
    return result
  end,
  updateField = function(_, args, ctx)
    require_perm(ctx, '*', nil, 'admin')
    local i = args.input
    local result = spaces_mod.update_field(args.fieldId, {
      name = i.name,
      notNull = i.notNull,
      description = i.description,
      formula = i.formula,
      triggerFields = i.triggerFields,
      language = i.language,
      reprFormula = i.reprFormula
    })
    reinit_with_formula_cache_reset()
    local sp_meta = box.space._tdb_spaces:get(result.spaceId)
    if sp_meta then
      triggers.register_space_trigger(sp_meta[2])
    end
    return result
  end,
  changeFieldType = function(_, args, ctx)
    require_perm(ctx, '*', nil, 'admin')
    local i = args.input
    local result = spaces_mod.change_field_type(args.fieldId, i.fieldType, i.conversionFormula, i.language)
    reinit_with_formula_cache_reset()
    local sp_meta = box.space._tdb_spaces:get(result.spaceId)
    if sp_meta then
      triggers.register_space_trigger(sp_meta[2])
    end
    return result
  end,
  createView = function(_, args, ctx)
    require_perm(ctx, 'view', nil, 'write')
    local i = args.input
    return views_mod.create_view(args.spaceId, i.name, i.viewType, i.config)
  end,
  updateView = function(_, args, ctx)
    require_perm(ctx, 'view', args.id, 'write')
    views_mod.update_view(args.id, args.input)
    return views_mod.get_view(args.id)
  end,
  deleteView = function(_, args, ctx)
    require_perm(ctx, 'view', args.id, 'admin')
    views_mod.delete_view(args.id)
    return true
  end,
  createRelation = function(_, args, ctx)
    require_perm(ctx, '*', nil, 'admin')
    local i = args.input
    local result = create_relation(i.name, i.fromSpaceId, i.fromFieldId, i.toSpaceId, i.toFieldId, i.reprFormula)
    reinit_with_formula_cache_reset()
    return result
  end,
  deleteRelation = function(_, args, ctx)
    require_perm(ctx, '*', nil, 'admin')
    local result = delete_relation(args.id)
    reinit_with_formula_cache_reset()
    return result
  end,
  updateRelation = function(_, args, ctx)
    require_perm(ctx, '*', nil, 'admin')
    local result = update_relation(args.id, args.input.reprFormula)
    reinit_with_formula_cache_reset()
    return result
  end,
  saveGridColumnPrefs = function(_, args, ctx)
    local uid = require_perm(ctx, 'space', args.spaceId, 'write')
    local owner_key = uid
    if args.asDefault then
      require_admin(ctx)
      owner_key = 'default'
    end
    local sp = box.space._tdb_ui_prefs
    if not (sp) then
      error('UI preferences storage not available')
    end
    local now = os.time()
    local encoded = json.encode(args.prefs or { })
    sp:replace({
      owner_key,
      args.spaceId,
      encoded,
      now
    })
    return true
  end
}
local Space = {
  fields = function(obj, args, ctx)
    require_perm(ctx, 'space', obj.id, 'read')
    return spaces_mod.list_fields(obj.id)
  end,
  views = function(obj, args, ctx)
    require_perm(ctx, 'space', obj.id, 'read')
    return views_mod.list_views(obj.id)
  end,
  records = function(obj, args, ctx)
    return data_r.Query.records(nil, {
      spaceId = obj.id,
      limit = args.limit,
      offset = args.offset,
      filter = args.filter,
      reprFormula = args.reprFormula,
      reprLanguage = args.reprLanguage
    }, ctx)
  end
}
return {
  Query = Query,
  Mutation = Mutation,
  Space = Space
}
