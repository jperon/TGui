#!/usr/bin/env moon
-- scripts/generate_docs.moon
-- Generate English documentation from GraphQL SDL and source comments.

shell_quote = (s) ->
  "'#{tostring(s)\gsub("'", "'\\''")}'"

trim = (s) ->
  return '' unless s
  s = s\gsub '^%s+', ''
  s = s\gsub '%s+$', ''
  s

normalize_spaces = (s) ->
  return '' unless s
  s = s\gsub '%s+', ' '
  trim s

is_filename_banner = (s) ->
  return false unless s
  s = trim s
  return false if s == ''
  return true if s\match '^[%w_./-]+%.moon$'
  return true if s\match '^[%w_./-]+%.coffee$'
  return true if s\match '^[%w_./-]+%.lua$'
  false

count_char = (s, ch) ->
  n = 0
  i = 1
  while i <= #s
    n += 1 if s\sub(i, i) == ch
    i += 1
  n

run_lines = (cmd) ->
  p, err = io.popen cmd
  error "Cannot execute command: #{cmd} (#{err or 'unknown error'})" unless p
  out = p\read '*a'
  p\close!

  lines = {}
  for line in out\gmatch '[^\n]+'
    table.insert lines, line
  lines

read_lines = (path) ->
  f = assert io.open(path, 'r'), "Cannot read file: #{path}"
  lines = {}
  for line in f\lines!
    table.insert lines, line
  f\close!
  lines

write_text = (path, content) ->
  f = assert io.open(path, 'w'), "Cannot write file: #{path}"
  f\write content
  f\close!

file_exists = (path) ->
  f = io.open path, 'r'
  return false unless f
  f\close!
  true

get_root_dir = ->
  script_path = if arg and arg[0] then arg[0] else 'scripts/generate_docs.lua'
  script_dir = script_path\match('^(.*)/[^/]+$') or '.'
  cmd = "cd #{shell_quote(script_dir .. '/..')} && pwd"
  lines = run_lines cmd
  lines[1] or '.'

ROOT_DIR = get_root_dir!
SCHEMA_FILE = "#{ROOT_DIR}/schema/tdb.graphql"
DOC_EN_DIR = "#{ROOT_DIR}/doc/en"
API_EN_DOC = "#{DOC_EN_DIR}/api.md"
DEV_EN_DOC = "#{DOC_EN_DIR}/dev.md"
DEV_EN_ARCH_DOC = "#{DOC_EN_DIR}/dev/architecture.md"
DEV_EN_RUNTIME_DOC = "#{DOC_EN_DIR}/dev/runtime.md"
DEV_EN_GRAPHQL_DOC = "#{DOC_EN_DIR}/dev/graphql.md"
DEV_EN_FRONTEND_DOC = "#{DOC_EN_DIR}/dev/frontend.md"
DEV_EN_TESTS_DOC = "#{DOC_EN_DIR}/dev/tests.md"

ensure_dir = (path) ->
  os.execute "mkdir -p #{shell_quote(path)}"

write_doc = (path, lines) ->
  dir = path\match('^(.*)/[^/]+$') or '.'
  ensure_dir dir
  write_text path, table.concat(lines, '\n')

now_utc = ->
  lines = run_lines "date -u +'%Y-%m-%d %H:%M:%S UTC'"
  lines[1] or ''

parse_field_line = (line) ->
  field, args_raw, returns = line\match '^([%a_][%w_]*)%s*(%b())%s*:%s*(%S+)'
  unless field
    field, returns = line\match '^([%a_][%w_]*)%s*:%s*(%S+)'
  return nil unless field
  args = '-'
  if args_raw and #args_raw >= 2
    args = args_raw\sub 2, -2
    args = normalize_spaces args
    args = '-' if args == ''
  { field: field, args: args, returns: returns }

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

list_type_names = (kind, schema_lines) ->
  names = {}
  for raw in *schema_lines
    name = raw\match "^%s*#{kind}%s+([%w_]+)"
    table.insert names, name if name
  names

normalize_list_field = (line) ->
  line = trim line
  line = line\gsub '^[-*]%s*', ''
  line = line\gsub '^,%s*', ''
  line = trim line
  nil_or_line = if line == '' then nil else line
  nil_or_line

is_comment_line = (line) ->
  return true if line\match '^%-%-'
  return true if line\match '^#'
  false

