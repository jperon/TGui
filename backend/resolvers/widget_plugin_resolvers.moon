-- resolvers/widget_plugin_resolvers.moon
-- CRUD resolvers for custom widget plugins used by custom views.

uuid_mod = require 'uuid'
clock = require 'clock'
yaml = require 'yaml'
{ :require_auth, :require_perm } = require 'resolvers.utils'

VALID_SCRIPT_LANGS = {
  coffeescript: true
  javascript: true
}

VALID_TEMPLATE_LANGS = {
  pug: true
  html: true
}

MAX_NAME_LEN = 120
MAX_DESC_LEN = 2000
MAX_CODE_LEN = 200000

normalize_script_lang = (lang) ->
  l = tostring(lang or 'coffeescript')
  string.lower l

normalize_template_lang = (lang) ->
  l = tostring(lang or 'pug')
  string.lower l

validate_name = (name) ->
  n = tostring(name or '')
  error 'WidgetPlugin name is required' if n == ''
  error "WidgetPlugin name too long: #{#n}" if #n > MAX_NAME_LEN
  ok = n\find '^[%a_][%w_%-]*$'
  error 'WidgetPlugin name must match [A-Za-z_][A-Za-z0-9_-]*' unless ok
  n

validate_description = (description) ->
  d = tostring(description or '')
  error "WidgetPlugin description too long: #{#d}" if #d > MAX_DESC_LEN
  d

validate_script_code = (code) ->
  c = tostring(code or '')
  error 'WidgetPlugin scriptCode is required' if c == ''
  error "WidgetPlugin scriptCode too long: #{#c}" if #c > MAX_CODE_LEN
  c

validate_template_code = (code) ->
  c = tostring(code or '')
  error 'WidgetPlugin templateCode is required' if c == ''
  error "WidgetPlugin templateCode too long: #{#c}" if #c > MAX_CODE_LEN
  c

validate_script_lang = (lang) ->
  l = normalize_script_lang lang
  error "Unsupported script language: #{l}" unless VALID_SCRIPT_LANGS[l]
  l

validate_template_lang = (lang) ->
  l = normalize_template_lang lang
  error "Unsupported template language: #{l}" unless VALID_TEMPLATE_LANGS[l]
  l

-- ────────────────────────────────────────────────────────────────────────────
-- Manifest (spec docs/superpowers/specs/2026-11-16-custom-widgets-design.md §3)
-- Optional YAML text declaring the source columns the widget expects, its typed
-- options and its data `access`. Stored as written (comments and defaults are
-- kept); only validated here, so a bad manifest never reaches a page.
-- ────────────────────────────────────────────────────────────────────────────

MAX_MANIFEST_LEN = 20000
VALID_ACCESS = { none: true, read: true, full: true }

