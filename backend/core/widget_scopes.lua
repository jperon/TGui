local yaml = require('yaml')
local BUILTIN_WIDGET_TYPES = {
  table = true,
  aggregate = true
}
local NAME_PATTERN = '^[%a_][%w_%-]*$'
local scope_of
scope_of = function(raw)
  if type(raw) == 'string' and raw ~= '' then
    return raw
  end
  return nil
end
local scope_column
scope_column = function(app_id)
  if type(app_id) == 'string' and app_id ~= '' then
    return app_id
  end
  return ''
end
local row_app_id
row_app_id = function(row)
  if not (row) then
    return nil
  end
  return scope_of(row[11])
end
local row_name
row_name = function(row)
  return row and row[2]
end
local find_row
find_row = function(name, app_id)
  if not (type(name) == 'string' and name ~= '') then
    return nil
  end
  return box.space._tdb_widget_plugins.index.by_scope_name:get({
    scope_column(app_id),
    name
  })
end
local rows_in_scope
rows_in_scope = function(app_id)
  local wanted = scope_column(app_id)
  local result = { }
  local _list_0 = box.space._tdb_widget_plugins:select({ })
  for _index_0 = 1, #_list_0 do
    local row = _list_0[_index_0]
    if scope_column(row_app_id(row)) == wanted then
      table.insert(result, row)
    end
  end
  return result
end
local visible_for_scope
visible_for_scope = function(app_id)
  local by_name = { }
  local _list_0 = rows_in_scope(nil)
  for _index_0 = 1, #_list_0 do
    local row = _list_0[_index_0]
    by_name[row[2]] = row
  end
  if app_id then
    local _list_1 = rows_in_scope(app_id)
    for _index_0 = 1, #_list_1 do
      local row = _list_1[_index_0]
      by_name[row[2]] = row
    end
  end
  local result = { }
  for _, row in pairs(by_name) do
    table.insert(result, row)
  end
  table.sort(result, function(a, b)
    return a[2] < b[2]
  end)
  return result
end
local page_app_id
page_app_id = function(page_id)
  if not (type(page_id) == 'string' and page_id ~= '') then
    return nil
  end
  local _list_0 = box.space._tdb_app_items:select({ })
  for _index_0 = 1, #_list_0 do
    local _continue_0 = false
    repeat
      do
        local row = _list_0[_index_0]
        if not (row[3] == 'page' and row[4] == page_id) then
          _continue_0 = true
          break
        end
        if row[6] == 'obsolète' then
          _continue_0 = true
          break
        end
        return scope_of(row[1])
      end
      _continue_0 = true
    until true
    if not _continue_0 then
      break
    end
  end
  return nil
end
local resolve_row
resolve_row = function(name, app_id)
  if app_id then
    local row = find_row(name, app_id)
    if row then
      return row
    end
  end
  return find_row(name, nil)
end
local resolve_for_page
resolve_for_page = function(name, page_id)
  return resolve_row(name, page_app_id(page_id))
end
local is_widget_node
is_widget_node = function(node)
  return type(node) == 'table' and type(node.widget) == 'table'
end
local referenced_plugin_names
referenced_plugin_names = function(text)
  local names = { }
  if not (type(text) == 'string' and text:match('%S')) then
    return { }
  end
  local collect
  collect = function(node, depth)
    if not (type(node) == 'table') then
      return 
    end
    if depth > 32 then
      return 
    end
    if is_widget_node(node) then
      local widget_type = node.widget.type
      if type(widget_type) == 'string' and widget_type ~= '' and not BUILTIN_WIDGET_TYPES[widget_type] then
        names[widget_type] = true
      end
    end
    for _, child in pairs(node) do
      if type(child) == 'table' then
        collect(child, depth + 1)
      end
    end
  end
  local ok, parsed = pcall(yaml.decode, text)
  if ok then
    collect(parsed, 0)
  end
  local result
  do
    local _accum_0 = { }
    local _len_0 = 1
    for name, _ in pairs(names) do
      _accum_0[_len_0] = name
      _len_0 = _len_0 + 1
    end
    result = _accum_0
  end
  table.sort(result)
  return result
end
local referenced_rows
referenced_rows = function(page_row)
  if not (page_row) then
    return { }
  end
  local app_id = page_app_id(page_row[1])
  local result = { }
  local _list_0 = referenced_plugin_names(page_row[4])
  for _index_0 = 1, #_list_0 do
    local name = _list_0[_index_0]
    local row = resolve_row(name, app_id)
    if row then
      table.insert(result, row)
    end
  end
  return result
end
local pages_using
pages_using = function(definition)
  if not (definition) then
    return { }
  end
  local name = definition[2]
  local result = { }
  local _list_0 = box.space._tdb_custom_views:select({ })
  for _index_0 = 1, #_list_0 do
    local _continue_0 = false
    repeat
      local page = _list_0[_index_0]
      local names = referenced_plugin_names(page[4])
      if not (names[name]) then
        _continue_0 = true
        break
      end
      local resolved = resolve_row(name, page_app_id(page[1]))
      if not (resolved and resolved[1] == definition[1]) then
        _continue_0 = true
        break
      end
      table.insert(result, page[2])
      _continue_0 = true
    until true
    if not _continue_0 then
      break
    end
  end
  table.sort(result)
  return result
end
local pages_using_name
pages_using_name = function(name, app_id)
  local row = find_row(name, app_id)
  if not (row) then
    return { }
  end
  return pages_using(row)
end
local unique_name
unique_name = function(base, app_id)
  local candidate = base
  local suffix = 2
  while find_row(candidate, app_id) do
    candidate = tostring(base) .. "_" .. tostring(suffix)
    suffix = suffix + 1
  end
  return candidate
end
local valid_name
valid_name = function(name)
  return type(name) == 'string' and name ~= '' and #name <= 120 and name:match(NAME_PATTERN) ~= nil
end
return {
  BUILTIN_WIDGET_TYPES = BUILTIN_WIDGET_TYPES,
  scope_of = scope_of,
  scope_column = scope_column,
  row_app_id = row_app_id,
  row_name = row_name,
  find_row = find_row,
  rows_in_scope = rows_in_scope,
  visible_for_scope = visible_for_scope,
  page_app_id = page_app_id,
  resolve_row = resolve_row,
  resolve_for_page = resolve_for_page,
  referenced_plugin_names = referenced_plugin_names,
  referenced_rows = referenced_rows,
  pages_using = pages_using,
  pages_using_name = pages_using_name,
  unique_name = unique_name,
  valid_name = valid_name
}