comment_text = (line) ->
  return nil unless is_comment_line line
  if line\match '^%-%-'
    return trim line\gsub '^%-%-%s*', ''
  trim line\gsub '^#+%s*', ''

is_hash_delimiter = (text) ->
  return false unless text
  text\match '^#+$'

first_comment_line = (path) ->
  f = io.open path, 'r'
  return '(pas de description en tête de fichier)' unless f

  line_no = 0
  for raw in f\lines!
    line_no += 1
    break if line_no > 30

    line = trim raw
    continue if line == ''
    continue if line\match '^#!'

    break unless is_comment_line line

    v = comment_text line
    continue if v == ''
    continue if is_hash_delimiter v
    continue if is_filename_banner v
    f\close!
    return v

  f\close!
  '(pas de description en tête de fichier)'

read_doc_header = (path) ->
  f = io.open path, 'r'
  return {
    summary: '(missing summary)'
    responsibilities: {}
    key_flows: {}
    depends_on: {}
    used_by: {}
  } unless f

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
    break unless is_comment_line line

    text = comment_text line
    continue if text == ''
    continue if is_hash_delimiter text
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
  data.summary = '(pas de description en tête de fichier)' unless data.summary
  data

list_files = (cmd) ->
  files = run_lines cmd
  table.sort files
  files

add_file_if_exists = (files, path) ->
  table.insert files, path if file_exists path

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

DOMAIN_LABELS =
  spaces_fields: 'Spaces & Fields'
  views: 'Views'
  relations: 'Relations'
  records: 'Data (records)'
  auth: 'Authentication'
  users_groups: 'Users & Groups'
  snapshot: 'Snapshots'
  misc: 'Misc'

describe_operation = (op_name, kind) ->
  domain = domain_for_operation op_name
  if domain == 'spaces_fields'
    return "#{kind == 'query' and 'Read' or 'Mutation'} operation on space/field metadata."
  if domain == 'views'
    return "Manage standard and custom views."
  if domain == 'relations'
    return "Manage inter-space relations and column display preferences."
  if domain == 'records'
    return "Read/write user records."
  if domain == 'auth'
    return "Authentication, sessions and password lifecycle."
  if domain == 'users_groups'
    return "Administration for users, groups and permissions."
  if domain == 'snapshot'
    return "Export, diff and import configuration snapshots."
  "GraphQL operation exposed by the backend."

rows_by_domain = (rows) ->
  grouped = {}
  for row in *rows
    domain = domain_for_operation row.field
    grouped[domain] = {} unless grouped[domain]
    table.insert grouped[domain], row
  grouped

append_examples = (out) ->
  table.insert out, '## Usage Examples'
  table.insert out, ''
  table.insert out, '### 1) Authenticate then query spaces'
  table.insert out, ''
  table.insert out, '```graphql'
  table.insert out, 'mutation Login($u: String!, $p: String!) {'
  table.insert out, '  login(username: $u, password: $p) { token user { id username } }'
  table.insert out, '}'
  table.insert out, '```'
  table.insert out, ''
  table.insert out, '```graphql'
  table.insert out, 'query { spaces { id name description } }'
  table.insert out, '```'
  table.insert out, ''
  table.insert out, '### 2) Paginated records query'
  table.insert out, ''
  table.insert out, '```graphql'
  table.insert out, 'query Records($spaceId: ID!, $limit: Int!, $offset: Int!) {'
  table.insert out, '  records(spaceId: $spaceId, limit: $limit, offset: $offset) {'
  table.insert out, '    total'
  table.insert out, '    items { id data }'
  table.insert out, '  }'
  table.insert out, '}'
  table.insert out, '```'
  table.insert out, ''
  table.insert out, '### 3) Structural mutation: create space and field'
  table.insert out, ''
  table.insert out, '```graphql'
  table.insert out, 'mutation CreateSpace($input: CreateSpaceInput!) {'
  table.insert out, '  createSpace(input: $input) { id name }'
  table.insert out, '}'
  table.insert out, '```'
  table.insert out, ''
  table.insert out, '```graphql'
  table.insert out, 'mutation AddField($spaceId: ID!, $input: FieldInput!) {'
  table.insert out, '  addField(spaceId: $spaceId, input: $input) { id name fieldType }'
  table.insert out, '}'
  table.insert out, '```'
  table.insert out, ''

