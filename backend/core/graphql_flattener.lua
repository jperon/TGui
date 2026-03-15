local json = require('json')
local GraphQLFlattener = { }
GraphQLFlattener.flatten = function(data, query, fieldDefinitions)
  local flattened = { }
  local records = data.records or data
  if not (records) then
    return flattened
  end
  for record in records do
    local flat = GraphQLFlattener.flattenRecord(record, query, fieldDefinitions, "")
    table.insert(flattened, flat)
  end
  return flattened
end
GraphQLFlattener.flattenRecord = function(record, query, fieldDefinitions, prefix)
  local flat = { }
  for field, value in pairs(record) do
    local fieldDef = GraphQLFlattener.findFieldDefinition(field, fieldDefinitions, prefix)
    if GraphQLFlattener.isListValue(value, fieldDef) then
      flat[tostring(prefix) .. tostring(field)] = GraphQLFlattener.flattenList(value, query, fieldDefinitions, tostring(prefix) .. tostring(field) .. "_")
    elseif GraphQLFlattener.isObject(value) then
      local nested = GraphQLFlattener.flattenRecord(value, query, fieldDefinitions, tostring(prefix) .. tostring(field) .. "_")
      for k, v in pairs(nested) do
        flat[k] = v
      end
    else
      local columnName
      if prefix ~= "" then
        columnName = tostring(prefix) .. tostring(field)
      else
        columnName = field
      end
      flat[columnName] = value
    end
  end
  return flat
end
GraphQLFlattener.flattenList = function(list, query, fieldDefinitions, prefix)
  local flattened_list = { }
  for i, item in ipairs(list) do
    if GraphQLFlattener.isObject(item) then
      local flat_item = GraphQLFlattener.flattenRecord(item, query, fieldDefinitions, tostring(prefix) .. tostring(i) .. "_")
      table.insert(flattened_list, flat_item)
    else
      flattened_list[tostring(prefix) .. tostring(i)] = item
    end
  end
  return flattened_list
end
GraphQLFlattener.findFieldDefinition = function(fieldName, fieldDefinitions, prefix)
  if fieldDefinitions[fieldName] then
    return fieldDefinitions[fieldName]
  end
  local prefixedName = prefix .. fieldName
  if fieldDefinitions[prefixedName] then
    return fieldDefinitions[prefixedName]
  end
  if prefix ~= "" then
    local baseName = fieldName:gsub("^" .. prefix, "")
    if fieldDefinitions[baseName] then
      return fieldDefinitions[baseName]
    end
  end
  return nil
end
GraphQLFlattener.isListValue = function(value, fieldDef)
  if not (value) then
    return false
  end
  if fieldDef and fieldDef.type == 'List' then
    return true
  end
  if GraphQLFlattener.isArray(value) then
    if #value > 0 then
      local firstItem = value[1]
      return GraphQLFlattener.isObject(firstItem)
    end
  end
  return false
end
GraphQLFlattener.isArray = function(value)
  return type(value) == 'table' and GraphQLFlattener.isNumericArray(value)
end
GraphQLFlattener.isNumericArray = function(table)
  if not (table) then
    return false
  end
  local count = 0
  for key, _ in pairs(table) do
    if type(key) ~= 'number' then
      return false
    end
    count = count + 1
  end
  return count > 0
end
GraphQLFlattener.isObject = function(value)
  return type(value) == 'table' and not GraphQLFlattener.isNumericArray(value)
end
GraphQLFlattener.isDate = function(value)
  if not (value) then
    return false
  end
  return type(value) == 'table' and value.year and value.month and value.day
end
GraphQLFlattener.isSimpleType = function(value)
  local typeValue = type(value)
  return typeValue == 'string' or typeValue == 'number' or typeValue == 'boolean'
end
GraphQLFlattener.convertToList = function(luaTable)
  local result = { }
  for i, v in ipairs(luaTable) do
    result[i] = v
  end
  return result
end
GraphQLFlattener.generateColumnNames = function(query)
  local columnNames = { }
  local fieldMatches = { }
  for match in query:gmatch("(%w+)%s*(%b{})") do
    local fieldName = match:match("(%w+)")
    if fieldName then
      table.insert(columnNames, fieldName)
    end
  end
  return columnNames
