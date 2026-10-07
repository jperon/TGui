-- core/formula_proxy.moon
-- Formula plumbing for reads: error formatting, the compiled-formula cache,
-- the space() helper and the self proxies that resolve FK fields (single and
-- 1-to-N) lazily. Extracted from core.triggers (T14).
--
-- The single/multiple proxies share their space loading, FK-map cache and
-- formula evaluation through the module-level helpers below (T14 step 4), with
-- no observable change. The `fk_cache.can_read` read guard is enforced in both
-- make_space_helper (space() calls) and ensure_space (FK target loading).

json                   = require 'json'
log                    = require 'log'
{ :safe_formula_call } = require 'core.config'
{ :compile_formula }   = require 'core.formula_sandbox'
{ :build_fk_def_map }  = require 'core.relation_maps'

-- Helper to format and categorize formula execution errors for the frontend
format_formula_error = (err) ->
  -- Single assignment outside the branches: a variable first assigned inside a
  -- branch would be local to that branch and nil afterwards (compiled to
  -- `local s` per branch, then `s:find` on a nil global — observed crash).
  s = if type(err) == 'string'
    err
  elseif type(err) == 'table' and err.message
    err.message
  else
    tostring(err)

  -- Categorize common error patterns
  if s\find "attempt to concatenate"
    short = "Invalid concatenation"
  elseif s\find "unexpected symbol" or s\find "malformed number" or s\find "parse error"
    short = "Syntax error"
  elseif s\find "stack overflow"
    short = "Infinite loop (recursion)"
  else
    -- Generic fallback for unexpected errors.
    short = "Unknown error"

  -- Remove Lua-generated prefix '[string \"...\"]:line: '.
  clean_msg = s\gsub '^%[string ".-"%]:%d+: ', ''

  -- Expected frontend format: [ERROR|Short type|Full message]
  "[ERROR|#{short}|#{clean_msg}]"

-- ── Formula compilation and caching ────────────────────────────────────────────

-- Cache for compiled formulas: space_name -> { field_name -> function }
formula_cache = {}

invalidate_formula_cache = (space_name = nil) ->
  if space_name
    formula_cache[space_name] = nil
  else
    for k in pairs formula_cache
      formula_cache[k] = nil

-- Get or compile formulas for a space
ensure_formulas = (space_name) ->
  return formula_cache[space_name] if formula_cache[space_name]

  space_meta = box.space._tdb_spaces.index.by_name\get { space_name }
  return {} unless space_meta

  space_id = space_meta[1]
  formulas = {}

  for field in *box.space._tdb_fields.index.by_space\select { space_id }
    if field[8] and field[8] != ''  -- formula column
      field_name = field[3]
      formula = field[8]
      language = field[10] or 'lua'

      compiled = compile_formula formula, field_name, language
      if compiled
        formulas[field_name] = compiled

  formula_cache[space_name] = formulas
  formulas

-- ── Shared proxy helpers ───────────────────────────────────────────────────────

-- Decode a Tarantool tuple into a plain record.
decode_tuple = (t) ->
  d = if type(t[2]) == 'string' then json.decode(t[2]) else t[2]
  d._id = tostring t[1]
  d

-- fk_cache: optional per-request cache carrying a `can_read(space_name)`
-- predicate (set by resolvers.utils.fk_cache_for for user-facing reads). When
-- present and refusing a target space, space(name) returns an empty list so a
-- formula cannot read a space the user has no `read` grant on. Absent for
-- write-time triggers, which then keep full access.
make_space_helper = (fk_cache) ->
  (sname) ->
    return {} if fk_cache and fk_cache.can_read and not fk_cache.can_read sname
    sp = box.space["data_#{sname}"]
    return {} unless sp
    [decode_tuple t for t in *sp\select {}]

