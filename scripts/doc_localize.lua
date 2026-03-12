local DOC_EN_FILES = {
  'doc/en/README.md',
  'doc/en/get-started.md',
  'doc/en/reference.md',
  'doc/en/api.md',
  'doc/en/dev.md',
  'doc/en/dev/architecture.md',
  'doc/en/dev/runtime.md',
  'doc/en/dev/graphql.md',
  'doc/en/dev/frontend.md',
  'doc/en/dev/tests.md'
}
local trim
trim = function(s)
  if not (s) then
    return ''
  end
  s = s:gsub('^%s+', '')
  return s:gsub('%s+$', '')
end
local shell_quote
shell_quote = function(s)
  return "'" .. tostring(tostring(s):gsub("'", "'\\''")) .. "'"
end
local file_exists
file_exists = function(path)
  local f = io.open(path, 'r')
  if not (f) then
    return false
  end
  f:close()
  return true
end
local read_text
read_text = function(path)
  local f, err = io.open(path, 'r')
  if not (f) then
    error("Cannot read file: " .. tostring(path) .. " (" .. tostring(err or 'unknown error') .. ")")
  end
  local content = f:read('*a')
  f:close()
  return content
end
local write_text
write_text = function(path, content)
  local f, err = io.open(path, 'w')
  if not (f) then
    error("Cannot write file: " .. tostring(path) .. " (" .. tostring(err or 'unknown error') .. ")")
  end
  f:write(content)
  return f:close()
end
local ensure_dir_for_file
ensure_dir_for_file = function(path)
  local dir = path:match('^(.*)/[^/]+$') or '.'
  return os.execute("mkdir -p " .. tostring(shell_quote(dir)))
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
local is_clean_text
is_clean_text = function(text)
  return not has_c1_controls(text) and not has_mojibake(text)
end
local escape_po
escape_po = function(s)
  s = s:gsub('\\', '\\\\')
  s = s:gsub('"', '\\"')
  s = s:gsub('\t', '\\t')
  s = s:gsub('\r', '\\r')
  return s:gsub('\n', '\\n')
end
local unescape_po
unescape_po = function(s)
  s = s:gsub('\\n', '\n')
  s = s:gsub('\\t', '\t')
  s = s:gsub('\\r', '\r')
  s = s:gsub('\\"', '"')
  return s:gsub('\\\\', '\\')
end
local parse_po
parse_po = function(path)
  if not (file_exists(path)) then
    return { }
  end
  local text = read_text(path)
  local translations = { }
  local current_msgid = nil
  local current_msgstr = nil
  local state = nil
  local flush
  flush = function()
    if current_msgid and current_msgid ~= '' then
      translations[current_msgid] = current_msgstr or ''
    end
    current_msgid = nil
    current_msgstr = nil
    state = nil
  end
  for line in text:gmatch('([^\n]*)\n?') do
    local _continue_0 = false
    repeat
      if line:match('^%s*$') then
        flush()
        _continue_0 = true
        break
      end
      if line:match('^#') then
        _continue_0 = true
        break
      end
      if line:match('^msgid%s+"') then
        flush()
        local chunk = line:match('^msgid%s+"(.*)"$' or '')
        current_msgid = unescape_po(chunk)
        current_msgstr = ''
        state = 'msgid'
        _continue_0 = true
        break
      end
      if line:match('^msgstr%s+"') then
        local chunk = line:match('^msgstr%s+"(.*)"$' or '')
        current_msgstr = unescape_po(chunk)
        state = 'msgstr'
        _continue_0 = true
        break
      end
      if line:match('^"') then
        local chunk = line:match('^"(.*)"$' or '')
        if state == 'msgid' then
          current_msgid = (current_msgid or '') .. unescape_po(chunk)
        elseif state == 'msgstr' then
          current_msgstr = (current_msgstr or '') .. unescape_po(chunk)
        end
        _continue_0 = true
        break
      end
      _continue_0 = true
    until true
    if not _continue_0 then
      break
    end
  end
  flush()
  return translations
end
local collect_source_entries
collect_source_entries = function()
  local refs_by_msgid = { }
  local order = { }
  local remember
  remember = function(msgid, ref)
    if msgid:match('^%s*$') then
      return 
    end
    local entry = refs_by_msgid[msgid]
    if not (entry) then
      entry = {
        refs = { },
        refs_set = { }
      }
      refs_by_msgid[msgid] = entry
      table.insert(order, msgid)
    end
    if not (entry.refs_set[ref]) then
      entry.refs_set[ref] = true
      return table.insert(entry.refs, ref)
    end
  end
  for _index_0 = 1, #DOC_EN_FILES do
    local en_path = DOC_EN_FILES[_index_0]
    local text = read_text(en_path)
    local line_no = 0
    for line in text:gmatch('([^\n]*)\n?') do
      line_no = line_no + 1
      remember(line, tostring(en_path) .. ":" .. tostring(line_no))
    end
  end
  return refs_by_msgid, order
