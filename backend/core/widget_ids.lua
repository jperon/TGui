local yaml = require('yaml')
local ID_PREFIX = 'w_'
local ID_HEX_DIGITS = 8
local random_id
random_id = function()
  local digits = { }
  for _ = 1, ID_HEX_DIGITS do
    table.insert(digits, string.format('%x', math.random(0, 15)))
  end
  return ID_PREFIX .. table.concat(digits)
end
local generate_unique_id
generate_unique_id = function(used)
  for _ = 1, 100 do
    local id = random_id()
    if not (used[id]) then
      return id
    end
  end
  local n = 0
  while true do
    local id = ID_PREFIX .. string.format('%08x', n)
    if not (used[id]) then
      return id
    end
    n = n + 1
  end
end
local collect_widgets
collect_widgets = function(node, out)
  if not (out) then
    out = { }
  end
  if not (type(node) == 'table') then
    return out
  end
  if type(node.widget) == 'table' then
    table.insert(out, node.widget)
    return out
  end
  local container = node
  if type(node.layout) == 'table' then
    container = node.layout
  elseif type(node.zone) == 'table' then
    container = node.zone
  end
  if type(container.widget) == 'table' then
    table.insert(out, container.widget)
  elseif type(container.children) == 'table' then
    for _, child in ipairs(container.children) do
      collect_widgets(child, out)
    end
  end
  return out
end
local decode_config
decode_config = function(yaml_str)
  if not (type(yaml_str) == 'string' and yaml_str ~= '') then
    return nil
  end
  local ok, config = pcall(yaml.decode, yaml_str)
  if not (ok and type(config) == 'table') then
    return nil
  end
  if not (type(config.layout) == 'table') then
    return nil
  end
  return config
end
local trim
trim = function(s)
  return tostring(s or ''):match('^%s*(.-)%s*$')
end
local is_missing_id
is_missing_id = function(widget)
  if type(widget) ~= 'table' then
    return true
  end
  local id = widget.id
  if id == nil then
    return true
  end
  if not (type(id) == 'string') then
    return false
  end
  local trimmed = trim(id)
  return trimmed == '' or trimmed == 'nil'
end
local split_lines
split_lines = function(text)
  local lines = { }
  for line in (text .. "\n"):gmatch('([^\n]*)\n') do
    table.insert(lines, line)
  end
  local trailing = false
  if #lines > 0 and lines[#lines] == '' and text:sub(-1) == "\n" then
    table.remove(lines)
    trailing = true
  end
  return {
    lines = lines,
    trailing = trailing
  }
end
local join_lines
join_lines = function(split)
  local text = table.concat(split.lines, "\n")
  if split.trailing then
    text = text .. "\n"
  end
  return text