-- Ensure the shared caches exist on an fk_cache table (created when absent).
prepare_cache = (fk_cache) ->
  fk_cache             = fk_cache or {}
  fk_cache.spaces      = fk_cache.spaces      or {}
  fk_cache.fk_def_maps = fk_cache.fk_def_maps or {}
  fk_cache.formulas    = fk_cache.formulas    or {}
  fk_cache

-- Load a target space once and build field indexes on demand (no extra scan).
-- Refuses to load a space the requesting user cannot read: an empty index makes
-- every lookup miss (nil for a single FK, empty list for a 1-to-N).
ensure_space = (fk_cache, s_name, to_field_name) ->
  if fk_cache.can_read and not fk_cache.can_read s_name
    return { records: {}, by_field: {} }
  sc = fk_cache.spaces[s_name]
  unless sc
    sc = { records: {}, by_field: {} }
    tb = box.space["data_#{s_name}"]
    if tb
      for tup in *tb\select {}
        d = decode_tuple tup
        sc.records[d._id] = d
    fk_cache.spaces[s_name] = sc

  -- Always build _id index for primary lookup
  unless sc.by_field['_id']
    idx = {}
    for _, d in pairs sc.records
      if d._id ~= nil
        key = tostring(d._id)
        idx[key] = d
    sc.by_field['_id'] = idx

  -- Build specific field index if needed and different from _id
  if to_field_name != '_id' and not sc.by_field[to_field_name]
    idx = {}
    for _, d in pairs sc.records
      if d[to_field_name] ~= nil
        key = tostring(d[to_field_name])
        idx[key] = d
    sc.by_field[to_field_name] = idx

  sc

-- Get or build a nested fk_def_map (cached, avoids repeated metadata scans).
ensure_fk_def_map = (fk_cache, space_id) ->
  return fk_cache.fk_def_maps[space_id] if fk_cache.fk_def_maps[space_id]
  fk_def_map = build_fk_def_map space_id
  fk_cache.fk_def_maps[space_id] = fk_def_map
  fk_def_map

-- Evaluate the computed formula for field k when the raw value is missing.
-- Returns (value, is_error): is_error=true means `value` is the formatted error
-- string to return directly; otherwise `value` is the (possibly original) raw
-- value and evaluation must continue with FK resolution.
eval_computed_formula = (t, k, v, space_name, fk_cache) ->
  return v, false unless (v == nil or v == '') and space_name
  fns = ensure_formulas space_name
  return v, false unless fns[k]
  fk_cache.space_helper = fk_cache.space_helper or make_space_helper fk_cache
  val, err = safe_formula_call fns[k], "formula #{space_name}.#{k}", nil, nil, { t, fk_cache.space_helper }
  if err != nil
    log.error "tdb proxy: error evaluating formula for '#{space_name}.#{k}': #{err}"
    return format_formula_error(err), true
  if val != nil and val != ''
    rawset t, k, val
    return val, false
  return v, false

-- ── Self proxy ────────────────────────────────────────────────────────────────

-- Build a self proxy that resolves FK fields lazily, with recursive chaining.
-- fk_def_map: { field_name => { toSpaceName, toFieldName } }
-- fk_cache: optional shared cache (passed across all records of a single request)
make_self_proxy = (record, fk_def_map, fk_cache, space_name) ->
  fk_cache = prepare_cache fk_cache

  proxy = setmetatable {}, {
    __index: (t, k) ->
      cached = rawget t, k
      return cached if cached != nil
      v = record[k]

      v, is_error = eval_computed_formula t, k, v, space_name, fk_cache
      return v if is_error
      return nil if v == nil or v == ''

      fk = fk_def_map and fk_def_map[k]
      if fk
        lookup_field = fk.toFieldName or '_id'
        sc = ensure_space fk_cache, fk.toSpaceName, lookup_field
        d = sc.by_field[lookup_field] and sc.by_field[lookup_field][tostring v]
        d = sc.by_field['_id'] and sc.by_field['_id'][tostring v] if not d and lookup_field != '_id'

        if d
          -- Always return a nested proxy for consistent behavior
          nested_space = box.space._tdb_spaces.index.by_name\get { fk.toSpaceName }
          nested_space_id = nested_space and nested_space[1]
          nested_fk_map = if nested_space_id then ensure_fk_def_map fk_cache, nested_space_id else {}
          nested = make_self_proxy d, nested_fk_map, fk_cache, fk.toSpaceName
          rawset t, k, nested
          return nested
        return nil
      v
  }
  proxy

