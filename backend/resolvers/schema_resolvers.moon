-- resolvers/schema_resolvers.moon
-- Resolvers for space, field, view, and relation metadata.

spaces_mod  = require 'core.spaces'
views_mod   = require 'core.views'
triggers    = require 'core.triggers'
executor    = require 'graphql.executor'
json        = require 'json'
local data_r
data_r      = require 'resolvers.data_resolvers'
{ :require_auth, :require_admin, :require_perm, :perm_ok } = require 'resolvers.utils'

reinit_with_formula_cache_reset = ->
  executor.reinit_schema!
  triggers.invalidate_formula_cache!

-- ────────────────────────────────────────────────────────────────────────────
-- Relation helpers (stored in _tdb_relations)
-- ────────────────────────────────────────────────────────────────────────────

-- Convert a _tdb_relations tuple to the public relation shape.
relation_from_tuple = (t) ->
  { id: t[1], fromSpaceId: t[2], fromFieldId: t[3], toSpaceId: t[4],
    toFieldId: t[5], name: t[6], reprFormula: t[7] or '', cardinality: t[8] or 'one' }

list_relations = (space_id) ->
  result = {}
  for t in *box.space._tdb_relations.index.by_from\select { space_id }
    table.insert result, relation_from_tuple t
  result

-- Declared cardinality of a relation: 'one' (default) or 'many'.
-- nil (field absent) means 'one'; any other value than 'one'/'many' is rejected.
normalize_cardinality = (value) ->
  return 'one' if value == nil
  unless value == 'one' or value == 'many'
    error "Invalid relation cardinality '#{value}': expected 'one' or 'many'"
  value

create_relation = (name, from_space_id, from_field_id, to_space_id, to_field_id, repr_formula, cardinality) ->
  uuid_mod = require 'uuid'
  rid = tostring uuid_mod.new!
  card = normalize_cardinality cardinality
  box.space._tdb_relations\insert { rid, from_space_id, from_field_id, to_space_id, to_field_id, name, repr_formula or '', card }
  { id: rid, name: name, fromSpaceId: from_space_id, fromFieldId: from_field_id,
    toSpaceId: to_space_id, toFieldId: to_field_id, reprFormula: repr_formula or '',
    cardinality: card }

delete_relation = (id) ->
  box.space._tdb_relations\delete id
  true

update_relation = (id, repr_formula, cardinality) ->
  t = box.space._tdb_relations\get id
  return nil unless t
  -- Validate first: an invalid cardinality must not leave a partial write.
  card = nil
  if cardinality != nil
    card = normalize_cardinality cardinality
  ops = {}
  table.insert ops, {'=', 7, repr_formula} if repr_formula != nil
  table.insert ops, {'=', 8, card} if card != nil
  box.space._tdb_relations\update id, ops if #ops > 0
  t2 = box.space._tdb_relations\get id
  relation_from_tuple t2

-- ────────────────────────────────────────────────────────────────────────────
-- Resolvers map
-- ────────────────────────────────────────────────────────────────────────────

