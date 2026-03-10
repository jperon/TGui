local spaces_mod = require('core.spaces')
local views_mod = require('core.views')
local triggers = require('core.triggers')
local executor = require('graphql.executor')
local data_r
data_r = require('resolvers.data_resolvers')
local require_auth
require_auth = require('resolvers.utils').require_auth
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
    return require_auth(ctx) and spaces_mod.list_spaces()
  end,
  space = function(_, args, ctx)
    return require_auth(ctx) and spaces_mod.get_space(args.id)
  end,
  views = function(_, args, ctx)
    return require_auth(ctx) and views_mod.list_views(args.spaceId)
  end,
  view = function(_, args, ctx)
    return require_auth(ctx) and views_mod.get_view(args.id)
  end,
  relations = function(_, args, ctx)
    return require_auth(ctx) and list_relations(args.spaceId)
  end
}
local Mutation = {
  createSpace = function(_, args, ctx)
    require_auth(ctx)
    local i = args.input
    local result = spaces_mod.create_user_space(i.name, i.description)
    spaces_mod.add_field(result.id, 'id', 'Sequence', true, 'Identifiant auto-incrémenté')
    executor.reinit_schema()
    return spaces_mod.get_space(result.id)
  end,
  updateSpace = function(_, args, ctx)
    require_auth(ctx)
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
    executor.reinit_schema()
    return result
  end,
  deleteSpace = function(_, args, ctx)
    require_auth(ctx)
    local t = box.space._tdb_spaces:get(args.id)
    if not (t) then
      error("Space not found")
    end
    spaces_mod.delete_user_space(t[2])
    executor.reinit_schema()
    return true
  end,
  addField = function(_, args, ctx)
    require_auth(ctx)
    local i = args.input
    local result = spaces_mod.add_field(args.spaceId, i.name, i.fieldType, i.notNull, i.description, i.formula, i.triggerFields, i.language, i.reprFormula)
    executor.reinit_schema()
    local sp_meta = box.space._tdb_spaces:get(args.spaceId)
    if sp_meta then
      triggers.register_space_trigger(sp_meta[2])
    end
    return result
  end,
  removeField = function(_, args, ctx)
    require_auth(ctx)
    local fld = box.space._tdb_fields:get(args.fieldId)
    local sp_meta = fld and box.space._tdb_spaces:get(fld[2])
    spaces_mod.remove_field(args.fieldId)
    executor.reinit_schema()
    if sp_meta then
      triggers.register_space_trigger(sp_meta[2])
    end
    return true
  end,
  reorderFields = function(_, args, ctx)
    require_auth(ctx)
    local result = spaces_mod.reorder_fields(args.spaceId, args.fieldIds)
    executor.reinit_schema()
    return result
  end,
  updateField = function(_, args, ctx)
    require_auth(ctx)
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
    executor.reinit_schema()
    local sp_meta = box.space._tdb_spaces:get(result.spaceId)
    if sp_meta then
      triggers.register_space_trigger(sp_meta[2])
    end
    return result
  end,
  changeFieldType = function(_, args, ctx)
    require_auth(ctx)
    local i = args.input
    local result = spaces_mod.change_field_type(args.fieldId, i.fieldType, i.conversionFormula, i.language)
    executor.reinit_schema()
    local sp_meta = box.space._tdb_spaces:get(result.spaceId)
    if sp_meta then
      triggers.register_space_trigger(sp_meta[2])
    end
    return result
  end,
  createView = function(_, args, ctx)
    require_auth(ctx)
    local i = args.input
    return views_mod.create_view(args.spaceId, i.name, i.viewType, i.config)
  end,
  updateView = function(_, args, ctx)
    require_auth(ctx)
    views_mod.update_view(args.id, args.input)
    return views_mod.get_view(args.id)
  end,
  deleteView = function(_, args, ctx)
    require_auth(ctx)
    views_mod.delete_view(args.id)
    return true
  end,
  createRelation = function(_, args, ctx)
    require_auth(ctx)
    local i = args.input
    local result = create_relation(i.name, i.fromSpaceId, i.fromFieldId, i.toSpaceId, i.toFieldId, i.reprFormula)
    executor.reinit_schema()
    return result
  end,
  deleteRelation = function(_, args, ctx)
    require_auth(ctx)
    local result = delete_relation(args.id)
    executor.reinit_schema()
    return result
  end,
  updateRelation = function(_, args, ctx)
    require_auth(ctx)
    local result = update_relation(args.id, args.input.reprFormula)
    return result
  end
}
local Space = {
  fields = function(obj, args, ctx)
    return spaces_mod.list_fields(obj.id)
  end,
  views = function(obj, args, ctx)
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
