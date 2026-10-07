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
-- Les deux composantes sont décodées (app_package.unkey_part) : tous les points
-- d'un nom sont échappés par app_package.key_part.
_scope_name = (rest) ->
  scope, name = rest\match '^(.*)%.([^%.]+)$'
  return nil unless scope and name and scope != ''
  app_package.unkey_part(scope), app_package.unkey_part(name)

_after = (key, prefix) ->
  return nil unless type(key) == 'string' and key\sub(1, #prefix) == prefix
  rest = key\sub #prefix + 1
  rest != '' and rest or nil

_split_scope = (key, prefix) ->
  rest = _after key, prefix
  return nil unless rest
  _scope_name rest

-- Normalisation à la frontière de lecture (task T22) : strip_null retire les
-- box.NULL issus d'un parseur YAML standard (`description: null`, `~`, liste),
-- puis normalize_content ramène le contenu à la forme canonique des builders
-- app_package.*_content. L'empreinte du paquet redevient alors égale à celle de
-- l'état local identique, et formula/triggerFields ne sont jamais nil.
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
  content = app_package.normalize_content entry.type, app_package.strip_null entry.content
  item = {
    type: entry.type
    key: entry.key
    content: content
    fingerprint: app_package.fingerprint content
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
      description: app_package.strip_null(app.description) or ''
    }
  else
    table.insert errors, 'package app id is required'
  unless type(package.items) == 'table'
    table.insert errors, 'package items must be a list'
    return { package: pkg, errors: errors }
  for entry in *package.items
    item = _normalize_item entry, errors
    table.insert pkg.items, item if item
  pkg.seed_keys = app_package.strip_null(package.seed_keys) or {}
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

-- ────────────────────────────────────────────────────────────────────────────
-- PARTIE 3 (V3b) : expansion des renommages d'espace
-- Un item `space:<nouveau>` portant renamed_from = `space:<ancien>` fait de
-- chaque enfant `field|relation|view:<nouveau>.x` (et `seed:<nouveau>|x`) un
-- renommage implicite depuis `<ancien>` si l'ancienne clé est installée : sans
-- cela les enfants seraient vus comme de nouveaux éléments. Les formules qui
-- citent l'ancien nom en clair ne sont pas réécrites (limitation documentée).
-- ────────────────────────────────────────────────────────────────────────────

_space_renames = (package, installed) ->
  map = {}
  for it in *package.items
    continue unless it.type == 'space' and it.renamed_from
    continue unless installed[it.renamed_from]
    new_name = _after it.key, 'space:'
    old_name = _after it.renamed_from, 'space:'
    new_name = app_package.unkey_part new_name if new_name
    old_name = app_package.unkey_part old_name if old_name
    map[new_name] = old_name if new_name and old_name
  map

_child_old_key = (key, space_renames) ->
  for prefix in *{ 'field:', 'relation:', 'view:' }
    scope, name = _split_scope key, prefix
    old_scope = scope and space_renames[scope]
    return "#{prefix}#{app_package.key_part old_scope}.#{app_package.key_part name}" if old_scope and name
  rest = _after key, 'seed:'
  if rest
    sep = rest\find '|'
    if sep
      scope = app_package.unkey_part rest\sub(1, sep - 1)
      if space_renames[scope]
        return "seed:#{app_package.key_part(space_renames[scope])}#{rest\sub sep}"
  nil

_expand_renames = (package, installed) ->
  space_renames = _space_renames package, installed
  items = {}
  for it in *package.items
    -- Renommage déjà appliqué lors d'une mise à jour précédente : l'ancienne
    -- clé n'est plus suivie mais la nouvelle clé l'est. On l'établit comme un
    -- élément installé ordinaire pour qu'il ne soit jamais recréé.
    if it.renamed_from and not installed[it.renamed_from] and installed[it.key]
      table.insert items, { type: it.type, key: it.key, content: it.content,
                            fingerprint: it.fingerprint }
      continue
    if it.renamed_from or it.type == 'space'
      table.insert items, it
      continue
    old_key = _child_old_key it.key, space_renames
    if old_key and installed[old_key]
      table.insert items, { type: it.type, key: it.key, content: it.content,
                            fingerprint: it.fingerprint, renamed_from: old_key }
    else
      table.insert items, it
  { app: package.app, items: items, seed_keys: package.seed_keys }

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
  pkg = _expand_renames pkg, installed
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

-- Un élément renommé est classé sous sa nouvelle clé par plan_update, mais son
-- ancien état installé est indexé sous renamed_from : les anciennes clés restent
-- la source de vérité pour local_id et empreinte.
_effective_old = (ctx, entry) ->
  ctx.installed[entry.key] or (entry.renamed_from and ctx.installed[entry.renamed_from])

_skip = (entry, report) ->
  false

_check_decisions = (conflicts, decisions) ->
  for c in *conflicts
    entry = c[1]
    continue if entry.type == 'seed'
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
  group_name = app_package.unkey_part parts[1]
  rtype = app_package.unkey_part parts[2]
  res = app_package.unkey_part parts[3]
  lvl = app_package.unkey_part parts[4]
  group = _find_group_by_name group_name
  return nil unless group
  for p in *perms_mod.list_permissions group.id
    match = p.resourceType == rtype and p.level == lvl
    return p.id if match and _resource_name(p.resourceId) == res
  nil

_page_by_name = (name) ->
  for row in *box.space._tdb_custom_views\select {}
    return row if row[2] == name
  nil

_resolve_page_id = (key) ->
  name = _after key, 'page:'
  row = name and _page_by_name(app_package.unkey_part name)
  row and row[1]

_resolve_dataview_id = (key) ->
  name = _after key, 'dataview:'
  v = name and data_views.get_view_by_name(app_package.unkey_part name)
  v and v.id

_resolve_plugin_id = (key) ->
  name = _after key, 'plugin:'
  row = name and box.space._tdb_widget_plugins.index.by_name\get app_package.unkey_part name
  row and row[1]

_resolve_group_id = (key) ->
  name = _after key, 'group:'
  g = name and _find_group_by_name(app_package.unkey_part name)
  g and g.id

-- Dispatch défini après tous les résolveurs de type (en Lua, un upvalue
-- référencé avant sa déclaration locale deviendrait une globale nil).
_resolve_local_id = (item_type, key) ->
  return nil unless key
  if item_type == 'space'
    name = _after key, 'space:'
    sp = name and spaces_mod.get_space_by_name(app_package.unkey_part name)
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
  name = app_package.unkey_part _after entry.key, 'space:'
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
    formula: c.formula or ''
    triggerFields: c.triggerFields or {}
    language: c.language
  }
  { id: fid, space: sp_name }