Query =
  spaces:    (_, args, ctx) ->
    require_auth ctx
    [sp for sp in *spaces_mod.list_spaces! when perm_ok ctx, 'space', sp.id, 'read']
  space:     (_, args, ctx) ->
    require_perm ctx, 'space', args.id, 'read'
    spaces_mod.get_space args.id
  views:     (_, args, ctx) ->
    require_auth ctx
    return {} unless perm_ok ctx, 'space', args.spaceId, 'read'
    views_mod.list_views args.spaceId
  view:      (_, args, ctx) ->
    v = views_mod.get_view args.id
    return nil unless v
    require_perm ctx, 'space', v.spaceId, 'read'
    v
  relations: (_, args, ctx) ->
    require_perm ctx, 'space', args.spaceId, 'read'
    list_relations args.spaceId
  gridColumnPrefs: (_, args, ctx) ->
    uid = require_perm ctx, 'space', args.spaceId, 'read'
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
    require_perm ctx, '*', nil, 'admin'
    i = args.input
    result = spaces_mod.create_user_space i.name, i.description
    spaces_mod.add_field result.id, 'id', 'Sequence', true, 'Identifiant auto-incrémenté'
    reinit_with_formula_cache_reset!
    spaces_mod.get_space result.id

  updateSpace: (_, args, ctx) ->
    require_perm ctx, '*', nil, 'admin'
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
    require_perm ctx, '*', nil, 'admin'
    t = box.space._tdb_spaces\get args.id
    error "Space not found" unless t
    spaces_mod.delete_user_space t[2]
    reinit_with_formula_cache_reset!
    true

  addField: (_, args, ctx) ->
    require_perm ctx, '*', nil, 'admin'
    i = args.input
    result = spaces_mod.add_field args.spaceId, i.name, i.fieldType, i.notNull, i.description, i.formula, i.triggerFields, i.language, i.reprFormula
    reinit_with_formula_cache_reset!
    sp_meta = box.space._tdb_spaces\get args.spaceId
    triggers.register_space_trigger sp_meta[2] if sp_meta
    result

  addFields: (_, args, ctx) ->
    require_perm ctx, '*', nil, 'admin'
    results = {}
    for input in *args.inputs
      result = spaces_mod.add_field args.spaceId, input.name, input.fieldType, input.notNull, input.description, input.formula, input.triggerFields, input.language, input.reprFormula
      table.insert results, result
    reinit_with_formula_cache_reset!
    sp_meta = box.space._tdb_spaces\get args.spaceId
    triggers.register_space_trigger sp_meta[2] if sp_meta
    results

  removeField: (_, args, ctx) ->
    require_perm ctx, '*', nil, 'admin'
    -- capture space name before deletion (for trigger refresh)
    fld     = box.space._tdb_fields\get args.fieldId
    sp_meta = fld and box.space._tdb_spaces\get fld[2]
    spaces_mod.remove_field args.fieldId
    reinit_with_formula_cache_reset!
    triggers.register_space_trigger sp_meta[2] if sp_meta
    true

  reorderFields: (_, args, ctx) ->
    require_perm ctx, '*', nil, 'admin'
    result = spaces_mod.reorder_fields args.spaceId, args.fieldIds
    reinit_with_formula_cache_reset!
    result

  updateField: (_, args, ctx) ->
    require_perm ctx, '*', nil, 'admin'
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
    require_perm ctx, '*', nil, 'admin'
    i = args.input
    result = spaces_mod.change_field_type args.fieldId, i.fieldType, i.conversionFormula, i.language
    reinit_with_formula_cache_reset!
    sp_meta = box.space._tdb_spaces\get result.spaceId
    triggers.register_space_trigger sp_meta[2] if sp_meta
    result

  createView: (_, args, ctx) ->
    require_perm ctx, 'view', nil, 'write'
    i = args.input
    views_mod.create_view args.spaceId, i.name, i.viewType, i.config

  updateView: (_, args, ctx) ->
    require_perm ctx, 'view', args.id, 'write'
    views_mod.update_view args.id, args.input
    views_mod.get_view args.id

  deleteView: (_, args, ctx) ->
    require_perm ctx, 'view', args.id, 'admin'
    views_mod.delete_view args.id
    true

  createRelation: (_, args, ctx) ->
    require_perm ctx, '*', nil, 'admin'
    i = args.input
    result = create_relation i.name, i.fromSpaceId, i.fromFieldId, i.toSpaceId, i.toFieldId, i.reprFormula, i.cardinality
    reinit_with_formula_cache_reset!
    result

  deleteRelation: (_, args, ctx) ->
    require_perm ctx, '*', nil, 'admin'
    result = delete_relation args.id
    reinit_with_formula_cache_reset!
    result

  updateRelation: (_, args, ctx) ->
    require_perm ctx, '*', nil, 'admin'
    result = update_relation args.id, args.input.reprFormula, args.input.cardinality
    reinit_with_formula_cache_reset!
    result

  saveGridColumnPrefs: (_, args, ctx) ->
    uid = require_perm ctx, 'space', args.spaceId, 'write'
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
  fields:   (obj, args, ctx) ->
    require_perm ctx, 'space', obj.id, 'read'
    spaces_mod.list_fields obj.id
  views:    (obj, args, ctx) ->
    require_perm ctx, 'space', obj.id, 'read'
    views_mod.list_views obj.id
  records:  (obj, args, ctx) -> data_r.Query.records(nil, { spaceId: obj.id, limit: args.limit, offset: args.offset, filter: args.filter, reprFormula: args.reprFormula, reprLanguage: args.reprLanguage }, ctx)

{ :Query, :Mutation, :Space }
