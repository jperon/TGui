#!/usr/bin/env moon
-- Summary: Validate documentation coverage and fail CI when required docs are missing.
-- Responsibilities:
-- - Check backend MoonScript modules have meaningful header summaries.
-- - Enforce structured header sections on critical backend modules.
-- - Ensure every GraphQL Query/Mutation maps to a documented API domain.
-- Depends on:
-- - schema/tdb.graphql, backend/**/*.moon, scripts/generate_docs.moon domain rules.
-- Used by:
-- - Makefile target `doc-check` and `make ci`.

trim = (s) ->
  return '' unless s
  s = s\gsub '^%s+', ''
  s = s\gsub '%s+$', ''
  s

run_lines = (cmd) ->
  p, err = io.popen cmd
  error "Cannot execute command: #{cmd} (#{err or 'unknown error'})" unless p
  out = p\read '*a'
  p\close!
  lines = {}
  for line in out\gmatch '[^\n]+'
    table.insert lines, line
  lines

is_filename_banner = (s) ->
  return false unless s
  s = trim s
  return false if s == ''
  return true if s\match '^[%w_./-]+%.moon$'
  return true if s\match '^[%w_./-]+%.coffee$'
  return true if s\match '^[%w_./-]+%.lua$'
  false

normalize_list_field = (line) ->
  line = trim line
  line = line\gsub '^[-*]%s*', ''
  line = line\gsub '^,%s*', ''
  line = trim line
  return nil if line == ''
  line

read_header = (path) ->
  f = io.open path, 'r'
  return nil unless f

  data = {
    summary: nil
    responsibilities: {}
    key_flows: {}
    depends_on: {}
    used_by: {}
  }

  section = nil
  line_no = 0
  for raw in f\lines!
    line_no += 1
    break if line_no > 80

    line = trim raw
    continue if line == ''
    continue if line\match '^#!'
    break unless line\match '^%-%-' or line\match '^#'

    text = if line\match '^%-%-'
      trim line\gsub '^%-%-%s*', ''
    else
      trim line\gsub '^#%s*', ''

    continue if text == ''
    continue if is_filename_banner text

    if text\match '^Summary:%s*'
      value = trim text\gsub '^Summary:%s*', ''
      data.summary = value unless value == ''
      section = nil
      continue

    if text\match '^Responsibilities:%s*$'
      section = 'responsibilities'
      continue
    if text\match '^Key Flows:%s*$'
      section = 'key_flows'
      continue
    if text\match '^Depends on:%s*$'
      section = 'depends_on'
      continue
    if text\match '^Used by:%s*$'
      section = 'used_by'
      continue

    if section
      item = normalize_list_field text
      table.insert data[section], item if item
      continue

    data.summary = text unless data.summary

  f\close!
  data

count_char = (s, ch) ->
  n = 0
  i = 1
  while i <= #s
    n += 1 if s\sub(i, i) == ch
    i += 1
  n

parse_field_line = (line) ->
  field, args_raw, returns = line\match '^([%a_][%w_]*)%s*(%b())%s*:%s*(%S+)'
  unless field
    field, returns = line\match '^([%a_][%w_]*)%s*:%s*(%S+)'
  return nil unless field
  { field: field, returns: returns }

extract_block_rows = (block_name, schema_lines) ->
  in_block = false
  depth = 0
  buf = ''
  rows = {}

  for raw in *schema_lines
    line = raw\gsub '#.*$', ''
    line = trim line
    continue if line == ''

    unless in_block
      if line\match "^type%s+#{block_name}%s*%{"
        in_block = true
      continue

    if depth == 0 and line\match '^}'
      if buf != ''
        row = parse_field_line buf
        table.insert rows, row if row
        buf = ''
      break

    if buf != ''
      buf = "#{buf} #{line}"
    else
      buf = line

    depth += count_char line, '('
    depth -= count_char line, ')'

    if depth == 0 and buf\find(':', 1, true)
      row = parse_field_line buf
      table.insert rows, row if row
      buf = ''

  rows

