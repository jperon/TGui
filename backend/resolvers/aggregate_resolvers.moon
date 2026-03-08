-- resolvers/aggregate_resolvers.moon
-- Aggregation query: GROUP BY via Lua iteration over tuples.
-- (Tarantool SQL engine requires a named format, which user spaces don't have.)

{ :require_auth } = require 'resolvers.utils'
json = require 'json'

-- Whitelist of allowed aggregate functions
ALLOWED_FNS = { sum: true, count: true, avg: true, min: true, max: true }

-- Auto-generate alias when 'as' is not provided
make_alias = (agg) ->
  return agg.as if agg.as and agg.as != ''
  if not agg.field then 'count' else "#{agg.fn}_#{agg.field}"

Query =
  aggregateSpace: (_, args, ctx) ->
    require_auth ctx

    space_name = args.spaceName
    group_by   = args.groupBy   or {}
    aggregates = args.aggregate or {}

    -- Validate space name
    error "Nom d'espace invalide: #{space_name}" unless space_name\match "^[%w_]+$"

    -- Validate fn values against whitelist
    for agg in *aggregates
      fn = (agg.fn or '')\lower!
      error "Fonction d'agrégation non supportée: #{agg.fn}" unless ALLOWED_FNS[fn]

    sp = box.space["data_#{space_name}"]
    error "Espace introuvable: #{space_name}" unless sp

    -- Full scan: group tuples by key
    groups     = {}  -- key -> { _vals, _d }
    group_keys = {}  -- ordered list of keys (insertion order)

    for tuple in *sp\select {}
      d = if type(tuple[2]) == 'string' then json.decode(tuple[2]) else tuple[2]

      -- Compute group key (tab-separated string of groupBy values)
      parts = [tostring(d[f] != nil and d[f] or '') for f in *group_by]
      key   = table.concat parts, '\t'

      unless groups[key]
        groups[key] = { _d: d, _vals: {} }
        table.insert group_keys, key
        -- Initialise accumulators for each aggregate
        for agg in *aggregates
          groups[key]._vals[agg] = { count: 0, sum: 0, min: nil, max: nil }

      g = groups[key]
      for agg in *aggregates
        acc = g._vals[agg]
        acc.count += 1
        if agg.field
          val = tonumber d[agg.field]
          if val != nil
            acc.sum += val
            acc.min  = if acc.min != nil then math.min(acc.min, val) else val
            acc.max  = if acc.max != nil then math.max(acc.max, val) else val

    -- Build result rows in insertion order
    rows = for key in *group_keys
      g   = groups[key]
      row = {}
      for f in *group_by
        row[f] = g._d[f]
      for agg in *aggregates
        alias = make_alias agg
        acc   = g._vals[agg]
        fn    = agg.fn\lower!
        row[alias] = switch fn
          when 'count' then acc.count
          when 'sum'   then acc.sum
          when 'avg'   then if acc.count > 0 then acc.sum / acc.count else nil
          when 'min'   then acc.min
          when 'max'   then acc.max
      row
    rows

{ :Query }
