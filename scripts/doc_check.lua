local trim
trim = function(s)
  if not (s) then
    return ''
  end
  s = s:gsub('^%s+', '')
  s = s:gsub('%s+$', '')
  return s
end
local read_text
read_text = function(path)
  local f = io.open(path, 'r')
  if not (f) then
    return nil
  end
  local text = f:read('*a')
  f:close()
  return text
end
local has_c1_controls
has_c1_controls = function(text)
  local i = 1
  while i <= #text do
    local b1 = text:byte(i)
    if b1 == 0xC2 and i < #text then
      local b2 = text:byte(i + 1)
      if b2 >= 0x80 and b2 <= 0x9F then
        return true
      end
      i = i + 2
    else
      i = i + 1
    end
  end
  return false
end
local MOJIBAKE_PREFIXES = {
  string.char(0xC3, 0xA2, 0xC2, 0x80),
  string.char(0xC3, 0xA2, 0xC2, 0x86),
  string.char(0xC3, 0xA2, 0xC2, 0x96),
  string.char(0xC3, 0xA2, 0xC2, 0x9C),
  string.char(0xC3, 0x83, 0xC2)
}
local has_mojibake
has_mojibake = function(text)
  for _index_0 = 1, #MOJIBAKE_PREFIXES do
    local prefix = MOJIBAKE_PREFIXES[_index_0]
    if text:find(prefix, 1, true) then
      return true
    end
  end
  return false
end
local run_lines
run_lines = function(cmd)
  local p, err = io.popen(cmd)
  if not (p) then
    error("Cannot execute command: " .. tostring(cmd) .. " (" .. tostring(err or 'unknown error') .. ")")
  end
  local out = p:read('*a')
  p:close()
  local lines = { }
  for line in out:gmatch('[^\n]+') do
    table.insert(lines, line)
  end
  return lines
end
local is_filename_banner
is_filename_banner = function(s)
  if not (s) then
    return false
  end
  s = trim(s)
  if s == '' then
    return false
  end
  if s:match('^[%w_./-]+%.moon$') then
    return true
  end
  if s:match('^[%w_./-]+%.coffee$') then
    return true
  end
  if s:match('^[%w_./-]+%.lua$') then
    return true
  end
  return false
end
local normalize_list_field
normalize_list_field = function(line)
  line = trim(line)
  line = line:gsub('^[-*]%s*', '')
  line = line:gsub('^,%s*', '')
  line = trim(line)
  if line == '' then
    return nil
  end
  return line
end
local read_header
read_header = function(path)
  local f = io.open(path, 'r')
  if not (f) then
    return nil
  end
  local data = {
    summary = nil,
    responsibilities = { },
    key_flows = { },
    depends_on = { },
    used_by = { }
  }
  local section = nil
  local line_no = 0
  for raw in f:lines() do
    local _continue_0 = false
    repeat
      line_no = line_no + 1
      if line_no > 80 then
        break
      end
      local line = trim(raw)
      if line == '' then
        _continue_0 = true
        break
      end
      if line:match('^#!') then
        _continue_0 = true
        break
      end
      if not (line:match('^%-%-' or line:match('^#'))) then
        break
      end
      local text
      if line:match('^%-%-') then
        text = trim(line:gsub('^%-%-%s*', ''))
      else
        text = trim(line:gsub('^#%s*', ''))
      end
      if text == '' then
        _continue_0 = true
        break
      end
      if is_filename_banner(text) then
        _continue_0 = true
        break
      end
      if text:match('^Summary:%s*') then
        local value = trim(text:gsub('^Summary:%s*', ''))
        if not (value == '') then
          data.summary = value
        end
        section = nil
        _continue_0 = true
        break
      end
      if text:match('^Responsibilities:%s*$') then
        section = 'responsibilities'
        _continue_0 = true
        break
      end
      if text:match('^Key Flows:%s*$') then
        section = 'key_flows'
        _continue_0 = true
        break
      end
      if text:match('^Depends on:%s*$') then
        section = 'depends_on'
        _continue_0 = true
        break
      end
      if text:match('^Used by:%s*$') then
        section = 'used_by'
        _continue_0 = true
        break
      end
      if section then
        local item = normalize_list_field(text)
        if item then
          table.insert(data[section], item)
        end
        _continue_0 = true
        break
      end
      if not (data.summary) then
        data.summary = text
      end
      _continue_0 = true
    until true
    if not _continue_0 then
      break
    end
  end
  f:close()
  return data
