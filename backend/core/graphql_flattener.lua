local json = require('json')
local GraphQLFlattener = { }
GraphQLFlattener.isArray = function(value)
  return type(value) == 'table' and #value > 0
end
GraphQLFlattener.isObject = function(value)
  return type(value) == 'table' and not GraphQLFlattener.isArray(value)
end
GraphQLFlattener.isSimpleType = function(value)
  local valueType = type(value)
  return valueType == 'string' or valueType == 'number' or valueType == 'boolean'
end
GraphQLFlattener.validateFlattened = function(flattened, schema)
  local errors = { }
  for _index_0 = 1, #flattened do
    local record = flattened[_index_0]
    for field, value in pairs(record) do
      if schema[field] then
        local expectedType = schema[field]
        local actualType = type(value)
        if expectedType == 'string' and actualType ~= 'string' then
          table.insert(errors, "Field " .. tostring(field) .. ": expected string, got " .. tostring(actualType))
        elseif expectedType == 'number' and actualType ~= 'number' then
          table.insert(errors, "Field " .. tostring(field) .. ": expected number, got " .. tostring(actualType))
        elseif expectedType == 'boolean' and actualType ~= 'boolean' then
          table.insert(errors, "Field " .. tostring(field) .. ": expected boolean, got " .. tostring(actualType))
        end
      end
    end
  end
  return errors
end
local flattenRecord
flattenRecord = function(record, query, fieldDefinitions, prefix)
  local flat = { }
  for field, value in pairs(record) do
    local _continue_0 = false
    repeat
      if field == "_id" then
        _continue_0 = true
        break
      elseif GraphQLFlattener.isArray(value) then
        flat[tostring(prefix) .. tostring(field)] = flattenList(value, query, fieldDefinitions, tostring(prefix) .. tostring(field) .. "_")
      elseif GraphQLFlattener.isObject(value) then
        local nested = flattenRecord(value, query, fieldDefinitions, tostring(prefix) .. tostring(field) .. "_")
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
      _continue_0 = true
    until true
    if not _continue_0 then
      break
    end
  end
  return flat
end
local flattenList
flattenList = function(list, query, fieldDefinitions, prefix)
  local flattened_list = { }
  for i, item in ipairs(list) do
    if GraphQLFlattener.isObject(item) then
      local flat_item = flattenRecord(item, query, fieldDefinitions, tostring(prefix) .. tostring(i) .. "_")
      table.insert(flattened_list, flat_item)
    else
      flattened_list[tostring(prefix) .. tostring(i)] = item
    end
  end
  return flattened_list
end
GraphQLFlattener.flatten = function(data, query, fieldDefinitions)
  local flattened = { }
  if not (data) then
    return flattened
  end
  local records = data.records or data
  if not (records) then
    return flattened
  end
  if type(records) == 'table' then
    if GraphQLFlattener.isArray(records) then
      for i, record in ipairs(records) do
        if type(record) == 'table' then
          local flat = { }
          for field, value in pairs(record) do
            if field ~= "_id" then
              flat[field] = value
            end
          end
          flattened[i] = flat
        end
      end
    else
      local flat = { }
      for field, value in pairs(records) do
        if field ~= "_id" then
          flat[field] = value
        end
      end
      flattened[1] = flat
    end
  end
  return flattened
end
return GraphQLFlattener