append_operation_groups = (out, rows, kind) ->
  grouped = rows_by_domain rows
  ordering = { 'spaces_fields', 'views', 'relations', 'records', 'auth', 'users_groups', 'snapshot', 'misc' }
  for domain in *ordering
    items = grouped[domain]
    continue unless items and #items > 0
    label = DOMAIN_LABELS[domain]
    table.insert out, "### #{label}"
    table.insert out, ''
    table.insert out, '| Operation | Arguments | Return | Description |'
    table.insert out, '|---|---|---|---|'
    for row in *items
      desc = describe_operation row.field, kind
      table.insert out, "| `#{row.field}` | `#{row.args}` | `#{row.returns}` | #{desc} |"
    table.insert out, ''

generate_api_doc = (path) ->
  schema_lines = read_lines SCHEMA_FILE
  query_rows = extract_block_rows 'Query', schema_lines
  mutation_rows = extract_block_rows 'Mutation', schema_lines
  inputs = list_type_names 'input', schema_lines
  enums = list_type_names 'enum', schema_lines

  out = {
    '# GraphQL API — TGui'
    ''
    '> Auto-generated file. Do not edit manually.'
    '>'
    "> Generated at: #{now_utc!}"
    '>'
    '> Source: `schema/tdb.graphql`'
    ''
    '## Overview'
    ''
    '- Endpoint: `/graphql`'
    '- Transport: HTTP POST JSON'
    '- Auth: Bearer token in `Authorization` header'
    '- Signature source of truth: `schema/tdb.graphql`'
    '- Runtime SDL snapshot: `schema/tdb.generated.graphql`'
    ''
    '## Queries'
    ''
  }
  append_operation_groups out, query_rows, 'query'
  table.insert out, '## Mutations'
  table.insert out, ''
  append_operation_groups out, mutation_rows, 'mutation'
  append_examples out
  table.insert out, '## Input Types'
  table.insert out, ''
  for name in *inputs
    table.insert out, "- `#{name}`"
  table.insert out, ''
  table.insert out, '## Enums'
  table.insert out, ''
  for name in *enums
    table.insert out, "- `#{name}`"
  table.insert out, ''
  table.insert out, '## Notes'
  table.insert out, ''
  table.insert out, '- Dynamic user-space types are rebuilt by backend schema reinitialization.'
  table.insert out, '- To refresh SDL runtime snapshot: `make sdl-gen`.'
  table.insert out, ''
  write_doc path, out

modules_from_rel = (rels) ->
  out = {}
  for rel in *rels
    table.insert out, "#{ROOT_DIR}/#{rel}"
  out

collect_modules = ->
  backend_files = list_files "cd #{shell_quote(ROOT_DIR)} && find ./backend -name '*.moon' -type f ! -path './backend/moonscript/*' | sed 's#^\\./##'"
  backend_abs = {}
  for rel in *backend_files
    table.insert backend_abs, "#{ROOT_DIR}/#{rel}"
  add_file_if_exists backend_abs, "#{ROOT_DIR}/backend/init.lua"
  add_file_if_exists backend_abs, "#{ROOT_DIR}/backend/html.lua"

  frontend_rel = list_files "cd #{shell_quote(ROOT_DIR)} && find ./frontend/src -name '*.coffee' -type f | sed 's#^\\./##'"
  frontend_abs = {}
  for rel in *frontend_rel
    table.insert frontend_abs, "#{ROOT_DIR}/#{rel}"

  tests_moon_rel = list_files "cd #{shell_quote(ROOT_DIR)} && find ./tests -name '*.moon' -type f | sed 's#^\\./##'"
  tests_coffee_rel = list_files "cd #{shell_quote(ROOT_DIR)} && find ./tests/js -name '*.coffee' -type f | sed 's#^\\./##'"
  tests_abs = {}
  for rel in *tests_moon_rel
    table.insert tests_abs, "#{ROOT_DIR}/#{rel}"
  for rel in *tests_coffee_rel
    table.insert tests_abs, "#{ROOT_DIR}/#{rel}"

  scripts_rel = list_files "cd #{shell_quote(ROOT_DIR)} && find ./scripts -maxdepth 1 -type f | grep -E '\\.(sh|moon|lua)$$' | sed 's#^\\./##'"
  scripts_abs = {}
  for rel in *scripts_rel
    table.insert scripts_abs, "#{ROOT_DIR}/#{rel}"

  {
    backend: backend_abs
    frontend: frontend_abs
    tests: tests_abs
    scripts: scripts_abs
  }