end
local count_char
count_char = function(s, ch)
  local n = 0
  local i = 1
  while i <= #s do
    if s:sub(i, i) == ch then
      n = n + 1
    end
    i = i + 1
  end
  return n
end
local parse_field_line
parse_field_line = function(line)
  local field, args_raw, returns = line:match('^([%a_][%w_]*)%s*(%b())%s*:%s*(%S+)')
  if not (field) then
    field, returns = line:match('^([%a_][%w_]*)%s*:%s*(%S+)')
  end
  if not (field) then
    return nil
  end
  return {
    field = field,
    returns = returns
  }
end
local extract_block_rows
extract_block_rows = function(block_name, schema_lines)
  local in_block = false
  local depth = 0
  local buf = ''
  local rows = { }
  for _index_0 = 1, #schema_lines do
    local _continue_0 = false
    repeat
      local raw = schema_lines[_index_0]
      local line = raw:gsub('#.*$', '')
      line = trim(line)
      if line == '' then
        _continue_0 = true
        break
      end
      if not (in_block) then
        if line:match("^type%s+" .. tostring(block_name) .. "%s*%{") then
          in_block = true
        end
        _continue_0 = true
        break
      end
      if depth == 0 and line:match('^}') then
        if buf ~= '' then
          local row = parse_field_line(buf)
          if row then
            table.insert(rows, row)
          end
          buf = ''
        end
        break
      end
      if buf ~= '' then
        buf = tostring(buf) .. " " .. tostring(line)
      else
        buf = line
      end
      depth = depth + count_char(line, '(')
      depth = depth - count_char(line, ')')
      if depth == 0 and buf:find(':', 1, true) then
        local row = parse_field_line(buf)
        if row then
          table.insert(rows, row)
        end
        buf = ''
      end
      _continue_0 = true
    until true
    if not _continue_0 then
      break
    end
  end
  return rows
