local shell_quote
shell_quote = function(s)
  return "'" .. tostring(tostring(s):gsub("'", "'\\''")) .. "'"
end
local trim
trim = function(s)
  if not (s) then
    return ''
  end
  s = s:gsub('^%s+', '')
  s = s:gsub('%s+$', '')
  return s
end
local normalize_spaces
normalize_spaces = function(s)
  if not (s) then
    return ''
  end
  s = s:gsub('%s+', ' ')
  return trim(s)
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
local read_lines
read_lines = function(path)
  local f = assert(io.open(path, 'r'), "Cannot read file: " .. tostring(path))
  local lines = { }
  for line in f:lines() do
    table.insert(lines, line)
  end
  f:close()
  return lines
end
local write_text
write_text = function(path, content)
  local f = assert(io.open(path, 'w'), "Cannot write file: " .. tostring(path))
  f:write(content)
  return f:close()
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
local get_root_dir
get_root_dir = function()
  local script_path
  if arg and arg[0] then
    script_path = arg[0]
  else
    script_path = 'scripts/generate_docs.lua'
  end
  local script_dir = script_path:match('^(.*)/[^/]+$') or '.'
  local cmd = "cd " .. tostring(shell_quote(script_dir .. '/..')) .. " && pwd"
  local lines = run_lines(cmd)
  return lines[1] or '.'
end
local ROOT_DIR = get_root_dir()
local SCHEMA_FILE = tostring(ROOT_DIR) .. "/schema/tdb.graphql"
local DOC_EN_DIR = tostring(ROOT_DIR) .. "/doc/en"
local API_EN_DOC = tostring(DOC_EN_DIR) .. "/api.md"
local DEV_EN_DOC = tostring(DOC_EN_DIR) .. "/dev.md"
local DEV_EN_ARCH_DOC = tostring(DOC_EN_DIR) .. "/dev/architecture.md"
local DEV_EN_RUNTIME_DOC = tostring(DOC_EN_DIR) .. "/dev/runtime.md"
local DEV_EN_GRAPHQL_DOC = tostring(DOC_EN_DIR) .. "/dev/graphql.md"
local DEV_EN_FRONTEND_DOC = tostring(DOC_EN_DIR) .. "/dev/frontend.md"
local DEV_EN_TESTS_DOC = tostring(DOC_EN_DIR) .. "/dev/tests.md"
local ensure_dir
ensure_dir = function(path)
  return os.execute("mkdir -p " .. tostring(shell_quote(path)))
end
local write_doc
write_doc = function(path, lines)
  local dir = path:match('^(.*)/[^/]+$') or '.'
  ensure_dir(dir)
  return write_text(path, table.concat(lines, '\n'))
