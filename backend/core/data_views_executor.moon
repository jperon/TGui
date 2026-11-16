-- core/data_views_executor.moon
-- Execution engine for Data Views queries.
-- Performs mapping, filtering, joining, grouping, aggregating, and sorting in-memory.

json = require 'json'
log = require 'log'
{ :yield_every } = require 'core.config'
{ :make_self_proxy, :build_fk_def_map } = require 'core.triggers'
{ :relation_field_value } = require 'core.formula_proxy'

-- Value of one field for one record, as a group label or an aggregate input.
-- A relation field must contribute its raw FK value (the Int that is stored, or
-- the value computed at read time): make_self_proxy resolves it to the target
-- record, i.e. a table, which is neither a usable label nor a number. Computed
-- fields keep the proxy, since their value only exists there.
field_value = (rec, field_name, fk_def_map, space_name, fk_cache) ->
  return rec.proxy[field_name] unless fk_def_map[field_name]
  raw = rec.d[field_name]
  return raw if raw != nil and raw != ''
  relation_field_value rec.d, field_name, space_name, fk_cache

-- Execute a data view config on a source space.
-- source_space_ref is the space id (UUID) stored by the frontend; for robustness
-- we also accept a space name.
execute_view = (source_space_ref, config_json, params) ->
  config = if type(config_json) == 'string' and config_json != ''
    json.decode config_json
  else
    {}

  sp_meta = box.space._tdb_spaces\get { source_space_ref }
  sp_meta or= box.space._tdb_spaces.index.by_name\get { source_space_ref }
  error "Source space not found: #{source_space_ref}" unless sp_meta
  space_id = sp_meta[1]
  source_space_name = sp_meta[2]
  sp = box.space["data_#{source_space_name}"]
  return {} unless sp

  -- 1. Full scan & build proxies
  fk_def_map = build_fk_def_map space_id
  fk_cache   = {}
  
  -- Gather all records
  records = {}
  tuples = sp\select {}
  for i, t in ipairs tuples
    -- One row per iteration, each building a self proxy (formulas resolved
    -- lazily below): yield so other requests progress during a full scan.
    yield_every i
    d = if type(t[2]) == 'string' then json.decode(t[2]) else t[2]
    d._id = tostring t[1]
    proxy = make_self_proxy d, fk_def_map, fk_cache, source_space_name
    table.insert records, { :d, :proxy }
  
  -- 2. Filter (WHERE)
  if config.filter
    resolvers = require 'resolvers.data_resolvers'
    filtered = {}
    for i, rec in ipairs records
      -- Filter formulas are evaluated per row: yield periodically.
      yield_every i
      if resolvers.matches_filter(rec.proxy, config.filter)
        table.insert filtered, rec
    records = filtered

  -- 3. Map (SELECT) & Joins
  -- Not fully implemented joins yet, relying on proxy for basic foreign key resolutions
  
  -- 4. Group By & Aggregation
  if config.groupBy and #config.groupBy > 0
    groups = {}
    group_keys = {}
    
    for i, rec in ipairs records
      -- Grouping reads computed fields per row (field_value -> proxy).
      yield_every i
      -- compute key
      parts = [tostring(field_value(rec, f, fk_def_map, source_space_name, fk_cache) or '') for f in *config.groupBy]
      key = table.concat parts, '\t'
      
      unless groups[key]
        -- _g porte la valeur *résolue* (formule comprise) de chaque champ de
        -- regroupement ; _d (données brutes) ne contient pas les colonnes
        -- calculées, d'où des libellés nuls dans les vues agrégées. Un champ
        -- relation y contribue par sa valeur brute (Int), jamais par l'objet
        -- cible rendu par le proxy FK.
        groups[key] = { _d: rec.d, _g: {}, _vals: {} }
        table.insert group_keys, key
        for f in *config.groupBy
          groups[key]._g[f] = field_value rec, f, fk_def_map, source_space_name, fk_cache
        if config.aggregates
          for agg in *config.aggregates
            groups[key]._vals[agg] = { count: 0, sum: 0, min: nil, max: nil }
      
      g = groups[key]
      if config.aggregates
        for agg in *config.aggregates
          acc = g._vals[agg]
          acc.count += 1
          if agg.field
            val = tonumber(field_value(rec, agg.field, fk_def_map, source_space_name, fk_cache))
            if val != nil
              acc.sum += val
              acc.min = if acc.min != nil then math.min(acc.min, val) else val
              acc.max = if acc.max != nil then math.max(acc.max, val) else val

    -- Build aggregated records
    agg_records = {}
    for key in *group_keys
      g = groups[key]
      row = {}
      for f in *config.groupBy
        row[f] = g._g[f]
      if config.aggregates
        for agg in *config.aggregates
          alias = agg.as or (if agg.field then "#{agg.fn}_#{agg.field}" else "count")
          acc = g._vals[agg]
          fn = (agg.fn or '')\lower!
          if fn == 'count' then row[alias] = acc.count
          elseif fn == 'sum' then row[alias] = acc.sum
          elseif fn == 'avg' then row[alias] = if acc.count > 0 then acc.sum / acc.count else nil
          elseif fn == 'min' then row[alias] = acc.min
          elseif fn == 'max' then row[alias] = acc.max
      table.insert agg_records, row
    
    -- Replace records with aggregated rows
    records = [{ d: row, proxy: row } for row in *agg_records]
  
  -- 5. Order By
  if config.orderBy and #config.orderBy > 0
    table.sort records, (a, b) ->
      for order in *config.orderBy
        field = order.field
        vA = a.proxy[field]
        vB = b.proxy[field]
        -- Handle nils
        if vA == nil and vB == nil then continue
        if vA == nil then return false
        if vB == nil then return true
        
        cmp = if type(vA) == "number" and type(vB) == "number"
          vA < vB
        else
          tostring(vA) < tostring(vB)
          
        if tostring(vA) != tostring(vB)
          return if order.desc then not cmp else cmp
      false

  -- 6. Map Columns
  if config.columns and #config.columns > 0
    mapped = {}
    for i, rec in ipairs records
      -- Mapping reads computed fields per row (rec.proxy[col]).
      yield_every i
      row = {}
      for col in *config.columns
        if type(col) == 'string'
          row[col] = rec.proxy[col]
        elseif type(col) == 'table' and col.field
          alias = col.as or col.field
          row[alias] = rec.proxy[col.field]
      -- always keep id if present and not overwritten
      row.id = rec.d._id unless row.id
      table.insert mapped, row
    records = [{ d: row, proxy: row } for row in *mapped]
    
  -- 7. Limit & Offset
  limit = tonumber(params and params.limit) or tonumber(config.limit)
  offset = tonumber(params and params.offset) or tonumber(config.offset) or 0
  
  if limit or offset > 0
    sliced = {}
    start_idx = offset + 1
    end_idx = if limit then offset + limit else #records
    for i = start_idx, math.min(end_idx, #records)
      table.insert sliced, records[i]
    records = sliced

  -- Return the raw dictionary list
  [rec.d for rec in *records]

{ :execute_view }
