spaces_mod = require 'core.spaces'

to_number = (v) ->
  return v if type(v) == 'number'
  return tonumber(v) if type(v) == 'string'
  nil

is_finite = (n) -> n == n and n > -math.huge and n < math.huge

describe_value = (v) ->
  t = type v
  if t == 'table' or t == 'cdata' or t == 'function' or t == 'userdata'
    t
  else
    "#{t} (#{tostring v})"

check_type = (field_type, value) ->
  t = type value
  if field_type == 'String'
    return true, value, nil if t == 'string'
    return false, nil, "expected #{field_type}, got #{describe_value value}"
  if field_type == 'Int'
    n = to_number value
    return true, n, nil if n != nil and is_finite(n) and n == math.floor n
    return false, nil, "expected #{field_type}, got #{describe_value value}"
  if field_type == 'Float'
    n = to_number value
    return true, n, nil if n != nil and is_finite(n)
    return false, nil, "expected #{field_type}, got #{describe_value value}"
  if field_type == 'Boolean'
    return true, value, nil if t == 'boolean'
    return true, true, nil if value == 'true'
    return true, false, nil if value == 'false'
    return false, nil, "expected #{field_type}, got #{describe_value value}"
  if field_type == 'ID' or field_type == 'UUID' or field_type == 'Datetime' or field_type == 'Relation'
    return true, value, nil if t == 'string' or t == 'number'
    return false, nil, "expected #{field_type}, got #{describe_value value}"
  if field_type == 'Map' or field_type == 'Array'
    return true, value, nil if t == 'table'
    return false, nil, "expected #{field_type}, got #{describe_value value}"
  return true, value, nil

not_null_reason = (mode) ->
  if mode == 'insert'
    'required (not_null)'
  else
    'null is not allowed (not_null)'

classify_field = (f, mode, present, value) ->
  unless present
    return 'error', nil, not_null_reason(mode) if mode == 'insert' and f.notNull
    return 'skip', nil, nil
  if value == nil or (f.fieldType != 'String' and value == '')
    if f.notNull
      return 'error', nil, not_null_reason(mode)
    return 'clear', nil, nil
  ok_t, new_v, reason = check_type f.fieldType, value
  if ok_t
    return 'set', new_v, nil
  return 'error', nil, reason

validate_record = (space_id, data, mode) ->
  unless mode == 'insert' or mode == 'update'
    error "Validation failed: mode: expected 'insert' or 'update'"
  unless type(data) == 'table'
    error "Validation failed: data: expected an object, got #{type data}"

  fields = spaces_mod.list_fields space_id
  declared = {}
  for f in *fields
    declared[f.name] = f

  provided = {}
  for k in pairs data
    provided[k] = true

  errors = {}
  for k in pairs data
    unless declared[k]
      table.insert errors, "#{k}: unknown field"

  cleaned = {}
  cleared = {}

  for f in *fields
    continue if f.formula and f.formula != ''
    continue if f.fieldType == 'Sequence'
    name = f.name
    action, new_v, reason = classify_field f, mode, provided[name] != nil, data[name]
    if action == 'error'
      table.insert errors, "#{name}: #{reason}"
    elseif action == 'set'
      cleaned[name] = new_v
    elseif action == 'clear'
      table.insert cleared, name if mode == 'update'

  if #errors > 0
    error "Validation failed: #{table.concat errors, '; '}"
  return cleaned, cleared

{ :validate_record }
