-- backend/core/graphql_flattener.moon
-- GraphQL Flattener with intelligent list handling

json = require 'json'

-- Main flattening class
GraphQLFlattener = {}

-- Main flattening method
GraphQLFlattener.flatten = (data, query, fieldDefinitions) ->
  flattened = {}
  
  records = data.records or data
  return flattened unless records
  
  for record in records
    flat = GraphQLFlattener.flattenRecord record, query, fieldDefinitions, ""
    table.insert flattened, flat
    
  return flattened

-- Flatten a single record
GraphQLFlattener.flattenRecord = (record, query, fieldDefinitions, prefix) ->
  flat = {}
  
  for field, value in pairs record
    fieldDef = GraphQLFlattener.findFieldDefinition field, fieldDefinitions, prefix
    
    if GraphQLFlattener.isListValue value, fieldDef
      -- List of records - preserve as array
      flat["#{prefix}#{field}"] = GraphQLFlattener.flattenList value, query, fieldDefinitions, "#{prefix}#{field}_"
    elseif GraphQLFlattener.isObject value
      -- Object - flatten recursively
      nested = GraphQLFlattener.flattenRecord value, query, fieldDefinitions, "#{prefix}#{field}_"
      for k, v in pairs nested
        flat[k] = v
    else
      -- Simple field
      columnName = if prefix != "" then "#{prefix}#{field}" else field
      flat[columnName] = value
      
  return flat

-- Flatten a list of records
GraphQLFlattener.flattenList = (list, query, fieldDefinitions, prefix) ->
  flattened_list = {}
  
  for i, item in ipairs list
    if GraphQLFlattener.isObject item
      flat_item = GraphQLFlattener.flattenRecord item, query, fieldDefinitions, "#{prefix}#{i}_"
      table.insert flattened_list, flat_item
    else
      -- Simple item in list
      flattened_list["#{prefix}#{i}"] = item
    
  return flattened_list

-- Find field definition by name
GraphQLFlattener.findFieldDefinition = (fieldName, fieldDefinitions, prefix) ->
  -- Try exact match first
  if fieldDefinitions[fieldName]
    return fieldDefinitions[fieldName]
  
  -- Try with prefix
  prefixedName = prefix .. fieldName
  if fieldDefinitions[prefixedName]
    return fieldDefinitions[prefixedName]
  
  -- Try without prefix for nested fields
  if prefix != ""
    baseName = fieldName\gsub("^" .. prefix, "")
    if fieldDefinitions[baseName]
      return fieldDefinitions[baseName]
  
  return nil

-- Check if value is a list
GraphQLFlattener.isListValue = (value, fieldDef) ->
  return false unless value
  
  -- Check field definition type
  if fieldDef and fieldDef.type == 'List'
    return true
  
  -- Check if it's an array with objects
  if GraphQLFlattener.isArray value
    if #value > 0
      firstItem = value[1]
      return GraphQLFlattener.isObject firstItem
  
  return false

-- Check if value is an array
GraphQLFlattener.isArray = (value) ->
  return type(value) == 'table' and GraphQLFlattener.isNumericArray value

-- Check if table is a numeric array (has consecutive numeric keys starting from 1)
GraphQLFlattener.isNumericArray = (table) ->
  return false unless table
  
  count = 0
  for key, _ in pairs table
    if type(key) != 'number'
      return false
    count += 1
  
  return count > 0

-- Check if value is an object (table with string keys)
GraphQLFlattener.isObject = (value) ->
  return type(value) == 'table' and not GraphQLFlattener.isNumericArray value

-- Check if value is a date
GraphQLFlattener.isDate = (value) ->
  return false unless value
  return type(value) == 'table' and value.year and value.month and value.day

-- Check if value is a simple type (string, number, boolean)
GraphQLFlattener.isSimpleType = (value) ->
  typeValue = type(value)
  return typeValue == 'string' or typeValue == 'number' or typeValue == 'boolean'

-- Convert list to Lua-style array for computed fields
GraphQLFlattener.convertToList = (luaTable) ->
  result = {}
  for i, v in ipairs luaTable
    result[i] = v
  return result

