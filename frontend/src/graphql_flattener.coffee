# frontend/src/graphql_flattener.coffee
# GraphQL Flattener with intelligent list handling

class GraphQLFlattener
  # Main flattening method
  @flatten: (data, query, fieldDefinitions) ->
    flattened = []
    
    records = data.records or data
    return flattened unless records
    
    for record in records
      flat = @flattenRecord record, query, fieldDefinitions, ""
      table.insert flattened, flat
      
    return flattened

  # Flatten a single record
  @flattenRecord: (record, query, fieldDefinitions, prefix = "") ->
    flat = {}
    
    for field, value of record
      fieldDef = @findFieldDefinition field, fieldDefinitions, prefix
      
      if @isListValue(value, fieldDef)
        # List of records - preserve as array
        flat["#{prefix}#{field}"] = @flattenList value, query, fieldDefinitions, "#{prefix}#{field}_"
      else if @isObject(value) and not @isDate(value) and not @isSimpleType(value)
        # Object - flatten recursively
        nested = @flattenRecord value, query, fieldDefinitions, "#{prefix}#{field}_"
        Object.assign flat, nested
      else
        # Simple field
        columnName = if prefix != "" then "#{prefix}#{field}" else field
        flat[columnName] = value
        
    return flat

  # Flatten a list of records
  @flattenList: (list, query, fieldDefinitions, prefix) ->
    flattened_list = []
    
    for i, item in ipairs(list)
      if @isObject(item) and not @isDate(item) and not @isSimpleType(item)
        flat_item = @flattenRecord item, query, fieldDefinitions, "#{prefix}#{i}_"
        table.insert flattened_list, flat_item
      else
        # Simple item in list
        flattened_list["#{prefix}#{i}"] = item
    
    return flattened_list

  # Find field definition by name
  @findFieldDefinition: (fieldName, fieldDefinitions, prefix) ->
    # Try exact match first
    if fieldDefinitions[fieldName]
      return fieldDefinitions[fieldName]
    
    # Try with prefix
    prefixedName = prefix + fieldName
    if fieldDefinitions[prefixedName]
      return fieldDefinitions[prefixedName]
    
    # Try without prefix for nested fields
    if prefix != ""
      baseName = fieldName.replace(new RegExp("^#{prefix}"), '')
      if fieldDefinitions[baseName]
        return fieldDefinitions[baseName]
    
    return null

  # Check if value is a list
  @isListValue: (value, fieldDef) ->
    return false unless value
    
    # Check field definition type
    if fieldDef?.type == 'List'
      return true
    
    # Check if it's an array with objects
    if @isArray(value) and value.length > 0
      firstItem = value[1] or value[0]
      return @isObject(firstItem) and not @isSimpleType(firstItem)
    
    return false

  # Check if value is an array
  @isArray: (value) ->
    return type(value) == 'table' and @isNumericArray(value)

  # Check if table is a numeric array (has consecutive numeric keys starting from 1)
  @isNumericArray: (table) ->
    return false unless table
    
    count = 0
    for key, _ of pairs(table)
      if type(key) != 'number'
        return false
      count += 1
    
    return count > 0

  # Check if value is an object (table with string keys)
  @isObject: (value) ->
    return type(value) == 'table' and not @isNumericArray(value)

  # Check if value is a date
  @isDate: (value) ->
    return false unless value
    return type(value) == 'table' and value.year and value.month and value.day

  # Check if value is a simple type (string, number, boolean)
  @isSimpleType: (value) ->
    typeValue = type(value)
    return typeValue == 'string' or typeValue == 'number' or typeValue == 'boolean'

  # Convert list to Lua-style array for computed fields
  @convertToList: (luaTable) ->
    result = {}
    for i, v in ipairs(luaTable)
      result[i] = v
    return result

  # Generate column names from query
  @generateColumnNames: (query) ->
    # Simple implementation - extract field names from query
    columnNames = []
    
    # Match field selections
    fieldMatches = query.match(/(\w+)\s*(?:\{[^}]*\})?/g)
    if fieldMatches
      for match in fieldMatches
        fieldName = match.match(/(\w+)/)[1]
        table.insert columnNames, fieldName
    
    return columnNames

  # Detect list fields in data
  @detectListFields: (data) ->
    listFields = {}
    
    records = data.records or data
    return listFields unless records and records.length > 0
    
    # Check first record for list fields
    firstRecord = records[1]
    for field, value of pairs(firstRecord)
      if @isArray(value) and value.length > 0
        firstItem = value[1] or value[0]
        if @isObject(firstItem)
          listFields[field] = true
    
    return listFields

# Export for use in other modules
window.GraphQLFlattener = GraphQLFlattener