-- A YAML mapping decodes to a table with string keys, a sequence to a table
-- with integer keys (Tarantool's yaml module). An empty table is ambiguous and
-- is accepted as either.
is_mapping = (value) ->
  return false unless type(value) == 'table'
  for key in pairs value
    return true if type(key) == 'string'
  false

is_sequence = (value) ->
  type(value) == 'table' and not is_mapping value

manifest_error = (msg) ->
  error "WidgetPlugin manifest: #{msg}"

manifest_name = (entry, where) ->
  name = entry.name
  unless type(name) == 'string' and name != ''
    manifest_error "#{where}.name is required and must be a string"
  unless name\match '^[%a_][%w_%-]*$'
    manifest_error "#{where}.name must match [A-Za-z_][A-Za-z0-9_-]*"
  name

validate_manifest_entries = (entries, field) ->
  return unless entries != nil
  unless is_sequence entries
    manifest_error "#{field} must be a list of {name, type, ...} entries"
  seen = {}
  index = 0
  for entry in *entries
    index += 1
    where = "#{field}[#{index}]"
    unless is_mapping entry
      manifest_error "#{where} must be a mapping like {name: titre, type: String}"
    name = manifest_name entry, where
    if seen[name]
      singular = if field == 'columns' then 'column' else 'option'
      manifest_error "duplicate #{singular} name: #{name}"
    seen[name] = true
    unless type(entry.type) == 'string' and entry.type != ''
      manifest_error "#{where}.type is required and must be a string"
  nil

validate_manifest_columns = (columns) ->
  validate_manifest_entries columns, 'columns'
  return unless columns != nil
  index = 0
  for entry in *columns
    index += 1
    if entry.optional != nil and type(entry.optional) != 'boolean'
      manifest_error "columns[#{index}].optional must be a boolean"
  nil

validate_manifest_options = (options) ->
  validate_manifest_entries options, 'options'
  return unless options != nil
  index = 0
  for entry in *options
    index += 1
    default = entry.default
    if default != nil and default != box.NULL
      t = type default
      unless t == 'string' or t == 'number' or t == 'boolean'
        manifest_error "options[#{index}].default must be a scalar"
  nil

-- Returns the manifest text to store ('' when absent or comment-only). Raises
-- with a field-precise message (columns[2].name, options[1].type, access) so
-- the editor can show it next to the YAML.
validate_manifest = (text) ->
  raw = if text == nil then '' else tostring text
  return '' if raw\match '^%s*$'
  error "WidgetPlugin manifest too long: #{#raw}" if #raw > MAX_MANIFEST_LEN
  ok, parsed = pcall yaml.decode, raw
  unless ok
    manifest_error "invalid YAML: #{tostring parsed}"
  -- Comment-only text decodes to nil: no manifest, not an error.
  return '' if parsed == nil
  unless type(parsed) == 'table'
    manifest_error 'must be a YAML mapping (access, columns, options)'
  if is_sequence(parsed) and next(parsed) != nil
    manifest_error 'must be a YAML mapping (access, columns, options)'
  if parsed.access != nil and parsed.access != box.NULL
    access = tostring parsed.access
    unless VALID_ACCESS[access]
      manifest_error "access must be one of none, read, full (got '#{access}')"
  validate_manifest_columns parsed.columns
  validate_manifest_options parsed.options
  raw

tuple_to_plugin = (t) ->
  return nil unless t
  {
    id: t[1]
    name: t[2]
    description: t[3] or ''
    scriptLanguage: t[4] or 'coffeescript'
    templateLanguage: t[5] or 'pug'
    scriptCode: t[6] or ''
    templateCode: t[7] or ''
    manifest: t[10] or ''
    createdAt: tostring t[8]
    updatedAt: tostring t[9]
  }

list_widget_plugins = ->
  result = {}
  for t in *box.space._tdb_widget_plugins\select {}
    table.insert result, tuple_to_plugin t
  table.sort result, (a, b) -> a.name < b.name
  result

get_widget_plugin = (id, name) ->
  t = nil
  if id
    t = box.space._tdb_widget_plugins\get id
  elseif name
    t = box.space._tdb_widget_plugins.index.by_name\get name
  tuple_to_plugin t

assert_unique_name = (name, ignore_id = nil) ->
  existing = box.space._tdb_widget_plugins.index.by_name\get name
  if existing and existing[1] != ignore_id
    error "WidgetPlugin name already exists: #{name}"

create_widget_plugin = (input) ->
  name = validate_name input.name
  description = validate_description input.description
  script_lang = validate_script_lang input.scriptLanguage
  template_lang = validate_template_lang input.templateLanguage
  script_code = validate_script_code input.scriptCode
  template_code = validate_template_code input.templateCode
  manifest = validate_manifest input.manifest

  assert_unique_name name

  id = tostring uuid_mod.new!
  now = clock.time!
  box.space._tdb_widget_plugins\insert { id, name, description, script_lang, template_lang, script_code, template_code, now, now, manifest }
  tuple_to_plugin box.space._tdb_widget_plugins\get id

update_widget_plugin = (id, input) ->
  t = box.space._tdb_widget_plugins\get id
  error "WidgetPlugin not found: #{id}" unless t

  name = if input.name != nil then validate_name(input.name) else t[2]
  description = if input.description != nil then validate_description(input.description) else (t[3] or '')
  script_lang = if input.scriptLanguage != nil then validate_script_lang(input.scriptLanguage) else (t[4] or 'coffeescript')
  template_lang = if input.templateLanguage != nil then validate_template_lang(input.templateLanguage) else (t[5] or 'pug')
  script_code = if input.scriptCode != nil then validate_script_code(input.scriptCode) else (t[6] or '')
  template_code = if input.templateCode != nil then validate_template_code(input.templateCode) else (t[7] or '')
  manifest = if input.manifest != nil then validate_manifest(input.manifest) else (t[10] or '')

  assert_unique_name name, id

  now = clock.time!
  box.space._tdb_widget_plugins\replace { id, name, description, script_lang, template_lang, script_code, template_code, t[8], now, manifest }
  tuple_to_plugin box.space._tdb_widget_plugins\get id

delete_widget_plugin = (id) ->
  box.space._tdb_widget_plugins\delete id
  true

Query =
  widgetPlugins: (_, args, ctx) ->
    require_perm ctx, '*', nil, 'read'
    list_widget_plugins!

  widgetPlugin: (_, args, ctx) ->
    require_perm ctx, '*', nil, 'read'
    if not args.id and not args.name
      error 'widgetPlugin requires id or name'
    get_widget_plugin args.id, args.name

Mutation =
  -- Widget plugin code runs in the browser of whoever opens a page (sandboxed
  -- iframe): writing a definition is equivalent to running code in another
  -- user's session, so it requires the admin level, like deleteWidgetPlugin.
  -- Spec docs/superpowers/specs/2026-11-16-custom-widgets-design.md §6.
  createWidgetPlugin: (_, args, ctx) ->
    require_perm ctx, '*', nil, 'admin'
    create_widget_plugin args.input or {}

  updateWidgetPlugin: (_, args, ctx) ->
    require_perm ctx, '*', nil, 'admin'
    update_widget_plugin args.id, args.input or {}

  deleteWidgetPlugin: (_, args, ctx) ->
    require_perm ctx, '*', nil, 'admin'
    delete_widget_plugin args.id

{ :Query, :Mutation, :validate_manifest }