end
GraphQLFlattener.detectListFields = function(data)
  local listFields = { }
  local records = data.records or data
  if not (records and #records > 0) then
    return listFields
  end
  local firstRecord = records[1]
  for field, value in pairs(firstRecord) do
    if GraphQLFlattener.isArray(value and #value > 0) then
      local firstItem = value[1]
      if GraphQLFlattener.isObject(firstItem) then
        listFields[field] = true
      end
    end
  end
  return listFields
end
GraphQLFlattener.flattenOptimized = function(data, query, fieldDefinitions, options)
  options = options or { }
  local batchSize = options.batchSize or 1000
  local maxDepth = options.maxDepth or 5
  local flattened = { }
  local records = data.records or data
  if not (records) then
    return flattened
  end
  for i = 1, #records, batchSize do
    local batchEnd = math.min(i + batchSize - 1, #records)
    for j = i, batchEnd do
      local record = records[j]
      local flat = GraphQLFlattener.flattenRecord(record, query, fieldDefinitions, "", maxDepth)
      table.insert(flattened, flat)
    end
  end
  return flattened
end
GraphQLFlattener.flattenRecord = function(record, query, fieldDefinitions, prefix, maxDepth)
  maxDepth = maxDepth or 5
  if maxDepth <= 0 then
    return {
      [tostring(prefix) .. "_depth_limit"] = "MAX_DEPTH_REACHED"
    }
  end
  local flat = { }
  for field, value in pairs(record) do
    local fieldDef = GraphQLFlattener.findFieldDefinition(field, fieldDefinitions, prefix)
    if GraphQLFlattener.isListValue(value, fieldDef) then
      flat[tostring(prefix) .. tostring(field)] = GraphQLFlattener.flattenList(value, query, fieldDefinitions, tostring(prefix) .. tostring(field) .. "_", maxDepth - 1)
    elseif GraphQLFlattener.isObject(value) then
      local nested = GraphQLFlattener.flattenRecord(value, query, fieldDefinitions, tostring(prefix) .. tostring(field) .. "_", maxDepth - 1)
      for k, v in pairs(nested) do
        flat[k] = v
      end
    else
      local columnName
      if prefix ~= "" then
        columnName = tostring(prefix) .. tostring(field)
      else
        columnName = field
      end
      flat[columnName] = value
    end
  end
  return flat
end
GraphQLFlattener.flattenList = function(list, query, fieldDefinitions, prefix, maxDepth)
  maxDepth = maxDepth or 5
  if maxDepth <= 0 then
    return {
      [tostring(prefix) .. "_depth_limit"] = "MAX_DEPTH_REACHED"
    }
  end
  local flattened_list = { }
  for i, item in ipairs(list) do
    if GraphQLFlattener.isObject(item) then
      local flat_item = GraphQLFlattener.flattenRecord(item, query, fieldDefinitions, tostring(prefix) .. tostring(i) .. "_", maxDepth - 1)
      table.insert(flattened_list, flat_item)
    else
      flattened_list[tostring(prefix) .. tostring(i)] = item
    end
  end
  return flattened_list
end
GraphQLFlattener.validateFlattened = function(flattened, schema)
  local errors = { }
  for i, record in ipairs(flattened) do
    for field, expectedType in pairs(schema) do
      local value = record[field]
      if value and not GraphQLFlattener.validateType(value, expectedType) then
        table.insert(errors, "Record " .. tostring(i) .. ": Field '" .. tostring(field) .. "' has invalid type")
      end
    end
  end
  return errors
end
GraphQLFlattener.validateType = function(value, expectedType)
  local _exp_0 = expectedType
  if 'string' == _exp_0 then
    return type(value) == 'string'
  elseif 'number' == _exp_0 then
    return type(value) == 'number'
  elseif 'boolean' == _exp_0 then
    return type(value) == 'boolean'
  elseif 'array' == _exp_0 then
    return GraphQLFlattener.isArray(value)
  elseif 'object' == _exp_0 then
    return GraphQLFlattener.isObject(value)
  else
    return true
  end
end
return GraphQLFlattener