-- ── Extended Self Proxy with List Support ────────────────────────────────────────

-- Build an extended self proxy that supports both single and multiple relations.
-- single_fk_map: { field_name => { toSpaceName, toFieldName } }
-- multiple_fk_map: { field_name => { toSpaceName, toFieldName } }
-- fk_cache: optional shared cache (passed across all records of a single request)
make_self_proxy_extended = (record, single_fk_map, multiple_fk_map, fk_cache, space_name) ->
  fk_cache = prepare_cache fk_cache

  -- Resolve multiple references (1-to-N relations)
  resolve_multiple_references = (source_id, relation_def) ->
    sc = ensure_space fk_cache, relation_def.toSpaceName, relation_def.toFieldName
    results = {}

    -- Find all records in target space that reference the source record
    for _, d in pairs sc.records
      if d[relation_def.toFieldName] == source_id
        -- Create a nested proxy for each found record
        nested_space = box.space._tdb_spaces.index.by_name\get { relation_def.toSpaceName }
        nested_space_id = nested_space and nested_space[1]
        nested_fk_map = if nested_space_id then ensure_fk_def_map fk_cache, nested_space_id else {}
        nested = make_self_proxy_extended d, single_fk_map, multiple_fk_map, fk_cache, relation_def.toSpaceName
        table.insert results, nested

    return results

  proxy = setmetatable {
    list: {
      length: (list) -> #list or 0
      first: (list) -> list and list[1] or nil
      last: (list) -> list and list[#list] or nil
      map: (list, fn) -> [fn(item) for item in *list]
      filter: (list, fn) -> [item for item in *list when fn(item)]
      reduce: (list, fn, init) ->
        result = init
        for item in *list
          result = fn(result, item)
        result
    }
  }, {
    __index: (t, k) ->
      cached = rawget t, k
      return cached if cached != nil
      v = record[k]

      v, is_error = eval_computed_formula t, k, v, space_name, fk_cache
      return v if is_error
      return nil if v == nil or v == ''

      -- Check if it's a multiple relation first
      multiple_fk = multiple_fk_map and multiple_fk_map[k]
      if multiple_fk
        -- Relation 1-to-N : return a list of records
        source_id = tostring v
        list = resolve_multiple_references source_id, multiple_fk
        rawset t, k, list
        return list

      -- Check if it's a single relation (standard FK)
      fk = single_fk_map and single_fk_map[k]
      if fk
        lookup_field = fk.toFieldName or '_id'
        sc = ensure_space fk_cache, fk.toSpaceName, lookup_field
        d = sc.by_field[lookup_field] and sc.by_field[lookup_field][tostring v]
        d = sc.by_field['_id'] and sc.by_field['_id'][tostring v] if not d and lookup_field != '_id'

        if d
          -- Always return a nested proxy for consistent behavior
          nested_space = box.space._tdb_spaces.index.by_name\get { fk.toSpaceName }
          nested_space_id = nested_space and nested_space[1]
          nested_fk_map = if nested_space_id then ensure_fk_def_map fk_cache, nested_space_id else {}
          nested = make_self_proxy_extended d, single_fk_map, multiple_fk_map, fk_cache, fk.toSpaceName
          rawset t, k, nested
          return nested
        return nil
      v
  }
  proxy

{ :make_self_proxy, :make_self_proxy_extended, :make_space_helper, :format_formula_error, :invalidate_formula_cache }
