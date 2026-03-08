-- resolvers/data_resolvers.moon
-- Resolvers for CRUD operations on user-defined data spaces.

json      = require 'json'
uuid_mod  = require 'uuid'
spaces_mod = require 'core.spaces'
{ :require_auth } = require 'resolvers.utils'

-- Retrieve the Tarantool space for user data
data_space = (space_id) ->
  meta = box.space._tdb_spaces\get space_id
  error "Space not found: #{space_id}" unless meta
  sp = box.space["data_#{meta[2]}"]
  error "Data space not initialized: #{meta[2]}" unless sp
  sp, meta

-- Return list of Sequence fields for a space: { field_name -> field_id }
sequence_fields = (space_id) ->
  result = {}
  for t in *box.space._tdb_fields.index.by_space\select { space_id }
    if t[4] == 'Sequence'
      result[t[3]] = t[1]  -- name -> field_id
  result

-- Test one record against a filter (recursively handles and/or).
-- rec is a {id, data} record; data fields are accessed via parsed.
matches_filter = (parsed, flt) ->
  return true unless flt
  ok = if flt.field
    v = tostring (parsed[flt.field] or '')
    switch flt.op
      when 'EQ'          then v == flt.value
      when 'NEQ'         then v != flt.value
      when 'CONTAINS'    then v\find(flt.value, 1, true) != nil
      when 'STARTS_WITH' then v\sub(1, #flt.value) == flt.value
      else true
  else true
  if ok and flt.and
    for sub in *flt.and
      break unless ok
      ok = matches_filter parsed, sub
  if flt.or
    any = false
    for sub in *flt.or
      if matches_filter parsed, sub
        any = true
        break
    ok = ok and any
  ok

apply_filter = (tuples, filter) ->
  return tuples unless filter and (filter.field or filter.and or filter.or)
  filtered = {}
  for rec in *tuples
    parsed = if type(rec.data) == 'string' then json.decode(rec.data) else rec.data
    if matches_filter parsed, filter
      table.insert filtered, rec
  filtered

Mutation =
  insertRecord: (_, args, ctx) ->
    require_auth ctx
    sp = data_space args.spaceId
    id   = tostring uuid_mod.new!
    data = if type(args.data) == 'string' then json.decode(args.data) else args.data
    -- Auto-populate Sequence fields (overrides any user-supplied value)
    for field_name, field_id in pairs sequence_fields(args.spaceId)
      seq = box.sequence["_tdb_seq_#{field_id}"]
      data[field_name] = seq\next! if seq
    sp\insert { id, json.encode data }
    { id: id, spaceId: args.spaceId, data: json.encode(data) }

  updateRecord: (_, args, ctx) ->
    require_auth ctx
    sp = data_space args.spaceId
    existing = sp\get args.id
    error "Record not found: #{args.id}" unless existing
    ok_d, old_data = pcall json.decode, existing[2]
    error "Corrupted record data: #{old_data}" unless ok_d
    new_data = if type(args.data) == 'string' then json.decode(args.data) else args.data
    -- Skip Sequence fields (immutable)
    seq_fields = sequence_fields args.spaceId
    for k, v in pairs new_data
      old_data[k] = v unless seq_fields[k]
    sp\replace { args.id, json.encode old_data }
    { id: args.id, spaceId: args.spaceId, data: json.encode(old_data) }

  deleteRecord: (_, args, ctx) ->
    require_auth ctx
    sp = data_space args.spaceId
    sp\delete args.id
    true

Query =
  records: (_, args, ctx) ->
    require_auth ctx
    sp = data_space args.spaceId
    limit  = args.limit  or 100
    offset = args.offset or 0
    -- Collect all records
    all = {}
    for t in *sp\select {}
      table.insert all, { id: t[1], spaceId: args.spaceId, data: t[2] }
    -- Filter
    filtered = apply_filter all, args.filter
    -- Paginate
    total = #filtered
    items = {}
    for i = offset + 1, math.min(offset + limit, total)
      table.insert items, filtered[i]
    { items: items, total: total, offset: offset, limit: limit }

  record: (_, args, ctx) ->
    sp = data_space args.spaceId
    t = sp\get args.id
    return nil unless t
    { id: t[1], spaceId: args.spaceId, data: t[2] }

{ :Query, :Mutation }