end
local cmd_update_pot
cmd_update_pot = function()
  local refs_by_msgid, order = collect_source_entries()
  local out = {
    'msgid ""',
    'msgstr ""',
    '"Project-Id-Version: tdb-docs\\n"',
    '"Content-Type: text/plain; charset=UTF-8\\n"',
    '"Content-Transfer-Encoding: 8bit\\n"',
    ''
  }
  for _index_0 = 1, #order do
    local msgid = order[_index_0]
    local entry = refs_by_msgid[msgid]
    local refs = table.concat(entry.refs, ' ')
    table.insert(out, "#: " .. tostring(refs))
    table.insert(out, "msgid \"" .. tostring(escape_po(msgid)) .. "\"")
    table.insert(out, 'msgstr ""')
    table.insert(out, '')
  end
  ensure_dir_for_file('po/tdb-docs.pot')
  write_text('po/tdb-docs.pot', table.concat(out, '\n'))
  if not (file_exists('po/fr.po')) then
    write_text('po/fr.po', table.concat({
      'msgid ""',
      'msgstr ""',
      '"Project-Id-Version: tdb-docs\\n"',
      '"Content-Type: text/plain; charset=UTF-8\\n"',
      '"Content-Transfer-Encoding: 8bit\\n"',
      ''
    }, '\n'))
  end
  return print('doc_localize: updated po/tdb-docs.pot')
end
local cmd_build_fr
cmd_build_fr = function()
  local translations = parse_po('po/fr.po')
  for _index_0 = 1, #DOC_EN_FILES do
    local en_path = DOC_EN_FILES[_index_0]
    local fr_path = en_path:gsub('^doc/en/', 'doc/fr/')
    local text = read_text(en_path)
    local had_trailing_newline = text:sub(-1) == '\n'
    local out_lines = { }
    for line in text:gmatch('([^\n]*)\n?') do
      local translated = line
      local candidate = translations[line]
      if candidate and candidate ~= '' and is_clean_text(candidate) then
        translated = candidate
      end
      table.insert(out_lines, translated)
    end
    local output = table.concat(out_lines, '\n')
    if had_trailing_newline and output:sub(-1) ~= '\n' then
      output = tostring(output) .. "\n"
    end
    if not is_clean_text(output) then
      io.stderr:write("WARNING: encoding issue in " .. tostring(fr_path) .. ", using English fallback\n")
      output = text
    end
    ensure_dir_for_file(fr_path)
    write_text(fr_path, output)
  end
  return print('doc_localize: generated doc/fr from doc/en + po/fr.po (fallback enabled)')
end
local cmd_check_encoding
cmd_check_encoding = function()
  local errors = { }
  local _list_0 = {
    'doc/fr/README.md',
    'doc/fr/get-started.md',
    'doc/fr/reference.md',
    'doc/fr/api.md',
    'doc/fr/dev.md',
    'doc/fr/dev/architecture.md',
    'doc/fr/dev/runtime.md',
    'doc/fr/dev/graphql.md',
    'doc/fr/dev/frontend.md',
    'doc/fr/dev/tests.md'
  }
  for _index_0 = 1, #_list_0 do
    local _continue_0 = false
    repeat
      local path = _list_0[_index_0]
      if not (file_exists(path)) then
        table.insert(errors, "missing file: " .. tostring(path))
        _continue_0 = true
        break
      end
      local text = read_text(path)
      if has_c1_controls(text) then
        table.insert(errors, "C1 control detected in " .. tostring(path))
      end
      if has_mojibake(text) then
        table.insert(errors, "mojibake marker detected in " .. tostring(path))
      end
      _continue_0 = true
    until true
    if not _continue_0 then
      break
    end
  end
  if #errors > 0 then
    io.stderr:write("doc_localize encoding check failed (" .. tostring(#errors) .. " issue(s)):\n")
    for _index_0 = 1, #errors do
      local err = errors[_index_0]
      io.stderr:write("- " .. tostring(err) .. "\n")
    end
    os.exit(1)
  end
  return print('doc_localize: encoding check OK')
end
local main
main = function()
  local command = arg and arg[1] or ''
  if command == 'update-pot' then
    return cmd_update_pot()
  elseif command == 'build-fr' then
    return cmd_build_fr()
  elseif command == 'check-encoding' then
    return cmd_check_encoding()
  else
    io.stderr:write("Usage: tarantool scripts/doc_localize.lua [update-pot|build-fr|check-encoding]\n")
    return os.exit(1)
  end
end
main()
return os.exit(0)
