-- resolvers/data_resolvers.moon
-- Resolvers for CRUD operations on user-defined data spaces.

json      = require 'json'
log       = require 'log'
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
-- self_val: the record as a make_self_proxy (for formula) or plain dict (for field filters)
matches_filter = (self_val, flt) ->
  return true unless flt
  ok = if flt.formula and flt.formula != ''
    if type(flt._formula_fn) == 'function'
      r_ok, r_val = pcall flt._formula_fn, self_val
      r_ok and r_val and r_val != false
    else false  -- formula failed to compile or not yet cached
  else if flt.field
    -- For field comparisons use the raw value (proxy passes through scalars)
    v = tostring (self_val[flt.field] or '')
    switch flt.op
      when 'EQ'          then v == flt.value
      when 'NEQ'         then v != flt.value
      when 'LT'          then tonumber(v) < tonumber(flt.value)
      when 'GT'          then tonumber(v) > tonumber(flt.value)
      when 'LTE'         then tonumber(v) <= tonumber(flt.value)
      when 'GTE'         then tonumber(v) >= tonumber(flt.value)
      when 'CONTAINS'    then v\find(flt.value, 1, true) != nil
      when 'STARTS_WITH' then v\sub(1, #flt.value) == flt.value
      else true
  else true
  if ok and flt.and
    for sub in *flt.and
      break unless ok
      ok = matches_filter self_val, sub
  if flt.or
    any = false
    for sub in *flt.or
      if matches_filter self_val, sub
        any = true
        break
    ok = ok and any
  ok

-- fk_def_map is optional; when present, formula filters receive an FK-aware proxy.
apply_filter = (tuples, filter, fk_def_map, fk_cache, space_name) ->
  return tuples unless filter and (filter.field or filter.formula or filter.and or filter.or)
  -- Pre-compile formula once to avoid re-compiling per record
  if filter.formula and filter.formula != '' and filter._formula_fn == nil
    triggers = require 'core.triggers'
    lang = filter.language or 'moonscript'
    ok_c, fn = pcall triggers.compile_formula, filter.formula, 'filter', lang
    filter._formula_fn = if ok_c and type(fn) == 'function' then fn else false
  triggers_mod = require 'core.triggers'
  filtered = {}
  for rec in *tuples
    parsed = if type(rec.data) == 'string' then json.decode(rec.data) else rec.data
    self_val = if fk_def_map
      parsed._id = tostring rec.id
      triggers_mod.make_self_proxy parsed, fk_def_map, fk_cache, space_name
    else parsed
    if matches_filter self_val, filter
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

  deleteRecords: (_, args, ctx) ->
    require_auth ctx
    sp = data_space args.spaceId
    results = for id in *args.ids
      sp\delete id
      true
    results

  insertRecords: (_, args, ctx) ->
    require_auth ctx
    sp, meta = data_space args.spaceId
    seq_fields = sequence_fields args.spaceId
    triggers_mod = require 'core.triggers'
    
    results = {}
    box.atomic ->
      for d in *args.data
        id = tostring uuid_mod.new!
        data = if type(d) == 'string' then json.decode(d) else d
        -- Auto-populate Sequence fields
        for field_name, field_id in pairs seq_fields
          seq = box.sequence["_tdb_seq_#{field_id}"]
          data[field_name] = seq\next! if seq
        sp\insert { id, json.encode data }
        table.insert results, { id: id, spaceId: args.spaceId, data: json.encode(data) }
    results

  updateRecords: (_, args, ctx) ->
    require_auth ctx
    sp, meta = data_space args.spaceId
    seq_fields = sequence_fields args.spaceId
    
    results = {}
    box.atomic ->
      for rec in *args.records
        id = rec.id
        existing = sp\get id
        unless existing
          log.error "Record not found: #{id}"
          continue
        
        ok_d, old_data = pcall json.decode, existing[2]
        unless ok_d
          log.error "Corrupted record data for #{id}: #{old_data}"
          continue
          
        new_data = if type(rec.data) == 'string' then json.decode(rec.data) else rec.data
        -- Skip Sequence fields (immutable)
        for k, v in pairs new_data
          old_data[k] = v unless seq_fields[k]
        
        sp\replace { id, json.encode old_data }
        table.insert results, { id: id, spaceId: args.spaceId, data: json.encode(old_data) }
    results

Query =
  records: (_, args, ctx) ->
    require_auth ctx
    sp = data_space args.spaceId
    limit  = args.limit  or 100
    offset = args.offset or 0
    triggers_mod = require 'core.triggers'
    -- Build FK map once for this space (used by both reprFormula and filter formulas)
    ok_fk, fk_def_map = pcall triggers_mod.build_fk_def_map, args.spaceId
    fk_def_map = if ok_fk then fk_def_map else {}
    
    -- Get space name to enable computed columns resolution
    sp_meta = box.space._tdb_spaces\get args.spaceId
    space_name = sp_meta and sp_meta[2]
    
    -- Reuse a per-request FK cache
    ctx._fk_cache = ctx._fk_cache or {}
    
    -- Pre-compile reprFormula if provided
    repr_fn = nil
    if args.reprFormula and args.reprFormula != ''
      lang = args.reprLanguage or 'moonscript'
      ok_c, fn = pcall triggers_mod.compile_formula, args.reprFormula, 'repr', lang
      repr_fn = if ok_c and type(fn) == 'function' then fn else nil
    -- Collect all records, injecting _repr when formula is available
    all = {}
    for t in *sp\select {}
      if repr_fn
        parsed = json.decode t[2]
        parsed._id = tostring t[1]
        self_proxy = triggers_mod.make_self_proxy parsed, fk_def_map, ctx._fk_cache, space_name
        ok_r, val = pcall repr_fn, self_proxy, nil
        if ok_r and val != nil
          parsed._repr = tostring val
        parsed._id = nil
        table.insert all, { id: t[1], spaceId: args.spaceId, data: json.encode(parsed) }
      else
        table.insert all, { id: t[1], spaceId: args.spaceId, data: t[2] }
    -- Filter (fk_def_map enables FK traversal in formula filters)
    filtered = apply_filter all, args.filter, fk_def_map, ctx._fk_cache, space_name
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
