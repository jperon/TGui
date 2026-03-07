-- resolvers/schema_resolvers.moon
-- Resolvers for space, field, view, and relation metadata.

spaces_mod  = require 'core.spaces'
views_mod   = require 'core.views'
triggers    = require 'core.triggers'
executor    = require 'graphql.executor'

fio = require 'fio'

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
    }
  result

create_relation = (name, from_space_id, from_field_id, to_space_id, to_field_id) ->
  uuid_mod = require 'uuid'
  rid = tostring uuid_mod.new!
  box.space._tdb_relations\insert { rid, from_space_id, from_field_id, to_space_id, to_field_id, name }
  { id: rid, name: name, fromSpaceId: from_space_id, fromFieldId: from_field_id,
    toSpaceId: to_space_id, toFieldId: to_field_id }

delete_relation = (id) ->
  box.space._tdb_relations\delete id
  true

-- ────────────────────────────────────────────────────────────────────────────
-- Resolvers map
-- ────────────────────────────────────────────────────────────────────────────

Query =
  spaces: (_, args, ctx) -> spaces_mod.list_spaces!
  space:  (_, args, ctx) -> spaces_mod.get_space args.id
  views:  (_, args, ctx) -> views_mod.list_views args.spaceId
  view:   (_, args, ctx) -> views_mod.get_view args.id
  relations: (_, args, ctx) -> list_relations args.spaceId

Mutation =
  createSpace: (_, args, ctx) ->
    i = args.input
    result = spaces_mod.create_user_space i.name, i.description
    spaces_mod.add_field result.id, 'id', 'Sequence', true, 'Identifiant auto-incrémenté'
    executor.reinit_schema!
    spaces_mod.get_space result.id

  updateSpace: (_, args, ctx) ->
    t = box.space._tdb_spaces\get args.id
    error "Space not found" unless t
    now  = os.time!
    name = args.input.name or t[2]
    desc = args.input.description or t[3]
    box.space._tdb_spaces\replace { args.id, name, desc, t[4], now }
    result = spaces_mod.get_space args.id
    executor.reinit_schema!
    result

  deleteSpace: (_, args, ctx) ->
    box.space._tdb_spaces\delete args.id
    executor.reinit_schema!
    true

  addField: (_, args, ctx) ->
    i = args.input
    result = spaces_mod.add_field args.spaceId, i.name, i.fieldType, i.notNull, i.description, i.formula, i.triggerFields
    executor.reinit_schema!
    sp_meta = box.space._tdb_spaces\get args.spaceId
    triggers.register_space_trigger sp_meta[2] if sp_meta
    result

  removeField: (_, args, ctx) ->
    -- capture space name before deletion (for trigger refresh)
    fld     = box.space._tdb_fields\get args.fieldId
    sp_meta = fld and box.space._tdb_spaces\get fld[2]
    spaces_mod.remove_field args.fieldId
    executor.reinit_schema!
    triggers.register_space_trigger sp_meta[2] if sp_meta
    true

  reorderFields: (_, args, ctx) ->
    result = spaces_mod.reorder_fields args.spaceId, args.fieldIds
    executor.reinit_schema!
    result

  createView: (_, args, ctx) ->
    i = args.input
    views_mod.create_view args.spaceId, i.name, i.viewType, i.config

  updateView: (_, args, ctx) ->
    views_mod.update_view args.id, args.input
    views_mod.get_view args.id

  deleteView: (_, args, ctx) ->
    views_mod.delete_view args.id
    true

  createRelation: (_, args, ctx) ->
    i = args.input
    result = create_relation i.name, i.fromSpaceId, i.fromFieldId, i.toSpaceId, i.toFieldId
    executor.reinit_schema!
    result

  deleteRelation: (_, args, ctx) ->
    result = delete_relation args.id
    executor.reinit_schema!
    result

-- Field-level resolvers for nested objects
Space =
  fields:   (obj, args, ctx) -> spaces_mod.list_fields obj.id
  views:    (obj, args, ctx) -> views_mod.list_views obj.id

{ :Query, :Mutation, :Space }
