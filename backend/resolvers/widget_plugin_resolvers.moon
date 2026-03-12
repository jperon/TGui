-- resolvers/widget_plugin_resolvers.moon
-- CRUD resolvers for custom widget plugins used by custom views.

uuid_mod = require 'uuid'
clock = require 'clock'
{ :require_auth } = require 'resolvers.utils'

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

  assert_unique_name name

  id = tostring uuid_mod.new!
  now = clock.time!
  box.space._tdb_widget_plugins\insert { id, name, description, script_lang, template_lang, script_code, template_code, now, now }
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

  assert_unique_name name, id

  now = clock.time!
  box.space._tdb_widget_plugins\replace { id, name, description, script_lang, template_lang, script_code, template_code, t[8], now }
  tuple_to_plugin box.space._tdb_widget_plugins\get id

delete_widget_plugin = (id) ->
  box.space._tdb_widget_plugins\delete id
  true

Query =
  widgetPlugins: (_, args, ctx) ->
    require_auth ctx
    list_widget_plugins!

  widgetPlugin: (_, args, ctx) ->
    require_auth ctx
    if not args.id and not args.name
      error 'widgetPlugin requires id or name'
    get_widget_plugin args.id, args.name

Mutation =
  createWidgetPlugin: (_, args, ctx) ->
    require_auth ctx
    create_widget_plugin args.input or {}

  updateWidgetPlugin: (_, args, ctx) ->
    require_auth ctx
    update_widget_plugin args.id, args.input or {}

  deleteWidgetPlugin: (_, args, ctx) ->
    require_auth ctx
    delete_widget_plugin args.id

{ :Query, :Mutation }