-- Colonne 8 de _tdb_relations (« cardinality », core/spaces.moon:145-146),
-- ajoutée par la migration tdb_v3. Un tuple de 8 champs n'est écrit que si la
-- colonne existe ; sinon la cardinalité reste au défaut 'one' de la colonne.
_relations_have_cardinality = ->
  fmt = box.space._tdb_relations\format!
  fmt != nil and #fmt >= 8

-- 'many' seulement si explicitement déclaré ; tout le reste (clé absente d'un
-- ancien paquet, valeur vide) vaut 'one'. Miroir de app_package et de
-- schema_resolvers.normalize_cardinality.
_cardinality = (value) ->
  return 'many' if value == 'many'
  'one'

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
  tuple = { rid, from_sid, from_fid, to_sid, to_fid, "#{from_sp}_#{from_fld}", '' }
  table.insert tuple, _cardinality(c.cardinality) if _relations_have_cardinality!
  box.space._tdb_relations\insert tuple
  { id: rid, space: from_sp }

_update_relation = (entry, old) ->
  rest = _after entry.key, 'relation:'
  from_sp, from_fld = _scope_name rest
  c = entry.content
  to_sid = _space_id c.toSpace
  to_fid = _field_id to_sid, c.toField
  ops = {
    { '=', 4, to_sid }
    { '=', 5, to_fid }
  }
  table.insert ops, { '=', 8, _cardinality(c.cardinality) } if _relations_have_cardinality!
  box.space._tdb_relations\update old.local_id, ops
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
    old = _effective_old ctx, entry
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
    old = _effective_old ctx, entry
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
    _record_kept ctx, entry, _effective_old(ctx, entry), entry.fingerprint
    table.insert ctx.report.kept, entry.key

_do_unchanged = (ctx) ->
  for key in *ctx.plan.unchanged
    item = ctx.pkg_map[key]
    continue unless item
    continue if item.type == 'seed'
    old = _effective_old ctx, item
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

