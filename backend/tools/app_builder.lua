local json = require('json')
local yaml = require('yaml')
local fio = require('fio')
local key_part
key_part = function(s)
  s = tostring(s)
  s = s:gsub('%%', '%%25')
  s = s:gsub('%.', '%%2E')
  s = s:gsub('%|', '%%7C')
  s = s:gsub(':', '%%3A')
  return s
end
local _formula
_formula = function(f)
  if not (f and f ~= '') then
    return ''
  end
  f = f:gsub('\n+$', '')
  if not (f:find('\n', 1, true)) then
    return f
  end
  local lines = { }
  for l in (f .. "\n"):gmatch('(.-)\n') do
    table.insert(lines, '  ' .. l)
  end
  return "\n" .. table.concat(lines, '\n')
end
local _field_item
_field_item = function(space, f)
  local language = f.language or (f.formula and 'moonscript' or 'lua')
  return {
    type = 'field',
    key = "field:" .. tostring(key_part(space)) .. "." .. tostring(key_part(f.name)),
    content = {
      fieldType = f.type,
      notNull = f.notNull == true,
      description = f.description or '',
      formula = _formula(f.formula),
      language = language
    }
  }
end
local _relation_item
_relation_item = function(space, f)
  local to_space, to_field = f.ref:match('^([^.]+)%.(.+)$')
  return {
    type = 'relation',
    key = "relation:" .. tostring(key_part(space)) .. "." .. tostring(key_part(f.name)),
    content = {
      fromSpace = space,
      fromField = f.name,
      toSpace = to_space,
      toField = to_field,
      cardinality = 'one'
    }
  }
end
local _all_fields
_all_fields = function(sp)
  local fields = {
    {
      name = 'id',
      type = 'Sequence',
      notNull = true,
      description = 'Identifiant'
    }
  }
  local _list_0 = (sp.fields or { })
  for _index_0 = 1, #_list_0 do
    local f = _list_0[_index_0]
    table.insert(fields, f)
  end
  return fields
end
local expand
expand = function(structure)
  local a = structure.app
  local spaces, fields, rels, seed_keys = { }, { }, { }, { }
  local _list_0 = structure.spaces
  for _index_0 = 1, #_list_0 do
    local sp = _list_0[_index_0]
    table.insert(spaces, {
      type = 'space',
      key = "space:" .. tostring(key_part(sp.name)),
      content = {
        description = sp.description or ''
      }
    })
    seed_keys[sp.name] = 'id'
    local _list_1 = _all_fields(sp)
    for _index_1 = 1, #_list_1 do
      local f = _list_1[_index_1]
      table.insert(fields, _field_item(sp.name, f))
      if f.ref then
        table.insert(rels, _relation_item(sp.name, f))
      end
    end
  end
  local items = { }
  local _list_1 = {
    spaces,
    fields,
    rels
  }
  for _index_0 = 1, #_list_1 do
    local group = _list_1[_index_0]
    for _index_1 = 1, #group do
      local it = group[_index_1]
      table.insert(items, it)
    end
  end
  return {
    app = {
      id = a.id,
      name = a.name,
      version = a.version,
      description = a.description or ''
    },
    items = items,
    seed_keys = seed_keys
  }
end
local add_seed
add_seed = function(pkg, space_name, rows)
  for _index_0 = 1, #rows do
    local row = rows[_index_0]
    local k = tostring(row.id)
    table.insert(pkg.items, {
      type = 'seed',
      key = "seed:" .. tostring(key_part(space_name)) .. "|" .. tostring(key_part(k)),
      content = {
        space = space_name,
        key = k,
        data = row
      }
    })
  end
end
local _scalar
_scalar = function(v)
  local _exp_0 = type(v)
  if 'string' == _exp_0 then
    return json.encode(v)
  elseif 'number' == _exp_0 or 'boolean' == _exp_0 then
    return tostring(v)
  else
    return 'null'
  end
end
local _is_array
_is_array = function(t)
  return #t > 0 or next(t) == nil
end
local _key
_key = function(k)
  k = tostring(k)
  return k:match('^[%w_]+$') and k or json.encode(k)
end
local _lines = nil
_lines = function(v, pad)
  local out = { }
  if _is_array(v) then
    for _index_0 = 1, #v do
      local item = v[_index_0]
      if type(item) == 'table' and next(item) ~= nil then
        local sub = _lines(item, pad .. '  ')
        sub[1] = pad .. '- ' .. sub[1]:sub(#pad + 3)
        for _index_1 = 1, #sub do
          local l = sub[_index_1]
          table.insert(out, l)
        end
      else
        table.insert(out, pad .. '- ' .. (type(item) == 'table' and (_is_array(item) and '[]' or '{}') or _scalar(item)))
      end
    end
  else
    local keys
    do
      local _accum_0 = { }
      local _len_0 = 1
      for k, _ in pairs(v) do
        _accum_0[_len_0] = k
        _len_0 = _len_0 + 1
      end
      keys = _accum_0
    end
    table.sort(keys, function(a, b)
      return tostring(a) < tostring(b)
    end)
    for _index_0 = 1, #keys do
      local k = keys[_index_0]
      local val = v[k]
      if type(val) == 'table' and next(val) ~= nil then
        table.insert(out, pad .. _key(k) .. ':')
        local _list_0 = _lines(val, pad .. '  ')
        for _index_1 = 1, #_list_0 do
          local l = _list_0[_index_1]
          table.insert(out, l)
        end
      elseif type(val) == 'table' then
        table.insert(out, pad .. _key(k) .. ': ' .. (_is_array(val) and '[]' or '{}'))
      else
        table.insert(out, pad .. _key(k) .. ': ' .. _scalar(val))
      end
    end
  end
  return out
end
local emit
emit = function(pkg)
  return "---\n" .. table.concat(_lines(pkg, ''), '\n') .. '\n'
end
local _read_yaml
_read_yaml = function(path)
  local fh = fio.open(path, {
    'O_RDONLY'
  })
  if not (fh) then
    error("cannot open " .. tostring(path))
  end
  local text = fh:read()
  fh:close()
  return yaml.decode(text)
end
local load_structure
load_structure = function(dir)
  local structure = {
    app = (_read_yaml(fio.pathjoin(dir, 'app.yaml'))).app,
    spaces = { }
  }
  local names = fio.glob(fio.pathjoin(dir, 'structure', '*.yaml'))
  table.sort(names)
  for _index_0 = 1, #names do
    local path = names[_index_0]
    local _list_0 = (_read_yaml(path)).spaces
    for _index_1 = 1, #_list_0 do
      local sp = _list_0[_index_1]
      table.insert(structure.spaces, sp)
    end
  end
  return structure
end
return {
  key_part = key_part,
  expand = expand,
  add_seed = add_seed,
  emit = emit,
  load_structure = load_structure
}
