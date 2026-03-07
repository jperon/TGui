-- graphql/dynamic.moon
-- Generates GraphQL SDL and resolvers dynamically from space metadata.
-- Called at startup and after every structural mutation (addField, createRelation, …).

json       = require 'json'
log        = require 'log'
spaces_mod = require 'core.spaces'
triggers   = require 'core.triggers'

-- Sanitize a name to a valid GraphQL identifier
gql_name = (name) ->
  s = name\gsub '[^%w]', '_'
  s\gsub '^(%d)', '_%1'

-- Map a tdb field type to a GraphQL scalar
gql_scalar = (ft) ->
  switch ft
    when 'Int', 'Sequence' then 'Int'
    when 'Float'           then 'Float'
    when 'Boolean'         then 'Boolean'
    when 'ID', 'UUID'      then 'ID'
    when 'Any', 'Map', 'Array' then 'Any'
    else                        'String'

-- Build a proxy for `self` in formula evaluation.
-- Scalars resolve directly from the record; FK fields are resolved lazily on first access.
-- fk_def_map: { gql_field_name => { toSpaceName, toFieldName } }
make_self_proxy = (record, fk_def_map) ->
  proxy = {}
  setmetatable proxy,
    __index: (t, k) ->
      cached = rawget t, k
      return cached if cached != nil
      v = record[k]
      return nil if v == nil
      fk = fk_def_map[k]
      if fk
        tb = box.space["data_#{fk.toSpaceName}"]
        if tb
          for tup in *tb\select {}
            d = decode_tuple tup
            if tostring(d[fk.toFieldName]) == tostring(v)
              rawset t, k, d
              return d
        return nil
      v
  proxy

