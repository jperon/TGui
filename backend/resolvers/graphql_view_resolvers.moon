-- backend/resolvers/graphql_view_resolvers.moon
-- GraphQL resolvers for data views with list support

triggers_mod = require 'core.triggers'
graphql_flattener = require 'core.graphql_flattener'
spaces_mod = require 'core.spaces'

-- Extended Query.records resolver with list support
Query:
  records_extended: (_, args, ctx) ->
    require_auth ctx

    space_id = args.spaceId
    limit = args.limit or 100
    offset = args.offset or 0

    -- Build relation maps for single and multiple relations
    single_fk_map, multiple_fk_map = triggers_mod.build_single_and_multiple_maps space_id

    -- Get space data
    sp = box.space["data_#{space_id}"]
    return {} unless sp

    -- Get space metadata for field definitions
    space_meta = box.space._tdb_spaces\get { space_id }
    return {} unless space_meta

    -- Build field definitions
    field_definitions = {}
    for field in *box.space._tdb_fields.index.by_space\select { space_id }
      field_name = field[3]
      field_type = field[4]

      -- Check if it's a relation
      single_relation = single_fk_map[field_name]
      multiple_relation = multiple_fk_map[field_name]

      if single_relation
        field_definitions[field_name] = {
          type: 'Single'
          space: single_relation.toSpaceName
          isRelation: true
        }
      elseif multiple_relation
        field_definitions[field_name] = {
          type: 'List'
          space: multiple_relation.toSpaceName
          isRelation: true
        }
      else
        field_definitions[field_name] = {
          type: field_type
          space: space_meta[2]
          isRelation: false
        }

    -- Process records with extended proxy
    records = {}
    fk_cache = {}

    for t in *sp\select {}, { limit: limit, offset: offset }
      d = if type(t[2]) == 'string' then json.decode(t[2]) else t[2]
      d._id = tostring t[1]

      -- Use extended proxy with list support
      proxy = triggers_mod.make_self_proxy_extended d, single_fk_map, multiple_fk_map, fk_cache, space_meta[2]

      -- Convert proxy to plain table for GraphQL
      record_data = {}
      for field in *box.space._tdb_fields.index.by_space\select { space_id }
        field_name = field[3]
        value = proxy[field_name]

        if value and type(value) == 'table' and value.__self  -- It's a proxy
          -- Convert proxy to plain table recursively
          record_data[field_name] = proxy_to_table value
        else
          record_data[field_name] = value

      table.insert records, record_data

    return records

  aggregated_records: (_, args, ctx) ->
    require_auth ctx

    space_id = args.config.spaceId
    config = args.config

    -- Get base records using extended resolver
    base_records = Query.records_extended _, { spaceId: space_id }, ctx

    -- Apply filters if specified
    if config.filter and config.filter.formula
      base_records = apply_filter_to_records base_records, config.filter.formula, space_id

    -- Apply grouping and aggregation
    if config.groupBy and #config.groupBy > 0
      return apply_grouping_and_aggregation base_records, config

    return base_records

-- Helper function to convert proxy to plain table
proxy_to_table = (proxy, visited = {}) ->
  return nil unless proxy

  -- Prevent infinite recursion
  proxy_id = tostring(proxy)
  if visited[proxy_id]
    return { _circular: true }
  visited[proxy_id] = true

  result = {}
  for key, value in pairs proxy
    if type(value) == 'table' and value.__self  -- Nested proxy
      result[key] = proxy_to_table value, visited
    elseif type(value) == 'table' and not (type(value) == 'function')
      -- Regular table
      if is_array(value)
        result[key] = [proxy_to_table(item, visited) for item in *value when type(item) == 'table' and item.__self]
      else
        result[key] = value
    else
      result[key] = value

  return result

-- Check if table is an array
is_array = (tbl) ->
  return false unless type(tbl) == 'table'

  count = 0
  for key, _ in pairs tbl
    if type(key) != 'number'
      return false
    count += 1

  return count > 0

-- Apply filter to records
apply_filter_to_records = (records, formula, space_id) ->
  return records unless formula and formula != ''

  -- Compile formula
  compiled = triggers_mod.compile_formula formula, 'filter', 'moonscript'
  return records unless compiled

  -- Create space helper
  space_helper = ->
    sp = box.space["data_#{space_id}"]
    return {} unless sp

    results = {}
    for t in *sp\select {}
      d = if type(t[2]) == 'string' then json.decode(t[2]) else t[2]
      d._id = tostring t[1]
      table.insert results, d

    return results

  -- Filter records
  filtered = {}
  for record in records
    -- Create proxy for formula evaluation
    single_fk_map, multiple_fk_map = triggers_mod.build_single_and_multiple_maps space_id
    proxy = triggers_mod.make_self_proxy_extended record, single_fk_map, multiple_fk_map, nil, space_id

    -- Evaluate formula
    success, result = pcall compiled, proxy, space_helper
    if success and result
      table.insert filtered, record

  return filtered

-- Apply grouping and aggregation
apply_grouping_and_aggregation = (records, config) ->
  return records unless records and #records > 0

  -- Group records
  groups = {}
  for record in records
    -- Build group key
    key_parts = {}
    for group_field in *config.groupBy
      value = record[group_field] or ''
      table.insert key_parts, tostring(value)

    key = table.concat(key_parts, '|')

    if not groups[key]
      groups[key] = {
        records: {}
        _values: {}
      }

    table.insert groups[key].records, record

    -- Initialize aggregation values
    if config.aggregates
      for agg in *config.aggregates
        agg_key = "#{agg.field}_#{agg.func}"
        groups[key]._values[agg_key] = {
          count: 0
          sum: 0
          min: nil
          max: nil
        }

  -- Calculate aggregations
  for key, group in pairs groups
    if config.aggregates
      for record in *group.records
        for agg in *config.aggregates
          if agg.field
            agg_key = "#{agg.field}_#{agg.func}"
            value = tonumber(record[agg.field])

            if value != nil
              acc = group._values[agg_key]
              acc.count += 1
              acc.sum += value
              acc.min = if acc.min != nil then math.min(acc.min, value) else value
              acc.max = if acc.max != nil then math.max(acc.max, value) else value

  -- Build result records
  result = {}
  for key, group in pairs groups
    result_record = {}

    -- Add group fields
    for i, group_field in *config.groupBy
      key_parts = {}
      for j, gf in *config.groupBy
        if j <= i
          table.insert key_parts, group.records[1][gf] or ''
      result_record[group_field] = table.concat(key_parts, '|')

    -- Add aggregations
    if config.aggregates
      for agg in *config.aggregates
        agg_key = "#{agg.field}_#{agg.func}"
        acc = group._values[agg_key]

        if acc
          alias = agg.as or "#{agg.func}_#{agg.field}"
          func = agg.func\lower!

          switch func
            when 'count'
              result_record[alias] = acc.count
            when 'sum'
              result_record[alias] = acc.sum
            when 'avg'
              result_record[alias] = if acc.count > 0 then acc.sum / acc.count else 0
            when 'min'
              result_record[alias] = acc.min
            when 'max'
              result_record[alias] = acc.max
            else
              result_record[alias] = nil

    table.insert result, result_record

  return result

return {
  Query: Query
}
