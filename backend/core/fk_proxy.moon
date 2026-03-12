-- core/fk_proxy.moon
-- Foreign-key proxy resolution module to simplify triggers.moon.
-- Handles FK resolution with caching and optimizations.

json = require 'json'
log  = require 'log'
{ :safe_call } = require 'core.config'

-- Debug flag for FK troubleshooting.
DEBUG_FK_PROXY = false

-- Global cache for spaces and FK relations.
fk_cache = {
  spaces: {}      -- space_name -> { records, by_field }
  fk_maps: {}     -- space_id -> fk_def_map
}

-- ── Helper functions ────────────────────────────────────────────────────────

-- Decodes a Tarantool tuple into a Lua object.
decode_tuple = (tup) ->
  data = if type(tup[2]) == 'string' then json.decode(tup[2]) else tup[2]
  data._id = tostring(tup[1])
  data

-- Loads and caches records for a space.
ensure_space = (s_name, to_field_name) ->
  sc = fk_cache.spaces[s_name]
  unless sc
    sc = { records: {}, by_field: {} }
    tb = box.space["data_#{s_name}"]
    if tb
      if DEBUG_FK_PROXY
        print("DEBUG ensure_space: loading #{#tb} records from #{s_name}")
      for tup in *tb\select {}
        d = decode_tuple tup
        sc.records[d._id] = d
    fk_cache.spaces[s_name] = sc

  -- Always build the _id index for primary lookups.
  unless sc.by_field['_id']
    idx = {}
    if DEBUG_FK_PROXY
      print("DEBUG ensure_space: building index for _id")
    for _, d in pairs sc.records
      if d._id ~= nil
        key = tostring(d._id)
        idx[key] = d
    sc.by_field['_id'] = idx

  -- Build a field-specific index when different from _id.
  if to_field_name != '_id' and not sc.by_field[to_field_name]
    idx = {}
    if DEBUG_FK_PROXY
      print("DEBUG ensure_space: building index for #{to_field_name}")
    for _, d in pairs sc.records
      if d[to_field_name] ~= nil
        key = tostring(d[to_field_name])
        idx[key] = d
    sc.by_field[to_field_name] = idx

  sc

-- Builds and caches FK definition map for one space.
ensure_fk_def_map = (space_id) ->
  return fk_cache.fk_maps[space_id] if fk_cache.fk_maps[space_id]

  -- Retrieve relations for this space.
  rels = {}
  for t in *box.space._tdb_relations\select {}
    if t[2] == space_id
      rels[t[3]] = { toSpaceId: t[4], toFieldId: t[5] }

  -- Resolve space and field names.
  space_by_id = {}
  for t in *box.space._tdb_spaces\select {}
    space_by_id[t[1]] = { name: t[2] }

  field_by_id = {}
  for t in *box.space._tdb_fields.index.by_space\select { space_id }
    field_by_id[t[1]] = { name: t[3] }

  -- Also load fields for target spaces.
  for _, rel in pairs rels
    for t in *box.space._tdb_fields.index.by_space\select { rel.toSpaceId }
      field_by_id[t[1]] = { name: t[3] }

  -- Build the final FK definition map.
  fk_def_map = {}
  for field_name, rel in pairs rels
    to_space = space_by_id[rel.toSpaceId]
    to_field = field_by_id[rel.toFieldId]
    if to_space and to_field
      fk_def_map[field_name] = {
        toSpaceName: to_space.name
        toFieldName: to_field.name
      }

  fk_cache.fk_maps[space_id] = fk_def_map
  fk_def_map

-- ── Public API ───────────────────────────────────────────────────────────────

-- Creates a proxy that resolves FK fields on demand.
make_self_proxy = (record, space_id, cache = fk_cache, space_name) ->
  -- If space_name is not provided, infer it from metadata.
  unless space_name
    space_meta = box.space._tdb_spaces\get space_id
    space_name = space_meta and space_meta[2]

  fk_def_map = ensure_fk_def_map space_id

  proxy = setmetatable {}, {
    __index: (t, k) ->
      cached = rawget t, k
      return cached if cached != nil

      v = record[k]

      -- Resolve FK when the field is a relation.
      fk = fk_def_map and fk_def_map[k]
      if fk
        sc = ensure_space fk.toSpaceName, '_id'
        d = sc.by_field['_id'] and sc.by_field['_id'][tostring v]

        -- Emit debug logs only when needed.
        if DEBUG_FK_PROXY or not d
          print("DEBUG FK lookup:")
          print("  - space: #{fk.toSpaceName}")
          print("  - toField: #{fk.toFieldName}")
          print("  - searching for value: #{tostring(v)}")
          print("  - found: #{tostring(d)}")

        if d
          nested = make_self_proxy d, nil, cache, fk.toSpaceName
          rawset t, k, nested
          return nested
        return nil
      v
  }
  proxy

-- Clears cache (useful for tests).
clear_cache = ->
  fk_cache.spaces = {}
  fk_cache.fk_maps = {}

-- Export
{
  :make_self_proxy, :clear_cache, :DEBUG_FK_PROXY
  :ensure_space, :ensure_fk_def_map
}
