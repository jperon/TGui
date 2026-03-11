-- resolvers/schema_resolvers.moon
-- Resolvers for space, field, view, and relation metadata.

spaces_mod  = require 'core.spaces'
views_mod   = require 'core.views'
triggers    = require 'core.triggers'
executor    = require 'graphql.executor'
json        = require 'json'
local data_r
data_r      = require 'resolvers.data_resolvers'
{ :require_auth, :require_admin } = require 'resolvers.utils'

reinit_with_formula_cache_reset = ->
  executor.reinit_schema!
  triggers.invalidate_formula_cache!

-- ────────────────────────────────────────────────────────────────────────────
-- Relation helpers (stored in _tdb_relations)
-- ────────────────────────────────────────────────────────────────────────────

list_relations = (space_id) ->
  result = {}
  for t in *box.space._tdb_relations.index.by_from\select { space_id }
    table.insert result, {
      id:           t[1]
      fromSpaceId:  t[2]
      fromFieldId:  t[3]
      toSpaceId:    t[4]
      toFieldId:    t[5]
      name:         t[6]
      reprFormula:  t[7] or ''
    }
  result

create_relation = (name, from_space_id, from_field_id, to_space_id, to_field_id, repr_formula) ->
  uuid_mod = require 'uuid'
  rid = tostring uuid_mod.new!
  box.space._tdb_relations\insert { rid, from_space_id, from_field_id, to_space_id, to_field_id, name, repr_formula or '' }
  { id: rid, name: name, fromSpaceId: from_space_id, fromFieldId: from_field_id,
    toSpaceId: to_space_id, toFieldId: to_field_id, reprFormula: repr_formula or '' }

delete_relation = (id) ->
  box.space._tdb_relations\delete id
  true

update_relation = (id, repr_formula) ->
  t = box.space._tdb_relations\get id
  return nil unless t
  box.space._tdb_relations\update id, { {'=', 7, repr_formula or ''} }
  t2 = box.space._tdb_relations\get id
  { id: t2[1], fromSpaceId: t2[2], fromFieldId: t2[3], toSpaceId: t2[4], toFieldId: t2[5], name: t2[6], reprFormula: t2[7] or '' }

-- ────────────────────────────────────────────────────────────────────────────
-- Resolvers map
-- ────────────────────────────────────────────────────────────────────────────

Query =
  spaces:    (_, args, ctx) -> require_auth(ctx) and spaces_mod.list_spaces!
  space:     (_, args, ctx) -> require_auth(ctx) and spaces_mod.get_space args.id
  views:     (_, args, ctx) -> require_auth(ctx) and views_mod.list_views args.spaceId
  view:      (_, args, ctx) -> require_auth(ctx) and views_mod.get_view args.id
  relations: (_, args, ctx) -> require_auth(ctx) and list_relations args.spaceId
  gridColumnPrefs: (_, args, ctx) ->
    uid = require_auth ctx
    sp = box.space._tdb_ui_prefs
    return {} unless sp

    user_t = sp\get { uid, args.spaceId }
    if user_t and user_t[3] and user_t[3] != ''
      ok, decoded = pcall json.decode, user_t[3]
      return decoded if ok and type(decoded) == 'table'

    default_t = sp\get { 'default', args.spaceId }
    if default_t and default_t[3] and default_t[3] != ''
      ok, decoded = pcall json.decode, default_t[3]
      return decoded if ok and type(decoded) == 'table'

    {}

