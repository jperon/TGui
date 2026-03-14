local registry = require('graphql.sdl_registry')
local format_field
format_field = function(f)
  local args
  if f.args and f.args ~= '' then
    args = "(" .. tostring(f.args) .. ")"
  else
    args = ''
  end
  return "  " .. tostring(f.name) .. tostring(args) .. ": " .. tostring(f.returns)
end
local emit_block
emit_block = function(type_name, fields)
  local lines = { }
  for _index_0 = 1, #fields do
    local f = fields[_index_0]
    table.insert(lines, format_field(f))
  end
  return "type " .. tostring(type_name) .. " {\n" .. tostring(table.concat(lines, '\n')) .. "\n}"
end
local generate
generate = function()
  local parts = {
    '# GENERATED FILE - passive SDL projection from MoonScript registry',
    '# Source: backend/graphql/sdl_registry.moon',
    ''
  }
  local _list_0 = registry.InputTypes
  for _index_0 = 1, #_list_0 do
    local input_type = _list_0[_index_0]
    table.insert(parts, input_type.definition)
    table.insert(parts, '')
  end
  local _list_1 = registry.ObjectTypes
  for _index_0 = 1, #_list_1 do
    local object_type = _list_1[_index_0]
    table.insert(parts, object_type.definition)
    table.insert(parts, '')
  end
  table.insert(parts, emit_block('Query', registry.Query))
  table.insert(parts, '')
  table.insert(parts, emit_block('Mutation', registry.Mutation))
  table.insert(parts, '')
  return table.concat(parts, '\n')
end
local write_file
write_file = function(out_path)
  local path = out_path or 'schema/tdb.generated.graphql'
  local content = generate()
  local f = io.open(path, 'w')
  if not (f) then
    error("Cannot write generated SDL file: " .. tostring(path))
  end
  f:write(content)
  f:close()
  return path
end
return {
  generate = generate,
  write_file = write_file
}