starts_with = (s, prefix) ->
  s\sub(1, #prefix) == prefix

domain_for_operation = (name) ->
  return 'snapshot' if name == 'exportSnapshot' or name == 'diffSnapshot' or name == 'importSnapshot'
  return 'auth' if name == 'login' or name == 'logout' or name == 'me' or name == 'changePassword' or name == 'adminSetPassword'
  return 'users_groups' if starts_with(name, 'createUser') or starts_with(name, 'createGroup') or starts_with(name, 'deleteGroup') or starts_with(name, 'addMember') or starts_with(name, 'removeMember') or name == 'users' or name == 'user' or name == 'groups' or name == 'group' or name == 'grant' or name == 'revoke'
  return 'spaces_fields' if starts_with(name, 'space') or starts_with(name, 'createSpace') or starts_with(name, 'updateSpace') or starts_with(name, 'deleteSpace') or starts_with(name, 'addField') or starts_with(name, 'addFields') or starts_with(name, 'removeField') or starts_with(name, 'reorderFields') or starts_with(name, 'updateField') or starts_with(name, 'changeFieldType')
  return 'views' if starts_with(name, 'view') or starts_with(name, 'views') or starts_with(name, 'createView') or starts_with(name, 'updateView') or starts_with(name, 'deleteView') or starts_with(name, 'customView') or starts_with(name, 'customViews') or starts_with(name, 'createCustomView') or starts_with(name, 'updateCustomView') or starts_with(name, 'deleteCustomView')
  return 'relations' if starts_with(name, 'relation') or starts_with(name, 'relations') or starts_with(name, 'createRelation') or starts_with(name, 'updateRelation') or starts_with(name, 'deleteRelation') or starts_with(name, 'gridColumnPrefs') or starts_with(name, 'saveGridColumnPrefs')
  return 'records' if starts_with(name, 'record') or starts_with(name, 'records') or starts_with(name, 'insertRecord') or starts_with(name, 'insertRecords') or starts_with(name, 'updateRecord') or starts_with(name, 'updateRecords') or starts_with(name, 'restoreRecords') or starts_with(name, 'deleteRecord') or starts_with(name, 'deleteRecords') or starts_with(name, 'aggregateSpace')
  'misc'

collect_backend_files = ->
  run_lines "find ./backend -name '*.moon' -type f ! -path './backend/moonscript/*' | sed 's#^\\./##'"

critical_modules = {
  'backend/init.moon'
  'backend/http_server.moon'
  'backend/resolvers/init.moon'
}

is_critical = (rel_path) ->
  for c in *critical_modules
    return true if rel_path == c
  false

errors = {}

backend_files = collect_backend_files!
for rel in *backend_files
  header = read_header rel
  unless header
    table.insert errors, "missing file: #{rel}"
    continue

  if not header.summary or trim(header.summary) == '' or is_filename_banner(header.summary)
    table.insert errors, "missing meaningful Summary in #{rel}"

  if is_critical rel
    if #header.responsibilities == 0
      table.insert errors, "missing Responsibilities section in #{rel}"
    if #header.key_flows == 0
      table.insert errors, "missing Key Flows section in #{rel}"
    if #header.depends_on == 0
      table.insert errors, "missing Depends on section in #{rel}"
    if #header.used_by == 0
      table.insert errors, "missing Used by section in #{rel}"

schema_lines = do
  f = io.open './schema/tdb.graphql', 'r'
  if not f
    table.insert errors, 'missing schema/tdb.graphql'
    {}
  else
    out = {}
    for line in f\lines!
      table.insert out, line
    f\close!
    out

for row in *extract_block_rows 'Query', schema_lines
  if domain_for_operation(row.field) == 'misc'
    table.insert errors, "undocumented Query domain mapping for `#{row.field}`"

for row in *extract_block_rows 'Mutation', schema_lines
  if domain_for_operation(row.field) == 'misc'
    table.insert errors, "undocumented Mutation domain mapping for `#{row.field}`"

required_docs = {
  './doc/fr/api.md'
  './doc/en/api.md'
  './doc/fr/dev.md'
  './doc/en/dev.md'
  './doc/fr/dev/architecture.md'
  './doc/fr/dev/runtime.md'
  './doc/fr/dev/graphql.md'
  './doc/fr/dev/frontend.md'
  './doc/fr/dev/tests.md'
  './doc/en/dev/architecture.md'
  './doc/en/dev/runtime.md'
  './doc/en/dev/graphql.md'
  './doc/en/dev/frontend.md'
  './doc/en/dev/tests.md'
}
for path in *required_docs
  f = io.open path, 'r'
  if not f
    table.insert errors, "missing generated doc file: #{path}"
  else
    f\close!

if #errors > 0
  io.stderr\write "doc-check failed (#{#errors} issue(s)):\n"
  for err in *errors
    io.stderr\write "- #{err}\n"
  os.exit 1

print "doc-check OK"
os.exit 0
