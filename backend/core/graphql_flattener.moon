-- backend/core/graphql_flattener.moon
-- GraphQL Flattener with intelligent list handling

json = require 'json'

-- Static utility methods
GraphQLFlattener = {}

GraphQLFlattener.isArray = (value) ->
  return type(value) == 'table' and #value > 0

GraphQLFlattener.isObject = (value) ->
  return type(value) == 'table' and not GraphQLFlattener.isArray(value)

GraphQLFlattener.isSimpleType = (value) ->
  valueType = type(value)
  return valueType == 'string' or valueType == 'number' or valueType == 'boolean'

GraphQLFlattener.validateFlattened = (flattened, schema) ->
  errors = {}

  for record in *flattened
    for field, value in pairs record
      if schema[field]
        expectedType = schema[field]
        actualType = type(value)

        -- Simple type validation
        if expectedType == 'string' and actualType != 'string'
          table.insert errors, "Field #{field}: expected string, got #{actualType}"
        elseif expectedType == 'number' and actualType != 'number'
          table.insert errors, "Field #{field}: expected number, got #{actualType}"
        elseif expectedType == 'boolean' and actualType != 'boolean'
          table.insert errors, "Field #{field}: expected boolean, got #{actualType}"

  return errors

-- Helper method to flatten a single record
flattenRecord = (record, query, fieldDefinitions, prefix) ->
  flat = {}

  for field, value in pairs record
    if field == "_id"
      -- Skip internal ID
      continue
    elseif GraphQLFlattener.isArray value
      -- List of records - preserve as array
      flat["#{prefix}#{field}"] = flattenList value, query, fieldDefinitions, "#{prefix}#{field}_"
    elseif GraphQLFlattener.isObject value
      -- Object - flatten recursively
      nested = flattenRecord value, query, fieldDefinitions, "#{prefix}#{field}_"
      for k, v in pairs nested
        flat[k] = v
    else
      -- Simple field
      columnName = if prefix != "" then "#{prefix}#{field}" else field
      flat[columnName] = value

  return flat

-- Helper method to flatten a list of records
flattenList = (list, query, fieldDefinitions, prefix) ->
  flattened_list = {}

  for i, item in ipairs list
    if GraphQLFlattener.isObject item
      flat_item = flattenRecord item, query, fieldDefinitions, "#{prefix}#{i}_"
      table.insert flattened_list, flat_item
    else
      -- Simple item in list
      flattened_list["#{prefix}#{i}"] = item

  return flattened_list

-- Main flattening method
GraphQLFlattener.flatten = (data, query, fieldDefinitions) ->
  flattened = {}

  return flattened unless data

  records = data.records or data
  return flattened unless records

  -- Simple flattening - just return the data as-is for now
  if type(records) == 'table'
    if GraphQLFlattener.isArray(records)
      -- Array of records
      for i, record in ipairs(records)
        if type(record) == 'table'
          flat = {}
          for field, value in pairs(record)
            if field != "_id"
              flat[field] = value
          flattened[i] = flat
    else
      -- Single record
      flat = {}
      for field, value in pairs(records)
        if field != "_id"
          flat[field] = value
      flattened[1] = flat

  return flattened

return GraphQLFlattener
