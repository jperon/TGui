-- backend/core/app_apply.moon
-- Application atomique d'un paquet d'app (spec §4, plan « Étape 4 », ligne V3).
-- Interfaces :
--   load_package(package) -> normalized | nil, err
--   preview_update(package, opts) -> plan
--   apply_update(package, decisions, opts) -> report
--
-- Réutilise les fonctions d'écriture existantes (jamais leur logique dupliquée) :
--   space    : core.spaces.create_user_space (core/spaces.moon:319-329)
--   field    : core.spaces.add_field (349-413), update_field (478-527),
--              change_field_type (547-630)
--   relation : même insertion que do_import (resolvers/export_resolvers.moon:373-400),
--              colonnes de _tdb_relations (core/spaces.moon:135-148)
--   view     : core.views.create_view (32-38), update_view (40-50)
--   page     : insertion de do_import (export_resolvers.moon:412-415)
--   dataview : core.data_views.create_view (24-43), update_view (53-73)
--   plugin   : insertion de do_import (export_resolvers.moon:441-454)
--   group    : core.permissions.create_group (20-23)
--   perm     : core.permissions.grant (78-82)
-- Le reinit de fin suit reinit_with_formula_cache_reset! (schema_resolvers.moon:13-15)
-- et l'enregistrement des triggers suit addField (schema_resolvers.moon:122-129).
--
-- ATOMICITÉ : mesurée le 2026-10-07 dans l'instance de test (box.begin/rollback
-- annule create_user_space + add_field String/Sequence + insert _tdb_apps,
-- _tdb_app_items, _tdb_custom_views, _tdb_data_views, _tdb_widget_plugins ;
-- box.commit les persiste). L'application est donc encadrée par box.begin/commit
-- avec rollback sur erreur.

json        = require 'json'
uuid_mod    = require 'uuid'
clock       = require 'clock'
spaces_mod  = require 'core.spaces'
views_mod   = require 'core.views'
perms_mod   = require 'core.permissions'
data_views  = require 'core.data_views'
app_package = require 'core.app_package'
{ :plan_update } = require 'core.app_plan'

TYPE_ORDER = { 'space', 'field', 'relation', 'view', 'page', 'dataview', 'plugin', 'group', 'perm', 'seed' }
TYPE_RANK = { t, i for i, t in ipairs TYPE_ORDER }

-- ────────────────────────────────────────────────────────────────────────────
-- Normalisation du paquet (validation + recalcul des empreintes)
-- ────────────────────────────────────────────────────────────────────────────

-- '<scope>.<name>' coupé sur le dernier point ; miroir de app_package.split_scope_name.
_scope_name = (rest) ->
  scope, name = rest\match '^(.*)%.([^%.]+)$'
  return nil unless scope and name and scope != ''
  scope, name

