local spaces_mod = require('core.spaces')
local to_number
to_number = function(v)
  if type(v) == 'number' then
    return v
  end
  if type(v) == 'string' then
    return tonumber(v)
  end
  return nil
end
local is_finite
is_finite = function(n)
  return n == n and n > -math.huge and n < math.huge
end
local describe_value
describe_value = function(v)
  local t = type(v)
  if t == 'table' or t == 'cdata' or t == 'function' or t == 'userdata' then
    return t
  else
    return tostring(t) .. " (" .. tostring(tostring(v)) .. ")"
  end
end
local check_type
check_type = function(field_type, value)
  local t = type(value)
  if field_type == 'String' then
    if t == 'string' then
      return true, value, nil
    end
    return false, nil, "expected " .. tostring(field_type) .. ", got " .. tostring(describe_value(value))
  end
  if field_type == 'Int' then
    local n = to_number(value)
    if n ~= nil and is_finite(n) and n == math.floor(n) then
      return true, n, nil
    end
    return false, nil, "expected " .. tostring(field_type) .. ", got " .. tostring(describe_value(value))
  end
  if field_type == 'Float' then
    local n = to_number(value)
    if n ~= nil and is_finite(n) then
      return true, n, nil
    end
    return false, nil, "expected " .. tostring(field_type) .. ", got " .. tostring(describe_value(value))
  end
  if field_type == 'Boolean' then
    if t == 'boolean' then
      return true, value, nil
    end
    if value == 'true' then
      return true, true, nil
    end
    if value == 'false' then
      return true, false, nil
    end
    return false, nil, "expected " .. tostring(field_type) .. ", got " .. tostring(describe_value(value))
  end
  if field_type == 'ID' or field_type == 'UUID' or field_type == 'Datetime' or field_type == 'Relation' then
    if t == 'string' or t == 'number' then
      return true, value, nil
    end
    return false, nil, "expected " .. tostring(field_type) .. ", got " .. tostring(describe_value(value))
  end
  if field_type == 'Map' or field_type == 'Array' then
    if t == 'table' then
      return true, value, nil
    end
    return false, nil, "expected " .. tostring(field_type) .. ", got " .. tostring(describe_value(value))
  end
  return true, value, nil
end
local not_null_reason
not_null_reason = function(mode)
  if mode == 'insert' then
    return 'required (not_null)'
  else
    return 'null is not allowed (not_null)'
  end
end
local classify_field
classify_field = function(f, mode, present, value)
  if not (present) then
    if mode == 'insert' and f.notNull then
      return 'error', nil, not_null_reason(mode)
    end
    return 'skip', nil, nil
  end
  if value == nil or (f.fieldType ~= 'String' and value == '') then
    if f.notNull then
      return 'error', nil, not_null_reason(mode)
    end
    return 'clear', nil, nil
  end
  local ok_t, new_v, reason = check_type(f.fieldType, value)
  if ok_t then
    return 'set', new_v, nil
  end
  return 'error', nil, reason
end
local validate_record
validate_record = function(space_id, data, mode)
  if not (mode == 'insert' or mode == 'update') then
    error("Validation failed: mode: expected 'insert' or 'update'")
  end
  if not (type(data) == 'table') then
    error("Validation failed: data: expected an object, got " .. tostring(type(data)))
  end
  local fields = spaces_mod.list_fields(space_id)
  local declared = { }
  for _index_0 = 1, #fields do
    local f = fields[_index_0]
    declared[f.name] = f
  end
  local provided = { }
  for k in pairs(data) do
    provided[k] = true
  end
  local errors = { }
  for k in pairs(data) do
    if not (declared[k]) then
      table.insert(errors, tostring(k) .. ": unknown field")
    end
  end
  local cleaned = { }
  local cleared = { }
  for _index_0 = 1, #fields do
    local _continue_0 = false
    repeat
      local f = fields[_index_0]
      if f.formula and f.formula ~= '' then
        _continue_0 = true
        break
      end
      if f.fieldType == 'Sequence' then
        _continue_0 = true
        break
      end
      local name = f.name
      local action, new_v, reason = classify_field(f, mode, provided[name] ~= nil, data[name])
      if action == 'error' then
        table.insert(errors, tostring(name) .. ": " .. tostring(reason))
      elseif action == 'set' then
        cleaned[name] = new_v
      elseif action == 'clear' then
        if mode == 'update' then
          table.insert(cleared, name)
        end
      end
      _continue_0 = true
    until true
    if not _continue_0 then
      break
    end
  end
  if #errors > 0 then
    error("Validation failed: " .. tostring(table.concat(errors, '; ')))
  end
  return cleaned, cleared
end
return {
  validate_record = validate_record
}