-- Apply a RecordFilter to a list of decoded record objects
-- Test one record object against a filter (recursively handles and/or)
matches_filter = (r, flt) ->
  return true unless flt
  -- Evaluate the primary condition (optional: flt may be pure and/or combinator)
  ok = if flt.field
    v = tostring (r[flt.field] or '')
    switch flt.op
      when 'EQ'          then v == flt.value
      when 'NEQ'         then v != flt.value
      when 'CONTAINS'    then (v\find flt.value, 1, true) != nil
      when 'STARTS_WITH' then (v\sub 1, #flt.value) == flt.value
      else true
  else true
  -- AND sub-conditions
  if ok and flt.and
    for sub in *flt.and
      break unless ok
      ok = matches_filter r, sub
  -- OR sub-conditions (short-circuit on first match)
  if not ok and flt.or
    for sub in *flt.or
      if matches_filter r, sub
        ok = true
        break
  ok

apply_filter = (all, flt) ->
  return all unless flt and (flt.field or flt.and or flt.or)
  [r for r in *all when matches_filter r, flt]

-- Build a record object from a raw Tarantool tuple
decode_tuple = (t) ->
  d = if type(t[2]) == 'string' then json.decode(t[2]) else t[2]
  d._id = t[1]
  d

-- ─────────────────────────────────────────────────────────────────────────────
-- Main entry point: generate SDL + resolver maps
-- ─────────────────────────────────────────────────────────────────────────────
generate = ->
  spaces = spaces_mod.list_spaces!
  for sp in *spaces
    sp.fields = spaces_mod.list_fields sp.id

  relations = {}
  for t in *box.space._tdb_relations\select {}
    table.insert relations, { id: t[1], fromSpaceId: t[2], fromFieldId: t[3],
                              toSpaceId: t[4], toFieldId: t[5], name: t[6] }

  space_by_id = {}
  for sp in *spaces do space_by_id[sp.id] = sp

  field_by_id = {}
  for sp in *spaces
    for f in *(sp.fields or {}) do field_by_id[f.id] = f

  fk_map      = {}
  backref_map = {}
  for rel in *relations
    fk_map[rel.fromSpaceId]    = fk_map[rel.fromSpaceId] or {}
    fk_map[rel.fromSpaceId][rel.fromFieldId] = rel
    backref_map[rel.toSpaceId] = backref_map[rel.toSpaceId] or {}
    table.insert backref_map[rel.toSpaceId], {
      rel:       rel
      fromSpace: space_by_id[rel.fromSpaceId]
      fromField: field_by_id[rel.fromFieldId]
      toField:   field_by_id[rel.toFieldId]
    }

  sdl_parts       = {}
  query_fields    = {}
  query_resolvers = {}
  type_resolvers  = {}

  for sp in *spaces
    tname    = gql_name sp.name
    fk_sp    = fk_map[sp.id] or {}
    backrefs = backref_map[sp.id] or {}

    -- ── SDL ────────────────────────────────────────────────────────────────
    fields_sdl = { '  _id: ID!' }
    for f in *(sp.fields or {})
      fn  = gql_name f.name
      rel = fk_sp[f.id]
      if rel and space_by_id[rel.toSpaceId]
        table.insert fields_sdl, "  #{fn}: #{gql_name space_by_id[rel.toSpaceId].name}_record"
      else
        table.insert fields_sdl, "  #{fn}: #{gql_scalar f.fieldType}"
    for ref in *backrefs
      table.insert fields_sdl, "  #{gql_name ref.rel.name}: #{gql_name ref.fromSpace.name}_page!"

    table.insert sdl_parts,
      "type #{tname}_record {\n#{table.concat fields_sdl, '\n'}\n}"
    table.insert sdl_parts,
      "type #{tname}_page {\n  items: [#{tname}_record!]!\n  total: Int!\n  offset: Int!\n  limit: Int!\n}"
    table.insert query_fields,
      "  #{tname}(limit: Int, offset: Int, filter: RecordFilter): #{tname}_page!"

    -- ── Resolvers — NOTE: MoonScript for-loop vars are per-iteration locals ─
    -- so sp, tname, fk_sp, backrefs are all properly captured by closures.

    -- Query resolver for this space
    query_resolvers[tname] = ((sp_cap, tname_cap, fk_sp_cap, backrefs_cap) ->
      (_, args, ctx) ->
        sp_box = box.space["data_#{sp_cap.name}"]
        unless sp_box
          return { items: {}, total: 0, offset: 0, limit: 0 }
        limit  = args.limit  or 100
        offset = args.offset or 0
        all    = [decode_tuple(t) for t in *sp_box\select {}]
        all    = apply_filter all, args.filter
        total  = #all
        items  = [all[i] for i = offset + 1, math.min(offset + limit, total)]
        { items: items, total: total, offset: offset, limit: limit }
    )(sp, tname, fk_sp, backrefs)

    -- Type resolvers for this space's _record type
    tr = {}

    -- FK field resolvers
    for f in *(sp.fields or {})
      rel = fk_sp[f.id]
      if rel and space_by_id[rel.toSpaceId]
        tr[gql_name f.name] = ((fn_cap, to_sp_cap, to_fn_cap) ->
          (obj, a, ctx) ->
            raw = obj[fn_cap]
            return nil if raw == nil
            tb  = box.space["data_#{to_sp_cap.name}"]
            return nil unless tb
            for t in *tb\select {}
              d = decode_tuple t
              return d if tostring(d[to_fn_cap]) == tostring(raw)
            nil
        )(
          gql_name(f.name),
          space_by_id[rel.toSpaceId],
          (field_by_id[rel.toFieldId] and field_by_id[rel.toFieldId].name) or 'id'
        )

    -- Back-reference resolvers
    for ref in *backrefs
      tr[gql_name ref.rel.name] = ((rel_fn_cap, to_fn_cap, from_fn_cap, from_sp_name_cap) ->
        (obj, args, ctx) ->
          filter_val = tostring (obj[to_fn_cap] or obj._id or '')
          tb = box.space["data_#{from_sp_name_cap}"]
          unless tb
            return { items: {}, total: 0, offset: 0, limit: 0 }
          limit  = (args and args.limit)  or 100
          offset = (args and args.offset) or 0
          all = {}
          for t in *tb\select {}
            d = decode_tuple t
            table.insert all, d if from_fn_cap and tostring(d[from_fn_cap]) == filter_val
          total = #all
          items = [all[i] for i = offset + 1, math.min(offset + limit, total)]
          { items: items, total: total, offset: offset, limit: limit }
      )(
        gql_name(ref.rel.name),
        (ref.toField  and ref.toField.name)  or 'id',
        ref.fromField and ref.fromField.name,
        ref.fromSpace.name
      )

    -- Formula field resolvers (pre-compiled at schema build time)
    -- Build FK name map so self proxy can lazily resolve FK fields
    fk_name_map = {}
    for f in *(sp.fields or {})
      rel = fk_sp[f.id]
      if rel and space_by_id[rel.toSpaceId]
        fk_name_map[gql_name f.name] =
          toSpaceName: space_by_id[rel.toSpaceId].name
          toFieldName: (field_by_id[rel.toFieldId] and field_by_id[rel.toFieldId].name) or 'id'

    for f in *(sp.fields or {})
      if f.formula and f.formula != ''
        formula_fn = triggers.compile_formula f.formula, f.name, (f.language or 'lua')
        if formula_fn
          tr[gql_name f.name] = ((fn_cap, fk_nm_cap) ->
            (obj, a, ctx) ->
              proxy = make_self_proxy obj, fk_nm_cap
              space_helper = (sname) ->
                sp_box = box.space["data_#{sname}"]
                return {} unless sp_box
                [decode_tuple t for t in *sp_box\select {}]
              r_ok, val = pcall fn_cap, proxy, space_helper
              if r_ok then val else nil
          )(formula_fn, fk_name_map)

    type_resolvers["#{tname}_record"] = tr

  table.insert sdl_parts,
    "extend type Query {\n#{table.concat query_fields, '\n'}\n}"

  {
    sdl:            table.concat(sdl_parts, "\n\n")
    Query:          query_resolvers
    type_resolvers: type_resolvers
  }

{ :generate, :gql_name, :gql_scalar }