-- ────────────────────────────────────────────────────────────────────────────
-- PARTIE 3 (V3b) : renommages sur place
-- Exécutés dans la transaction AVANT les autres opérations pour que les
-- données soient conservées. La ligne de suivi de l'ancienne clé est supprimée
-- (les enfants d'un espace renommé sont remappés par _rename_space).
-- ────────────────────────────────────────────────────────────────────────────

_remap_child_key = (key, old_name, new_name) ->
  for prefix in *{ 'field:', 'relation:', 'view:' }
    rest = _after key, "#{prefix}#{app_package.key_part old_name}."
    return "#{prefix}#{app_package.key_part new_name}.#{rest}" if rest
  rest = _after key, "seed:#{app_package.key_part old_name}|"
  return "seed:#{app_package.key_part new_name}|#{rest}" if rest
  nil

_remap_child_tracking = (app_id, old_name, new_name) ->
  rows = box.space._tdb_app_items.index.by_app\select { app_id }
  for t in *rows
    new_key = _remap_child_key t[2], old_name, new_name
    continue unless new_key
    box.space._tdb_app_items\delete { t[1], t[2] }
    box.space._tdb_app_items\replace { t[1], new_key, t[3], t[4], t[5], t[6], t[7] }

_delete_tracking = (app_id, key) ->
  box.space._tdb_app_items\delete { app_id, key }

_rename_space = (ctx, from_key, to_key) ->
  old_name = _after from_key, 'space:'
  new_name = _after to_key, 'space:'
  return unless old_name and new_name
  old_name = app_package.unkey_part old_name
  new_name = app_package.unkey_part new_name
  data_sp = box.space["data_#{old_name}"]
  data_sp\rename "data_#{new_name}" if data_sp
  meta = spaces_mod.get_space_by_name old_name
  box.space._tdb_spaces\update meta.id, { { '=', 2, new_name }, { '=', 5, os.time! } } if meta
  _remap_child_tracking ctx.pkg.app.id, old_name, new_name
  _delete_tracking ctx.pkg.app.id, from_key

_rename_record_key = (sp, old_key, new_key) ->
  for row in *sp\select {}
    d = _decode row[2]
    if d[old_key] != nil
      d[new_key] = d[old_key]
      d[old_key] = nil
      sp\replace { row[1], json.encode d }

_rename_field = (ctx, from_key, to_key) ->
  f_scope, f_name = _split_scope from_key, 'field:'
  t_scope, t_name = _split_scope to_key, 'field:'
  if f_scope == t_scope and f_name != t_name
    old = ctx.installed[from_key]
    fid = old and old.local_id
    if fid and box.space._tdb_fields\get fid
      spaces_mod.update_field fid, { name: t_name }
      sp = box.space["data_#{f_scope}"]
      _rename_record_key sp, f_name, t_name if sp
  _delete_tracking ctx.pkg.app.id, from_key

_rename_row_name = (space_name, id, name_col, new_name) ->
  t = id and box.space[space_name]\get id
  box.space[space_name]\update(id, { { '=', name_col, new_name } }) if t

_rename_view = (ctx, from_key, to_key) ->
  f_scope, f_name = _split_scope from_key, 'view:'
  t_scope, t_name = _split_scope to_key, 'view:'
  old = ctx.installed[from_key]
  if old and f_scope == t_scope and f_name != t_name
    _rename_row_name '_tdb_views', old.local_id, 3, t_name
  _delete_tracking ctx.pkg.app.id, from_key

_rename_page = (ctx, from_key, to_key) ->
  name = app_package.unkey_part _after to_key, 'page:'
  old = ctx.installed[from_key]
  _rename_row_name '_tdb_custom_views', old and old.local_id, 2, name
  _delete_tracking ctx.pkg.app.id, from_key

_rename_dataview = (ctx, from_key, to_key) ->
  name = app_package.unkey_part _after to_key, 'dataview:'
  old = ctx.installed[from_key]
  _rename_row_name '_tdb_data_views', old and old.local_id, 2, name
  _delete_tracking ctx.pkg.app.id, from_key

_rename_plugin = (ctx, from_key, to_key) ->
  name = app_package.unkey_part _after to_key, 'plugin:'
  old = ctx.installed[from_key]
  _rename_row_name '_tdb_widget_plugins', old and old.local_id, 2, name
  _delete_tracking ctx.pkg.app.id, from_key

_rename_group = (ctx, from_key, to_key) ->
  name = app_package.unkey_part _after to_key, 'group:'
  old = ctx.installed[from_key]
  _rename_row_name '_tdb_groups', old and old.local_id, 2, name
  _delete_tracking ctx.pkg.app.id, from_key

_do_rename = (ctx, from_key, to_key) ->
  old = ctx.installed[from_key]
  return unless old
  switch old.type
    when 'space' then _rename_space ctx, from_key, to_key
    when 'field' then _rename_field ctx, from_key, to_key
    when 'view' then _rename_view ctx, from_key, to_key
    when 'page' then _rename_page ctx, from_key, to_key
    when 'dataview' then _rename_dataview ctx, from_key, to_key
    when 'plugin' then _rename_plugin ctx, from_key, to_key
    when 'group' then _rename_group ctx, from_key, to_key
    else _delete_tracking ctx.pkg.app.id, from_key

_do_renames = (ctx) ->
  renames = [p for p in *ctx.plan.rename]
  table.sort renames, (a, b) ->
    ta = ctx.installed[a[1]] and ctx.installed[a[1]].type
    tb = ctx.installed[b[1]] and ctx.installed[b[1]].type
    ra = TYPE_RANK[ta] or 99
    rb = TYPE_RANK[tb] or 99
    if ra != rb
      ra < rb
    else
      a[1] < b[1]
  for pair in *renames
    _do_rename ctx, pair[1], pair[2]

-- Refuse tout renommage dont la cible existe déjà localement : ce serait un
-- écrasement silencieux. Abort avant toute écriture.
_check_renames = (plan, pkg_map) ->
  for pair in *plan.rename
    target = pair[2]
    item = pkg_map[target]
    itype = item and item.type
    continue unless itype
    if app_package.describe_local itype, target
      return "rename target '#{target}' already exists locally"
  nil

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
  _do_renames ctx
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

-- ────────────────────────────────────────────────────────────────────────────
-- PARTIE 4 (V3b) : aperçu des pertes et purge des obsolètes
-- Seule une clé suivie pour cette app avec state = 'obsolète' peut être purgée :
-- jamais un élément actif ni un élément local (absent de _tdb_app_items).
-- ────────────────────────────────────────────────────────────────────────────

_normalize_keys = (keys) ->
  return { keys } if type(keys) == 'string'
  keys or {}

-- Renvoie les lignes de suivi purgables, ou nil + message.
_purge_rows = (app_id, keys) ->
  rows = {}
  for key in *_normalize_keys keys
    t = box.space._tdb_app_items\get { app_id, key }
    return nil, "unknown app item '#{key}' for app '#{app_id}'" unless t
    unless t[6] == 'obsolète'
      return nil, "item '#{key}' is not obsolete (state=#{t[6]}); only obsolete installed items can be purged"
    table.insert rows, { key: t[2], type: t[3], local_id: t[4] }
  rows, nil

_relation_touching_count = (sid) ->
  seen = {}
  n = 0
  for t in *box.space._tdb_relations.index.by_from\select { sid }
    n += 1 unless seen[t[1]]
    seen[t[1]] = true
  for t in *box.space._tdb_relations.index.by_to\select { sid }
    n += 1 unless seen[t[1]]
    seen[t[1]] = true
  n

_views_referencing_count = (name, sid) ->
  n = 0
  n += 1 for _ in *views_mod.list_views sid
  for t in *box.space._tdb_data_views\select {}
    n += 1 if t[4] == sid or t[4] == name
  for row in *box.space._tdb_custom_views\select {}
    n += 1 if row[4] and row[4]\find(name, 1, true)
  n

_field_value_count = (key) ->
  scope, name = _split_scope key, 'field:'
  sp = scope and box.space["data_#{scope}"]
  return 0 unless sp and name
  n = 0
  for t in *sp\select {}
    n += 1 if _decode(t[2])[name] != nil
  n

_loss_for = (row) ->
  loss = { key: row.key, type: row.type, records: 0, fields: 0, relations: 0, views: 0 }
  if row.type == 'field'
    loss.records = _field_value_count row.key
  elseif row.type == 'space'
    name = app_package.unkey_part _after row.key, 'space:'
    sp = name and spaces_mod.get_space_by_name name
    if sp
      data_sp = box.space["data_#{name}"]
      loss.records = data_sp and #data_sp\select({}) or 0
      loss.fields = #spaces_mod.list_fields sp.id
      loss.relations = _relation_touching_count sp.id
      loss.views = _views_referencing_count name, sp.id
  loss

preview_purge = (app_id, keys) ->
  rows, err = _purge_rows app_id, keys
  return { error: err, losses: {}, total_records: 0 } if err
  losses = {}
  total = 0
  for row in *rows
    loss = _loss_for row
    table.insert losses, loss
    total += loss.records
  { losses: losses, total_records: total, error: nil }

_is_child_of_space = (key, name) ->
  for prefix in *{ 'field:', 'relation:', 'view:' }
    return true if _after key, "#{prefix}#{app_package.key_part name}."
  _after(key, "seed:#{app_package.key_part name}|") != nil

_delete_space_children = (app_id, name) ->
  rows = box.space._tdb_app_items.index.by_app\select { app_id }
  for t in *rows
    box.space._tdb_app_items\delete { t[1], t[2] } if _is_child_of_space t[2], name

_remove_record_key = (sp, field_name) ->
  for t in *sp\select {}
    d = _decode t[2]
    if d[field_name] != nil
      d[field_name] = nil
      sp\replace { t[1], json.encode d }

_purge_field = (row) ->
  scope, name = _split_scope row.key, 'field:'
  if row.local_id and box.space._tdb_fields\get row.local_id
    spaces_mod.remove_field row.local_id
  sp = scope and box.space["data_#{scope}"]
  _remove_record_key sp, name if sp and name

_purge_space = (ctx, row) ->
  name = app_package.unkey_part _after row.key, 'space:'
  spaces_mod.delete_user_space name if name
  _delete_space_children ctx.app_id, name if name

_purge_seed = (row) ->
  rest = _after row.key, 'seed:'
  return unless rest
  sep = rest\find '|'
  return unless sep
  sp = box.space["data_#{app_package.unkey_part rest\sub(1, sep - 1)}"]
  sp\delete row.local_id if sp and row.local_id and row.local_id != ''

_purge_one = (ctx, row) ->
  unless row.local_id and row.local_id != ''
    error "missing local_id for '#{row.key}'"
  switch row.type
    when 'field' then _purge_field row
    when 'space' then _purge_space ctx, row
    when 'relation' then box.space._tdb_relations\delete row.local_id
    when 'view' then box.space._tdb_views\delete row.local_id
    when 'page' then box.space._tdb_custom_views\delete row.local_id
    when 'dataview' then box.space._tdb_data_views\delete row.local_id
    when 'plugin' then box.space._tdb_widget_plugins\delete row.local_id
    when 'group' then perms_mod.delete_group row.local_id
    when 'perm' then box.space._tdb_permissions\delete row.local_id
    when 'seed' then _purge_seed row
    else error "unsupported purge type '#{row.type}'"

_purge_transaction = (app_id, rows) ->
  ordered = [r for r in *rows]
  table.sort ordered, (a, b) ->
    ra = TYPE_RANK[a.type] or 99
    rb = TYPE_RANK[b.type] or 99
    if ra != rb
      ra < rb
    else
      a.key < b.key
  box.begin!
  ctx = { app_id: app_id }
  for row in *ordered
    _purge_one ctx, row
  for row in *rows
    _delete_tracking app_id, row.key
  box.commit!

purge_obsolete = (app_id, keys, opts) ->
  opts or= {}
  report = { ok: false, purged: {}, error: nil }
  unless opts.confirmed == true
    report.error = 'confirmation required'
    return report
  rows, err = _purge_rows app_id, keys
  if err
    report.error = err
    return report
  ok, err2 = pcall _purge_transaction, app_id, rows
  unless ok
    pcall -> box.rollback! if box.is_in_txn!
    report.error = tostring err2
    return report
  report.ok = true
  report.purged = keys
  _finalize report, {}
  report

apply_update = (package, decisions, opts) ->
  decisions or= {}
  opts or= {}
  report = _empty_report!
  normalized = _normalize package
  return _abort report, normalized.errors if #normalized.errors > 0
  pkg = normalized.package
  installed = _read_installed pkg.app.id
  pkg = _expand_renames pkg, installed
  pkg_map = {}
  for it in *pkg.items
    pkg_map[it.key] = it
  local_states = _build_local_states pkg, installed
  plan = plan_update installed, pkg, local_states, _effective_opts(pkg.app.id, opts)
  return _abort report, plan.errors if #plan.errors > 0
  rename_error = _check_renames plan, pkg_map
  return _abort report, { rename_error } if rename_error
  conflict_error = _check_decisions plan.conflict, decisions
  return _abort report, { conflict_error } if conflict_error
  for key in *plan.obsolete
    table.insert report.obsolete, key
  err = _do_apply plan, pkg, pkg_map, decisions, opts, installed, report
  return _abort report, { err } if err
  report.ok = true
  _finalize report, report.touched
  report

{ :load_package, :preview_update, :apply_update, :preview_purge, :purge_obsolete }