-- Generate column names from query
GraphQLFlattener.generateColumnNames = (query) ->
  -- Simple implementation - extract field names from query
  columnNames = {}
  
  -- Match field selections
  fieldMatches = {}
  for match in query\gmatch "(%w+)%s*(%b{})"
    fieldName = match\match "(%w+)"
    if fieldName
      table.insert columnNames, fieldName
  
  return columnNames

-- Detect list fields in data
GraphQLFlattener.detectListFields = (data) ->
  listFields = {}
  
  records = data.records or data
  return listFields unless records and #records > 0
  
  -- Check first record for list fields
  firstRecord = records[1]
  for field, value in pairs firstRecord
    if GraphQLFlattener.isArray value and #value > 0
      firstItem = value[1]
      if GraphQLFlattener.isObject firstItem
        listFields[field] = true
  
  return listFields

-- Flatten with performance optimization for large datasets
GraphQLFlattener.flattenOptimized = (data, query, fieldDefinitions, options) ->
  options = options or {}
  batchSize = options.batchSize or 1000
  maxDepth = options.maxDepth or 5
  
  flattened = {}
  records = data.records or data
  return flattened unless records
  
  -- Process in batches for large datasets
  for i = 1, #records, batchSize
    batchEnd = math.min i + batchSize - 1, #records
    
    for j = i, batchEnd
      record = records[j]
      flat = GraphQLFlattener.flattenRecord record, query, fieldDefinitions, "", maxDepth
      table.insert flattened, flat
  
  return flattened

-- Flatten with depth limit to prevent infinite recursion
GraphQLFlattener.flattenRecord = (record, query, fieldDefinitions, prefix, maxDepth) ->
  maxDepth = maxDepth or 5
  if maxDepth <= 0
    -- Return simple representation when depth limit reached
    return { "#{prefix}_depth_limit": "MAX_DEPTH_REACHED" }
  
  flat = {}
  
  for field, value in pairs record
    fieldDef = GraphQLFlattener.findFieldDefinition field, fieldDefinitions, prefix
    
    if GraphQLFlattener.isListValue value, fieldDef
      -- List of records - preserve as array
      flat["#{prefix}#{field}"] = GraphQLFlattener.flattenList value, query, fieldDefinitions, "#{prefix}#{field}_", maxDepth - 1
    elseif GraphQLFlattener.isObject value
      -- Object - flatten recursively
      nested = GraphQLFlattener.flattenRecord value, query, fieldDefinitions, "#{prefix}#{field}_", maxDepth - 1
      for k, v in pairs nested
        flat[k] = v
    else
      -- Simple field
      columnName = if prefix != "" then "#{prefix}#{field}" else field
      flat[columnName] = value
      
  return flat

-- Flatten list with depth limit
GraphQLFlattener.flattenList = (list, query, fieldDefinitions, prefix, maxDepth) ->
  maxDepth = maxDepth or 5
  if maxDepth <= 0
    return { "#{prefix}_depth_limit": "MAX_DEPTH_REACHED" }
  
  flattened_list = {}
  
  for i, item in ipairs list
    if GraphQLFlattener.isObject item
      flat_item = GraphQLFlattener.flattenRecord item, query, fieldDefinitions, "#{prefix}#{i}_", maxDepth - 1
      table.insert flattened_list, flat_item
    else
      -- Simple item in list
      flattened_list["#{prefix}#{i}"] = item
  
  return flattened_list

-- Validate flattened data structure
GraphQLFlattener.validateFlattened = (flattened, schema) ->
  errors = {}
  
  for i, record in ipairs flattened
    for field, expectedType in pairs schema
      value = record[field]
      if value and not GraphQLFlattener.validateType value, expectedType
        table.insert errors, "Record #{i}: Field '#{field}' has invalid type"
  
  return errors

-- Validate field type
GraphQLFlattener.validateType = (value, expectedType) ->
  switch expectedType
    when 'string'
      return type(value) == 'string'
    when 'number'
      return type(value) == 'number'
    when 'boolean'
      return type(value) == 'boolean'
    when 'array'
      return GraphQLFlattener.isArray value
    when 'object'
      return GraphQLFlattener.isObject value
    else
      return true -- Unknown type, assume valid

return GraphQLFlattener