end
local match_widget_key
match_widget_key = function(line)
  local indent = line:match('^%s*')
  local body = line:sub(#indent + 1)
  local key_col = #indent
  local dash = body:match('^%-%s+')
  if dash then
    key_col = key_col + #dash
    body = body:sub(#dash + 1)
  end
  local rest = body:match('^widget%s*:%s*(.*)$')
  if not (rest) then
    return nil
  end
  return {
    indent = indent,
    key_col = key_col,
    rest = rest
  }
end
local find_child_indent
find_child_indent = function(lines, header_idx, key_col)
  for j = header_idx + 1, #lines do
    local raw = lines[j]
    if not ((raw:match('^%s*$')) or (raw:match('^%s*#'))) then
      local ind = #(raw:match('^%s*'))
      if ind > key_col then
        return ind
      end
      return nil
    end
  end
  return nil
end
local find_id_line
find_id_line = function(lines, header_idx, key_col)
  for j = header_idx + 1, #lines do
    local _continue_0 = false
    repeat
      local raw = lines[j]
      if (raw:match('^%s*$')) or (raw:match('^%s*#')) then
        _continue_0 = true
        break
      end
      local ind = #(raw:match('^%s*'))
      if ind <= key_col then
        break
      end
      local key, value = raw:match('^%s*([%w_%-%.]+)%s*:%s*(.*)$')
      if key == 'id' then
        return {
          line = j,
          indent = ind,
          value = value
        }
      end
      _continue_0 = true
    until true
    if not _continue_0 then
      break
    end
  end
  return nil
end
local is_empty_scalar
is_empty_scalar = function(raw)
  local value = trim(raw)
  if value == '' then
    return true
  end
  if value:sub(1, 1) == '#' then
    return true
  end
  if value == "''" or value == '""' or value == '~' then
    return true
  end
  local lowered = value:lower()
  return lowered == 'null' or lowered == 'nil'
end
local apply_to_block
apply_to_block = function(lines, header_idx, key_col, new_id)
  local found = find_id_line(lines, header_idx, key_col)
  if found then
    if not (is_empty_scalar(found.value)) then
      return false
    end
    lines[found.line] = (' '):rep(found.indent) .. 'id: ' .. new_id
    return true
  end
  local child_indent = find_child_indent(lines, header_idx, key_col)
  if not (child_indent) then
    child_indent = key_col + 2
  end
  table.insert(lines, header_idx + 1, (' '):rep(child_indent) .. 'id: ' .. new_id)
  return true
end
local apply_to_flow
apply_to_flow = function(line, new_id)
  local header = line:find('widget%s*:%s*{')
  if not (header) then
    return nil
  end
  local open = line:find('{', header)
  if not (open) then
    return nil
  end
  local inside = line:sub(open + 1)
  if inside:match('^%s*id%s*:') then
    return nil
  end
  if inside:match('^%s*}') then
    return line:sub(1, open) .. 'id: ' .. new_id .. ' ' .. inside
  else
    return line:sub(1, open) .. 'id: ' .. new_id .. ', ' .. inside
  end
end
local text_matches
text_matches = function(text, intended)
  local ok, config = pcall(yaml.decode, text)
  if not (ok and type(config) == 'table') then
    return false
  end
  local widgets = collect_widgets(config)
  if not (#widgets == #intended) then
    return false
  end
  for k, widget in ipairs(widgets) do
    if is_missing_id(widget) then
      return false
    end
    if not (tostring(widget.id) == intended[k]) then
      return false
    end
  end
  return true
end
local patch_text
patch_text = function(text, intended)
  local split = split_lines(text)
  local lines = split.lines
  local headers = { }
  for idx, raw in ipairs(lines) do
    local _continue_0 = false
    repeat
      local m = match_widget_key(raw)
      if not (m) then
        _continue_0 = true
        break
      end
      local head = m.rest:sub(1, 1)
      if m.rest == '' or head == '#' or head == '{' then
        table.insert(headers, {
          idx = idx,
          rest = m.rest,
          key_col = m.key_col
        })
      end
      _continue_0 = true
    until true
    if not _continue_0 then
      break
    end
  end
  if not (#headers == #intended) then
    return nil
  end
  for k = #headers, 1, -1 do
    local header = headers[k]
    if header.rest:sub(1, 1) == '{' then
      local patched = apply_to_flow(lines[header.idx], intended[k])
      if not (patched) then
        return nil
      end
      lines[header.idx] = patched
    else
      if not (apply_to_block(lines, header.idx, header.key_col, intended[k])) then
        return nil
      end
    end
  end
  return join_lines(split)
end
local ensure_widget_ids
ensure_widget_ids = function(yaml_str)
  local config = decode_config(yaml_str)
  if not (config) then
    return yaml_str, false
  end
  local widgets = collect_widgets(config)
  if #widgets == 0 then
    return yaml_str, false
  end
  local used = { }
  local any_missing = false
  for _index_0 = 1, #widgets do
    local widget = widgets[_index_0]
    if is_missing_id(widget) then
      any_missing = true
    else
      used[tostring(widget.id)] = true
    end
  end
  if not (any_missing) then
    return yaml_str, false
  end
  local intended = { }
  for _index_0 = 1, #widgets do
    local widget = widgets[_index_0]
    local id
    if is_missing_id(widget) then
      id = generate_unique_id(used)
    else
      id = tostring(widget.id)
    end
    used[id] = true
    widget.id = id
    table.insert(intended, id)
  end
  local patched = patch_text(yaml_str, intended)
  if patched and text_matches(patched, intended) then
    return patched, true
  end
  return yaml.encode(config), true
end
local normalize_tuple
normalize_tuple = function(old_tuple, new_tuple)
  if new_tuple == nil then
    return nil
  end
  local yaml_str = new_tuple[4]
  if not (type(yaml_str) == 'string') then
    return new_tuple
  end
  local patched, changed = ensure_widget_ids(yaml_str)
  if not (changed) then
    return new_tuple
  end
  return new_tuple:update({
    {
      '=',
      4,
      patched
    }
  })
end
local install_trigger
install_trigger = function()
  local sp = box.space._tdb_custom_views
  if not (sp) then
    return false
  end
  sp:before_replace(normalize_tuple)
  return true
end
local migrate_stored_pages
migrate_stored_pages = function()
  local sp = box.space._tdb_custom_views
  if not (sp) then
    return 0
  end
  local changed = 0
  local _list_0 = sp:select({ })
  for _index_0 = 1, #_list_0 do
    local t = _list_0[_index_0]
    local patched, patched_changed = ensure_widget_ids(t[4])
    if patched_changed then
      sp:replace({
        t[1],
        t[2],
        t[3],
        patched,
        t[5],
        t[6]
      })
      changed = changed + 1
    end
  end
  return changed
end
return {
  ensure_widget_ids = ensure_widget_ids,
  collect_widgets = collect_widgets,
  install_trigger = install_trigger,
  migrate_stored_pages = migrate_stored_pages,
  ID_PREFIX = ID_PREFIX
}