extract_rel = (abs_path) ->
  abs_path\gsub "^#{ROOT_DIR}/", ''

emit_module_summaries = (out, files) ->
  table.insert out, '| Module | Summary |'
  table.insert out, '|---|---|'
  for path in *files
    rel = extract_rel path
    doc = read_doc_header path
    sum = doc.summary
    sum = sum\gsub '|', '\\|'
    table.insert out, "| `#{rel}` | #{sum} |"
  table.insert out, ''

generate_dev_detail = (path, title, intro, files) ->
  out = {
    "# #{title}"
    ''
    '> Auto-generated file. Do not edit manually.'
    '>'
    "> Generated at: #{now_utc!}"
    ''
    intro
    ''
  }
  emit_module_summaries out, files
  write_doc path, out

generate_dev_compact = (path) ->
  out = {
    '# Developer Documentation — TGui'
    ''
    '> Auto-generated file. Do not edit manually.'
    '>'
    "> Generated at: #{now_utc!}"
    ''
    'Compact architecture overview for TGui. Full reference is available in `doc/en/dev/*.md`.'
    ''
    '## Architecture (summary)'
    ''
    '- Runtime entrypoint: `backend/init.moon`'
    '- HTTP edge: `backend/http_server.moon`'
    '- GraphQL execution: `backend/graphql/executor.moon`'
    '- Schema/resolver assembly: `backend/resolvers/init.moon`'
    '- Metadata engine: `backend/core/spaces.moon`'
    '- Frontend SPA shell: `frontend/src/app.coffee`'
    ''
    '## Detailed references'
    ''
    '- Global architecture: `doc/en/dev/architecture.md`'
    '- Backend runtime: `doc/en/dev/runtime.md`'
    '- GraphQL pipeline: `doc/en/dev/graphql.md`'
    '- Frontend SPA: `doc/en/dev/frontend.md`'
    '- Testing strategy: `doc/en/dev/tests.md`'
    ''
    '## Commands'
    ''
    '- Generate docs: `make doc-gen`'
    '- Check docs: `make doc-check`'
    '- Full CI: `make ci`'
    ''
  }
  write_doc path, out

generate_all_dev_docs = ->
  modules = collect_modules!
  core_backend = modules_from_rel {
    'backend/init.moon'
    'backend/http_server.moon'
    'backend/core/spaces.moon'
    'backend/core/auth.moon'
    'backend/core/permissions.moon'
    'backend/core/triggers.moon'
    'backend/core/views.moon'
    'backend/resolvers/init.moon'
  }
  graphql_backend = modules_from_rel {
    'backend/graphql/lexer.moon'
    'backend/graphql/parser.moon'
    'backend/graphql/schema.moon'
    'backend/graphql/executor.moon'
    'backend/graphql/dynamic.moon'
    'backend/graphql/introspection.moon'
    'backend/resolvers/schema_resolvers.moon'
    'backend/resolvers/data_resolvers.moon'
    'backend/resolvers/auth_resolvers.moon'
  }
  frontend_core = modules_from_rel {
    'frontend/src/app.coffee'
    'frontend/src/graphql_client.coffee'
    'frontend/src/spaces.coffee'
    'frontend/src/auth.coffee'
    'frontend/src/views/data_view.coffee'
    'frontend/src/views/custom_view.coffee'
  }

  generate_dev_compact DEV_EN_DOC

  generate_dev_detail DEV_EN_ARCH_DOC, 'Architecture — detailed reference', 'Architecture-level view of backend/frontend modules and relationships.', core_backend
  generate_dev_detail DEV_EN_RUNTIME_DOC, 'Backend runtime — detailed reference', 'Tarantool startup, HTTP lifecycle and subsystem initialization details.', modules.backend
  generate_dev_detail DEV_EN_GRAPHQL_DOC, 'GraphQL pipeline — detailed reference', 'SDL/parser/executor/resolver flow (static + dynamic).', graphql_backend
  generate_dev_detail DEV_EN_FRONTEND_DOC, 'Frontend SPA — detailed reference', 'CoffeeScript module organization and key UI flows.', frontend_core
  generate_dev_detail DEV_EN_TESTS_DOC, 'Tests — detailed reference', 'Backend/frontend test panorama and per-file intent.', modules.tests

generate_api_doc API_EN_DOC
generate_all_dev_docs!

print "Generated: #{API_EN_DOC}"
print "Generated: #{DEV_EN_DOC}"
os.exit 0