end
local now_utc
now_utc = function()
  local lines = run_lines("date -u +'%Y-%m-%d %H:%M:%S UTC'")
  return lines[1] or ''
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
  local args = '-'
  if args_raw and #args_raw >= 2 then
    args = args_raw:sub(2, -2)
    args = normalize_spaces(args)
    if args == '' then
      args = '-'
    end
  end
  return {
    field = field,
    args = args,
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
local list_type_names
list_type_names = function(kind, schema_lines)
  local names = { }
  for _index_0 = 1, #schema_lines do
    local raw = schema_lines[_index_0]
    local name = raw:match("^%s*" .. tostring(kind) .. "%s+([%w_]+)")
    if name then
      table.insert(names, name)
    end
  end
  return names
end
local normalize_list_field
normalize_list_field = function(line)
  line = trim(line)
  line = line:gsub('^[-*]%s*', '')
  line = line:gsub('^,%s*', '')
  line = trim(line)
  local nil_or_line
  if line == '' then
    nil_or_line = nil
  else
    nil_or_line = line
  end
  return nil_or_line
end
local is_comment_line
is_comment_line = function(line)
  if line:match('^%-%-') then
    return true
  end
  if line:match('^#') then
    return true
  end
  return false
end
local comment_text
comment_text = function(line)
  if not (is_comment_line(line)) then
    return nil
  end
  if line:match('^%-%-') then
    return trim(line:gsub('^%-%-%s*', ''))
  end
  return trim(line:gsub('^#+%s*', ''))
end
local is_hash_delimiter
is_hash_delimiter = function(text)
  if not (text) then
    return false
  end
  return text:match('^#+$')
end
local first_comment_line
first_comment_line = function(path)
  local f = io.open(path, 'r')
  if not (f) then
    return '(pas de description en tête de fichier)'
  end
  local line_no = 0
  for raw in f:lines() do
    local _continue_0 = false
    repeat
      do
        line_no = line_no + 1
        if line_no > 30 then
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
        if not (is_comment_line(line)) then
          break
        end
        local v = comment_text(line)
        if v == '' then
          _continue_0 = true
          break
        end
        if is_hash_delimiter(v) then
          _continue_0 = true
          break
        end
        if is_filename_banner(v) then
          _continue_0 = true
          break
        end
        f:close()
        return v
      end
      _continue_0 = true
    until true
    if not _continue_0 then
      break
    end
  end
  f:close()
  return '(pas de description en tête de fichier)'
end
local read_doc_header
read_doc_header = function(path)
  local f = io.open(path, 'r')
  if not (f) then
    return {
      summary = '(missing summary)',
      responsibilities = { },
      key_flows = { },
      depends_on = { },
      used_by = { }
    }
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
      if not (is_comment_line(line)) then
        break
      end
      local text = comment_text(line)
      if text == '' then
        _continue_0 = true
        break
      end
      if is_hash_delimiter(text) then
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
  if not (data.summary) then
    data.summary = '(pas de description en tête de fichier)'
  end
  return data
end
local list_files
list_files = function(cmd)
  local files = run_lines(cmd)
  table.sort(files)
  return files
end
local add_file_if_exists
add_file_if_exists = function(files, path)
  if file_exists(path) then
    return table.insert(files, path)
  end
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
local DOMAIN_LABELS = {
  spaces_fields = 'Spaces & Fields',
  views = 'Views',
  relations = 'Relations',
  records = 'Data (records)',
  auth = 'Authentication',
  users_groups = 'Users & Groups',
  snapshot = 'Snapshots',
  misc = 'Misc'
}
local describe_operation
describe_operation = function(op_name, kind)
  local domain = domain_for_operation(op_name)
  if domain == 'spaces_fields' then
    return tostring(kind == 'query' and 'Read' or 'Mutation') .. " operation on space/field metadata."
  end
  if domain == 'views' then
    return "Manage standard and custom views."
  end
  if domain == 'relations' then
    return "Manage inter-space relations and column display preferences."
  end
  if domain == 'records' then
    return "Read/write user records."
  end
  if domain == 'auth' then
    return "Authentication, sessions and password lifecycle."
  end
  if domain == 'users_groups' then
    return "Administration for users, groups and permissions."
  end
  if domain == 'snapshot' then
    return "Export, diff and import configuration snapshots."
  end
  return "GraphQL operation exposed by the backend."
end
local rows_by_domain
rows_by_domain = function(rows)
  local grouped = { }
  for _index_0 = 1, #rows do
    local row = rows[_index_0]
    local domain = domain_for_operation(row.field)
    if not (grouped[domain]) then
      grouped[domain] = { }
    end
    table.insert(grouped[domain], row)
  end
  return grouped
end
local append_examples
append_examples = function(out)
  table.insert(out, '## Usage Examples')
  table.insert(out, '')
  table.insert(out, '### 1) Authenticate then query spaces')
  table.insert(out, '')
  table.insert(out, '```graphql')
  table.insert(out, 'mutation Login($u: String!, $p: String!) {')
  table.insert(out, '  login(username: $u, password: $p) { token user { id username } }')
  table.insert(out, '}')
  table.insert(out, '```')
  table.insert(out, '')
  table.insert(out, '```graphql')
  table.insert(out, 'query { spaces { id name description } }')
  table.insert(out, '```')
  table.insert(out, '')
  table.insert(out, '### 2) Paginated records query')
  table.insert(out, '')
  table.insert(out, '```graphql')
  table.insert(out, 'query Records($spaceId: ID!, $limit: Int!, $offset: Int!) {')
  table.insert(out, '  records(spaceId: $spaceId, limit: $limit, offset: $offset) {')
  table.insert(out, '    total')
  table.insert(out, '    items { id data }')
  table.insert(out, '  }')
  table.insert(out, '}')
  table.insert(out, '```')
  table.insert(out, '')
  table.insert(out, '### 3) Structural mutation: create space and field')
  table.insert(out, '')
  table.insert(out, '```graphql')
  table.insert(out, 'mutation CreateSpace($input: CreateSpaceInput!) {')
  table.insert(out, '  createSpace(input: $input) { id name }')
  table.insert(out, '}')
  table.insert(out, '```')
  table.insert(out, '')
  table.insert(out, '```graphql')
  table.insert(out, 'mutation AddField($spaceId: ID!, $input: FieldInput!) {')
  table.insert(out, '  addField(spaceId: $spaceId, input: $input) { id name fieldType }')
  table.insert(out, '}')
  table.insert(out, '```')
  return table.insert(out, '')
end
local append_operation_groups
append_operation_groups = function(out, rows, kind)
  local grouped = rows_by_domain(rows)
  local ordering = {
    'spaces_fields',
    'views',
    'relations',
    'records',
    'auth',
    'users_groups',
    'snapshot',
    'misc'
  }
  for _index_0 = 1, #ordering do
    local _continue_0 = false
    repeat
      local domain = ordering[_index_0]
      local items = grouped[domain]
      if not (items and #items > 0) then
        _continue_0 = true
        break
      end
      local label = DOMAIN_LABELS[domain]
      table.insert(out, "### " .. tostring(label))
      table.insert(out, '')
      table.insert(out, '| Operation | Arguments | Return | Description |')
      table.insert(out, '|---|---|---|---|')
      for _index_1 = 1, #items do
        local row = items[_index_1]
        local desc = describe_operation(row.field, kind)
        table.insert(out, "| `" .. tostring(row.field) .. "` | `" .. tostring(row.args) .. "` | `" .. tostring(row.returns) .. "` | " .. tostring(desc) .. " |")
      end
      table.insert(out, '')
      _continue_0 = true
    until true
    if not _continue_0 then
      break
    end
  end
end
local generate_api_doc
generate_api_doc = function(path)
  local schema_lines = read_lines(SCHEMA_FILE)
  local query_rows = extract_block_rows('Query', schema_lines)
  local mutation_rows = extract_block_rows('Mutation', schema_lines)
  local inputs = list_type_names('input', schema_lines)
  local enums = list_type_names('enum', schema_lines)
  local out = {
    '# GraphQL API — TGui',
    '',
    '> Auto-generated file. Do not edit manually.',
    '>',
    "> Generated at: " .. tostring(now_utc()),
    '>',
    '> Source: `schema/tdb.graphql`',
    '',
    '## Overview',
    '',
    '- Endpoint: `/graphql`',
    '- Transport: HTTP POST JSON',
    '- Auth: Bearer token in `Authorization` header',
    '- Signature source of truth: `schema/tdb.graphql`',
    '- Runtime SDL snapshot: `schema/tdb.generated.graphql`',
    '',
    '## Queries',
    ''
  }
  append_operation_groups(out, query_rows, 'query')
  table.insert(out, '## Mutations')
  table.insert(out, '')
  append_operation_groups(out, mutation_rows, 'mutation')
  append_examples(out)
  table.insert(out, '## Input Types')
  table.insert(out, '')
  for _index_0 = 1, #inputs do
    local name = inputs[_index_0]
    table.insert(out, "- `" .. tostring(name) .. "`")
  end
  table.insert(out, '')
  table.insert(out, '## Enums')
  table.insert(out, '')
  for _index_0 = 1, #enums do
    local name = enums[_index_0]
    table.insert(out, "- `" .. tostring(name) .. "`")
  end
  table.insert(out, '')
  table.insert(out, '## Notes')
  table.insert(out, '')
  table.insert(out, '- Dynamic user-space types are rebuilt by backend schema reinitialization.')
  table.insert(out, '- To refresh SDL runtime snapshot: `make sdl-gen`.')
  table.insert(out, '')
  return write_doc(path, out)
end
local modules_from_rel
modules_from_rel = function(rels)
  local out = { }
  for _index_0 = 1, #rels do
    local rel = rels[_index_0]
    table.insert(out, tostring(ROOT_DIR) .. "/" .. tostring(rel))
  end
  return out
end
local collect_modules
collect_modules = function()
  local backend_files = list_files("cd " .. tostring(shell_quote(ROOT_DIR)) .. " && find ./backend -name '*.moon' -type f ! -path './backend/moonscript/*' | sed 's#^\\./##'")
  local backend_abs = { }
  for _index_0 = 1, #backend_files do
    local rel = backend_files[_index_0]
    table.insert(backend_abs, tostring(ROOT_DIR) .. "/" .. tostring(rel))
  end
  add_file_if_exists(backend_abs, tostring(ROOT_DIR) .. "/backend/init.lua")
  add_file_if_exists(backend_abs, tostring(ROOT_DIR) .. "/backend/html.lua")
  local frontend_rel = list_files("cd " .. tostring(shell_quote(ROOT_DIR)) .. " && find ./frontend/src -name '*.coffee' -type f | sed 's#^\\./##'")
  local frontend_abs = { }
  for _index_0 = 1, #frontend_rel do
    local rel = frontend_rel[_index_0]
    table.insert(frontend_abs, tostring(ROOT_DIR) .. "/" .. tostring(rel))
  end
  local tests_moon_rel = list_files("cd " .. tostring(shell_quote(ROOT_DIR)) .. " && find ./tests -name '*.moon' -type f | sed 's#^\\./##'")
  local tests_coffee_rel = list_files("cd " .. tostring(shell_quote(ROOT_DIR)) .. " && find ./tests/js -name '*.coffee' -type f | sed 's#^\\./##'")
  local tests_abs = { }
  for _index_0 = 1, #tests_moon_rel do
    local rel = tests_moon_rel[_index_0]
    table.insert(tests_abs, tostring(ROOT_DIR) .. "/" .. tostring(rel))
  end
  for _index_0 = 1, #tests_coffee_rel do
    local rel = tests_coffee_rel[_index_0]
    table.insert(tests_abs, tostring(ROOT_DIR) .. "/" .. tostring(rel))
  end
  local scripts_rel = list_files("cd " .. tostring(shell_quote(ROOT_DIR)) .. " && find ./scripts -maxdepth 1 -type f | grep -E '\\.(sh|moon|lua)$$' | sed 's#^\\./##'")
  local scripts_abs = { }
  for _index_0 = 1, #scripts_rel do
    local rel = scripts_rel[_index_0]
    table.insert(scripts_abs, tostring(ROOT_DIR) .. "/" .. tostring(rel))
  end
  return {
    backend = backend_abs,
    frontend = frontend_abs,
    tests = tests_abs,
    scripts = scripts_abs
  }
end
local extract_rel
extract_rel = function(abs_path)
  return abs_path:gsub("^" .. tostring(ROOT_DIR) .. "/", '')
end
local emit_module_summaries
emit_module_summaries = function(out, files)
  table.insert(out, '| Module | Summary |')
  table.insert(out, '|---|---|')
  for _index_0 = 1, #files do
    local path = files[_index_0]
    local rel = extract_rel(path)
    local doc = read_doc_header(path)
    local sum = doc.summary
    sum = sum:gsub('|', '\\|')
    table.insert(out, "| `" .. tostring(rel) .. "` | " .. tostring(sum) .. " |")
  end
  return table.insert(out, '')
end
local generate_dev_detail
generate_dev_detail = function(path, title, intro, files)
  local out = {
    "# " .. tostring(title),
    '',
    '> Auto-generated file. Do not edit manually.',
    '>',
    "> Generated at: " .. tostring(now_utc()),
    '',
    intro,
    ''
  }
  emit_module_summaries(out, files)
  return write_doc(path, out)
end
local generate_dev_compact
generate_dev_compact = function(path)
  local out = {
    '# Developer Documentation — TGui',
    '',
    '> Auto-generated file. Do not edit manually.',
    '>',
    "> Generated at: " .. tostring(now_utc()),
    '',
    'Compact architecture overview for TGui. Full reference is available in `doc/en/dev/*.md`.',
    '',
    '## Architecture (summary)',
    '',
    '- Runtime entrypoint: `backend/init.moon`',
    '- HTTP edge: `backend/http_server.moon`',
    '- GraphQL execution: `backend/graphql/executor.moon`',
    '- Schema/resolver assembly: `backend/resolvers/init.moon`',
    '- Metadata engine: `backend/core/spaces.moon`',
    '- Frontend SPA shell: `frontend/src/app.coffee`',
    '',
    '## Detailed references',
    '',
    '- Global architecture: `doc/en/dev/architecture.md`',
    '- Backend runtime: `doc/en/dev/runtime.md`',
    '- GraphQL pipeline: `doc/en/dev/graphql.md`',
    '- Frontend SPA: `doc/en/dev/frontend.md`',
    '- Testing strategy: `doc/en/dev/tests.md`',
    '',
    '## Commands',
    '',
    '- Generate docs: `make doc-gen`',
    '- Check docs: `make doc-check`',
    '- Full CI: `make ci`',
    ''
  }
  return write_doc(path, out)
end
local generate_all_dev_docs
generate_all_dev_docs = function()
  local modules = collect_modules()
  local core_backend = modules_from_rel({
    'backend/init.moon',
    'backend/http_server.moon',
    'backend/core/spaces.moon',
    'backend/core/auth.moon',
    'backend/core/permissions.moon',
    'backend/core/triggers.moon',
    'backend/core/views.moon',
    'backend/resolvers/init.moon'
  })
  local graphql_backend = modules_from_rel({
    'backend/graphql/lexer.moon',
    'backend/graphql/parser.moon',
    'backend/graphql/schema.moon',
    'backend/graphql/executor.moon',
    'backend/graphql/dynamic.moon',
    'backend/graphql/introspection.moon',
    'backend/resolvers/schema_resolvers.moon',
    'backend/resolvers/data_resolvers.moon',
    'backend/resolvers/auth_resolvers.moon'
  })
  local frontend_core = modules_from_rel({
    'frontend/src/app.coffee',
    'frontend/src/graphql_client.coffee',
    'frontend/src/spaces.coffee',
    'frontend/src/auth.coffee',
    'frontend/src/views/data_view.coffee',
    'frontend/src/views/custom_view.coffee'
  })
  generate_dev_compact(DEV_EN_DOC)
  generate_dev_detail(DEV_EN_ARCH_DOC, 'Architecture — detailed reference', 'Architecture-level view of backend/frontend modules and relationships.', core_backend)
  generate_dev_detail(DEV_EN_RUNTIME_DOC, 'Backend runtime — detailed reference', 'Tarantool startup, HTTP lifecycle and subsystem initialization details.', modules.backend)
  generate_dev_detail(DEV_EN_GRAPHQL_DOC, 'GraphQL pipeline — detailed reference', 'SDL/parser/executor/resolver flow (static + dynamic).', graphql_backend)
  generate_dev_detail(DEV_EN_FRONTEND_DOC, 'Frontend SPA — detailed reference', 'CoffeeScript module organization and key UI flows.', frontend_core)
  return generate_dev_detail(DEV_EN_TESTS_DOC, 'Tests — detailed reference', 'Backend/frontend test panorama and per-file intent.', modules.tests)
end
generate_api_doc(API_EN_DOC)
generate_all_dev_docs()
print("Generated: " .. tostring(API_EN_DOC))
print("Generated: " .. tostring(DEV_EN_DOC))
return os.exit(0)