end
local starts_with
starts_with = function(s, prefix)
  return s:sub(1, #prefix) == prefix
end
local domain_for_operation
domain_for_operation = function(name)
  if name == 'exportSnapshot' or name == 'diffSnapshot' or name == 'importSnapshot' then
    return 'snapshot'
  end
  if name == 'login' or name == 'logout' or name == 'me' or name == 'changePassword' or name == 'adminSetPassword' then
    return 'auth'
  end
  if starts_with(name, 'createUser') or starts_with(name, 'createGroup') or starts_with(name, 'deleteGroup') or starts_with(name, 'addMember') or starts_with(name, 'removeMember') or name == 'users' or name == 'user' or name == 'groups' or name == 'group' or name == 'grant' or name == 'revoke' then
    return 'users_groups'
  end
  if starts_with(name, 'space') or starts_with(name, 'createSpace') or starts_with(name, 'updateSpace') or starts_with(name, 'deleteSpace') or starts_with(name, 'addField') or starts_with(name, 'addFields') or starts_with(name, 'removeField') or starts_with(name, 'reorderFields') or starts_with(name, 'updateField') or starts_with(name, 'changeFieldType') then
    return 'spaces_fields'
  end
  if starts_with(name, 'view') or starts_with(name, 'views') or starts_with(name, 'createView') or starts_with(name, 'updateView') or starts_with(name, 'deleteView') or starts_with(name, 'customView') or starts_with(name, 'customViews') or starts_with(name, 'createCustomView') or starts_with(name, 'updateCustomView') or starts_with(name, 'deleteCustomView') then
    return 'views'
  end
  if starts_with(name, 'relation') or starts_with(name, 'relations') or starts_with(name, 'createRelation') or starts_with(name, 'updateRelation') or starts_with(name, 'deleteRelation') or starts_with(name, 'gridColumnPrefs') or starts_with(name, 'saveGridColumnPrefs') then
    return 'relations'
  end
  if starts_with(name, 'record') or starts_with(name, 'records') or starts_with(name, 'insertRecord') or starts_with(name, 'insertRecords') or starts_with(name, 'updateRecord') or starts_with(name, 'updateRecords') or starts_with(name, 'restoreRecords') or starts_with(name, 'deleteRecord') or starts_with(name, 'deleteRecords') or starts_with(name, 'aggregateSpace') then
    return 'records'
  end
  return 'misc'
end
local collect_backend_files
collect_backend_files = function()
  return run_lines("find ./backend -name '*.moon' -type f ! -path './backend/moonscript/*' | sed 's#^\\./##'")
end
local critical_modules = {
  'backend/init.moon',
  'backend/http_server.moon',
  'backend/resolvers/init.moon'
}
local is_critical
is_critical = function(rel_path)
  for _index_0 = 1, #critical_modules do
    local c = critical_modules[_index_0]
    if rel_path == c then
      return true
    end
  end
  return false
end
local errors = { }
local backend_files = collect_backend_files()
for _index_0 = 1, #backend_files do
  local _continue_0 = false
  repeat
    local rel = backend_files[_index_0]
    local header = read_header(rel)
    if not (header) then
      table.insert(errors, "missing file: " .. tostring(rel))
      _continue_0 = true
      break
    end
    if not header.summary or trim(header.summary) == '' or is_filename_banner(header.summary) then
      table.insert(errors, "missing meaningful Summary in " .. tostring(rel))
    end
    if is_critical(rel) then
      if #header.responsibilities == 0 then
        table.insert(errors, "missing Responsibilities section in " .. tostring(rel))
      end
      if #header.key_flows == 0 then
        table.insert(errors, "missing Key Flows section in " .. tostring(rel))
      end
      if #header.depends_on == 0 then
        table.insert(errors, "missing Depends on section in " .. tostring(rel))
      end
      if #header.used_by == 0 then
        table.insert(errors, "missing Used by section in " .. tostring(rel))
      end
    end
    _continue_0 = true
  until true
  if not _continue_0 then
    break
  end
end
local schema_lines
do
  local f = io.open('./schema/tdb.graphql', 'r')
  if not f then
    table.insert(errors, 'missing schema/tdb.graphql')
    schema_lines = { }
  else
    local out = { }
    for line in f:lines() do
      table.insert(out, line)
    end
    f:close()
    schema_lines = out
  end
end
local _list_0 = extract_block_rows('Query', schema_lines)
for _index_0 = 1, #_list_0 do
  local row = _list_0[_index_0]
  if domain_for_operation(row.field) == 'misc' then
    table.insert(errors, "undocumented Query domain mapping for `" .. tostring(row.field) .. "`")
  end
end
local _list_1 = extract_block_rows('Mutation', schema_lines)
for _index_0 = 1, #_list_1 do
  local row = _list_1[_index_0]
  if domain_for_operation(row.field) == 'misc' then
    table.insert(errors, "undocumented Mutation domain mapping for `" .. tostring(row.field) .. "`")
  end
end
local required_docs = {
  './doc/en/README.md',
  './doc/fr/README.md',
  './doc/en/get-started.md',
  './doc/fr/get-started.md',
  './doc/en/reference.md',
  './doc/fr/reference.md',
  './doc/fr/api.md',
  './doc/en/api.md',
  './doc/fr/dev.md',
  './doc/en/dev.md',
  './doc/fr/dev/architecture.md',
  './doc/fr/dev/runtime.md',
  './doc/fr/dev/graphql.md',
  './doc/fr/dev/frontend.md',
  './doc/fr/dev/tests.md',
  './doc/en/dev/architecture.md',
  './doc/en/dev/runtime.md',
  './doc/en/dev/graphql.md',
  './doc/en/dev/frontend.md',
  './doc/en/dev/tests.md'
}
for _index_0 = 1, #required_docs do
  local path = required_docs[_index_0]
  local text = read_text(path)
  if not text then
    table.insert(errors, "missing generated doc file: " .. tostring(path))
  else
    if path:match('^./doc/fr/') then
      if has_c1_controls(text) then
        table.insert(errors, "encoding regression (C1 control) in " .. tostring(path))
      end
      if has_mojibake(text) then
        table.insert(errors, "encoding regression (mojibake marker) in " .. tostring(path))
      end
    end
  end
end
local required_po = {
  './po/tdb-docs.pot',
  './po/fr.po'
}
for _index_0 = 1, #required_po do
  local path = required_po[_index_0]
  local f = io.open(path, 'r')
  if not f then
    table.insert(errors, "missing PO catalog file: " .. tostring(path))
  else
    f:close()
  end
end
if #errors > 0 then
  io.stderr:write("doc-check failed (" .. tostring(#errors) .. " issue(s)):\n")
  for _index_0 = 1, #errors do
    local err = errors[_index_0]
    io.stderr:write("- " .. tostring(err) .. "\n")
  end
  os.exit(1)
end
print("doc-check OK")
return os.exit(0)