Mutation =
  createSpace: (_, args, ctx) ->
    require_auth ctx
    i = args.input
    result = spaces_mod.create_user_space i.name, i.description
    spaces_mod.add_field result.id, 'id', 'Sequence', true, 'Identifiant auto-incrémenté'
    reinit_with_formula_cache_reset!
    spaces_mod.get_space result.id

  updateSpace: (_, args, ctx) ->
    require_auth ctx
    t = box.space._tdb_spaces\get args.id
    error "Space not found" unless t
    now  = os.time!
    name = args.input.name or t[2]
    desc = args.input.description or t[3]
    box.space._tdb_spaces\replace { args.id, name, desc, t[4], now }
    result = spaces_mod.get_space args.id
    reinit_with_formula_cache_reset!
    result

  deleteSpace: (_, args, ctx) ->
    require_auth ctx
    t = box.space._tdb_spaces\get args.id
    error "Space not found" unless t
    spaces_mod.delete_user_space t[2]
    reinit_with_formula_cache_reset!
    true

  addField: (_, args, ctx) ->
    require_auth ctx
    i = args.input
    result = spaces_mod.add_field args.spaceId, i.name, i.fieldType, i.notNull, i.description, i.formula, i.triggerFields, i.language, i.reprFormula
    reinit_with_formula_cache_reset!
    sp_meta = box.space._tdb_spaces\get args.spaceId
    triggers.register_space_trigger sp_meta[2] if sp_meta
    result

  addFields: (_, args, ctx) ->
    require_auth ctx
    results = {}
    for input in *args.inputs
      result = spaces_mod.add_field args.spaceId, input.name, input.fieldType, input.notNull, input.description, input.formula, input.triggerFields, input.language, input.reprFormula
      table.insert results, result
    reinit_with_formula_cache_reset!
    sp_meta = box.space._tdb_spaces\get args.spaceId
    triggers.register_space_trigger sp_meta[2] if sp_meta
    results

  removeField: (_, args, ctx) ->
    require_auth ctx
    -- capture space name before deletion (for trigger refresh)
    fld     = box.space._tdb_fields\get args.fieldId
    sp_meta = fld and box.space._tdb_spaces\get fld[2]
    spaces_mod.remove_field args.fieldId
    reinit_with_formula_cache_reset!
    triggers.register_space_trigger sp_meta[2] if sp_meta
    true

  reorderFields: (_, args, ctx) ->
    require_auth ctx
    result = spaces_mod.reorder_fields args.spaceId, args.fieldIds
    reinit_with_formula_cache_reset!
    result

  updateField: (_, args, ctx) ->
    require_auth ctx
    i = args.input
    result = spaces_mod.update_field args.fieldId, {
      name:          i.name
      notNull:       i.notNull
      description:   i.description
      formula:       i.formula
      triggerFields: i.triggerFields
      language:      i.language
      reprFormula:   i.reprFormula
    }
    reinit_with_formula_cache_reset!
    sp_meta = box.space._tdb_spaces\get result.spaceId
    triggers.register_space_trigger sp_meta[2] if sp_meta
    result

  changeFieldType: (_, args, ctx) ->
    require_auth ctx
    i = args.input
    result = spaces_mod.change_field_type args.fieldId, i.fieldType, i.conversionFormula, i.language
    reinit_with_formula_cache_reset!
    sp_meta = box.space._tdb_spaces\get result.spaceId
    triggers.register_space_trigger sp_meta[2] if sp_meta
    result

  createView: (_, args, ctx) ->
    require_auth ctx
    i = args.input
    views_mod.create_view args.spaceId, i.name, i.viewType, i.config

  updateView: (_, args, ctx) ->
    require_auth ctx
    views_mod.update_view args.id, args.input
    views_mod.get_view args.id

  deleteView: (_, args, ctx) ->
    require_auth ctx
    views_mod.delete_view args.id
    true

  createRelation: (_, args, ctx) ->
    require_auth ctx
    i = args.input
    result = create_relation i.name, i.fromSpaceId, i.fromFieldId, i.toSpaceId, i.toFieldId, i.reprFormula
    reinit_with_formula_cache_reset!
    result

  deleteRelation: (_, args, ctx) ->
    require_auth ctx
    result = delete_relation args.id
    reinit_with_formula_cache_reset!
    result

  updateRelation: (_, args, ctx) ->
    require_auth ctx
    result = update_relation args.id, args.input.reprFormula
    reinit_with_formula_cache_reset!
    result

  saveGridColumnPrefs: (_, args, ctx) ->
    uid = require_auth ctx
    owner_key = uid
    if args.asDefault
      require_admin ctx
      owner_key = 'default'

    sp = box.space._tdb_ui_prefs
    error 'UI preferences storage not available' unless sp
    now = os.time!
    encoded = json.encode(args.prefs or {})
    sp\replace { owner_key, args.spaceId, encoded, now }
    true

-- Field-level resolvers for nested objects
Space =
  fields:   (obj, args, ctx) -> spaces_mod.list_fields obj.id
  views:    (obj, args, ctx) -> views_mod.list_views obj.id
  records:  (obj, args, ctx) -> data_r.Query.records(nil, { spaceId: obj.id, limit: args.limit, offset: args.offset, filter: args.filter, reprFormula: args.reprFormula, reprLanguage: args.reprLanguage }, ctx)

{ :Query, :Mutation, :Space }