_after = (key, prefix) ->
  return nil unless type(key) == 'string' and key\sub(1, #prefix) == prefix
  rest = key\sub #prefix + 1
  rest != '' and rest or nil

_normalize_item = (entry, errors) ->
  unless type(entry) == 'table'
    table.insert errors, 'package item must be a table'
    return nil
  unless type(entry.type) == 'string' and app_package.ITEM_TYPES[entry.type]
    table.insert errors, 'package item has an unknown type'
    return nil
  unless type(entry.key) == 'string' and entry.key != ''
    table.insert errors, "package item of type #{entry.type} is missing key"
    return nil
  unless type(entry.content) == 'table'
    table.insert errors, "package item #{entry.key} is missing content"
    return nil
  item = {
    type: entry.type
    key: entry.key
    content: entry.content
    fingerprint: app_package.fingerprint entry.content
  }
  item.renamed_from = entry.renamed_from if entry.renamed_from
  item

-- Best-effort : renvoie un paquet normalisé même invalide, plus la liste d'erreurs.
_normalize = (package) ->
  errors = {}
  pkg = { app: {}, items: {}, seed_keys: {} }
  unless type(package) == 'table'
    table.insert errors, 'package must be a table'
    return { package: pkg, errors: errors }
  app = package.app
  if type(app) == 'table' and type(app.id) == 'string' and app.id != ''
    pkg.app = {
      id: app.id
      name: app.name
      version: app.version
      description: app.description or ''
    }
  else
    table.insert errors, 'package app id is required'
  unless type(package.items) == 'table'
    table.insert errors, 'package items must be a list'
    return { package: pkg, errors: errors }
  for entry in *package.items
    item = _normalize_item entry, errors
    table.insert pkg.items, item if item
  pkg.seed_keys = package.seed_keys or {}
  { package: pkg, errors: errors }

-- Valide la forme et recalcule chaque empreinte depuis le contenu : une
-- empreinte fournie n'est jamais crue. Renvoie nil + erreurs si invalide.
load_package = (package) ->
  normalized = _normalize package
  return nil, table.concat(normalized.errors, '; ') if #normalized.errors > 0
  normalized.package

-- ────────────────────────────────────────────────────────────────────────────
-- Lecture de l'état installé et de l'état local
-- ────────────────────────────────────────────────────────────────────────────

_read_installed = (app_id) ->
  result = {}
  return result unless app_id
  for t in *box.space._tdb_app_items.index.by_app\select { app_id }
    result[t[2]] = {
      type: t[3], local_id: t[4], fingerprint: t[5], state: t[6], version: t[7]
    }
  result

_installed_version = (app_id) ->
  return nil unless app_id
  t = box.space._tdb_apps\get app_id
  t and t[3] or nil

_local_state = (item_type, key) ->
  content = app_package.describe_local item_type, key
  return nil unless content
  { fingerprint: app_package.fingerprint(content), content: content }

-- local_states pour toutes les clés concernées : clés du paquet, clés
-- installées, et clés d'où l'on renomme.
_build_local_states = (package, installed) ->
  types = {}
  for it in *package.items
    types[it.key] = it.type if it.key
    types[it.renamed_from] = it.type if it.renamed_from
  for key, info in pairs installed
    types[key] = info.type
  states = {}
  for key, item_type in pairs types
    state = _local_state item_type, key
    states[key] = state if state
  states

-- ────────────────────────────────────────────────────────────────────────────
-- Plan
-- ────────────────────────────────────────────────────────────────────────────

_error_plan = (errors) ->
  {
    create: {}, update: {}, conflict: {}, keep_local: {}, obsolete: {},
    rename: {}, unchanged: {}, errors: errors
  }

_effective_opts = (app_id, opts) ->
  {
    allow_downgrade: opts.allow_downgrade
    installed_version: _installed_version(app_id) or opts.installed_version
  }

preview_update = (package, opts) ->
  opts or= {}
  normalized = _normalize package
  return _error_plan(normalized.errors) if #normalized.errors > 0
  pkg = normalized.package
  installed = _read_installed pkg.app.id
  local_states = _build_local_states pkg, installed
  plan_update installed, pkg, local_states, _effective_opts(pkg.app.id, opts)

-- ────────────────────────────────────────────────────────────────────────────
-- Ordonnancement et petits utilitaires
-- ────────────────────────────────────────────────────────────────────────────

_order = (entries) ->
  copy = [e for e in *entries]
  table.sort copy, (a, b) ->
    ra = TYPE_RANK[a.type] or 99
    rb = TYPE_RANK[b.type] or 99
    if ra != rb
      ra < rb
    else
      a.key < b.key
  copy

_order_conflicts = (conflicts) ->
  copy = [c for c in *conflicts]
  table.sort copy, (a, b) ->
    ra = TYPE_RANK[a[1].type] or 99
    rb = TYPE_RANK[b[1].type] or 99
    if ra != rb
      ra < rb
    else
      a[1].key < b[1].key
  copy

_skip = (entry, report) ->
  if entry.renamed_from
    table.insert report.skipped, { key: entry.key, reason: 'rename (V3b)' }
    return true
  false

_check_decisions = (conflicts, decisions) ->
  for c in *conflicts
    entry = c[1]
    continue if entry.type == 'seed' or entry.renamed_from
    d = decisions[entry.key]
    unless d == 'local' or d == 'delivered'
      return "conflict on '#{entry.key}' requires a decision ('local' or 'delivered')"
  nil

_empty_report = ->
  {
    ok: false, error: nil, reinit_error: nil
    created: {}, updated: {}, unchanged: {}, kept: {}, obsolete: {}, skipped: {}
    conflicts: {}
  }

_abort = (report, errors) ->
  report.ok = false
  report.error = table.concat errors, '; '
  report

-- ────────────────────────────────────────────────────────────────────────────
-- Résolution des identifiants locaux et de l'espace
-- ────────────────────────────────────────────────────────────────────────────

_space_id = (name) ->
  sp = spaces_mod.get_space_by_name name
  error "unknown space '#{name}'" unless sp
  sp.id

_field_id = (space_id, field_name) ->
  for f in *spaces_mod.list_fields space_id
    return f.id if f.name == field_name
  error "unknown field '#{field_name}'"

_resource_name = (resource_id) ->
  return '*' if resource_id == nil or resource_id == perms_mod.WILDCARD_ID
  t = box.space._tdb_spaces\get resource_id
  t and t[2] or resource_id

_find_group_by_name = (name) ->
  for g in *perms_mod.list_groups!
    return g if g.name == name
  nil

_resolve_field_id = (key) ->
  rest = _after key, 'field:'
  return nil unless rest
  sp_name, f_name = _scope_name rest
  sp = sp_name and spaces_mod.get_space_by_name sp_name
  return nil unless sp
  for f in *spaces_mod.list_fields sp.id
    return f.id if f.name == f_name
  nil

_resolve_relation_id = (key) ->
  rest = _after key, 'relation:'
  return nil unless rest
  sp_name, f_name = _scope_name rest
  sp = sp_name and spaces_mod.get_space_by_name sp_name
  return nil unless sp
  for t in *box.space._tdb_relations.index.by_from\select { sp.id }
    fld = box.space._tdb_fields\get t[3]
    return t[1] if fld and fld[3] == f_name
  nil

_resolve_view_id = (key) ->
  rest = _after key, 'view:'
  return nil unless rest
  sp_name, v_name = _scope_name rest
  sp = sp_name and spaces_mod.get_space_by_name sp_name
  return nil unless sp
  for v in *views_mod.list_views sp.id
    return v.id if v.name == v_name
  nil

_resolve_perm_id = (key) ->
  rest = _after key, 'perm:'
  return nil unless rest
  parts = [p for p in rest\gmatch '[^|]+']
  return nil unless #parts == 4
  group = _find_group_by_name parts[1]
  return nil unless group
  for p in *perms_mod.list_permissions group.id
    match = p.resourceType == parts[2] and p.level == parts[4]
    return p.id if match and _resource_name(p.resourceId) == parts[3]
  nil

_page_by_name = (name) ->
  for row in *box.space._tdb_custom_views\select {}
    return row if row[2] == name
  nil

_resolve_page_id = (key) ->
  name = _after key, 'page:'
  row = name and _page_by_name name
  row and row[1]

_resolve_dataview_id = (key) ->
  name = _after key, 'dataview:'
  v = name and data_views.get_view_by_name name
  v and v.id

_resolve_plugin_id = (key) ->
  name = _after key, 'plugin:'
  row = name and box.space._tdb_widget_plugins.index.by_name\get name
  row and row[1]

_resolve_group_id = (key) ->
  name = _after key, 'group:'
  g = name and _find_group_by_name name
  g and g.id

-- Dispatch défini après tous les résolveurs de type (en Lua, un upvalue
-- référencé avant sa déclaration locale deviendrait une globale nil).
_resolve_local_id = (item_type, key) ->
  return nil unless key
  if item_type == 'space'
    name = _after key, 'space:'
    sp = name and spaces_mod.get_space_by_name name
    return sp and sp.id
  return _resolve_field_id key if item_type == 'field'
  return _resolve_relation_id key if item_type == 'relation'
  return _resolve_view_id key if item_type == 'view'
  return _resolve_page_id key if item_type == 'page'
  return _resolve_dataview_id key if item_type == 'dataview'
  return _resolve_plugin_id key if item_type == 'plugin'
  return _resolve_group_id key if item_type == 'group'
  return _resolve_perm_id key if item_type == 'perm'
  nil

-- ────────────────────────────────────────────────────────────────────────────
-- Opérations par type d'élément
-- ────────────────────────────────────────────────────────────────────────────

_create_space = (entry) ->
  name = _after entry.key, 'space:'
  sp = spaces_mod.create_user_space name, entry.content.description or ''
  { id: sp.id, space: name }

_update_space = (entry, old) ->
  t = box.space._tdb_spaces\get old.local_id
  error "space not found: #{old.local_id}" unless t
  box.space._tdb_spaces\replace { t[1], t[2], entry.content.description or '', t[4], os.time! }
  { id: t[1], space: t[2] }

_create_field = (entry) ->
  rest = _after entry.key, 'field:'
  sp_name, f_name = _scope_name rest
  error "invalid field key '#{entry.key}'" unless sp_name
  sid = _space_id sp_name
  c = entry.content
  f = spaces_mod.add_field sid, f_name, c.fieldType, c.notNull or false,
    c.description or '', c.formula or '', c.triggerFields or {}, c.language or 'lua'
  { id: f.id, space: sp_name }

_update_field = (entry, old) ->
  rest = _after entry.key, 'field:'
  sp_name, f_name = _scope_name rest
  fid = old.local_id
  t = box.space._tdb_fields\get fid
  error "field not found: #{tostring fid}" unless t
  c = entry.content
  if c.fieldType and t[4] != c.fieldType
    spaces_mod.change_field_type fid, c.fieldType
  spaces_mod.update_field fid, {
    notNull: c.notNull
    description: c.description
    formula: c.formula
    triggerFields: c.triggerFields
    language: c.language
  }
  { id: fid, space: sp_name }

_create_relation = (entry) ->
  rest = _after entry.key, 'relation:'
  from_sp, from_fld = _scope_name rest
  error "invalid relation key '#{entry.key}'" unless from_sp
  c = entry.content
  from_sid = _space_id from_sp
  to_sid = _space_id c.toSpace
  from_fid = _field_id from_sid, from_fld
  to_fid = _field_id to_sid, c.toField
  rid = tostring uuid_mod.new!
  box.space._tdb_relations\insert {
    rid, from_sid, from_fid, to_sid, to_fid, "#{from_sp}_#{from_fld}", ''
  }
  { id: rid, space: from_sp }

_update_relation = (entry, old) ->
  rest = _after entry.key, 'relation:'
  from_sp, from_fld = _scope_name rest
  c = entry.content
  to_sid = _space_id c.toSpace
  to_fid = _field_id to_sid, c.toField
  box.space._tdb_relations\update old.local_id, {
    { '=', 4, to_sid }
    { '=', 5, to_fid }
  }
  { id: old.local_id, space: from_sp }

_create_view = (entry) ->
  c = entry.content
  sid = _space_id c.space
  v = views_mod.create_view sid, c.name, c.viewType, c.config
  { id: v.id, space: c.space }

_update_view = (entry, old) ->
  c = entry.content
  views_mod.update_view old.local_id, { name: c.name, viewType: c.viewType, config: c.config }
  { id: old.local_id, space: c.space }

_create_page = (entry) ->
  c = entry.content
  id = tostring uuid_mod.new!
  now = clock.time!
  box.space._tdb_custom_views\insert {
    id, c.name, c.description or '', c.yaml or '', now, now
  }
  { id: id }

_update_page = (entry, old) ->
  c = entry.content
  box.space._tdb_custom_views\update old.local_id, {
    { '=', 3, c.description or '' }
    { '=', 4, c.yaml or '' }
    { '=', 6, clock.time! }
  }
  { id: old.local_id }

_config_json = (config) ->
  return '{}' if config == nil
  return config if type(config) == 'string'
  json.encode config

_create_dataview = (entry) ->
  c = entry.content
  sid = _space_id c.sourceSpace
  v = data_views.create_view c.name, c.description or '', sid, _config_json(c.config)
  { id: v.id }

_update_dataview = (entry, old) ->
  c = entry.content
  sid = _space_id c.sourceSpace
  data_views.update_view old.local_id, {
    name: c.name, description: c.description or '', sourceSpace: sid, config: _config_json(c.config)
  }
  { id: old.local_id }

_create_plugin = (entry) ->
  c = entry.content
  id = tostring uuid_mod.new!
  now = clock.time!
  box.space._tdb_widget_plugins\insert {
    id, c.name, c.description or '', c.scriptLanguage or 'coffeescript',
    c.templateLanguage or 'pug', c.scriptCode or '', c.templateCode or '', now, now
  }
  { id: id }

_update_plugin = (entry, old) ->
  c = entry.content
  box.space._tdb_widget_plugins\update old.local_id, {
    { '=', 3, c.description or '' }
    { '=', 4, c.scriptLanguage or 'coffeescript' }
    { '=', 5, c.templateLanguage or 'pug' }
    { '=', 6, c.scriptCode or '' }
    { '=', 7, c.templateCode or '' }
    { '=', 9, clock.time! }
  }
  { id: old.local_id }

_create_group = (entry) ->
  c = entry.content
  g = perms_mod.create_group c.name, c.description
  { id: g.id }

_update_group = (entry, old) ->
  box.space._tdb_groups\update old.local_id, { { '=', 3, entry.content.description or '' } }
  { id: old.local_id }

_resource_id = (resource) ->
  return perms_mod.WILDCARD_ID if resource == nil or resource == '' or resource == '*'
  sp = spaces_mod.get_space_by_name resource
  sp and sp.id or resource

_create_perm = (entry) ->
  c = entry.content
  group = _find_group_by_name c.group
  error "unknown group '#{c.group}'" unless group
  p = perms_mod.grant group.id, c.resourceType or 'space', _resource_id(c.resource), c.level
  { id: p.id }

EXECUTORS =
  space:    { create: _create_space,    update: _update_space }
  field:    { create: _create_field,    update: _update_field }
  relation: { create: _create_relation, update: _update_relation }
  view:     { create: _create_view,     update: _update_view }
  page:     { create: _create_page,     update: _update_page }
  dataview: { create: _create_dataview, update: _update_dataview }
  plugin:   { create: _create_plugin,   update: _update_plugin }
  group:    { create: _create_group,    update: _update_group }
  perm:     { create: _create_perm }

-- ────────────────────────────────────────────────────────────────────────────
-- Exécution (transactionnelle)
-- ────────────────────────────────────────────────────────────────────────────

_record = (app_id, version, item_type, key, local_id, fingerprint, state) ->
  box.space._tdb_app_items\replace {
    app_id, key, item_type, local_id or '', fingerprint, state or 'actif', version
  }

_record_kept = (ctx, entry, old, fingerprint) ->
  local_id = old and old.local_id or _resolve_local_id(entry.type, entry.key)
  _record ctx.pkg.app.id, ctx.pkg.app.version, entry.type, entry.key, local_id, fingerprint, 'actif'

_do_creates = (ctx) ->
  for entry in *_order ctx.plan.create
    continue if _skip entry, ctx.report
    continue if entry.type == 'seed'
    ex = EXECUTORS[entry.type]
    error "unsupported type '#{entry.type}'" unless ex and ex.create
    result = ex.create entry
    _record ctx.pkg.app.id, ctx.pkg.app.version, entry.type, entry.key, result.id, entry.fingerprint, 'actif'
    table.insert ctx.report.created, entry.key
    ctx.touched[result.space] = true if result.space

_do_updates = (ctx) ->
  for entry in *_order ctx.plan.update
    continue if _skip entry, ctx.report
    continue if entry.type == 'seed'
    old = ctx.installed[entry.key]
    error "cannot update unknown item '#{entry.key}'" unless old
    ex = EXECUTORS[entry.type]
    error "unsupported type '#{entry.type}'" unless ex and ex.update
    result = ex.update entry, old
    _record ctx.pkg.app.id, ctx.pkg.app.version, entry.type, entry.key, result.id, entry.fingerprint, 'actif'
    table.insert ctx.report.updated, entry.key
    ctx.touched[result.space] = true if result.space

_do_conflicts = (ctx) ->
  for c in *_order_conflicts ctx.plan.conflict
    entry = c[1]
    continue if _skip entry, ctx.report
    continue if entry.type == 'seed'
    old = ctx.installed[entry.key]
    resolution = ctx.decisions[entry.key]
    if resolution == 'delivered'
      ex = EXECUTORS[entry.type]
      error "unsupported type '#{entry.type}'" unless ex and ex.update
      result = ex.update entry, old
      _record ctx.pkg.app.id, ctx.pkg.app.version, entry.type, entry.key, result.id, entry.fingerprint, 'actif'
      ctx.touched[result.space] = true if result.space
    else
      _record_kept ctx, entry, old, entry.fingerprint
    table.insert ctx.report.conflicts, { key: entry.key, resolution: resolution }

_do_keep_local = (ctx) ->
  for entry in *_order ctx.plan.keep_local
    continue if _skip entry, ctx.report
    continue if entry.type == 'seed'
    _record_kept ctx, entry, ctx.installed[entry.key], entry.fingerprint
    table.insert ctx.report.kept, entry.key

_do_unchanged = (ctx) ->
  for key in *ctx.plan.unchanged
    item = ctx.pkg_map[key]
    continue unless item
    continue if item.type == 'seed'
    old = ctx.installed[key]
    local_id = old and old.local_id or _resolve_local_id(item.type, key)
    _record ctx.pkg.app.id, ctx.pkg.app.version, item.type, key, local_id, item.fingerprint, 'actif'
    table.insert ctx.report.unchanged, key

-- ────────────────────────────────────────────────────────────────────────────
-- PARTIE 2 (V3b) : lignes seed
-- Un item seed a pour clé `seed:<espace>|<valeur>` et content {space, key, data}
-- (app_package.seed_content). Jamais de suppression d'enregistrement :
--   create    → insère { id_uuid, json.encode(data) } (comme insertRecord,
--               resolvers/data_resolvers.moon:100-112), valeurs livrées ;
--   update    → remplace l'enregistrement local par les données livrées ;
--   keep_local/conflits → l'enregistrement local est conservé tel quel.
-- L'enregistrement local est retrouvé par local_id de _tdb_app_items, sinon par
-- la valeur de clé naturelle dans le champ désigné par pkg.seed_keys.
-- ────────────────────────────────────────────────────────────────────────────

_decode = (blob) ->
  return blob if type(blob) == 'table'
  return {} unless type(blob) == 'string'
  ok, d = pcall json.decode, blob
  (ok and type(d) == 'table') and d or {}

_effective_old = (ctx, entry) ->
  ctx.installed[entry.key] or (entry.renamed_from and ctx.installed[entry.renamed_from])

_find_seed_id = (ctx, entry) ->
  c = entry.content
  key_field = ctx.pkg.seed_keys[c.space]
  sp = box.space["data_#{c.space}"]
  return nil unless sp and key_field
  for t in *sp\select {}
    v = _decode(t[2])[key_field]
    return t[1] if v != nil and tostring(v) == tostring(c.key)
  nil

_seed_local_id = (ctx, entry, old) ->
  if old and old.local_id and old.local_id != ''
    sp = box.space["data_#{entry.content.space}"]
    return old.local_id if sp and sp\get old.local_id
  _find_seed_id ctx, entry

_seed_create = (ctx, entry) ->
  c = entry.content
  sp = box.space["data_#{c.space}"]
  error "unknown seed space '#{c.space}'" unless sp
  id = tostring uuid_mod.new!
  sp\insert { id, json.encode c.data }
  _record ctx.pkg.app.id, ctx.pkg.app.version, 'seed', entry.key, id, entry.fingerprint, 'actif'
  table.insert ctx.report.created, entry.key

_seed_update = (ctx, entry, old) ->
  c = entry.content
  sp = box.space["data_#{c.space}"]
  error "unknown seed space '#{c.space}'" unless sp
  id = _seed_local_id ctx, entry, old
  if id
    sp\replace { id, json.encode c.data }
  else
    id = tostring uuid_mod.new!
    sp\insert { id, json.encode c.data }
  _record ctx.pkg.app.id, ctx.pkg.app.version, 'seed', entry.key, id, entry.fingerprint, 'actif'
  table.insert ctx.report.updated, entry.key

_seed_keep = (ctx, entry, old) ->
  id = _seed_local_id ctx, entry, old
  _record ctx.pkg.app.id, ctx.pkg.app.version, 'seed', entry.key, id or '', entry.fingerprint, 'actif'
  table.insert ctx.report.kept, entry.key

_seed_unchanged = (ctx, entry) ->
  old = _effective_old ctx, entry
  id = (old and old.local_id) or _find_seed_id(ctx, entry)
  _record ctx.pkg.app.id, ctx.pkg.app.version, 'seed', entry.key, id or '', entry.fingerprint, 'actif'
  table.insert ctx.report.unchanged, entry.key

_do_seeds = (ctx) ->
  for entry in *_order ctx.plan.create
    _seed_create ctx, entry if entry.type == 'seed'
  for entry in *_order ctx.plan.update
    _seed_update ctx, entry, _effective_old(ctx, entry) if entry.type == 'seed'
  for c in *_order_conflicts ctx.plan.conflict
    _seed_keep ctx, c[1], _effective_old(ctx, c[1]) if c[1].type == 'seed'
  for entry in *_order ctx.plan.keep_local
    _seed_keep ctx, entry, _effective_old(ctx, entry) if entry.type == 'seed'
  for key in *ctx.plan.unchanged
    item = ctx.pkg_map[key]
    _seed_unchanged ctx, item if item and item.type == 'seed'

-- PARTIE 1 (V3b) : un élément installé absent du nouveau paquet passe à
-- state = 'obsolète'. L'élément local n'est ni supprimé ni modifié : seule sa
-- ligne de suivi change, avec ses valeurs installées conservées.
_do_obsolete = (ctx) ->
  for key in *ctx.plan.obsolete
    old = ctx.installed[key]
    continue unless old
    _record ctx.pkg.app.id, (old.version or ctx.pkg.app.version), old.type, key,
      old.local_id, old.fingerprint, 'obsolète'

_write_app = (app, opts) ->
  existing = box.space._tdb_apps\get app.id
  source = opts.source or (existing and existing[5]) or 'package'
  name = app.name or (existing and existing[2]) or ''
  version = app.version or (existing and existing[3]) or ''
  box.space._tdb_apps\replace { app.id, name, version, os.time!, source }

_transaction = (ctx) ->
  box.begin!
  _do_creates ctx
  _do_updates ctx
  _do_conflicts ctx
  _do_keep_local ctx
  _do_unchanged ctx
  _do_seeds ctx
  _do_obsolete ctx
  _write_app ctx.pkg.app, ctx.opts
  box.commit!

_do_apply = (plan, pkg, pkg_map, decisions, opts, installed, report) ->
  ctx = {
    plan: plan, pkg: pkg, pkg_map: pkg_map, decisions: decisions,
    opts: opts, installed: installed, report: report, touched: {}
  }
  ok, err = pcall _transaction, ctx
  unless ok
    pcall -> box.rollback! if box.is_in_txn!
    return tostring err
  report.touched = ctx.touched
  nil

_finalize = (report, touched) ->
  executor = require 'graphql.executor'
  triggers = require 'core.triggers'
  ok, err = pcall ->
    executor.reinit_schema!
    triggers.invalidate_formula_cache!
  report.reinit_error = tostring(err) unless ok
  for name, _ in pairs touched
    pcall triggers.register_space_trigger, name

apply_update = (package, decisions, opts) ->
  decisions or= {}
  opts or= {}
  report = _empty_report!
  normalized = _normalize package
  return _abort report, normalized.errors if #normalized.errors > 0
  pkg = normalized.package
  pkg_map = {}
  for it in *pkg.items
    pkg_map[it.key] = it
  installed = _read_installed pkg.app.id
  local_states = _build_local_states pkg, installed
  plan = plan_update installed, pkg, local_states, _effective_opts(pkg.app.id, opts)
  return _abort report, plan.errors if #plan.errors > 0
  conflict_error = _check_decisions plan.conflict, decisions
  return _abort report, { conflict_error } if conflict_error
  for key in *plan.obsolete
    table.insert report.obsolete, key
  err = _do_apply plan, pkg, pkg_map, decisions, opts, installed, report
  return _abort report, { err } if err
  report.ok = true
  _finalize report, report.touched
  report

{ :load_package, :preview_update, :apply_update }
